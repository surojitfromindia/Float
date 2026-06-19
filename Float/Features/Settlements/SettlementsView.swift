import SwiftData
import SwiftUI

struct SettlementsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @Query(sort: \SettlementCaseItem.updatedAt, order: .reverse) private var cases:
        [SettlementCaseItem]
    @State private var searchText = ""
    @State private var selectedStatus: SettlementCaseStatus?
    @State private var selectedDirection: SettlementDirection?
    @State private var showActiveOnly = true
    @State private var editorPresentation: SettlementCaseEditorPresentation?
    @State private var entryPresentation: SettlementEntryEditorPresentation?
    @State private var casePendingDeletion: SettlementCaseItem?

    private var filteredCases: [SettlementCaseItem] {
        cases.filter { caseItem in
            let matchesSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || caseItem.displayTitle.localizedCaseInsensitiveContains(searchText)
                || caseItem.personName.localizedCaseInsensitiveContains(searchText)
                || (caseItem.note?.localizedCaseInsensitiveContains(searchText) ?? false)
            let matchesStatus = selectedStatus == nil || caseItem.status == selectedStatus
            let matchesDirection = selectedDirection == nil || caseItem.direction == selectedDirection
            let matchesActive = !showActiveOnly || caseItem.isActive
            return matchesSearch && matchesStatus && matchesDirection && matchesActive
        }
    }

    private var dashboard: SettlementDashboardSummary {
        SettlementDashboardSummary(cases: cases)
    }

    private var hasCustomFilters: Bool {
        selectedStatus != nil || selectedDirection != nil || !showActiveOnly
    }

    private var shouldShowFilters: Bool {
        !cases.isEmpty || hasCustomFilters
            || !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                dashboardSection
                if shouldShowFilters {
                    filtersSection
                }

                if filteredCases.isEmpty {
                    GlassCard {
                        EmptyStateView(
                            icon: "person.line.dotted.person.fill",
                            title: cases.isEmpty
                                ? "No settlement cases yet"
                                : "No matching cases",
                            message: cases.isEmpty
                                ? "Create a case when a bill or payment will settle over time."
                                : "Try changing the search or filters."
                        )
                    }
                } else {
                    ForEach(filteredCases) { caseItem in
                        NavigationLink {
                            SettlementCaseDetailView(caseItem: caseItem)
                        } label: {
                            SettlementCaseRow(caseItem: caseItem)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                entryPresentation = SettlementEntryEditorPresentation(
                                    caseItem: caseItem,
                                    entry: nil,
                                    kind: .payment
                                )
                            } label: {
                                Label("Record payment", systemImage: "checkmark.circle.fill")
                            }
                            Button {
                                entryPresentation = SettlementEntryEditorPresentation(
                                    caseItem: caseItem,
                                    entry: nil,
                                    kind: .addition
                                )
                            } label: {
                                Label("Add charge", systemImage: "plus.circle.fill")
                            }
                            Button {
                                markResolved(caseItem)
                            } label: {
                                Label("Mark resolved", systemImage: "xmark.seal.fill")
                            }
                            .disabled(caseItem.balanceSnapshot.remainingMinor <= 0)
                            Button {
                                editorPresentation = SettlementCaseEditorPresentation(caseItem: caseItem)
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                casePendingDeletion = caseItem
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .padding(20)
            .padding(.bottom, 120)
        }
        .navigationTitle("Settlements")
        .searchable(text: $searchText, prompt: "Search cases or people")
        .keyboardDismissControls()
        .floatBackground()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editorPresentation = SettlementCaseEditorPresentation(caseItem: nil)
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add settlement case")
            }
        }
        .sheet(item: $editorPresentation) { presentation in
            SettlementCaseEditorView(caseItem: presentation.caseItem)
        }
        .sheet(item: $entryPresentation) { presentation in
            SettlementEntryEditorView(
                caseItem: presentation.caseItem,
                entry: presentation.entry,
                initialKind: presentation.kind
            )
        }
        .alert(
            "Delete settlement case?",
            isPresented: Binding(
                get: { casePendingDeletion != nil },
                set: { isPresented in
                    if !isPresented {
                        casePendingDeletion = nil
                    }
                }
            )
        ) {
            Button("Cancel", role: .cancel) {
                casePendingDeletion = nil
            }
            Button("Delete", role: .destructive) {
                deletePendingCase()
            }
        } message: {
            Text("This permanently deletes the case and its full entry history.")
        }
    }

    private var dashboardSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Overview")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                SummaryMetricTile(
                    title: "To collect",
                    value: money(dashboard.receivableMinor),
                    captionText: "\(dashboard.receivableCases) open",
                    icon: "arrow.down.circle.fill",
                    tint: appState.themePalette.positive
                )
                SummaryMetricTile(
                    title: "To pay",
                    value: money(dashboard.payableMinor),
                    captionText: "\(dashboard.payableCases) open",
                    icon: "arrow.up.circle.fill",
                    tint: appState.themePalette.caution
                )
                SummaryMetricTile(
                    title: "Open cases",
                    value: "\(dashboard.openCases)",
                    caption: "Active matters",
                    icon: "tray.full.fill",
                    tint: appState.themePalette.accent
                )
                SummaryMetricTile(
                    title: "Settled",
                    value: "\(dashboard.settledCases)",
                    caption: "Completed",
                    icon: "checkmark.seal.fill",
                    tint: appState.themePalette.positive
                )
            }
        }
    }

    private var filtersSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button {
                    showActiveOnly.toggle()
                } label: {
                    SettlementFilterChip(
                        title: String(localized: "Active only"),
                        systemImage: showActiveOnly ? "checkmark.circle.fill" : "circle",
                        isSelected: showActiveOnly
                    )
                }
                .buttonStyle(.plain)

                Menu {
                    Picker("Direction", selection: $selectedDirection) {
                        Text("All directions").tag(SettlementDirection?.none)
                        ForEach(SettlementDirection.allCases) { direction in
                            Text(direction.title).tag(Optional(direction))
                        }
                    }
                } label: {
                    SettlementFilterChip(
                        title: selectedDirection?.title ?? String(localized: "All directions"),
                        systemImage: "arrow.left.arrow.right",
                        isSelected: selectedDirection != nil
                    )
                }

                Menu {
                    Picker("Status", selection: $selectedStatus) {
                        Text("All").tag(SettlementCaseStatus?.none)
                        ForEach(SettlementCaseStatus.allCases) { status in
                            Text(status.title).tag(Optional(status))
                        }
                    }
                } label: {
                    SettlementFilterChip(
                        title: selectedStatus?.title ?? String(localized: "Status"),
                        systemImage: "line.3.horizontal.decrease.circle",
                        isSelected: selectedStatus != nil
                    )
                }

                if hasCustomFilters {
                    Button {
                        resetFilters()
                    } label: {
                        SettlementFilterChip(
                            title: String(localized: "Clear"),
                            systemImage: "xmark.circle.fill",
                            isSelected: false
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }

    private func money(_ amount: Int64) -> String {
        MoneyFormatter.string(
            minorUnits: amount,
            currencyCode: appState.selectedCurrencyCode
        )
    }

    private func deletePendingCase() {
        guard let casePendingDeletion else { return }
        try? SettlementCaseRepository(modelContext: modelContext).delete(casePendingDeletion)
        self.casePendingDeletion = nil
    }

    private func markResolved(_ caseItem: SettlementCaseItem) {
        let remaining = caseItem.balanceSnapshot.remainingMinor
        guard remaining > 0 else { return }
        _ = try? SettlementCaseRepository(modelContext: modelContext).addEntry(
            to: caseItem,
            kind: .waived,
            amountMinor: remaining,
            entryDate: Date(),
            note: String(localized: "Marked resolved"),
            reference: nil
        )
        Haptics.confirm()
    }

    private func resetFilters() {
        selectedStatus = nil
        selectedDirection = nil
        showActiveOnly = true
    }
}

private struct SettlementCaseEditorPresentation: Identifiable {
    let id = UUID()
    let caseItem: SettlementCaseItem?
}

private struct SettlementFilterChip: View {
    @EnvironmentObject private var appState: AppState
    let title: String
    let systemImage: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(isSelected ? appState.themePalette.accent : .primary)
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background {
            Capsule()
                .fill(
                    isSelected
                        ? appState.themePalette.accent.opacity(0.18)
                        : Color.primary.opacity(0.07)
                )
        }
        .overlay {
            Capsule()
                .stroke(
                    isSelected
                        ? appState.themePalette.accent.opacity(0.45)
                        : Color.primary.opacity(0.11),
                    lineWidth: 1
                )
        }
    }
}

