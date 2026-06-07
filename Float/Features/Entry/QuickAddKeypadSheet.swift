import SwiftData
import SwiftUI

private enum QuickTransactionKind: String, CaseIterable, Identifiable {
    case expense
    case income
    case pending

    var id: String { rawValue }

    var title: String {
        switch self {
        case .expense: "Expense"
        case .income: "Income"
        case .pending: "Pending"
        }
    }

    var isExpense: Bool {
        self != .income
    }
}

struct QuickAddKeypadSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @Query(sort: \CategoryItem.sortOrder) private var categories: [CategoryItem]
    @Query(sort: \AccountItem.createdAt) private var accounts: [AccountItem]

    let transactionToEdit: TransactionItem?
    let event: EventItem?
    var initialTimestamp: Date?
    var initialIsExpense: Bool?
    @State private var keypadText = ""
    @State private var transactionKind = QuickTransactionKind.expense
    @State private var selectedCategory: CategoryItem?
    @State private var selectedAccount: AccountItem?
    @State private var note = ""
    @State private var timestamp = Date()
    @State private var expectedDueDate = Date()
    @State private var validationMessage: String?
    @State private var showingCategoryPicker = false
    @State private var showingSplitEntry = false
    @State private var recentTransactions: [TransactionItem] = []
    @State private var recentTransactionsLoadKey = false
    @State private var templates: [TransactionTemplateItem] = []
    @State private var templatesLoadKey = false

    private var palette: FloatThemePalette {
        appState.themePalette
    }

    init(
        transactionToEdit: TransactionItem?,
        event: EventItem? = nil,
        initialTimestamp: Date? = nil,
        initialIsExpense: Bool? = nil
    ) {
        self.transactionToEdit = transactionToEdit
        self.event = event
        self.initialTimestamp = initialTimestamp
        self.initialIsExpense = initialIsExpense
    }

    private var amountMinor: Int64 {
        MoneyParser.parseMinorUnits(from: keypadText)
    }
    private var isPending: Bool {
        transactionKind == .pending
    }
    private var isExpense: Bool {
        transactionKind.isExpense
    }
    private var visibleCategories: [CategoryItem] {
        guard !isPending else { return [] }
        return categories.filter { !$0.archived && $0.isIncome != isExpense }
    }
    private var recentCategories: [CategoryItem] {
        uniqueCategories(
            recentTransactions.compactMap { transaction in
                guard transaction.isPosted && transaction.isExpense == isExpense else { return nil }
                return transaction.category
            }
        )
        .prefix(6)
        .map { $0 }
    }
    private var recentTransactionTemplates: [TransactionItem] {
        var seen = Set<String>()
        return recentTransactions
            .filter { $0.isPosted && $0.isExpense == isExpense }
            .filter { transaction in
                let key = [
                    transaction.amountMinor.description,
                    transaction.category?.id.uuidString ?? "",
                    transaction.account?.id.uuidString ?? "",
                    transaction.note ?? "",
                ].joined(separator: "|")
                guard !seen.contains(key) else { return false }
                seen.insert(key)
                return true
            }
            .prefix(4)
            .map { $0 }
    }
    private var visibleTemplates: [TransactionTemplateItem] {
        templates
            .filter { $0.isExpense == isExpense }
            .prefix(8)
            .map { $0 }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    Picker("Type", selection: $transactionKind) {
                        ForEach(QuickTransactionKind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(
                        MoneyFormatter.string(
                            minorUnits: amountMinor,
                            currencyCode: appState.selectedCurrencyCode
                        )
                    )
                    .moneyStyle(size: 46, weight: .bold)
                    .contentTransition(.numericText())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)

                    if transactionToEdit != nil && !isPending {
                        splitAmountButton
                    }

                    keypad

                    if transactionToEdit == nil && !isPending {
                        splitAmountButton
                    }

                    if !isPending {
                        templateSection

                        categorySection
                    }

                    GlassCard {
                        VStack(spacing: 14) {
                            if !isPending {
                                AccountPicker(
                                    selectedAccount: $selectedAccount,
                                    accounts: accounts.filter { !$0.archived }
                                )
                                Divider()
                            }
                            TextField("Note", text: $note, axis: .vertical)
                                .textFieldStyle(.plain)
                                .lineLimit(1...3)
                            if isPending {
                                DatePicker(
                                    "Expected due date",
                                    selection: $expectedDueDate,
                                    displayedComponents: [.date]
                                )
                            } else {
                                DatePicker(
                                    "Date",
                                    selection: $timestamp,
                                    displayedComponents: [.date, .hourAndMinute]
                                )
                            }
                        }
                    }

                    VStack(spacing: 10) {
                        if let validationMessage {
                            Text(validationMessage)
                                .font(.footnote)
                                .foregroundStyle(Color(hex: "#B4613B"))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityLabel(validationMessage)
                        }

                        if transactionToEdit != nil {
                            Button(role: .destructive, action: deleteTransaction) {
                                Label("Delete transaction", systemImage: "trash")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderless)
                        }

                        if transactionToEdit == nil && amountMinor > 0 {
                            Button(action: saveAndAddAnother) {
                                Label("Save and add another", systemImage: "plus.square.on.square")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                .padding(20)
                .padding(.bottom, 24)
            }
            .navigationTitle(transactionToEdit == nil ? "Add" : "Edit")
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDismissControls()
            .toolbarBackground(Color(.systemGroupedBackground), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(transactionToEdit == nil ? "Save" : "Done", action: save)
                        .disabled(amountMinor == 0)
                }
            }
            .floatBackground()
            .onAppear(perform: configureDefaults)
            .task {
                await loadSuggestionData()
            }
            .onChange(of: transactionKind) { oldValue, newValue in
                if selectedCategory?.isIncome == isExpense {
                    selectedCategory = nil
                }
                if oldValue == .pending && newValue != .pending {
                    timestamp = Date()
                }
                Task {
                    await loadSuggestionData()
                }
            }
            .onChange(of: note) { _, _ in
                applySmartCategorySuggestion()
            }
            .sheet(isPresented: $showingCategoryPicker) {
                CategoryPickerSheet(
                    title: isExpense ? "Expense Category" : "Income Category",
                    categories: visibleCategories,
                    selectedCategory: $selectedCategory
                )
            }
            .sheet(isPresented: $showingSplitEntry) {
                BulkTransactionEntrySheet(
                    initialSplitAmountMinor: amountMinor,
                    initialSplitTimestamp: timestamp,
                    transactionToReplace: transactionToEdit,
                    onCreate: { dismiss() }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
    }

    @ViewBuilder
    private var splitAmountButton: some View {
        if amountMinor > 0 {
            Button {
                showingSplitEntry = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "divide.circle.fill")
                        .font(.headline)
                    Text(transactionToEdit == nil ? "Split amount" : "Split transaction")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                }
                .padding(14)
                .foregroundStyle(palette.accent)
                .background(
                    palette.accent.opacity(0.12),
                    in: RoundedRectangle(
                        cornerRadius: FloatTheme.controlRadius,
                        style: .continuous
                    )
                )
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var templateSection: some View {
        if transactionToEdit == nil
            && (!visibleTemplates.isEmpty || !recentTransactionTemplates.isEmpty) {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Templates")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(visibleTemplates) { template in
                            Button {
                                applyTemplate(template)
                            } label: {
                                templateTile(
                                    title: template.displayTitle,
                                    amountMinor: template.amountMinor,
                                    icon: template.category?.iconKey ?? "square.text.square",
                                    colorHex: template.category?.colorHex ?? "#0E7C7B"
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        if visibleTemplates.isEmpty {
                            ForEach(recentTransactionTemplates) { transaction in
                                Button {
                                    applyTemplate(transaction)
                                } label: {
                                    templateTile(
                                        title: transaction.categoryName,
                                        amountMinor: transaction.amountMinor,
                                        icon: transaction.categoryIconKey,
                                        colorHex: transaction.categoryColorHex
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }

    private func templateTile(
        title: String,
        amountMinor: Int64,
        icon: String,
        colorHex: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundStyle(Color(hex: colorHex))
                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            Text(
                MoneyFormatter.string(
                    minorUnits: amountMinor,
                    currencyCode: appState.selectedCurrencyCode
                )
            )
            .font(.caption.monospacedDigit().weight(.bold))
            .foregroundStyle(.primary)
        }
        .padding(12)
        .frame(width: 132, alignment: .leading)
        .background(
            Color.primary.opacity(0.06),
            in: RoundedRectangle(
                cornerRadius: FloatTheme.tileRadius,
                style: .continuous
            )
        )
    }

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            categoryChips(title: "Recent", categories: recentCategories)
            categorySelector
        }
    }

    private var categorySelector: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Category")
            Button {
                showingCategoryPicker = true
            } label: {
                GlassCard {
                    HStack(spacing: 12) {
                        categorySelectorIcon
                        VStack(alignment: .leading, spacing: 4) {
                            Text(selectedCategory?.name ?? "Choose category")
                                .font(.subheadline.weight(.semibold))
                            Text("Tap to browse \(visibleCategories.count) categories")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(visibleCategories.isEmpty)
        }
    }

    private var categorySelectorIcon: some View {
        let icon = selectedCategory?.iconKey ?? "square.grid.2x2.fill"
        let tint = selectedCategory.map { Color(hex: $0.colorHex) } ?? palette.accent
        return Image(systemName: icon)
            .font(.headline)
            .foregroundStyle(tint)
            .frame(width: 38, height: 38)
            .background(tint.opacity(0.14), in: Circle())
    }

    @ViewBuilder
    private func categoryChips(
        title: String,
        categories: [CategoryItem]
    ) -> some View {
        if !categories.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: title)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(categories) { category in
                            Button {
                                selectedCategory = category
                                validationMessage = nil
                                Haptics.tick()
                            } label: {
                                CategoryChip(
                                    category: category,
                                    isSelected: selectedCategory?.id == category.id
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var keypad: some View {
        let keys = [
            "1", "2", "3", "4", "5", "6", "7", "8", "9", "00", "0",
            "delete.left",
        ]
        return LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(), spacing: 10),
                count: 3
            ),
            spacing: 10
        ) {
            ForEach(keys, id: \.self) { key in
                Button {
                    if key == "delete.left" {
                        keypadText = MoneyParser.deleteLast(from: keypadText)
                    } else {
                        keypadText = MoneyParser.keypadText(
                            afterAppending: key,
                            to: keypadText
                        )
                    }
                    validationMessage = nil
                    Haptics.tick()
                } label: {
                    Group {
                        if key == "delete.left" {
                            Image(systemName: key)
                        } else {
                            Text(key)
                        }
                    }
                    .font(.title2.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(
                        .thinMaterial,
                        in: RoundedRectangle(
                            cornerRadius: 20,
                            style: .continuous
                        )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func configureDefaults() {
        guard keypadText.isEmpty else { return }
        if let transactionToEdit {
            keypadText = String(transactionToEdit.amountMinor)
            if transactionToEdit.isPending {
                if let initialIsExpense {
                    transactionKind = initialIsExpense ? .expense : .income
                    timestamp = Date()
                } else {
                    transactionKind = .pending
                    timestamp = transactionToEdit.timestamp
                }
            } else {
                transactionKind = transactionToEdit.isExpense ? .expense : .income
                timestamp = transactionToEdit.timestamp
            }
            selectedCategory = transactionToEdit.category
            selectedAccount = transactionToEdit.account
            note = transactionToEdit.note ?? ""
            expectedDueDate = transactionToEdit.expectedDueDate ?? transactionToEdit.timestamp
            return
        }
        transactionKind = initialIsExpense == false ? .income : .expense
        selectedCategory =
            categories.first {
                !$0.archived
                    && $0.isIncome != isExpense
                    && $0.id.uuidString == appState.lastUsedCategoryID
            }
        selectedAccount =
            accounts.first {
                !$0.archived && $0.id.uuidString == appState.lastUsedAccountID
            }
        if let initialTimestamp {
            timestamp = initialTimestamp
            expectedDueDate = initialTimestamp
        }
        applySmartCategorySuggestion()
    }

    private func loadSuggestionData() async {
        await Task.yield()
        loadTemplates()
        loadRecentTransactions()
    }

    private func loadTemplates() {
        guard !isPending else {
            templates = []
            return
        }
        let loadKey = isExpense
        guard templates.isEmpty || templatesLoadKey != loadKey else {
            return
        }

        templatesLoadKey = loadKey
        do {
            var descriptor = FetchDescriptor<TransactionTemplateItem>(
                predicate: #Predicate<TransactionTemplateItem> { template in
                    template.isExpense == loadKey
                },
                sortBy: [SortDescriptor(\TransactionTemplateItem.createdAt, order: .reverse)]
            )
            descriptor.fetchLimit = 8
            templates = try modelContext.fetch(descriptor)
        } catch {
            templates = []
        }
    }

    private func loadRecentTransactions() {
        guard !isPending else {
            recentTransactions = []
            return
        }
        let loadKey = isExpense
        guard recentTransactions.isEmpty || recentTransactionsLoadKey != loadKey else {
            return
        }

        recentTransactionsLoadKey = loadKey
        do {
            var descriptor = FetchDescriptor<TransactionItem>(
                predicate: #Predicate<TransactionItem> { transaction in
                    transaction.isExpense == loadKey
                },
                sortBy: [SortDescriptor(\TransactionItem.timestamp, order: .reverse)]
            )
            descriptor.fetchLimit = 80
            recentTransactions = try modelContext.fetch(descriptor)
        } catch {
            recentTransactions = []
        }
    }

    private func save() {
        save(keepOpen: false)
    }

    private func saveAndAddAnother() {
        save(keepOpen: true)
    }

    private func save(keepOpen: Bool) {
        guard amountMinor > 0 else {
            validationMessage = "Enter an amount greater than zero."
            return
        }
        if transactionToEdit == nil, event?.isEnded == true {
            validationMessage = "Ended events cannot add transactions."
            return
        }

        let cleanNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let repository = TransactionRepository(modelContext: modelContext)

        if isPending {
            do {
                if let transactionToEdit {
                    try repository.updatePending(
                        transactionToEdit,
                        amountMinor: amountMinor,
                        expectedDueDate: expectedDueDate,
                        event: event,
                        note: cleanNote
                    )
                } else {
                    _ = try repository.createPending(
                        amountMinor: amountMinor,
                        expectedDueDate: expectedDueDate,
                        event: event,
                        note: cleanNote
                    )
                }
                Haptics.confirm()
                if keepOpen {
                    keypadText = ""
                    note = ""
                    validationMessage = nil
                    expectedDueDate = Date()
                } else {
                    dismiss()
                }
            } catch {
                validationMessage = error.localizedDescription
            }
            return
        }

        let category = selectedCategory ?? DefaultCategoryResolver.resolve(
            isExpense: isExpense,
            preferredID: appState.lastUsedCategoryID,
            categories: categories,
            modelContext: modelContext
        )
        let account = selectedAccount ?? DefaultAccountResolver.resolve(
            preferredID: appState.lastUsedAccountID,
            accounts: accounts,
            modelContext: modelContext,
            currencyCode: appState.selectedCurrencyCode
        )
        do {
            if let transactionToEdit {
                try repository.update(
                    transactionToEdit,
                    amountMinor: amountMinor,
                    isExpense: isExpense,
                    timestamp: timestamp,
                    category: category,
                    account: account,
                    event: event,
                    note: cleanNote
                )
            } else {
                _ = try repository.create(
                    amountMinor: amountMinor,
                    isExpense: isExpense,
                    timestamp: timestamp,
                    category: category,
                    account: account,
                    event: event,
                    note: cleanNote
                )
            }
            appState.lastUsedCategoryID = category.id.uuidString
            appState.lastUsedAccountID = account.id.uuidString
            Haptics.confirm()
            if keepOpen {
                keypadText = ""
                note = ""
                validationMessage = nil
                timestamp = initialTimestamp ?? Date()
            } else {
                dismiss()
            }
        } catch {
            validationMessage = error.localizedDescription
        }
    }

    private func applyTemplate(_ transaction: TransactionItem) {
        keypadText = String(transaction.amountMinor)
        transactionKind = transaction.isExpense ? .expense : .income
        selectedCategory = transaction.category
        selectedAccount = transaction.account
        note = transaction.note ?? ""
        validationMessage = nil
        Haptics.tick()
    }

    private func applyTemplate(_ template: TransactionTemplateItem) {
        keypadText = String(template.amountMinor)
        transactionKind = template.isExpense ? .expense : .income
        selectedCategory = template.category
        selectedAccount = template.account
        note = template.note ?? ""
        validationMessage = nil
        Haptics.tick()
    }

    private func applySmartCategorySuggestion() {
        guard transactionToEdit == nil else { return }
        let query = note.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return }
        let canReplace =
            selectedCategory == nil
            || selectedCategory?.id.uuidString == appState.lastUsedCategoryID
        guard canReplace else { return }
        if let match = visibleCategories.first(where: {
            query.contains($0.name.lowercased())
        }) {
            selectedCategory = match
        }
    }

    private func deleteTransaction() {
        guard let transactionToEdit else { return }
        do {
            try TransactionRepository(modelContext: modelContext)
                .delete(transactionToEdit)
            Haptics.tick()
            dismiss()
        } catch {
            validationMessage = error.localizedDescription
        }
    }

    private func uniqueCategories(_ categories: [CategoryItem]) -> [CategoryItem] {
        var seen = Set<UUID>()
        return categories.filter { category in
            guard !category.archived, !seen.contains(category.id) else {
                return false
            }
            seen.insert(category.id)
            return true
        }
    }
}

private struct CategoryPickerSheet: View {
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
                                ZStack {
                                    Circle()
                                        .fill(Color(hex: category.colorHex).opacity(0.14))
                                    Image(systemName: category.iconKey)
                                        .foregroundStyle(Color(hex: category.colorHex))
                                }
                                .frame(width: 36, height: 36)

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

struct FlowLayout<Content: View>: View {
    let spacing: CGFloat
    let content: Content

    init(spacing: CGFloat = 8, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: spacing) { content }
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 120), spacing: spacing)],
                spacing: spacing
            ) { content }
        }
    }
}
