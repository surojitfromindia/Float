import SwiftData
import SwiftUI

struct BulkTransactionEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @Query(sort: \CategoryItem.sortOrder) private var categories: [CategoryItem]
    @Query(sort: \AccountItem.createdAt) private var accounts: [AccountItem]
    @Query(sort: \TransactionTemplateGroupItem.createdAt, order: .reverse)
    private var groups: [TransactionTemplateGroupItem]
    @Query(sort: \TransactionTemplateItem.createdAt, order: .reverse)
    private var templates: [TransactionTemplateItem]

    private let initialSplitAmountMinor: Int64?
    private let initialSplitTimestamp: Date?
    private let onCreate: (() -> Void)?

    @State private var mode: BulkEntryMode
    @State private var selectedGroup: TransactionTemplateGroupItem?
    @State private var groupDraftEntries: [BulkGroupDraftEntry] = []
    @State private var selectedTemplateIDs = Set<UUID>()
    @State private var splitAmountText = ""
    @State private var splitRows: [RatioSplitDraftRow] = RatioSplitDraftRow.defaultRows()
    @State private var splitSelectedAccount: AccountItem?
    @State private var splitTimestamp = Date()
    @State private var splitCategoryPickerRowID: UUID?
    @State private var message: String?

    init(
        initialSplitAmountMinor: Int64? = nil,
        initialSplitTimestamp: Date? = nil,
        onCreate: (() -> Void)? = nil
    ) {
        self.initialSplitAmountMinor = initialSplitAmountMinor
        self.initialSplitTimestamp = initialSplitTimestamp
        self.onCreate = onCreate
        _mode = State(initialValue: initialSplitAmountMinor == nil ? .groups : .split)
    }

    private var selectedTemplates: [TransactionTemplateItem] {
        switch mode {
        case .groups:
            return selectedGroupTemplates
        case .templates:
            return templates.filter { selectedTemplateIDs.contains($0.id) }
        case .split:
            return []
        }
    }

    private var selectedGroupTemplates: [TransactionTemplateItem] {
        groupDraftEntries.flatMap { entry -> [TransactionTemplateItem] in
            guard let template = template(for: entry.templateID) else { return [] }
            return Array(repeating: template, count: max(1, entry.multiplier))
        }
    }

    private var validSelectedTemplates: [TransactionTemplateItem] {
        selectedTemplates.filter {
            $0.amountMinor > 0 && $0.category != nil && $0.account != nil
        }
    }

    private var splitAmountMinor: Int64 {
        MoneyParser.parseDisplayAmountMinor(
            from: splitAmountText,
            currencyCode: appState.selectedCurrencyCode
        )
    }

    private var splitRatios: [Int] {
        splitRows.map { Int($0.ratioText) ?? 0 }
    }

    private var splitAmounts: [Int64] {
        RatioSplitCalculator.amounts(
            totalMinor: splitAmountMinor,
            ratios: splitRatios
        )
    }

    private var canCreate: Bool {
        switch mode {
        case .groups, .templates:
            return !validSelectedTemplates.isEmpty
        case .split:
            return splitValidationMessage == nil
        }
    }

    private var confirmationTitle: String {
        switch mode {
        case .groups, .templates:
            return "Create"
        case .split:
            return "Create \(splitRows.count)"
        }
    }

    private var splitValidationMessage: String? {
        guard splitAmountMinor > 0 else {
            return "Enter a total amount greater than zero."
        }
        guard splitRows.count >= 2 else {
            return "Add at least two split rows."
        }
        guard splitRatios.allSatisfy({ $0 > 0 }) else {
            return "Ratios must be greater than zero."
        }
        guard splitAmounts.count == splitRows.count,
              splitAmounts.allSatisfy({ $0 > 0 })
        else {
            return "Each split needs a non-zero amount."
        }
        guard splitRows.allSatisfy({ row in
            guard let category = row.category else { return false }
            let wantsIncome = !row.isExpense
            return !category.archived && category.isIncome == wantsIncome
        }) else {
            return "Choose a category for every split row."
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("Bulk mode", selection: $mode) {
                        Text("Groups").tag(BulkEntryMode.groups)
                        Text("Templates").tag(BulkEntryMode.templates)
                        Text("Split").tag(BulkEntryMode.split)
                    }
                    .pickerStyle(.segmented)

                    switch mode {
                    case .groups:
                        groupPicker
                    case .templates:
                        templatePicker
                    case .split:
                        splitEditor
                    }

                    previewSection

                    if let message {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(Color(hex: "#B4613B"))
                    }
                }
                .padding(20)
                .padding(.bottom, 24)
            }
            .navigationTitle("Bulk Add")
            .navigationBarTitleDisplayMode(.inline)
            .floatBackground()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(confirmationTitle, action: create)
                        .disabled(!canCreate)
                }
            }
            .onAppear {
                configureSplitDefaults()
                if mode == .groups, selectedGroup == nil, let group = groups.first {
                    select(group)
                }
            }
            .onChange(of: mode) { _, _ in
                message = nil
                configureSplitDefaults()
            }
            .sheet(
                item: Binding(
                    get: { splitCategoryPickerPresentation },
                    set: { splitCategoryPickerRowID = $0?.row.id }
                )
            ) { presentation in
                RatioSplitCategoryPickerSheet(
                    title: presentation.row.isExpense
                        ? "Expense Category"
                        : "Income Category",
                    categories: visibleSplitCategories(isExpense: presentation.row.isExpense),
                    selectedCategory: Binding(
                        get: {
                            splitRows.first { $0.id == presentation.row.id }?.category
                        },
                        set: { category in
                            setCategory(category, for: presentation.row.id)
                        }
                    )
                )
            }
        }
    }

    @ViewBuilder
    private var groupPicker: some View {
        if groups.isEmpty {
            GlassCard {
                EmptyStateView(
                    icon: "square.stack.3d.up.slash",
                    title: "No groups",
                    message: "Create template groups from Settings."
                )
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Groups")
                ForEach(groups) { group in
                    Button {
                        select(group)
                    } label: {
                        BulkGroupCard(
                            group: group,
                            currencyCode: appState.selectedCurrencyCode,
                            isSelected: selectedGroup?.id == group.id
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var templatePicker: some View {
        if templates.isEmpty {
            GlassCard {
                EmptyStateView(
                    icon: "square.text.square",
                    title: "No templates",
                    message: "Create templates before using bulk entry."
                )
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Templates")
                ForEach(templates) { template in
                    Button {
                        toggle(template)
                    } label: {
                        BulkTemplateSelectionRow(
                            template: template,
                            currencyCode: appState.selectedCurrencyCode,
                            isSelected: selectedTemplateIDs.contains(template.id)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var splitEditor: some View {
        VStack(alignment: .leading, spacing: 14) {
            splitAmountCard

            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Ratios")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(RatioSplitPreset.defaults) { preset in
                            Button {
                                apply(preset)
                            } label: {
                                RatioPresetChip(
                                    preset: preset,
                                    isSelected: preset.matches(rows: splitRows)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Will create", actionTitle: "Add row") {
                    addSplitRow()
                }
                GlassCard {
                    VStack(spacing: 14) {
                        ForEach(Array(splitRows.enumerated()), id: \.element.id) { index, row in
                            RatioSplitRowEditor(
                                row: binding(for: row.id),
                                amountMinor: splitAmount(at: index),
                                currencyCode: appState.selectedCurrencyCode,
                                palette: appState.themePalette,
                                canRemove: splitRows.count > 2,
                                moveUp: index > 0 ? { moveSplitRow(from: index, to: index - 1) } : nil,
                                moveDown: index < splitRows.count - 1 ? { moveSplitRow(from: index, to: index + 1) } : nil,
                                chooseCategory: {
                                    splitCategoryPickerRowID = row.id
                                },
                                remove: {
                                    removeSplitRow(row.id)
                                }
                            )
                            if index < splitRows.count - 1 {
                                Divider()
                            }
                        }
                    }
                }
            }

            GlassCard {
                VStack(spacing: 14) {
                    AccountPicker(
                        selectedAccount: $splitSelectedAccount,
                        accounts: accounts.filter { !$0.archived }
                    )
                    Divider()
                    DatePicker(
                        "Date",
                        selection: $splitTimestamp,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }
            }
        }
    }

    private var splitAmountCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Total amount")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(
                            MoneyFormatter.string(
                                minorUnits: splitAmountMinor,
                                currencyCode: appState.selectedCurrencyCode
                            )
                        )
                        .moneyStyle(size: 30, weight: .bold)
                        .contentTransition(.numericText())
                    }
                    Spacer(minLength: 12)
                    Text("\(splitRows.count) transactions")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(appState.themePalette.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            appState.themePalette.accent.opacity(0.12),
                            in: RoundedRectangle(
                                cornerRadius: FloatTheme.tileRadius,
                                style: .continuous
                            )
                        )
                }

                TextField("Amount", text: $splitAmountText)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.plain)
                    .font(.title3.monospacedDigit().weight(.semibold))
                    .padding(14)
                    .background(
                        Color.primary.opacity(0.06),
                        in: RoundedRectangle(
                            cornerRadius: FloatTheme.tileRadius,
                            style: .continuous
                        )
                    )
            }
        }
    }

    @ViewBuilder
    private var previewSection: some View {
        switch mode {
        case .groups:
            if !groupDraftEntries.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Will create")
                    GlassCard {
                        VStack(spacing: 14) {
                            ForEach($groupDraftEntries) { $entry in
                                if let template = template(for: entry.templateID) {
                                    BulkGroupDraftRow(
                                        entry: $entry,
                                        template: template,
                                        templates: templates,
                                        currencyCode: appState.selectedCurrencyCode
                                    )
                                    if entry.id != groupDraftEntries.last?.id {
                                        Divider()
                                    }
                                }
                            }
                        }
                    }
                }
            }
        case .templates:
            if !selectedTemplates.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Will create")
                    GlassCard {
                        VStack(spacing: 12) {
                            ForEach(Array(selectedTemplates.enumerated()), id: \.offset) { index, template in
                                BulkTemplateSummaryRow(
                                    template: template,
                                    currencyCode: appState.selectedCurrencyCode
                                )
                                if index < selectedTemplates.count - 1 {
                                    Divider()
                                }
                            }
                        }
                    }
                }
            }
        case .split:
            EmptyView()
        }
    }

    private func select(_ group: TransactionTemplateGroupItem) {
        selectedGroup = group
        groupDraftEntries = group.validTemplates.map { template in
            BulkGroupDraftEntry(templateID: template.id)
        }
        message = nil
        Haptics.tick()
    }

    private func toggle(_ template: TransactionTemplateItem) {
        if selectedTemplateIDs.contains(template.id) {
            selectedTemplateIDs.remove(template.id)
        } else {
            selectedTemplateIDs.insert(template.id)
        }
        message = nil
        Haptics.tick()
    }

    private func create() {
        switch mode {
        case .groups, .templates:
            createTransactions()
        case .split:
            createSplitTransactions()
        }
    }

    private func createTransactions() {
        let invalidCount = selectedTemplates.count - validSelectedTemplates.count
        do {
            let createdCount = try TransactionRepository(modelContext: modelContext)
                .createMany(from: validSelectedTemplates, timestamp: Date())
            guard createdCount > 0 else {
                message = "Select templates with an amount, category, and account."
                return
            }
            Haptics.confirm()
            if invalidCount > 0 {
                message = "Created \(createdCount). Skipped \(invalidCount) incomplete templates."
            }
            dismiss()
        } catch {
            message = error.localizedDescription
        }
    }

    private func createSplitTransactions() {
        if let splitValidationMessage {
            message = splitValidationMessage
            return
        }

        let account = splitSelectedAccount ?? DefaultAccountResolver.resolve(
            preferredID: appState.lastUsedAccountID,
            accounts: accounts,
            modelContext: modelContext,
            currencyCode: appState.selectedCurrencyCode
        )

        let drafts = zip(splitRows, splitAmounts).compactMap { row, amount -> TransactionDraft? in
            guard let category = row.category else { return nil }
            return TransactionDraft(
                amountMinor: amount,
                isExpense: row.isExpense,
                timestamp: splitTimestamp,
                category: category,
                account: account,
                note: row.note
            )
        }

        do {
            let createdCount = try TransactionRepository(modelContext: modelContext)
                .createMany(from: drafts)
            guard createdCount == splitRows.count else {
                message = "Choose a category for every split row."
                return
            }
            appState.lastUsedAccountID = account.id.uuidString
            if let category = splitRows.last?.category {
                appState.lastUsedCategoryID = category.id.uuidString
            }
            Haptics.confirm()
            dismiss()
            onCreate?()
        } catch {
            message = error.localizedDescription
        }
    }

    private func configureSplitDefaults() {
        guard mode == .split else { return }

        if let initialSplitAmountMinor, splitAmountText.isEmpty {
            splitAmountText = displayAmountText(for: initialSplitAmountMinor)
        }

        if let initialSplitTimestamp,
           Calendar.current.compare(splitTimestamp, to: Date(), toGranularity: .second) == .orderedSame {
            splitTimestamp = initialSplitTimestamp
        }

        if splitSelectedAccount == nil {
            splitSelectedAccount = accounts.first {
                !$0.archived && $0.id.uuidString == appState.lastUsedAccountID
            } ?? accounts.first { !$0.archived }
        }

        for index in splitRows.indices where splitRows[index].category == nil {
            splitRows[index].category = defaultCategory(isExpense: splitRows[index].isExpense)
        }
    }

    private var splitCategoryPickerPresentation: RatioSplitCategoryPickerPresentation? {
        guard let rowID = splitCategoryPickerRowID,
              let row = splitRows.first(where: { $0.id == rowID })
        else {
            return nil
        }
        return RatioSplitCategoryPickerPresentation(row: row)
    }

    private func splitAmount(at index: Int) -> Int64 {
        guard splitAmounts.indices.contains(index) else { return 0 }
        return splitAmounts[index]
    }

    private func binding(for rowID: UUID) -> Binding<RatioSplitDraftRow> {
        Binding(
            get: {
                splitRows.first { $0.id == rowID } ?? RatioSplitDraftRow()
            },
            set: { newValue in
                guard let index = splitRows.firstIndex(where: { $0.id == rowID }) else {
                    return
                }
                var updated = newValue
                if let category = updated.category,
                   category.isIncome != (!updated.isExpense) {
                    updated.category = defaultCategory(isExpense: updated.isExpense)
                }
                splitRows[index] = updated
                message = nil
            }
        )
    }

    private func apply(_ preset: RatioSplitPreset) {
        splitRows = preset.parts.enumerated().map { index, part in
            let existing = splitRows.indices.contains(index) ? splitRows[index] : nil
            let isExpense = existing?.isExpense ?? true
            return RatioSplitDraftRow(
                ratioText: String(part),
                isExpense: isExpense,
                category: existing?.category ?? defaultCategory(isExpense: isExpense),
                note: existing?.note ?? ""
            )
        }
        message = nil
        Haptics.tick()
    }

    private func addSplitRow() {
        let isExpense = splitRows.last?.isExpense ?? true
        splitRows.append(
            RatioSplitDraftRow(
                isExpense: isExpense,
                category: defaultCategory(isExpense: isExpense)
            )
        )
        message = nil
        Haptics.tick()
    }

    private func removeSplitRow(_ rowID: UUID) {
        guard splitRows.count > 2 else { return }
        splitRows.removeAll { $0.id == rowID }
        message = nil
        Haptics.tick()
    }

    private func moveSplitRow(from source: Int, to destination: Int) {
        guard splitRows.indices.contains(source),
              splitRows.indices.contains(destination)
        else {
            return
        }
        let row = splitRows.remove(at: source)
        splitRows.insert(row, at: destination)
        Haptics.tick()
    }

    private func setCategory(_ category: CategoryItem?, for rowID: UUID) {
        guard let index = splitRows.firstIndex(where: { $0.id == rowID }) else {
            return
        }
        splitRows[index].category = category
        message = nil
    }

    private func visibleSplitCategories(isExpense: Bool) -> [CategoryItem] {
        let wantsIncome = !isExpense
        return categories.filter { !$0.archived && $0.isIncome == wantsIncome }
    }

    private func defaultCategory(isExpense: Bool) -> CategoryItem? {
        let wantsIncome = !isExpense
        return categories.first {
            !$0.archived
                && $0.isIncome == wantsIncome
                && $0.id.uuidString == appState.lastUsedCategoryID
        } ?? categories.first {
            !$0.archived
                && $0.isIncome == wantsIncome
                && (isExpense
                    ? $0.name.localizedCaseInsensitiveCompare("Other") == .orderedSame
                    : $0.name.localizedCaseInsensitiveCompare("Salary") == .orderedSame)
        } ?? categories.first {
            !$0.archived && $0.isIncome == wantsIncome
        }
    }

    private func displayAmountText(for minorUnits: Int64) -> String {
        let fractionDigits = MoneyFormatter.fractionDigits(for: appState.selectedCurrencyCode)
        guard fractionDigits > 0 else { return String(minorUnits) }

        let divisor = Decimal(pow(10.0, Double(fractionDigits)))
        let value = Decimal(minorUnits) / divisor
        return NSDecimalNumber(decimal: value).stringValue
    }

    private func template(for id: UUID) -> TransactionTemplateItem? {
        templates.first { $0.id == id }
    }
}

private enum BulkEntryMode: String, CaseIterable {
    case groups
    case templates
    case split
}

private struct RatioSplitDraftRow: Identifiable {
    let id: UUID
    var ratioText: String
    var isExpense: Bool
    var category: CategoryItem?
    var note: String

    init(
        id: UUID = UUID(),
        ratioText: String = "1",
        isExpense: Bool = true,
        category: CategoryItem? = nil,
        note: String = ""
    ) {
        self.id = id
        self.ratioText = ratioText
        self.isExpense = isExpense
        self.category = category
        self.note = note
    }

    static func defaultRows() -> [RatioSplitDraftRow] {
        [
            RatioSplitDraftRow(ratioText: "1", isExpense: true),
            RatioSplitDraftRow(ratioText: "2", isExpense: false),
        ]
    }
}

private struct RatioSplitPreset: Identifiable {
    let id: String
    let parts: [Int]

    var title: String {
        parts.map(String.init).joined(separator: ":")
    }

    static let defaults = [
        RatioSplitPreset(id: "1-1", parts: [1, 1]),
        RatioSplitPreset(id: "1-2", parts: [1, 2]),
        RatioSplitPreset(id: "2-1", parts: [2, 1]),
        RatioSplitPreset(id: "1-1-1", parts: [1, 1, 1]),
        RatioSplitPreset(id: "2-3", parts: [2, 3]),
    ]

    func matches(rows: [RatioSplitDraftRow]) -> Bool {
        rows.map { Int($0.ratioText) ?? 0 } == parts
    }
}

private struct RatioSplitCategoryPickerPresentation: Identifiable {
    let row: RatioSplitDraftRow
    var id: UUID { row.id }
}

private struct RatioPresetChip: View {
    let preset: RatioSplitPreset
    let isSelected: Bool

    var body: some View {
        Text(preset.title)
            .font(.subheadline.monospacedDigit().weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                isSelected
                    ? Color(hex: "#0E7C7B").opacity(0.2)
                    : Color.primary.opacity(0.06),
                in: RoundedRectangle(
                    cornerRadius: FloatTheme.tileRadius,
                    style: .continuous
                )
            )
            .foregroundStyle(isSelected ? Color(hex: "#0E7C7B") : .primary)
    }
}

private struct RatioSplitRowEditor: View {
    @Binding var row: RatioSplitDraftRow
    let amountMinor: Int64
    let currencyCode: String
    let palette: FloatThemePalette
    let canRemove: Bool
    let moveUp: (() -> Void)?
    let moveDown: (() -> Void)?
    let chooseCategory: () -> Void
    let remove: () -> Void

    private var tint: Color {
        row.isExpense ? palette.caution : palette.positive
    }

    private var amountText: String {
        MoneyFormatter.string(
            minorUnits: amountMinor,
            currencyCode: currencyCode,
            showsSign: !row.isExpense
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text(amountText)
                    .moneyStyle(size: 18, weight: .bold)
                    .foregroundStyle(row.isExpense ? .primary : palette.positive)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Spacer(minLength: 8)

                Button {
                    moveUp?()
                } label: {
                    Image(systemName: "chevron.up")
                        .frame(width: 30, height: 30)
                }
                .disabled(moveUp == nil)
                .accessibilityLabel("Move split row up")

                Button {
                    moveDown?()
                } label: {
                    Image(systemName: "chevron.down")
                        .frame(width: 30, height: 30)
                }
                .disabled(moveDown == nil)
                .accessibilityLabel("Move split row down")

                Button(role: .destructive, action: remove) {
                    Image(systemName: "trash")
                        .frame(width: 30, height: 30)
                }
                .disabled(!canRemove)
                .accessibilityLabel("Remove split row")
            }
            .font(.subheadline.weight(.semibold))
            .buttonStyle(.borderless)

            HStack(spacing: 10) {
                TextField("Ratio", text: $row.ratioText)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.plain)
                    .font(.headline.monospacedDigit())
                    .multilineTextAlignment(.center)
                    .frame(width: 64, height: 42)
                    .background(
                        Color.primary.opacity(0.06),
                        in: RoundedRectangle(
                            cornerRadius: FloatTheme.tileRadius,
                            style: .continuous
                        )
                    )

                Picker("Type", selection: $row.isExpense) {
                    Text("Expense").tag(true)
                    Text("Income").tag(false)
                }
                .pickerStyle(.segmented)
            }

            Button(action: chooseCategory) {
                HStack(spacing: 12) {
                    FloatIconBadge(
                        icon: row.category?.iconKey ?? "square.grid.2x2.fill",
                        tint: row.category.map { Color(hex: $0.colorHex) } ?? tint,
                        size: 36
                    )
                    VStack(alignment: .leading, spacing: 3) {
                        Text(row.category?.name ?? "Choose category")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(row.isExpense ? "Expense category" : "Income category")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(
                    tint.opacity(0.08),
                    in: RoundedRectangle(
                        cornerRadius: FloatTheme.tileRadius,
                        style: .continuous
                    )
                )
            }
            .buttonStyle(.plain)

            TextField("Note", text: $row.note, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...2)
                .padding(12)
                .background(
                    Color.primary.opacity(0.05),
                    in: RoundedRectangle(
                        cornerRadius: FloatTheme.tileRadius,
                        style: .continuous
                    )
                )
        }
    }
}

private struct RatioSplitCategoryPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let categories: [CategoryItem]
    @Binding var selectedCategory: CategoryItem?
    @State private var searchText = ""

    private var filteredCategories: [CategoryItem] {
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSearch.isEmpty else { return categories }
        return categories.filter {
            $0.name.localizedCaseInsensitiveContains(trimmedSearch)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if filteredCategories.isEmpty {
                    EmptyStateView(
                        icon: "magnifyingglass",
                        title: "No categories",
                        message: "Try a different search."
                    )
                } else {
                    ForEach(filteredCategories) { category in
                        Button {
                            selectedCategory = category
                            Haptics.tick()
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                FloatIconBadge(
                                    icon: category.iconKey,
                                    tint: Color(hex: category.colorHex),
                                    size: 36
                                )
                                Text(category.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Spacer()
                                if selectedCategory?.id == category.id {
                                    Image(systemName: "checkmark")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Color(hex: category.colorHex))
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search categories")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

private struct BulkGroupDraftEntry: Identifiable {
    let id: UUID
    var templateID: UUID
    var multiplier: Int

    init(id: UUID = UUID(), templateID: UUID, multiplier: Int = 1) {
        self.id = id
        self.templateID = templateID
        self.multiplier = multiplier
    }
}

struct TransactionTemplateGroupManagerView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @Query(sort: \TransactionTemplateGroupItem.createdAt, order: .reverse)
    private var groups: [TransactionTemplateGroupItem]
    @State private var editorPresentation: TransactionTemplateGroupEditorPresentation?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if groups.isEmpty {
                    GlassCard {
                        EmptyStateView(
                            icon: "square.stack.3d.up",
                            title: "No groups",
                            message: "Create a daily set from your transaction templates."
                        )
                    }
                }

                ForEach(groups) { group in
                    BulkGroupCard(
                        group: group,
                        currencyCode: appState.selectedCurrencyCode,
                        isSelected: false
                    )
                    .contextMenu {
                        Button {
                            editorPresentation =
                                TransactionTemplateGroupEditorPresentation(group: group)
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            delete(group)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .onTapGesture {
                        editorPresentation =
                            TransactionTemplateGroupEditorPresentation(group: group)
                    }
                }
            }
            .padding(20)
            .padding(.bottom, 120)
        }
        .navigationTitle("Template Groups")
        .floatBackground()
        .toolbar {
            Button {
                editorPresentation =
                    TransactionTemplateGroupEditorPresentation(group: nil)
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("Add template group")
        }
        .sheet(item: $editorPresentation) { presentation in
            TransactionTemplateGroupEditorView(group: presentation.group)
        }
    }

    private func delete(_ group: TransactionTemplateGroupItem) {
        try? TransactionTemplateGroupRepository(modelContext: modelContext)
            .delete(group)
    }
}

private struct TransactionTemplateGroupEditorPresentation: Identifiable {
    let id = UUID()
    let group: TransactionTemplateGroupItem?
}

private struct TransactionTemplateGroupEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @Query(sort: \TransactionTemplateItem.createdAt, order: .reverse)
    private var templates: [TransactionTemplateItem]

    let group: TransactionTemplateGroupItem?
    @State private var name = ""
    @State private var orderedEntries: [TemplateGroupEditorEntry] = []
    @State private var validationMessage: String?

    private var selectedTemplates: [TransactionTemplateItem] {
        orderedEntries.compactMap { template(for: $0.templateID) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Group name", text: $name)
                }

                Section("Included") {
                    if orderedEntries.isEmpty {
                        Text("Add templates to this group.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(orderedEntries) { entry in
                            if let template = template(for: entry.templateID) {
                                BulkTemplateSummaryRow(
                                    template: template,
                                    currencyCode: appState.selectedCurrencyCode
                                )
                            }
                        }
                        .onMove { source, destination in
                            orderedEntries.move(
                                fromOffsets: source,
                                toOffset: destination
                            )
                        }
                        .onDelete { offsets in
                            orderedEntries.remove(atOffsets: offsets)
                        }
                    }
                }

                Section("Available") {
                    if templates.isEmpty {
                        Text("No templates available.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(templates) { template in
                            Button {
                                orderedEntries.append(
                                    TemplateGroupEditorEntry(templateID: template.id)
                                )
                                validationMessage = nil
                            } label: {
                                BulkTemplateSummaryRow(
                                    template: template,
                                    currencyCode: appState.selectedCurrencyCode
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if let validationMessage {
                    Text(validationMessage)
                        .font(.footnote)
                        .foregroundStyle(Color(hex: "#B4613B"))
                }
            }
            .navigationTitle(group == nil ? "New Group" : "Edit Group")
            .scrollContentBackground(.hidden)
            .floatBackground()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .principal) {
                    if selectedTemplates.count > 1 {
                        EditButton()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear(perform: configure)
        }
    }

    private func configure() {
        guard name.isEmpty, orderedEntries.isEmpty else { return }
        if let group {
            name = group.name
            orderedEntries = group.validTemplates.map { template in
                TemplateGroupEditorEntry(templateID: template.id)
            }
        }
    }

    private func save() {
        guard !selectedTemplates.isEmpty else {
            validationMessage = "Add at least one template."
            return
        }

        do {
            let repository = TransactionTemplateGroupRepository(modelContext: modelContext)
            if let group {
                try repository.update(
                    group,
                    name: name,
                    templates: selectedTemplates
                )
            } else {
                _ = try repository.create(
                    name: name,
                    templates: selectedTemplates
                )
            }
            dismiss()
        } catch {
            validationMessage = error.localizedDescription
        }
    }

    private func template(for id: UUID) -> TransactionTemplateItem? {
        templates.first { $0.id == id }
    }
}

private struct TemplateGroupEditorEntry: Identifiable {
    let id: UUID
    var templateID: UUID

    init(id: UUID = UUID(), templateID: UUID) {
        self.id = id
        self.templateID = templateID
    }
}

private struct BulkGroupCard: View {
    let group: TransactionTemplateGroupItem
    let currencyCode: String
    let isSelected: Bool

    private var templates: [TransactionTemplateItem] {
        group.validTemplates
    }

    private var totalMinor: Int64 {
        templates.reduce(Int64(0)) { total, template in
            total + (template.isExpense ? template.amountMinor : -template.amountMinor)
        }
    }

    var body: some View {
        GlassCard {
            HStack(spacing: 14) {
                FloatIconBadge(
                    icon: "square.stack.3d.up.fill",
                    tint: Color(hex: "#0E7C7B"),
                    size: 42
                )
                VStack(alignment: .leading, spacing: 5) {
                    Text(group.displayName)
                        .font(.headline)
                        .lineLimit(1)
                    Text("\(templates.count) templates")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text(totalText)
                    .moneyStyle(size: 15, weight: .semibold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color(hex: "#1B8A5A"))
                }
            }
        }
    }

    private var totalText: String {
        let amount = MoneyFormatter.string(
            minorUnits: abs(totalMinor),
            currencyCode: currencyCode
        )
        if totalMinor < 0 {
            return "+\(amount)"
        }
        return amount
    }
}

private struct BulkTemplateSelectionRow: View {
    let template: TransactionTemplateItem
    let currencyCode: String
    let isSelected: Bool

    var body: some View {
        GlassCard(padding: 14) {
            HStack(spacing: 12) {
                BulkTemplateSummaryRow(
                    template: template,
                    currencyCode: currencyCode
                )
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color(hex: "#1B8A5A") : .secondary)
            }
        }
    }
}

private struct BulkGroupDraftRow: View {
    @Binding var entry: BulkGroupDraftEntry
    let template: TransactionTemplateItem
    let templates: [TransactionTemplateItem]
    let currencyCode: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            BulkTemplateSummaryRow(
                template: template,
                currencyCode: currencyCode
            )
            HStack(spacing: 12) {
                Menu {
                    ForEach(templates) { option in
                        Button {
                            entry.templateID = option.id
                        } label: {
                            Label(
                                option.displayTitle,
                                systemImage: option.id == entry.templateID
                                    ? "checkmark"
                                    : "arrow.triangle.2.circlepath"
                            )
                        }
                    }
                } label: {
                    Label("Swap", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption.weight(.semibold))
                }
                .disabled(templates.isEmpty)

                Spacer(minLength: 8)

                Stepper(value: $entry.multiplier, in: 1...99) {
                    Text("Qty \(entry.multiplier)")
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                }
                .fixedSize()
            }
        }
    }
}

private struct BulkTemplateSummaryRow: View {
    let template: TransactionTemplateItem
    let currencyCode: String

    var body: some View {
        HStack(spacing: 12) {
            FloatIconBadge(
                icon: template.category?.iconKey ?? "square.text.square",
                tint: Color(hex: template.category?.colorHex ?? "#0E7C7B"),
                size: 34
            )
            VStack(alignment: .leading, spacing: 3) {
                Text(template.displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(amount)
                .moneyStyle(size: 14, weight: .semibold)
                .foregroundStyle(template.isExpense ? .primary : Color(hex: "#1B8A5A"))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    private var detail: String {
        "\(template.category?.name ?? "Missing Category") • \(template.account?.name ?? "Missing Account")"
    }

    private var amount: String {
        MoneyFormatter.string(
            minorUnits: template.amountMinor,
            currencyCode: currencyCode,
            showsSign: !template.isExpense
        )
    }
}