struct SettlementDashboardSummary {
    let receivableMinor: Int64
    let payableMinor: Int64
    let receivableCases: Int
    let payableCases: Int
    let openCases: Int
    let settledCases: Int

    init(cases: [SettlementCaseItem]) {
        var receivableMinor: Int64 = 0
        var payableMinor: Int64 = 0
        var receivableCases = 0
        var payableCases = 0
        var openCases = 0
        var settledCases = 0

        for caseItem in cases {
            let snapshot = caseItem.balanceSnapshot
            switch snapshot.status {
            case .settled, .writtenOff:
                settledCases += 1
            case .unpaid, .partiallyPaid, .overpaid:
                openCases += 1
            }

            guard snapshot.remainingMinor > 0 else { continue }
            switch caseItem.direction {
            case .theyOweYou:
                receivableMinor += snapshot.remainingMinor
                receivableCases += 1
            case .youOweThem:
                payableMinor += snapshot.remainingMinor
                payableCases += 1
            }
        }

        self.receivableMinor = receivableMinor
        self.payableMinor = payableMinor
        self.receivableCases = receivableCases
        self.payableCases = payableCases
        self.openCases = openCases
        self.settledCases = settledCases
    }
}

private struct SettlementCaseRow: View {
    @EnvironmentObject private var appState: AppState
    let caseItem: SettlementCaseItem

