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
    private let transactionToReplace: TransactionItem?
    private let onCreate: (() -> Void)?

    @AppStorage("savedRatioSplitPresetsData") private var savedRatioSplitPresetsData = "[]"
    @State private var mode: BulkEntryMode
    @State private var selectedGroup: TransactionTemplateGroupItem?
    @State private var groupDraftEntries: [BulkGroupDraftEntry] = []
    @State private var selectedTemplateIDs = Set<UUID>()
    @State private var splitAmountText = ""
    @State private var splitRows: [RatioSplitDraftRow] = RatioSplitDraftRow.defaultRows()
    @State private var pendingRows: [BulkPendingDraftRow] = BulkPendingDraftRow.defaultRows()
    @State private var splitSelectedAccount: AccountItem?
    @State private var splitTimestamp = Date()
    @State private var splitCategoryPickerRowID: UUID?
    @State private var showingSaveSplitTemplate = false
    @State private var newSplitTemplateName = ""
    @State private var message: String?

    init(
        initialSplitAmountMinor: Int64? = nil,
        initialSplitTimestamp: Date? = nil,
        transactionToReplace: TransactionItem? = nil,
        onCreate: (() -> Void)? = nil
    ) {
        self.initialSplitAmountMinor = initialSplitAmountMinor
            ?? transactionToReplace?.amountMinor
        self.initialSplitTimestamp = initialSplitTimestamp
            ?? transactionToReplace?.timestamp
        self.transactionToReplace = transactionToReplace
        self.onCreate = onCreate
        _mode = State(initialValue: initialSplitAmountMinor == nil && transactionToReplace == nil ? .groups : .split)
        if let transactionToReplace {
            _splitRows = State(
                initialValue: [
                    RatioSplitDraftRow(
                        ratioText: "1",
                        kind: transactionToReplace.isPending
                            ? .pending
                            : (transactionToReplace.isExpense ? .expense : .income),
                        category: transactionToReplace.isPending ? nil : transactionToReplace.category,
                        expectedDueDate: transactionToReplace.expectedDueDate ?? transactionToReplace.timestamp,
                        note: transactionToReplace.note ?? ""
                    ),
                    RatioSplitDraftRow(
                        ratioText: "1",
                        kind: transactionToReplace.isPending
                            ? .pending
                            : (transactionToReplace.isExpense ? .expense : .income),
                        category: transactionToReplace.isPending ? nil : transactionToReplace.category,
                        expectedDueDate: transactionToReplace.expectedDueDate ?? transactionToReplace.timestamp,
                        note: transactionToReplace.note ?? ""
                    ),
                ]
            )
        }
    }

    private var selectedTemplates: [TransactionTemplateItem] {
        switch mode {
        case .groups:
            return selectedGroupTemplates
        case .templates:
            return templates.filter { selectedTemplateIDs.contains($0.id) }
        case .pending:
            return []
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

    private var savedSplitPresets: [SavedRatioSplitPreset] {
        decodeSavedSplitPresets()
    }

    private var splitPresetOptions: [RatioSplitPreset] {
        RatioSplitPreset.defaults
            + savedSplitPresets.map { preset in
                RatioSplitPreset(
                    id: "saved-\(preset.id.uuidString)",
                    title: preset.name,
                    parts: preset.parts,
                    savedID: preset.id
                )
            }
    }

    private var currentSplitRatioText: String {
        splitRatios.map(String.init).joined(separator: ":")
    }

    private var canCreate: Bool {
        switch mode {
        case .groups, .templates:
            return !validSelectedTemplates.isEmpty
        case .pending:
            return pendingValidationMessage == nil
        case .split:
            return splitValidationMessage == nil
        }
    }

    private var confirmationTitle: String {
        switch mode {
        case .groups, .templates:
            return "Create"
        case .pending:
            return "Create \(pendingRows.count)"
        case .split:
            return "Create \(splitRows.count)"
        }
    }

    private var pendingValidationMessage: String? {
        guard !pendingRows.isEmpty else {
            return "Add at least one pending transaction."
        }
        guard pendingRows.allSatisfy({ $0.amountMinor(currencyCode: appState.selectedCurrencyCode) > 0 }) else {
            return "Every pending transaction needs an amount."
        }
        return nil
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
            guard row.kind != .pending else { return true }
            guard let category = row.category else { return false }
            let wantsIncome = row.kind == .income
            return !category.archived && category.isIncome == wantsIncome
        }) else {
            return "Choose a category for every expense or income split row."
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
                        Text("Pending").tag(BulkEntryMode.pending)
                        Text("Split").tag(BulkEntryMode.split)
                    }
                    .pickerStyle(.segmented)

                    switch mode {
                    case .groups:
                        groupPicker
                    case .templates:
                        templatePicker
                    case .pending:
                        pendingEditor
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
            .scrollDismissesKeyboard(.interactively)
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
            .alert("Save Split Template", isPresented: $showingSaveSplitTemplate) {
                TextField("Name", text: $newSplitTemplateName)
                Button("Save", action: saveCurrentSplitTemplate)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Save \(currentSplitRatioText) for quick reuse.")
            }
            .sheet(
                item: Binding(
                    get: { splitCategoryPickerPresentation },
                    set: { splitCategoryPickerRowID = $0?.row.id }
                )
            ) { presentation in
                RatioSplitCategoryPickerSheet(
                    title: presentation.row.kind == .expense
                        ? "Expense Category"
                        : "Income Category",
                    categories: visibleSplitCategories(for: presentation.row.kind),
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
                SectionHeader(
                    title: "Ratios",
                    actionTitle: "Save",
                    action: presentSaveSplitTemplate
                )
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(splitPresetOptions) { preset in
                            Button {
                                apply(preset)
                            } label: {
                                RatioPresetChip(
                                    preset: preset,
                                    isSelected: preset.matches(rows: splitRows)
                                )
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                if let savedID = preset.savedID {
                                    Button(role: .destructive) {
                                        deleteSavedSplitPreset(savedID)
                                    } label: {
                                        Label("Delete Template", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                splitListHeader

                VStack(spacing: 8) {
                    ForEach(Array(splitRows.enumerated()), id: \.element.id) { index, row in
                        RatioSplitRowEditor(
                            row: binding(for: row.id),
                            amountMinor: splitAmount(at: index),
                            currencyCode: appState.selectedCurrencyCode,
                            palette: appState.themePalette,
                            canDelete: splitRows.count > 2,
                            chooseCategory: {
                                splitCategoryPickerRowID = row.id
                            },
                            delete: {
                                removeSplitRow(row.id)
                            }
                        )
                        .transition(
                            .asymmetric(
                                insertion: .scale(scale: 0.96).combined(with: .opacity),
                                removal: .opacity
                            )
                        )
                    }
                }
                .animation(
                    .spring(response: 0.32, dampingFraction: 0.88),
                    value: splitRows.map(\.id)
                )
            }

            if splitRows.contains(where: { $0.kind != .pending }) {
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
    }

    private var pendingEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader(title: "Pending transactions")
                Spacer()
                Button {
                    pendingRows.append(BulkPendingDraftRow())
                    message = nil
                    Haptics.tick()
                } label: {
                    Image(systemName: "plus")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 34, height: 34)
                        .floatGlassCircle(
                            tint: appState.themePalette.accent,
                            interactive: true,
                            strokeOpacity: 0.1
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add pending row")
            }

            VStack(spacing: 8) {
                ForEach($pendingRows) { $row in
                    BulkPendingRowEditor(
                        row: $row,
                        currencyCode: appState.selectedCurrencyCode,
                        canDelete: pendingRows.count > 1,
                        delete: {
                            pendingRows.removeAll { $0.id == row.id }
                            message = nil
                            Haptics.tick()
                        }
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

    private var splitListHeader: some View {
        HStack(spacing: 10) {
            Text("Will create")
                .font(.headline)
            Spacer()
            Button {
                addSplitRow()
            } label: {
                Image(systemName: "plus")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 34, height: 34)
                    .floatGlassCircle(
                        tint: appState.themePalette.accent,
                        interactive: true,
                        strokeOpacity: 0.1
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add split row")
        }
        .foregroundStyle(.primary)
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
        case .pending:
            EmptyView()
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
        case .pending:
            createPendingTransactions()
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

    private func createPendingTransactions() {
        if let pendingValidationMessage {
            message = pendingValidationMessage
            return
        }

        let drafts = pendingRows.map { row in
            PendingTransactionDraft(
                amountMinor: row.amountMinor(currencyCode: appState.selectedCurrencyCode),
                expectedDueDate: row.expectedDueDate,
                note: row.note
            )
        }

        do {
            let createdCount = try TransactionRepository(modelContext: modelContext)
                .createManyPending(from: drafts)
            guard createdCount == pendingRows.count else {
                message = "Every pending transaction needs an amount."
                return
            }
            Haptics.confirm()
            dismiss()
            onCreate?()
        } catch {
            message = error.localizedDescription
        }
    }

    private func createSplitTransactions() {
        if let splitValidationMessage {
            message = splitValidationMessage
            return
        }

        let hasPostedRows = splitRows.contains { $0.kind != .pending }
        let account = hasPostedRows
            ? splitSelectedAccount ?? DefaultAccountResolver.resolve(
                preferredID: appState.lastUsedAccountID,
                accounts: accounts,
                modelContext: modelContext,
                currencyCode: appState.selectedCurrencyCode
            )
            : nil

        let drafts = zip(splitRows, splitAmounts).compactMap { row, amount -> TransactionCreationDraft? in
            switch row.kind {
            case .expense, .income:
                guard let category = row.category,
                      let account
                else {
                    return nil
                }
                return .posted(
                    TransactionDraft(
                        amountMinor: amount,
                        isExpense: row.kind == .expense,
                        timestamp: splitTimestamp,
                        category: category,
                        account: account,
                        note: row.note
                    )
                )
            case .pending:
                return .pending(
                    PendingTransactionDraft(
                        amountMinor: amount,
                        expectedDueDate: row.expectedDueDate,
                        note: row.note
                    )
                )
            }
        }

        guard drafts.count == splitRows.count else {
            message = "Choose a category for every expense or income split row."
            return
        }

        do {
            let repository = TransactionRepository(modelContext: modelContext)
            let createdCount: Int
            if let transactionToReplace {
                createdCount = try repository.replace(transactionToReplace, with: drafts)
            } else {
                createdCount = try repository.createMany(from: drafts)
            }
            guard createdCount == splitRows.count else {
                message = "Choose a category for every expense or income split row."
                return
            }
            if let account {
                appState.lastUsedAccountID = account.id.uuidString
            }
            if let category = splitRows.last(where: { $0.kind != .pending })?.category {
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

        if splitRows.contains(where: { $0.kind != .pending }),
           splitSelectedAccount == nil {
            splitSelectedAccount = transactionToReplace?.account ?? accounts.first {
                !$0.archived && $0.id.uuidString == appState.lastUsedAccountID
            } ?? accounts.first { !$0.archived }
        }

        for index in splitRows.indices where splitRows[index].category == nil {
            splitRows[index].category = defaultCategory(for: splitRows[index].kind)
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
                if updated.kind == .pending {
                    updated.category = nil
                } else if updated.category == nil {
                    updated.category = defaultCategory(for: updated.kind)
                } else if let category = updated.category,
                          category.isIncome != (updated.kind == .income) {
                    updated.category = defaultCategory(for: updated.kind)
                }
                splitRows[index] = updated
                message = nil
            }
        )
    }

    private func apply(_ preset: RatioSplitPreset) {
        splitRows = preset.parts.enumerated().map { index, part in
            let existing = splitRows.indices.contains(index) ? splitRows[index] : nil
            let kind = existing?.kind ?? .expense
            return RatioSplitDraftRow(
                ratioText: String(part),
                kind: kind,
                category: existing?.category ?? defaultCategory(for: kind),
                expectedDueDate: existing?.expectedDueDate ?? Date(),
                note: existing?.note ?? ""
            )
        }
        message = nil
        Haptics.tick()
    }

    private func presentSaveSplitTemplate() {
        guard splitRows.count >= 2,
              splitRatios.allSatisfy({ $0 > 0 })
        else {
            message = "Enter valid ratios before saving a split template."
            return
        }

        if savedSplitPresets.contains(where: { $0.parts == splitRatios }) {
            message = "\(currentSplitRatioText) is already saved."
            return
        }

        newSplitTemplateName = currentSplitRatioText
        showingSaveSplitTemplate = true
    }

    private func saveCurrentSplitTemplate() {
        guard splitRows.count >= 2,
              splitRatios.allSatisfy({ $0 > 0 })
        else {
            message = "Enter valid ratios before saving a split template."
            return
        }

        var presets = savedSplitPresets
        guard !presets.contains(where: { $0.parts == splitRatios }) else {
            message = "\(currentSplitRatioText) is already saved."
            return
        }

        let trimmedName = newSplitTemplateName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let name = trimmedName.isEmpty ? currentSplitRatioText : trimmedName
        presets.insert(
            SavedRatioSplitPreset(name: name, parts: splitRatios),
            at: 0
        )
        encodeSavedSplitPresets(Array(presets.prefix(16)))
        message = "Saved \(name)."
        Haptics.confirm()
    }

    private func deleteSavedSplitPreset(_ id: UUID) {
        let presets = savedSplitPresets.filter { $0.id != id }
        encodeSavedSplitPresets(presets)
        message = "Split template deleted."
        Haptics.tick()
    }

    private func addSplitRow() {
        let kind = splitRows.last?.kind ?? .expense
        splitRows.append(
            RatioSplitDraftRow(
                kind: kind,
                category: defaultCategory(for: kind)
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

    private func setCategory(_ category: CategoryItem?, for rowID: UUID) {
        guard let index = splitRows.firstIndex(where: { $0.id == rowID }) else {
            return
        }
        splitRows[index].category = category
        message = nil
    }

    private func visibleSplitCategories(for kind: RatioSplitKind) -> [CategoryItem] {
        let wantsIncome = kind == .income
        return categories.filter { !$0.archived && $0.isIncome == wantsIncome }
    }

    private func defaultCategory(for kind: RatioSplitKind) -> CategoryItem? {
        guard kind != .pending else { return nil }

        let wantsIncome = kind == .income
        return categories.first {
            !$0.archived
                && $0.isIncome == wantsIncome
                && $0.id.uuidString == appState.lastUsedCategoryID
        } ?? categories.first {
            !$0.archived
                && $0.isIncome == wantsIncome
                && (kind == .expense
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

    private func decodeSavedSplitPresets() -> [SavedRatioSplitPreset] {
        guard let data = savedRatioSplitPresetsData.data(using: .utf8) else {
            return []
        }
        return (try? JSONDecoder().decode([SavedRatioSplitPreset].self, from: data)) ?? []
    }

    private func encodeSavedSplitPresets(_ presets: [SavedRatioSplitPreset]) {
        guard let data = try? JSONEncoder().encode(presets),
              let string = String(data: data, encoding: .utf8)
        else {
            return
        }
        savedRatioSplitPresetsData = string
    }
}

private enum BulkEntryMode: String, CaseIterable {
    case groups
    case templates
    case pending
    case split
}

private struct BulkPendingDraftRow: Identifiable {
    let id: UUID
    var amountText: String
    var expectedDueDate: Date
    var note: String

    init(
        id: UUID = UUID(),
        amountText: String = "",
        expectedDueDate: Date = Date(),
        note: String = ""
    ) {
        self.id = id
        self.amountText = amountText
        self.expectedDueDate = expectedDueDate
        self.note = note
    }

    func amountMinor(currencyCode: String) -> Int64 {
        MoneyParser.parseDisplayAmountMinor(
            from: amountText,
            currencyCode: currencyCode
        )
    }

    static func defaultRows() -> [BulkPendingDraftRow] {
        [
            BulkPendingDraftRow(),
            BulkPendingDraftRow(),
        ]
    }
}

private enum RatioSplitKind: String, CaseIterable, Identifiable {
    case expense
    case income
    case pending

    var id: String { rawValue }

    var title: String {
        switch self {
        case .expense:
            return "Expense"
        case .income:
            return "Income"
        case .pending:
            return "Pending"
        }
    }

    var accessibilityLabel: String {
        "\(title) split"
    }
}

private struct RatioSplitDraftRow: Identifiable {
    let id: UUID
    var ratioText: String
    var kind: RatioSplitKind
    var category: CategoryItem?
    var expectedDueDate: Date
    var note: String

    init(
        id: UUID = UUID(),
        ratioText: String = "1",
        kind: RatioSplitKind = .expense,
        category: CategoryItem? = nil,
        expectedDueDate: Date = Date(),
        note: String = ""
    ) {
        self.id = id
        self.ratioText = ratioText
        self.kind = kind
        self.category = category
        self.expectedDueDate = expectedDueDate
        self.note = note
    }

    static func defaultRows() -> [RatioSplitDraftRow] {
        [
            RatioSplitDraftRow(ratioText: "1", kind: .expense),
            RatioSplitDraftRow(ratioText: "2", kind: .income),
        ]
    }
}

private struct RatioSplitPreset: Identifiable {
    let id: String
    var title: String? = nil
    let parts: [Int]
    var savedID: UUID? = nil

    var ratioText: String {
        parts.map(String.init).joined(separator: ":")
    }

    var displayTitle: String {
        title ?? ratioText
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

private struct SavedRatioSplitPreset: Codable, Identifiable {
    let id: UUID
    var name: String
    var parts: [Int]

    init(id: UUID = UUID(), name: String, parts: [Int]) {
        self.id = id
        self.name = name
        self.parts = parts
    }
}

private struct RatioSplitCategoryPickerPresentation: Identifiable {
    let row: RatioSplitDraftRow
    var id: UUID { row.id }
}

private struct RatioPresetChip: View {
    let preset: RatioSplitPreset
    let isSelected: Bool

    private var tint: Color {
        Color(hex: "#0E7C7B")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(preset.displayTitle)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            if preset.title != nil {
                Text(preset.ratioText)
                    .font(.caption2.monospacedDigit().weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
            .padding(.horizontal, 14)
            .padding(.vertical, preset.title == nil ? 10 : 8)
            .floatGlassSurface(
                cornerRadius: FloatTheme.tileRadius,
                tint: isSelected ? tint : nil,
                interactive: true,
                strokeOpacity: isSelected ? 0.1 : 0.06
            )
            .foregroundStyle(isSelected ? tint : .primary)
    }
}

private struct RatioSplitRowEditor: View {
    @Binding var row: RatioSplitDraftRow
    let amountMinor: Int64
    let currencyCode: String
    let palette: FloatThemePalette
    let canDelete: Bool
    let chooseCategory: () -> Void
    let delete: () -> Void

    @State private var isEditingNote = false

    private var tint: Color {
        switch row.kind {
        case .expense:
            return palette.caution
        case .income:
            return palette.positive
        case .pending:
            return Color(hex: "#6B7280")
        }
    }

    private var amountText: String {
        MoneyFormatter.string(
            minorUnits: amountMinor,
            currencyCode: currencyCode,
            showsSign: row.kind == .income
        )
    }

    private var trimmedNote: String {
        row.note.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(amountText)
                    .moneyStyle(size: 17, weight: .bold)
                    .foregroundStyle(row.kind == .income ? palette.positive : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
                    .contentTransition(.numericText())
                    .layoutPriority(1)

                Spacer(minLength: 8)

                ratioField

                typeToggle

                rowMenu
            }

            if row.kind == .pending {
                dueDatePicker
            } else {
                categoryButton
            }

            noteArea
        }
        .padding(12)
        .floatGlassSurface(
            cornerRadius: FloatTheme.controlRadius,
            material: .thinMaterial,
            tint: tint,
            strokeOpacity: 0.07,
            shadowOpacity: 0.04,
            shadowRadius: 14,
            shadowY: 8
        )
    }

    private var ratioField: some View {
        TextField("1", text: $row.ratioText)
            .keyboardType(.numberPad)
            .textFieldStyle(.plain)
            .font(.subheadline.monospacedDigit().weight(.bold))
            .multilineTextAlignment(.center)
            .frame(width: 46, height: 34)
            .background(
                Color.primary.opacity(0.07),
                in: RoundedRectangle(
                    cornerRadius: 12,
                    style: .continuous
                )
            )
            .accessibilityLabel("Ratio")
    }

    private var typeToggle: some View {
        Menu {
            ForEach(RatioSplitKind.allCases) { kind in
                Button {
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.9)) {
                        row.kind = kind
                    }
                } label: {
                    Label(
                        kind.title,
                        systemImage: row.kind == kind ? "checkmark.circle.fill" : "circle"
                    )
                }
            }
        } label: {
            Text(row.kind.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 78, height: 34)
                .background(
                    tint.opacity(0.12),
                    in: Capsule(style: .continuous)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(tint.opacity(0.18), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(row.kind.accessibilityLabel)
    }

    private var rowMenu: some View {
        let isActive = isEditingNote || !trimmedNote.isEmpty

        return Menu {
            Button {
                withAnimation(.spring(response: 0.24, dampingFraction: 0.9)) {
                    isEditingNote.toggle()
                }
            } label: {
                Label(isEditingNote ? "Hide note" : "Edit note", systemImage: "note.text")
            }

            Button(role: .destructive) {
                guard canDelete else { return }
                delete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .disabled(!canDelete)
        } label: {
            Image(systemName: "ellipsis")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(isActive ? palette.accent : .secondary)
                .frame(width: 34, height: 34)
                .floatGlassCircle(
                    tint: isActive ? palette.accent : nil,
                    interactive: true,
                    strokeOpacity: isActive ? 0.1 : 0.06
                )
        }
        .accessibilityLabel("Split row actions")
    }

    private var categoryButton: some View {
        Button(action: chooseCategory) {
            HStack(spacing: 10) {
                FloatIconBadge(
                    icon: row.category?.iconKey ?? "square.grid.2x2.fill",
                    tint: tint,
                    size: 30
                )
                VStack(alignment: .leading, spacing: 1) {
                    Text(row.category?.name ?? "Choose category")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if row.category == nil {
                        Text(row.kind == .expense ? "Expense category" : "Income category")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(
                Color.primary.opacity(0.05),
                in: RoundedRectangle(
                    cornerRadius: 14,
                    style: .continuous
                )
            )
        }
        .buttonStyle(.plain)
    }

    private var dueDatePicker: some View {
        DatePicker(
            "Expected due date",
            selection: $row.expectedDueDate,
            displayedComponents: [.date]
        )
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            Color.primary.opacity(0.05),
            in: RoundedRectangle(
                cornerRadius: 14,
                style: .continuous
            )
        )
    }

    @ViewBuilder
    private var noteArea: some View {
        if isEditingNote {
            TextField("Note", text: $row.note, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.subheadline)
                .lineLimit(1...3)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    Color.primary.opacity(0.05),
                    in: RoundedRectangle(
                        cornerRadius: 14,
                        style: .continuous
                    )
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
        } else if !trimmedNote.isEmpty {
            Button {
                withAnimation(.spring(response: 0.24, dampingFraction: 0.9)) {
                    isEditingNote = true
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "note.text")
                    Text(trimmedNote)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 2)
            }
            .buttonStyle(.plain)
            .transition(.opacity)
        }
    }
}

private struct BulkPendingRowEditor: View {
    @Binding var row: BulkPendingDraftRow
    let currencyCode: String
    let canDelete: Bool
    let delete: () -> Void

    private var amountMinor: Int64 {
        row.amountMinor(currencyCode: currencyCode)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pending")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(
                        MoneyFormatter.string(
                            minorUnits: amountMinor,
                            currencyCode: currencyCode
                        )
                    )
                    .moneyStyle(size: 20, weight: .bold)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                }
                Spacer()
                Button(role: .destructive) {
                    guard canDelete else { return }
                    delete()
                } label: {
                    Image(systemName: "trash")
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.bordered)
                .disabled(!canDelete)
                .accessibilityLabel("Delete pending row")
            }

            TextField("Amount", text: $row.amountText)
                .keyboardType(.decimalPad)
                .textFieldStyle(.plain)
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    Color.primary.opacity(0.05),
                    in: RoundedRectangle(
                        cornerRadius: 14,
                        style: .continuous
                    )
                )

            DatePicker(
                "Expected due date",
                selection: $row.expectedDueDate,
                displayedComponents: [.date]
            )

            TextField("Note", text: $row.note, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.subheadline)
                .lineLimit(1...3)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    Color.primary.opacity(0.05),
                    in: RoundedRectangle(
                        cornerRadius: 14,
                        style: .continuous
                    )
                )
        }
        .padding(12)
        .floatGlassSurface(
            cornerRadius: FloatTheme.controlRadius,
            material: .thinMaterial,
            tint: Color(hex: "#6B7280"),
            strokeOpacity: 0.07,
            shadowOpacity: 0.04,
            shadowRadius: 14,
            shadowY: 8
        )
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
