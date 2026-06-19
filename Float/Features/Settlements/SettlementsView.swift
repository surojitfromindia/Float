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

    private var needsAttentionCases: [SettlementCaseItem] {
        filteredCases.filter {
            [.overdue, .dueSoon].contains($0.operationalSnapshot.workflowStatus)
        }
    }

    private var activeCases: [SettlementCaseItem] {
        filteredCases.filter {
            $0.operationalSnapshot.workflowStatus == .active
        }
    }

    private var closedCases: [SettlementCaseItem] {
        filteredCases.filter {
            [.settled, .archived].contains($0.operationalSnapshot.workflowStatus)
        }
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
                    settlementSection(title: "Needs attention", cases: needsAttentionCases)
                    settlementSection(title: "Active", cases: activeCases)
                    settlementSection(title: "Closed", cases: closedCases)
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
                initialKind: presentation.kind,
                milestone: presentation.milestone
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

    @ViewBuilder
    private func settlementSection(
        title: LocalizedStringResource,
        cases sectionCases: [SettlementCaseItem]
    ) -> some View {
        if !sectionCases.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: title)
                ForEach(sectionCases) { caseItem in
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
                                kind: .payment,
                                milestone: caseItem.sortedMilestones.first(where: \.isOpen)
                            )
                        } label: {
                            Label("Record payment", systemImage: "checkmark.circle.fill")
                        }
                        Button {
                            entryPresentation = SettlementEntryEditorPresentation(
                                caseItem: caseItem,
                                entry: nil,
                                kind: .addition,
                                milestone: nil
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
                            archive(caseItem)
                        } label: {
                            Label("Archive", systemImage: "archivebox.fill")
                        }
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

    private func archive(_ caseItem: SettlementCaseItem) {
        try? SettlementCaseRepository(modelContext: modelContext).archive(caseItem)
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
            if caseItem.archived {
                settledCases += 1
                continue
            }
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

    private var operational: SettlementOperationalSnapshot {
        caseItem.operationalSnapshot
    }

    private var statusTint: Color {
        if operational.workflowStatus == .overdue || operational.workflowStatus == .dueSoon {
            return settlementWorkflowTint(for: operational.workflowStatus)
        }
        return settlementStatusTint(for: snapshot.status)
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

                        SettlementStatusPill(
                            title: operational.workflowStatus.title,
                            tint: statusTint
                        )
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
                        dueDateLabel
                        Spacer(minLength: 8)
                        deltaChips
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            activityDate
                            dueDateLabel
                        }
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
    private var dueDateLabel: some View {
        if let nextDueDate = operational.nextDueDate {
            Label {
                Text(dueText(for: nextDueDate))
                    .lineLimit(1)
            } icon: {
                Image(systemName: "clock.fill")
                    .font(.caption2.weight(.semibold))
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(settlementWorkflowTint(for: operational.workflowStatus))
        }
    }

    @ViewBuilder
    private var deltaChips: some View {
        let addedMinor = snapshot.additionsMinor + snapshot.adjustmentsMinor
        HStack(spacing: 8) {
            if operational.openMilestoneCount > 0 {
                SettlementRowDeltaChip(
                    title: "Plan",
                    value: "\(operational.openMilestoneCount)",
                    icon: "calendar.badge.clock",
                    tint: appState.themePalette.accent
                )
            }

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

    private func dueText(for date: Date) -> String {
        guard let days = operational.daysUntilDue else {
            return date.formatted(date: .abbreviated, time: .omitted)
        }
        if days < 0 {
            return String(localized: "Overdue")
        }
        if days == 0 {
            return String(localized: "Due today")
        }
        return date.formatted(date: .abbreviated, time: .omitted)
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
    @Query(sort: \TransactionItem.timestamp, order: .reverse) private var transactions:
        [TransactionItem]
    let caseItem: SettlementCaseItem
    @State private var editorPresentation: SettlementEntryEditorPresentation?
    @State private var milestonePresentation: SettlementMilestoneEditorPresentation?
    @State private var editingCase = false
    @State private var entryPendingDeletion: SettlementEntryItem?
    @State private var transactionLinkEntry: SettlementEntryItem?

    private var snapshot: SettlementBalanceSnapshot {
        caseItem.balanceSnapshot
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                summaryCard
                milestonesSection
                linkedTransactionsSection
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
                        milestonePresentation = SettlementMilestoneEditorPresentation(
                            caseItem: caseItem,
                            milestone: nil
                        )
                    } label: {
                        Label("Add milestone", systemImage: "calendar.badge.plus")
                    }
                    Button {
                        editorPresentation = SettlementEntryEditorPresentation(
                            caseItem: caseItem,
                            entry: nil,
                            kind: .addition,
                            milestone: nil
                        )
                    } label: {
                        Label("Add charge", systemImage: "plus.circle.fill")
                    }
                    Button {
                        editorPresentation = SettlementEntryEditorPresentation(
                            caseItem: caseItem,
                            entry: nil,
                            kind: .payment,
                            milestone: caseItem.sortedMilestones.first(where: \.isOpen)
                        )
                    } label: {
                        Label("Record payment", systemImage: "checkmark.circle.fill")
                    }
                    Button {
                        editorPresentation = SettlementEntryEditorPresentation(
                            caseItem: caseItem,
                            entry: nil,
                            kind: .adjustment,
                            milestone: nil
                        )
                    } label: {
                        Label("Correction up", systemImage: "slider.horizontal.3")
                    }
                    Button {
                        editorPresentation = SettlementEntryEditorPresentation(
                            caseItem: caseItem,
                            entry: nil,
                            kind: .waived,
                            milestone: nil
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
                initialKind: presentation.kind,
                milestone: presentation.milestone
            )
        }
        .sheet(item: $milestonePresentation) { presentation in
            SettlementMilestoneEditorView(
                caseItem: presentation.caseItem,
                milestone: presentation.milestone
            )
        }
        .sheet(item: $transactionLinkEntry) { entry in
            SettlementTransactionLinkView(
                entry: entry,
                transactions: matchingTransactions(for: entry)
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

    private var milestonesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Payment plan")
            if caseItem.sortedMilestones.isEmpty {
                GlassCard {
                    EmptyStateView(
                        icon: "calendar.badge.plus",
                        title: "No payment plan",
                        message: "Add milestones when this settlement will be paid over time."
                    )
                }
            } else {
                VStack(spacing: 6) {
                    ForEach(caseItem.sortedMilestones) { milestone in
                        SettlementMilestoneRow(
                            milestone: milestone,
                            currencyCode: caseCurrencyCode
                        )
                        .contentShape(Rectangle())
                        .contextMenu {
                            Button {
                                editorPresentation = SettlementEntryEditorPresentation(
                                    caseItem: caseItem,
                                    entry: nil,
                                    kind: .payment,
                                    milestone: milestone
                                )
                            } label: {
                                Label("Record payment", systemImage: "checkmark.circle.fill")
                            }
                            Button {
                                milestonePresentation = SettlementMilestoneEditorPresentation(
                                    caseItem: caseItem,
                                    milestone: milestone
                                )
                            } label: {
                                Label("Edit milestone", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                deleteMilestone(milestone)
                            } label: {
                                Label("Delete milestone", systemImage: "trash")
                            }
                        }

                        if milestone.id != caseItem.sortedMilestones.last?.id {
                            Divider()
                                .padding(.leading, 48)
                        }
                    }
                }
                .padding(14)
                .transactionSectionGlassSurface(cornerRadius: FloatTheme.controlRadius)
            }
        }
    }

    @ViewBuilder
    private var linkedTransactionsSection: some View {
        let paymentEntries = caseItem.sortedEntries.filter { $0.kind == .payment }
        if !paymentEntries.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Linked transactions")
                VStack(spacing: 6) {
                    ForEach(paymentEntries) { entry in
                        SettlementLinkedTransactionRow(
                            entry: entry,
                            currencyCode: caseCurrencyCode
                        )
                        .contentShape(Rectangle())
                        .contextMenu {
                            Button {
                                transactionLinkEntry = entry
                            } label: {
                                Label("Link transaction", systemImage: "link")
                            }
                            if entry.linkedTransaction != nil {
                                Button(role: .destructive) {
                                    unlinkTransaction(from: entry)
                                } label: {
                                    Label("Unlink transaction", systemImage: "link.badge.minus")
                                }
                            }
                        }

                        if entry.id != paymentEntries.last?.id {
                            Divider()
                                .padding(.leading, 48)
                        }
                    }
                }
                .padding(14)
                .transactionSectionGlassSurface(cornerRadius: FloatTheme.controlRadius)
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
                            if entry.kind == .payment {
                                Button {
                                    transactionLinkEntry = entry
                                } label: {
                                    Label("Link existing transaction", systemImage: "link")
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
                kind: entry.kind,
                milestone: nil
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

    private func unlinkTransaction(from entry: SettlementEntryItem) {
        try? SettlementCaseRepository(modelContext: modelContext).linkTransaction(nil, to: entry)
        Haptics.confirm()
    }

    private func deleteMilestone(_ milestone: SettlementMilestoneItem) {
        try? SettlementCaseRepository(modelContext: modelContext).deleteMilestone(milestone)
        Haptics.confirm()
    }

    private func matchingTransactions(for entry: SettlementEntryItem) -> [TransactionItem] {
        let isExpense = linkedTransactionIsExpense(for: entry)
        let dayRange = Calendar.current.dateInterval(of: .day, for: entry.entryDate)
        let nearby = transactions.filter { transaction in
            transaction.isPosted
                && transaction.isExpense == isExpense
                && transaction.id != entry.linkedTransaction?.id
        }
        return nearby.sorted { lhs, rhs in
            let lhsScore = transactionMatchScore(lhs, entry: entry, dayRange: dayRange)
            let rhsScore = transactionMatchScore(rhs, entry: entry, dayRange: dayRange)
            if lhsScore == rhsScore {
                return lhs.timestamp > rhs.timestamp
            }
            return lhsScore > rhsScore
        }
        .prefix(20)
        .map { $0 }
    }

    private func transactionMatchScore(
        _ transaction: TransactionItem,
        entry: SettlementEntryItem,
        dayRange: DateInterval?
    ) -> Int {
        var score = 0
        if transaction.amountMinor == entry.amountMinor {
            score += 6
        }
        if dayRange?.contains(transaction.timestamp) == true {
            score += 3
        }
        if let personID = caseItem.person?.id,
           transaction.personTags.contains(where: { $0.person?.id == personID }) {
            score += 2
        }
        return score
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
    let milestone: SettlementMilestoneItem?
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

                if entry.kind == .payment {
                    Label(entry.reconciliationStatus.title, systemImage: entry.linkedTransaction == nil ? "link.badge.plus" : "link")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(reconciliationTint)
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

    private var reconciliationTint: Color {
        switch entry.reconciliationStatus {
        case .unlinked:
            Color(hex: "#B4613B")
        case .partiallyLinked:
            Color(hex: "#8B5CF6")
        case .fullyLinked:
            Color(hex: "#1B8A5A")
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

private struct SettlementMilestoneEditorPresentation: Identifiable {
    let id = UUID()
    let caseItem: SettlementCaseItem
    let milestone: SettlementMilestoneItem?
}

private struct SettlementMilestoneRow: View {
    let milestone: SettlementMilestoneItem
    let currencyCode: String

    var body: some View {
        HStack(spacing: 12) {
            FloatIconBadge(icon: icon, tint: tint, size: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(milestone.displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(milestone.dueDate.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let note = cleaned(milestone.note) {
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(Color.primary.opacity(0.62))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                Text(MoneyFormatter.string(minorUnits: milestone.amountMinor, currencyCode: currencyCode))
                    .moneyStyle(size: 15, weight: .semibold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                SettlementStatusPill(title: milestone.status.title, tint: tint)
            }
        }
        .padding(.vertical, 5)
    }

    private var tint: Color {
        switch milestone.status {
        case .pending: Color(hex: "#B4613B")
        case .paid: Color(hex: "#1B8A5A")
        case .skipped: Color(hex: "#5A6B6B")
        }
    }

    private var icon: String {
        switch milestone.status {
        case .pending: "calendar.badge.clock"
        case .paid: "checkmark.circle.fill"
        case .skipped: "forward.end.fill"
        }
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

private struct SettlementLinkedTransactionRow: View {
    let entry: SettlementEntryItem
    let currencyCode: String

    var body: some View {
        HStack(spacing: 12) {
            FloatIconBadge(icon: icon, tint: tint, size: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(entry.entryDate.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let transaction = entry.linkedTransaction {
                    Text(cleaned(transaction.note) ?? transaction.categoryName)
                        .font(.caption2)
                        .foregroundStyle(Color.primary.opacity(0.62))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                Text(MoneyFormatter.string(minorUnits: entry.amountMinor, currencyCode: currencyCode))
                    .moneyStyle(size: 15, weight: .semibold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                SettlementStatusPill(title: entry.reconciliationStatus.title, tint: tint)
            }
        }
        .padding(.vertical, 5)
    }

    private var title: LocalizedStringResource {
        entry.linkedTransaction == nil ? "Unlinked payment" : "Linked payment"
    }

    private var icon: String {
        entry.linkedTransaction == nil ? "link.badge.plus" : "link"
    }

    private var tint: Color {
        switch entry.reconciliationStatus {
        case .unlinked: Color(hex: "#B4613B")
        case .partiallyLinked: Color(hex: "#8B5CF6")
        case .fullyLinked: Color(hex: "#1B8A5A")
        }
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
    @Query(sort: \PersonItem.name) private var people: [PersonItem]
    let caseItem: SettlementCaseItem?
    @State private var title = ""
    @State private var personName = ""
    @State private var selectedPersonID: UUID?
    @State private var direction = SettlementDirection.theyOweYou
    @State private var amountText = ""
    @State private var date = Date()
    @State private var hasDueDate = false
    @State private var dueDate = Date()
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
                    if !activePeople.isEmpty {
                        Picker("Person", selection: $selectedPersonID) {
                            Text("Custom person").tag(UUID?.none)
                            ForEach(activePeople) { person in
                                Text(person.name).tag(Optional(person.id))
                            }
                        }
                    }
                    if selectedPersonID == nil {
                        TextField("Person name", text: $personName)
                    }
                    Picker("Direction", selection: $direction) {
                        ForEach(SettlementDirection.allCases) { direction in
                            Text(direction.title).tag(direction)
                        }
                    }
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    Toggle("Set due date", isOn: $hasDueDate)
                    if hasDueDate {
                        DatePicker("Due date", selection: $dueDate, displayedComponents: .date)
                    }
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
        selectedPersonID = caseItem.person?.id
        direction = caseItem.direction
        date = caseItem.createdAt
        if let existingDueDate = caseItem.dueDate {
            hasDueDate = true
            dueDate = existingDueDate
        }
        note = caseItem.note ?? ""
        amountText = decimalText(for: caseItem.balanceSnapshot.initialAmountMinor)
    }

    private func save() {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanPersonName = personName.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedPerson = selectedPersonID.flatMap { id in
            activePeople.first { $0.id == id } ?? people.first { $0.id == id }
        }
        guard !cleanTitle.isEmpty else {
            validationMessage = String(localized: "Enter a title.")
            return
        }
        guard selectedPerson != nil || !cleanPersonName.isEmpty else {
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
                    note: note,
                    person: selectedPerson,
                    dueDate: hasDueDate ? dueDate : nil
                )
            } else {
                _ = try repository.create(
                    title: cleanTitle,
                    personName: selectedPerson?.name ?? cleanPersonName,
                    direction: direction,
                    initialAmountMinor: amountMinor,
                    date: date,
                    currencyCode: appState.selectedCurrencyCode,
                    note: note,
                    person: selectedPerson,
                    dueDate: hasDueDate ? dueDate : nil
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

    private var activePeople: [PersonItem] {
        people.filter { !$0.archived }
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
    let milestone: SettlementMilestoneItem?
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
                    if let milestone, entry == nil {
                        LabeledContent("Milestone") {
                            Text(milestone.displayTitle)
                        }
                    }
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
            if let milestone, kind == .payment {
                amountText = decimalText(for: milestone.amountMinor)
                entryDate = milestone.dueDate
                note = milestone.note ?? ""
            }
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
            } else if kind == .payment, let milestone {
                _ = try repository.recordPayment(
                    to: caseItem,
                    milestone: milestone,
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

private struct SettlementMilestoneEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let caseItem: SettlementCaseItem
    let milestone: SettlementMilestoneItem?
    @State private var title = ""
    @State private var amountText = ""
    @State private var dueDate = Date()
    @State private var note = ""
    @State private var status = SettlementMilestoneStatus.pending
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
                Section("Milestone") {
                    TextField("Title", text: $title)
                    HStack {
                        TextField("Amount", text: $amountText)
                            .keyboardType(.decimalPad)
                        SettlementAmountPreview(
                            minorUnits: amountMinor,
                            currencyCode: caseItem.currencyCode
                        )
                    }
                    DatePicker("Due date", selection: $dueDate, displayedComponents: .date)
                    Picker("Status", selection: $status) {
                        ForEach(SettlementMilestoneStatus.allCases) { status in
                            Text(status.title).tag(status)
                        }
                    }
                    TextField("Note", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                }

                if let validationMessage {
                    Section {
                        Text(validationMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(milestone == nil ? "New milestone" : "Edit milestone")
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
        guard let milestone else { return }
        title = milestone.title
        amountText = decimalText(for: milestone.amountMinor)
        dueDate = milestone.dueDate
        note = milestone.note ?? ""
        status = milestone.status
    }

    private func save() {
        guard amountMinor > 0 else {
            validationMessage = String(localized: "Enter an amount.")
            return
        }
        do {
            let repository = SettlementCaseRepository(modelContext: modelContext)
            if let milestone {
                try repository.updateMilestone(
                    milestone,
                    title: title,
                    amountMinor: amountMinor,
                    dueDate: dueDate,
                    note: note,
                    status: status
                )
            } else {
                _ = try repository.addMilestone(
                    to: caseItem,
                    title: title,
                    amountMinor: amountMinor,
                    dueDate: dueDate,
                    note: note
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
}

private struct SettlementTransactionLinkView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let entry: SettlementEntryItem
    let transactions: [TransactionItem]

    var body: some View {
        NavigationStack {
            List {
                if let linkedTransaction = entry.linkedTransaction {
                    Section("Current") {
                        transactionButton(linkedTransaction, isSelected: true)
                        Button(role: .destructive) {
                            link(nil)
                        } label: {
                            Label("Unlink transaction", systemImage: "link.badge.minus")
                        }
                    }
                }

                Section("Matches") {
                    if transactions.isEmpty {
                        Text("No matching transactions")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(transactions) { transaction in
                            transactionButton(
                                transaction,
                                isSelected: transaction.id == entry.linkedTransaction?.id
                            )
                        }
                    }
                }
            }
            .navigationTitle("Link transaction")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func transactionButton(
        _ transaction: TransactionItem,
        isSelected: Bool
    ) -> some View {
        Button {
            link(transaction)
        } label: {
            HStack(spacing: 12) {
                FloatIconBadge(
                    icon: transaction.categoryIconKey,
                    tint: Color(hex: transaction.categoryColorHex),
                    size: 34
                )
                VStack(alignment: .leading, spacing: 3) {
                    Text(transactionTitle(transaction))
                        .font(.subheadline.weight(.semibold))
                    Text(transaction.timestamp.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(MoneyFormatter.string(
                    minorUnits: transaction.amountMinor,
                    currencyCode: entry.caseItem?.currencyCode ?? "USD"
                ))
                .moneyStyle(size: 14, weight: .semibold)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color(hex: "#1B8A5A"))
                }
            }
        }
    }

    private func link(_ transaction: TransactionItem?) {
        try? SettlementCaseRepository(modelContext: modelContext).linkTransaction(transaction, to: entry)
        Haptics.confirm()
        dismiss()
    }

    private func transactionTitle(_ transaction: TransactionItem) -> String {
        let trimmed = transaction.note?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed ?? transaction.categoryName : transaction.categoryName
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

func settlementWorkflowTint(for status: SettlementWorkflowStatus) -> Color {
    switch status {
    case .active:
        Color(hex: "#3B82F6")
    case .dueSoon:
        Color(hex: "#B4613B")
    case .overdue:
        Color(hex: "#B91C1C")
    case .settled:
        Color(hex: "#1B8A5A")
    case .archived:
        Color(hex: "#5A6B6B")
    }
}