    private var snapshot: SettlementBalanceSnapshot {
        caseItem.balanceSnapshot
    }

    private var statusTint: Color {
        settlementStatusTint(for: snapshot.status)
    }

    var body: some View {
        GlassCard(padding: 0) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    FloatIconBadge(
                        icon: caseItem.direction == .theyOweYou
                            ? "arrow.down.circle.fill"
                            : "arrow.up.circle.fill",
                        tint: statusTint,
                        size: 38
                    )

                    VStack(alignment: .leading, spacing: 6) {
                        Text(caseItem.displayTitle)
                            .font(.headline.weight(.semibold))
                            .lineLimit(1)

                        HStack(spacing: 6) {
                            Text(caseItem.personName)
                                .lineLimit(1)

                            Circle()
                                .fill(Color.primary.opacity(0.24))
                                .frame(width: 4, height: 4)

                            Text(caseItem.direction.title)
                                .lineLimit(1)
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)

                    VStack(alignment: .trailing, spacing: 6) {
                        Text(balanceText)
                            .moneyStyle(size: 18, weight: .bold)
                            .lineLimit(1)
                            .minimumScaleFactor(0.68)

                        SettlementStatusPill(title: snapshot.status.title, tint: statusTint)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    SettlementSummaryProgress(fraction: paidFraction, tint: statusTint)

                    HStack(spacing: 0) {
                        SettlementRowMetric(
                            title: "Paid",
                            value: money(snapshot.paymentsMinor),
                            tint: appState.themePalette.positive
                        )
                        SettlementMetricDivider()
                        SettlementRowMetric(
                            title: balanceMetricTitle,
                            value: balanceText,
                            tint: statusTint
                        )
                        SettlementMetricDivider()
                        SettlementRowMetric(
                            title: "Original",
                            value: money(snapshot.initialAmountMinor),
                            tint: appState.themePalette.accent
                        )
                    }
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        activityDate
                        Spacer(minLength: 8)
                        deltaChips
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        activityDate
                        deltaChips
                    }
                }
            }
            .padding(16)
            .padding(.leading, 6)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(statusTint.opacity(0.75))
                    .frame(width: 4)
                    .padding(.vertical, 18)
            }
        }
    }

    private var balanceText: String {
        if snapshot.creditMinor > 0 {
            return money(snapshot.creditMinor)
        }
        return money(snapshot.remainingMinor)
    }

    private var balanceMetricTitle: LocalizedStringResource {
        if snapshot.creditMinor > 0 {
            return "Overpaid"
        }
        return "Remaining"
    }

    private var paidFraction: Double {
        guard snapshot.dueMinor > 0 else {
            return snapshot.paymentsMinor > 0 ? 1 : 0
        }
        return min(max(Double(snapshot.paymentsMinor) / Double(snapshot.dueMinor), 0), 1)
    }

    private var activityDate: some View {
        Label {
            Text(caseItem.lastActivityDate.formatted(date: .abbreviated, time: .omitted))
                .lineLimit(1)
        } icon: {
            Image(systemName: "calendar")
                .font(.caption2.weight(.semibold))
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(.tertiary)
    }

    @ViewBuilder
    private var deltaChips: some View {
        let addedMinor = snapshot.additionsMinor + snapshot.adjustmentsMinor
        HStack(spacing: 8) {
            if addedMinor > 0 {
                SettlementRowDeltaChip(
                    title: "Added",
                    value: money(addedMinor),
                    icon: "plus.circle.fill",
                    tint: appState.themePalette.caution
                )
            }

            if snapshot.reductionsMinor > 0 {
                SettlementRowDeltaChip(
                    title: "Reduced",
                    value: money(snapshot.reductionsMinor),
                    icon: "minus.circle.fill",
                    tint: Color(hex: "#8B5CF6")
                )
            }
        }
    }

    private func money(_ amount: Int64) -> String {
        MoneyFormatter.string(
            minorUnits: amount,
            currencyCode: caseCurrencyCode
        )
    }

    private var caseCurrencyCode: String {
        let trimmed = caseItem.currencyCode.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? appState.selectedCurrencyCode : trimmed
    }
}

private struct SettlementStatusPill: View {
    let title: String
    let tint: Color

    var body: some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.12), in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(tint.opacity(0.18), lineWidth: 1)
            }
    }
}

private struct SettlementRowMetric: View {
    let title: LocalizedStringResource
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
            Text(value)
                .moneyStyle(size: 13, weight: .semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SettlementRowDeltaChip: View {
    let title: LocalizedStringResource
    let value: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.caption2.weight(.semibold))
            Text(title)
                .font(.caption2.weight(.semibold))
            Text(value)
                .moneyStyle(size: 11, weight: .semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .floatGlassSurface(
            cornerRadius: 10,
            tint: tint,
            strokeOpacity: 0.04
        )
    }
}

struct SettlementCaseDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @Query(sort: \CategoryItem.sortOrder) private var categories: [CategoryItem]
    @Query(sort: \AccountItem.createdAt) private var accounts: [AccountItem]
    let caseItem: SettlementCaseItem
    @State private var editorPresentation: SettlementEntryEditorPresentation?
    @State private var editingCase = false
    @State private var entryPendingDeletion: SettlementEntryItem?

    private var snapshot: SettlementBalanceSnapshot {
        caseItem.balanceSnapshot
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                summaryCard
                timelineSection
            }
            .padding(20)
            .padding(.bottom, 120)
        }
        .navigationTitle(caseItem.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .floatBackground()
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    editingCase = true
                } label: {
                    Image(systemName: "pencil")
                }
                .accessibilityLabel("Edit case")

                Menu {
                    Button {
                        editorPresentation = SettlementEntryEditorPresentation(
                            caseItem: caseItem,
                            entry: nil,
                            kind: .addition
                        )
                    } label: {
                        Label("Add charge", systemImage: "plus.circle.fill")
                    }
                    Button {
                        editorPresentation = SettlementEntryEditorPresentation(
                            caseItem: caseItem,
                            entry: nil,
                            kind: .payment
                        )
                    } label: {
                        Label("Record payment", systemImage: "checkmark.circle.fill")
                    }
                    Button {
                        editorPresentation = SettlementEntryEditorPresentation(
                            caseItem: caseItem,
                            entry: nil,
                            kind: .adjustment
                        )
                    } label: {
                        Label("Correction up", systemImage: "slider.horizontal.3")
                    }
                    Button {
                        editorPresentation = SettlementEntryEditorPresentation(
                            caseItem: caseItem,
                            entry: nil,
                            kind: .waived
                        )
                    } label: {
                        Label("Waive amount", systemImage: "xmark.seal.fill")
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add settlement entry")
            }
        }
        .sheet(isPresented: $editingCase) {
            SettlementCaseEditorView(caseItem: caseItem)
        }
        .sheet(item: $editorPresentation) { presentation in
            SettlementEntryEditorView(
                caseItem: presentation.caseItem,
                entry: presentation.entry,
                initialKind: presentation.kind
            )
        }
        .alert(
            "Delete entry?",
            isPresented: Binding(
                get: { entryPendingDeletion != nil },
                set: { isPresented in
                    if !isPresented {
                        entryPendingDeletion = nil
                    }
                }
            )
        ) {
            Button("Cancel", role: .cancel) {
                entryPendingDeletion = nil
            }
            Button("Delete", role: .destructive) {
                deletePendingEntry()
            }
        } message: {
            Text("This removes one timeline entry from the settlement case.")
        }
    }

    private var summaryCard: some View {
        GlassCard(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    FloatIconBadge(
                        icon: caseItem.direction == .theyOweYou
                            ? "arrow.down.circle.fill"
                            : "arrow.up.circle.fill",
                        tint: settlementStatusTint(for: snapshot.status),
                        size: 38
                    )

                    VStack(alignment: .leading, spacing: 4) {
                        Text(caseItem.personName)
                            .font(.headline.weight(.semibold))
                            .lineLimit(1)
                        Text(caseItem.direction.title)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    VStack(alignment: .trailing, spacing: 3) {
                        Text(primaryBalance)
                            .moneyStyle(size: 21, weight: .bold)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(snapshot.status.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(settlementStatusTint(for: snapshot.status))
                    }
                }

                SettlementSummaryProgress(
                    fraction: paidFraction,
                    tint: settlementStatusTint(for: snapshot.status)
                )

                HStack(spacing: 0) {
                    SettlementDetailMetric(
                        title: "Original",
                        value: money(snapshot.initialAmountMinor),
                        tint: appState.themePalette.accent
                    )
                    SettlementMetricDivider()
                    SettlementDetailMetric(
                        title: "Added",
                        value: money(snapshot.additionsMinor + snapshot.adjustmentsMinor),
                        tint: appState.themePalette.caution
                    )
                    SettlementMetricDivider()
                    SettlementDetailMetric(
                        title: "Reduced",
                        value: money(snapshot.reductionsMinor),
                        tint: Color(hex: "#8B5CF6")
                    )
                    SettlementMetricDivider()
                    SettlementDetailMetric(
                        title: "Paid",
                        value: money(snapshot.paymentsMinor),
                        tint: appState.themePalette.positive
                    )
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .floatGlassSurface(cornerRadius: 14, strokeOpacity: 0.05)

                if let note = caseItem.note {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
    }

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "History")
            VStack(spacing: 6) {
                ForEach(caseItem.sortedEntries) { entry in
                    Button {
                        edit(entry)
                    } label: {
                        SettlementEntryRow(entry: entry, currencyCode: caseCurrencyCode)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .contextMenu {
                        if entry.kind == .initialAmount {
                            Button {
                                editingCase = true
                            } label: {
                                Label("Edit case", systemImage: "pencil")
                            }
                        } else {
                            Button {
                                edit(entry)
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            if entry.canCreateLinkedTransaction {
                                Button {
                                    createLinkedTransaction(for: entry)
                                } label: {
                                    Label("Create transaction", systemImage: "link.badge.plus")
                                }
                            }
                            Button(role: .destructive) {
                                entryPendingDeletion = entry
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    } preview: {
                        SettlementEntryRow(entry: entry, currencyCode: caseCurrencyCode)
                            .padding(16)
                            .frame(maxWidth: 420)
                    }

                    if entry.id != caseItem.sortedEntries.last?.id {
                        Divider()
                            .padding(.leading, 48)
                    }
                }
            }
            .padding(14)
            .transactionSectionGlassSurface(cornerRadius: FloatTheme.controlRadius)
        }
    }

    private var primaryBalance: String {
        if snapshot.creditMinor > 0 {
            return money(snapshot.creditMinor)
        }
        return money(snapshot.remainingMinor)
    }

    private var paidFraction: Double {
        guard snapshot.dueMinor > 0 else {
            return snapshot.paymentsMinor > 0 ? 1 : 0
        }
        return min(max(Double(snapshot.paymentsMinor) / Double(snapshot.dueMinor), 0), 1)
    }

    private func money(_ amount: Int64) -> String {
        MoneyFormatter.string(
            minorUnits: amount,
            currencyCode: caseCurrencyCode
        )
    }

    private var caseCurrencyCode: String {
        let trimmed = caseItem.currencyCode.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? appState.selectedCurrencyCode : trimmed
    }

    private func deletePendingEntry() {
        guard let entryPendingDeletion else { return }
        try? SettlementCaseRepository(modelContext: modelContext).deleteEntry(entryPendingDeletion)
        self.entryPendingDeletion = nil
    }

    private func edit(_ entry: SettlementEntryItem) {
        if entry.kind == .initialAmount {
            editingCase = true
        } else {
            editorPresentation = SettlementEntryEditorPresentation(
                caseItem: caseItem,
                entry: entry,
                kind: entry.kind
            )
        }
    }

    private func createLinkedTransaction(for entry: SettlementEntryItem) {
        guard entry.canCreateLinkedTransaction else { return }
        let isExpense = linkedTransactionIsExpense(for: entry)
        let category = DefaultCategoryResolver.resolve(
            isExpense: isExpense,
            preferredID: appState.lastUsedCategoryID,
            categories: categories,
            modelContext: modelContext
        )
        let account = DefaultAccountResolver.resolve(
            preferredID: appState.lastUsedAccountID,
            accounts: accounts,
            modelContext: modelContext,
            currencyCode: caseCurrencyCode
        )
        let transaction = TransactionItem(
            amountMinor: entry.amountMinor,
            isExpense: isExpense,
            timestamp: entry.entryDate,
            category: category,
            account: account,
            note: linkedTransactionNote(for: entry)
        )
        modelContext.insert(transaction)
        entry.linkedTransaction = transaction
        entry.updatedAt = Date()
        caseItem.updatedAt = Date()
        appState.lastUsedCategoryID = category.id.uuidString
        appState.lastUsedAccountID = account.id.uuidString
        try? modelContext.save()
        Haptics.confirm()
    }

    private func linkedTransactionIsExpense(for entry: SettlementEntryItem) -> Bool {
        switch entry.kind {
        case .payment:
            caseItem.direction == .youOweThem
        case .addition, .adjustment:
            caseItem.direction == .youOweThem
        case .initialAmount, .discount, .waived, .correctionDown:
            false
        }
    }

    private func linkedTransactionNote(for entry: SettlementEntryItem) -> String {
        [caseItem.displayTitle, entry.note, entry.reference]
            .compactMap { value in
                let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed?.isEmpty == false ? trimmed : nil
            }
            .joined(separator: " - ")
    }
}

private struct SettlementEntryEditorPresentation: Identifiable {
    let id = UUID()
    let caseItem: SettlementCaseItem
    let entry: SettlementEntryItem?
    let kind: SettlementEntryKind
}

private struct SettlementSummaryProgress: View {
    let fraction: Double
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(tint.opacity(0.78))
                    .frame(width: proxy.size.width * fraction)
            }
        }
        .frame(height: 5)
        .accessibilityHidden(true)
    }
}

private struct SettlementDetailMetric: View {
    let title: LocalizedStringResource
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(tint)
                .lineLimit(1)
            Text(value)
                .moneyStyle(size: 12, weight: .semibold)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SettlementMetricDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(width: 1, height: 28)
            .padding(.horizontal, 8)
    }
}

private struct SettlementEntryRow: View {
    let entry: SettlementEntryItem
    let currencyCode: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 12) {
                FloatIconBadge(icon: entry.kind.icon, tint: tint, size: 36)

                Text(entry.kind.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(displayAmount)
                    .moneyStyle(size: 15, weight: .semibold)
                    .foregroundStyle(amountTint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(minWidth: 104, alignment: .trailing)
//                    .floatGlassSurface(
//                        cornerRadius: 12,
//                        tint: amountTint,
//                        strokeOpacity: 0.04
//                    )
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.entryDate.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Color.primary.opacity(0.52))
                    .lineLimit(1)

                if let note = cleaned(entry.note) {
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(Color.primary.opacity(0.68))
                        .lineLimit(1)
                }

                if let reference = cleaned(entry.reference) {
                    Text(reference)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Color.primary.opacity(0.44))
                        .lineLimit(1)
                }

                if entry.linkedTransaction != nil {
                    Label("Linked transaction", systemImage: "link")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color(hex: "#1B8A5A"))
                        .lineLimit(1)
                }
            }
            .padding(.leading, 48)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var tint: Color {
        switch entry.kind {
        case .initialAmount:
            Color(hex: "#3B82F6")
        case .addition, .adjustment:
            Color(hex: "#B4613B")
        case .payment:
            Color(hex: "#1B8A5A")
        case .discount, .waived, .correctionDown:
            Color(hex: "#8B5CF6")
        }
    }

    private var amountTint: Color {
        switch entry.kind {
        case .initialAmount:
            Color(hex: "#2563EB")
        case .addition, .adjustment:
            Color(hex: "#B45309")
        case .payment:
            Color(hex: "#15803D")
        case .discount, .waived, .correctionDown:
            Color(hex: "#7C3AED")
        }
    }

    private var displayAmount: String {
        switch entry.kind {
        case .initialAmount:
            money(entry.amountMinor)
        case .addition, .adjustment:
            "+" + money(entry.amountMinor)
        case .payment, .discount, .waived, .correctionDown:
            "-" + money(entry.amountMinor)
        }
    }

    private func money(_ amount: Int64) -> String {
        MoneyFormatter.string(minorUnits: amount, currencyCode: currencyCode)
    }

    private func cleaned(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else {
            return nil
        }
        return trimmed
    }
}

private struct SettlementCaseEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    let caseItem: SettlementCaseItem?
    @State private var title = ""
    @State private var personName = ""
    @State private var direction = SettlementDirection.theyOweYou
    @State private var amountText = ""
    @State private var date = Date()
    @State private var note = ""
    @State private var validationMessage: String?

    private var amountMinor: Int64 {
        MoneyParser.parseDisplayAmountMinor(
            from: amountText,
            currencyCode: appState.selectedCurrencyCode
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Case") {
                    TextField("Title", text: $title)
                    TextField("Person name", text: $personName)
                    Picker("Direction", selection: $direction) {
                        ForEach(SettlementDirection.allCases) { direction in
                            Text(direction.title).tag(direction)
                        }
                    }
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    TextField("Note", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section("Starting amount") {
                    HStack {
                        TextField("Amount", text: $amountText)
                            .keyboardType(.decimalPad)
                        SettlementAmountPreview(
                            minorUnits: amountMinor,
                            currencyCode: caseCurrencyCode
                        )
                    }
                }

                if let validationMessage {
                    Section {
                        Text(validationMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(caseItem == nil ? "New settlement" : "Edit settlement")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                }
            }
            .onAppear(perform: populate)
        }
    }

    private func populate() {
        guard let caseItem else { return }
        title = caseItem.title
        personName = caseItem.personName == String(localized: "No person") ? "" : caseItem.personName
        direction = caseItem.direction
        date = caseItem.createdAt
        note = caseItem.note ?? ""
        amountText = decimalText(for: caseItem.balanceSnapshot.initialAmountMinor)
    }

    private func save() {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanPersonName = personName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else {
            validationMessage = String(localized: "Enter a title.")
            return
        }
        guard !cleanPersonName.isEmpty else {
            validationMessage = String(localized: "Enter a person name.")
            return
        }
        guard caseItem != nil || amountMinor > 0 else {
            validationMessage = String(localized: "Enter a starting amount.")
            return
        }

        do {
            let repository = SettlementCaseRepository(modelContext: modelContext)
            if let caseItem {
                try repository.update(
                    caseItem,
                    title: cleanTitle,
                    personName: cleanPersonName,
                    direction: direction,
                    currencyCode: caseCurrencyCode(for: caseItem),
                    initialAmountMinor: amountMinor,
                    date: date,
                    note: note
                )
            } else {
                _ = try repository.create(
                    title: cleanTitle,
                    personName: cleanPersonName,
                    direction: direction,
                    initialAmountMinor: amountMinor,
                    date: date,
                    currencyCode: appState.selectedCurrencyCode,
                    note: note
                )
            }
            dismiss()
        } catch {
            validationMessage = error.localizedDescription
        }
    }

    private func caseCurrencyCode(for caseItem: SettlementCaseItem) -> String {
        let trimmed = caseItem.currencyCode.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? appState.selectedCurrencyCode : trimmed
    }

    private var caseCurrencyCode: String {
        if let caseItem {
            return caseCurrencyCode(for: caseItem)
        }
        return appState.selectedCurrencyCode
    }

    private func decimalText(for minorUnits: Int64) -> String {
        let fractionDigits = MoneyFormatter.fractionDigits(for: caseCurrencyCode)
        let divisor = pow(10.0, Double(fractionDigits))
        return String(format: "%.\(fractionDigits)f", Double(minorUnits) / divisor)
    }
}

private struct SettlementEntryEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @Query(sort: \CategoryItem.sortOrder) private var categories: [CategoryItem]
    @Query(sort: \AccountItem.createdAt) private var accounts: [AccountItem]
    let caseItem: SettlementCaseItem
    let entry: SettlementEntryItem?
    let initialKind: SettlementEntryKind
    @State private var kind = SettlementEntryKind.addition
    @State private var amountText = ""
    @State private var entryDate = Date()
    @State private var note = ""
    @State private var reference = ""
    @State private var createLinkedTransaction = false
    @State private var validationMessage: String?

    private var amountMinor: Int64 {
        MoneyParser.parseDisplayAmountMinor(
            from: amountText,
            currencyCode: caseItem.currencyCode
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Entry") {
                    if entry?.linkedTransaction != nil {
                        LabeledContent("Type") {
                            Text(kind.title)
                        }
                    } else {
                        Picker("Type", selection: $kind) {
                            Text(SettlementEntryKind.addition.title).tag(SettlementEntryKind.addition)
                            Text(SettlementEntryKind.payment.title).tag(SettlementEntryKind.payment)
                            Text(SettlementEntryKind.adjustment.title).tag(SettlementEntryKind.adjustment)
                            Text(SettlementEntryKind.discount.title).tag(SettlementEntryKind.discount)
                            Text(SettlementEntryKind.waived.title).tag(SettlementEntryKind.waived)
                            Text(SettlementEntryKind.correctionDown.title).tag(SettlementEntryKind.correctionDown)
                        }
                    }
                    HStack {
                        TextField("Amount", text: $amountText)
                            .keyboardType(.decimalPad)
                        SettlementAmountPreview(
                            minorUnits: amountMinor,
                            currencyCode: caseItem.currencyCode
                        )
                    }
                    DatePicker("Date", selection: $entryDate, displayedComponents: .date)
                    TextField("Note", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                    TextField("Reference", text: $reference)
                }

                if entry == nil && canCreateLinkedTransaction {
                    Section("Transaction") {
                        Toggle("Create linked transaction", isOn: $createLinkedTransaction)
                        Text(linkedTransactionPreview)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let validationMessage {
                    Section {
                        Text(validationMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(entry == nil ? "New entry" : "Edit entry")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                }
            }
            .onAppear(perform: populate)
        }
    }

    private func populate() {
        if let entry {
            kind = entry.kind == .initialAmount ? .addition : entry.kind
            amountText = decimalText(for: entry.amountMinor)
            entryDate = entry.entryDate
            note = entry.note ?? ""
            reference = entry.reference ?? ""
            createLinkedTransaction = false
        } else {
            kind = initialKind == .initialAmount ? .addition : initialKind
            createLinkedTransaction = false
        }
    }

    private func save() {
        guard amountMinor > 0 else {
            validationMessage = String(localized: "Enter an amount.")
            return
        }
        do {
            let repository = SettlementCaseRepository(modelContext: modelContext)
            if let entry {
                try repository.updateEntry(
                    entry,
                    kind: kind,
                    amountMinor: amountMinor,
                    entryDate: entryDate,
                    note: note,
                    reference: reference
                )
            } else if createLinkedTransaction && canCreateLinkedTransaction {
                let isExpense = linkedTransactionIsExpense
                let category = DefaultCategoryResolver.resolve(
                    isExpense: isExpense,
                    preferredID: appState.lastUsedCategoryID,
                    categories: categories,
                    modelContext: modelContext
                )
                let account = DefaultAccountResolver.resolve(
                    preferredID: appState.lastUsedAccountID,
                    accounts: accounts,
                    modelContext: modelContext,
                    currencyCode: caseItem.currencyCode
                )
                _ = try repository.addEntryAndCreateTransaction(
                    to: caseItem,
                    kind: kind,
                    amountMinor: amountMinor,
                    entryDate: entryDate,
                    note: note,
                    reference: reference,
                    category: category,
                    account: account
                )
                appState.lastUsedCategoryID = category.id.uuidString
                appState.lastUsedAccountID = account.id.uuidString
            } else {
                _ = try repository.addEntry(
                    to: caseItem,
                    kind: kind,
                    amountMinor: amountMinor,
                    entryDate: entryDate,
                    note: note,
                    reference: reference
                )
            }
            dismiss()
        } catch {
            validationMessage = error.localizedDescription
        }
    }

    private func decimalText(for minorUnits: Int64) -> String {
        let fractionDigits = MoneyFormatter.fractionDigits(for: caseItem.currencyCode)
        let divisor = pow(10.0, Double(fractionDigits))
        return String(format: "%.\(fractionDigits)f", Double(minorUnits) / divisor)
    }

    private var canCreateLinkedTransaction: Bool {
        kind == .payment
    }

    private var linkedTransactionIsExpense: Bool {
        switch kind {
        case .payment:
            caseItem.direction == .youOweThem
        case .addition, .adjustment:
            caseItem.direction == .youOweThem
        case .initialAmount, .discount, .waived, .correctionDown:
            false
        }
    }

    private var linkedTransactionPreview: String {
        linkedTransactionIsExpense
            ? String(localized: "This will post as an expense.")
            : String(localized: "This will post as income.")
    }
}

private struct SettlementAmountPreview: View {
    let minorUnits: Int64
    let currencyCode: String

    var body: some View {
        Text(MoneyFormatter.string(minorUnits: minorUnits, currencyCode: currencyCode))
            .moneyStyle(size: 14, weight: .semibold)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
    }
}

func settlementStatusTint(for status: SettlementCaseStatus) -> Color {
    switch status {
    case .unpaid:
        Color(hex: "#3B82F6")
    case .partiallyPaid:
        Color(hex: "#B4613B")
    case .settled:
        Color(hex: "#1B8A5A")
    case .overpaid:
        Color(hex: "#8B5CF6")
    case .writtenOff:
        Color(hex: "#5A6B6B")
    }
}
