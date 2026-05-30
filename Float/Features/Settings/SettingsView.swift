import SwiftData
import SwiftUI
import UniformTypeIdentifiers

private struct CurrencyOption: Identifiable {
    let code: String
    let symbol: String

    var id: String { code }
}

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @Query(sort: \TransactionItem.timestamp, order: .reverse) private
        var transactions: [TransactionItem]
    @Query private var accounts: [AccountItem]
    @Query private var categories: [CategoryItem]
    @Query private var goals: [GoalItem]
    @Query private var recurringRules: [RecurringRuleItem]
    @Query private var budgets: [BudgetPeriodItem]
    @State private var exportingBackup = false
    @State private var importingBackup = false
    @State private var backupDocument = BackupDocument()
    @State private var message = ""
    @State private var showingResetConfirmation = false

    var body: some View {
        ZStack {
            settingsList
            filePresentationHost
        }
        .navigationTitle("Settings")
        .alert("Reset all data?", isPresented: $showingResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset all data", role: .destructive) {
                resetAllData()
                message = "All data has been reset."
            }
        } message: {
            Text(
                "This permanently deletes your accounts, categories, budgets, goals, recurring rules, and transactions. This action cannot be undone."
            )
        }
    }

    private var settingsList: some View {
        List {
            Section("Preferences") {
                Picker("Currency", selection: $appState.selectedCurrencyCode) {
                    ForEach(Self.currencyOptions) { currency in
                        Text("\(currency.symbol) \(currency.code)")
                            .tag(currency.code)
                    }
                }
                .pickerStyle(.menu)
                Picker("Appearance", selection: $appState.selectedAppearance) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                Picker("Theme", selection: $appState.selectedThemeMode) {
                    Text("Float").tag("float")
                    Text("System dynamic").tag("system")
                }
            }
            Section("Manage") {
                NavigationLink("Budget", destination: BudgetSettingsView())
                NavigationLink("Goals", destination: GoalsView())
                NavigationLink("Recurring", destination: RecurringView())
                NavigationLink("Categories", destination: CategoryManagerView())
                NavigationLink("Accounts", destination: AccountManagerView())
            }
            Section("Portable data") {
                Button("Create backup", action: createBackup)
                    .buttonStyle(.borderless)
                Button("Restore backup", action: presentBackupImporter)
                    .buttonStyle(.borderless)
                if !message.isEmpty {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Privacy") {
                Text(
                    "Data stays on device. Float has no backend, no account, no analytics, and no tracking SDKs. Backup files are created only when you choose them."
                )
                .font(.subheadline)
            }
            Section("About") { Text("Float 1.0") }
            Section {
                Button(
                    "Reset all data",
                    role: .destructive,
                    action: { showingResetConfirmation = true }
                )
            }
        }
        .keyboardDismissControls()
    }

    private var filePresentationHost: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        .fileExporter(
            isPresented: $exportingBackup,
            document: backupDocument,
            contentType: .floatBackup,
            defaultFilename: "float.floatbak"
        ) { result in
            message = resultMessage(result, success: "Backup created.")
        }
        .fileImporter(
            isPresented: $importingBackup,
            allowedContentTypes: [.floatBackup, .data]
        ) { result in restoreBackup(result) }
    }

    private static let currencyOptions: [CurrencyOption] = [
        CurrencyOption(code: "USD", symbol: "$"),
        CurrencyOption(code: "INR", symbol: "₹"),
        CurrencyOption(code: "EUR", symbol: "€"),
        CurrencyOption(code: "GBP", symbol: "£"),
        CurrencyOption(code: "JPY", symbol: "¥"),
        CurrencyOption(code: "CAD", symbol: "C$"),
        CurrencyOption(code: "AUD", symbol: "A$"),
        CurrencyOption(code: "SGD", symbol: "S$"),
        CurrencyOption(code: "AED", symbol: "د.إ"),
        CurrencyOption(code: "CHF", symbol: "CHF"),
        CurrencyOption(code: "CNY", symbol: "¥"),
        CurrencyOption(code: "HKD", symbol: "HK$"),
        CurrencyOption(code: "NZD", symbol: "NZ$"),
        CurrencyOption(code: "SEK", symbol: "kr"),
        CurrencyOption(code: "NOK", symbol: "kr"),
        CurrencyOption(code: "DKK", symbol: "kr"),
        CurrencyOption(code: "ZAR", symbol: "R"),
        CurrencyOption(code: "BRL", symbol: "R$"),
        CurrencyOption(code: "MXN", symbol: "MX$"),
    ]

    private func presentBackupImporter() {
        DispatchQueue.main.async {
            importingBackup = true
            message = "Opening backup picker."
        }
    }

    private func createBackup() {
        let dto = FloatBackupDTO(
            accounts: accounts.map {
                AccountDTO(
                    id: $0.id,
                    name: $0.name,
                    type: $0.type,
                    openingBalanceMinor: $0.openingBalanceMinor,
                    currencyCode: $0.currencyCode,
                    archived: $0.archived,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt
                )
            },
            categories: categories.map {
                CategoryDTO(
                    id: $0.id,
                    name: $0.name,
                    iconKey: $0.iconKey,
                    colorHex: $0.colorHex,
                    isIncome: $0.isIncome,
                    sortOrder: $0.sortOrder,
                    archived: $0.archived,
                    isDefault: $0.isDefault,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt
                )
            },
            transactions: transactions.map {
                TransactionDTO(
                    id: $0.id,
                    amountMinor: $0.amountMinor,
                    isExpense: $0.isExpense,
                    timestamp: $0.timestamp,
                    categoryID: $0.category?.id,
                    accountID: $0.account?.id,
                    note: $0.note,
                    recurringRuleID: $0.recurringRule?.id,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt
                )
            },
            goals: goals.map {
                GoalDTO(
                    id: $0.id,
                    name: $0.name,
                    targetMinor: $0.targetMinor,
                    savedMinor: $0.savedMinor,
                    targetDate: $0.targetDate,
                    colorHex: $0.colorHex,
                    achieved: $0.achieved,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt
                )
            },
            recurringRules: recurringRules.map {
                RecurringRuleDTO(
                    id: $0.id,
                    amountMinor: $0.amountMinor,
                    isExpense: $0.isExpense,
                    categoryID: $0.category?.id,
                    accountID: $0.account?.id,
                    note: $0.note,
                    cadence: $0.cadence,
                    intervalCount: $0.intervalCount,
                    nextRunDate: $0.nextRunDate,
                    endDate: $0.endDate,
                    active: $0.active,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt
                )
            },
            budgets: budgets.map {
                BudgetDTO(
                    id: $0.id,
                    cadence: $0.cadence,
                    startDayOfMonth: $0.startDayOfMonth,
                    startDayOfWeek: $0.startDayOfWeek,
                    expectedIncomeMinor: $0.expectedIncomeMinor,
                    currencyCode: $0.currencyCode,
                    isActive: $0.isActive,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt
                )
            },
            settings: SettingsDTO(
                currencyCode: appState.selectedCurrencyCode,
                exportedAt: Date()
            )
        )
        do {
            backupDocument = try BackupArchiveService.document(from: dto)
            message = "Preparing backup."
            DispatchQueue.main.async {
                exportingBackup = true
            }
        } catch { message = error.localizedDescription }
    }

    private func restoreBackup(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            let document = BackupDocument(data: try Data(contentsOf: url))
            let dto = try BackupArchiveService.dto(from: document)
            restore(dto)
            message = "Backup restored."
        } catch { message = error.localizedDescription }
    }

    private func restore(_ dto: FloatBackupDTO) {
        resetAllData(reseedDefaults: false)
        var categoryMap: [UUID: CategoryItem] = [:]
        var accountMap: [UUID: AccountItem] = [:]
        for item in dto.categories {
            let model = CategoryItem(
                id: item.id,
                name: item.name,
                iconKey: item.iconKey,
                colorHex: item.colorHex,
                isIncome: item.isIncome,
                sortOrder: item.sortOrder,
                archived: item.archived,
                isDefault: item.isDefault,
                createdAt: item.createdAt ?? Date(),
                updatedAt: item.updatedAt ?? item.createdAt ?? Date()
            )
            categoryMap[item.id] = model
            modelContext.insert(model)
        }
        for item in dto.accounts {
            let model = AccountItem(
                id: item.id,
                name: item.name,
                type: item.type,
                openingBalanceMinor: item.openingBalanceMinor,
                currencyCode: item.currencyCode,
                archived: item.archived,
                createdAt: item.createdAt,
                updatedAt: item.updatedAt
            )
            accountMap[item.id] = model
            modelContext.insert(model)
        }
        for item in dto.goals {
            modelContext.insert(
                GoalItem(
                    id: item.id,
                    name: item.name,
                    targetMinor: item.targetMinor,
                    savedMinor: item.savedMinor,
                    targetDate: item.targetDate,
                    colorHex: item.colorHex,
                    achieved: item.achieved,
                    createdAt: item.createdAt,
                    updatedAt: item.updatedAt
                )
            )
        }
        for item in dto.budgets {
            modelContext.insert(
                BudgetPeriodItem(
                    id: item.id,
                    cadence: item.cadence,
                    startDayOfMonth: item.startDayOfMonth,
                    startDayOfWeek: item.startDayOfWeek,
                    expectedIncomeMinor: item.expectedIncomeMinor,
                    currencyCode: item.currencyCode,
                    isActive: item.isActive,
                    createdAt: item.createdAt,
                    updatedAt: item.updatedAt
                )
            )
        }
        var recurringMap: [UUID: RecurringRuleItem] = [:]
        for item in dto.recurringRules {
            let model = RecurringRuleItem(
                id: item.id,
                amountMinor: item.amountMinor,
                isExpense: item.isExpense,
                category: item.categoryID.flatMap { categoryMap[$0] },
                account: item.accountID.flatMap { accountMap[$0] },
                note: item.note,
                cadence: item.cadence,
                intervalCount: item.intervalCount,
                nextRunDate: item.nextRunDate,
                endDate: item.endDate,
                active: item.active,
                createdAt: item.createdAt,
                updatedAt: item.updatedAt
            )
            recurringMap[item.id] = model
            modelContext.insert(model)
        }
        for item in dto.transactions {
            modelContext.insert(
                TransactionItem(
                    id: item.id,
                    amountMinor: item.amountMinor,
                    isExpense: item.isExpense,
                    timestamp: item.timestamp,
                    category: item.categoryID.flatMap { categoryMap[$0] },
                    account: item.accountID.flatMap { accountMap[$0] },
                    note: item.note,
                    recurringRule: item.recurringRuleID.flatMap { recurringMap[$0] },
                    createdAt: item.createdAt,
                    updatedAt: item.updatedAt
                )
            )
        }
        appState.selectedCurrencyCode = dto.settings.currencyCode
        try? modelContext.save()
    }

    private func resetAllData(reseedDefaults: Bool = true) {
        for item in transactions { modelContext.delete(item) }
        for item in recurringRules { modelContext.delete(item) }
        for item in goals { modelContext.delete(item) }
        for item in budgets { modelContext.delete(item) }
        for item in accounts { modelContext.delete(item) }
        for item in categories { modelContext.delete(item) }
        try? modelContext.save()
        if reseedDefaults {
            SeedDataService.ensureSeedData(
                modelContext: modelContext,
                currencyCode: appState.selectedCurrencyCode
            )
        }
    }

    private func resultMessage(_ result: Result<URL, Error>, success: String)
        -> String
    {
        switch result {
        case .success: success
        case .failure(let error): error.localizedDescription
        }
    }
}

struct BudgetSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @Query(sort: \TransactionItem.timestamp, order: .reverse) private
        var transactions: [TransactionItem]
    @Query private var goals: [GoalItem]
    @Query private var recurringRules: [RecurringRuleItem]
    @Query private var budgets: [BudgetPeriodItem]

    @State private var cadence: BudgetCadence = .monthly
    @State private var startDayOfMonth = 1
    @State private var startDayOfWeek = Calendar.current.firstWeekday
    @State private var expectedIncomeText = ""
    @State private var message = ""

    private var activeBudget: BudgetPeriodItem? {
        budgets.first { $0.isActive } ?? budgets.first
    }

    private var previewResult: SafeToSpendResult {
        SafeToSpendUseCase.calculate(
            period: BudgetPeriodCalculator.currentPeriod(
                cadence: cadence,
                startDayOfMonth: cadence == .monthly ? startDayOfMonth : nil,
                startDayOfWeek: cadence == .weekly ? startDayOfWeek : nil
            ),
            expectedIncomeMinor: previewExpectedIncomeMinor,
            transactions: transactions,
            goals: goals,
            recurringRules: recurringRules
        )
    }

    private var previewExpectedIncomeMinor: Int64 {
        BudgetAmountField.minorUnits(
            fromMajorAmount: expectedIncomeText,
            currencyCode: appState.selectedCurrencyCode
        )
    }

    var body: some View {
        Form {
            Section("Period") {
                Picker("Cadence", selection: $cadence) {
                    ForEach(BudgetCadence.allCases) { cadence in
                        Text(cadence.title).tag(cadence)
                    }
                }
                .pickerStyle(.segmented)

                if cadence == .monthly {
                    Stepper(
                        "Starts on day \(startDayOfMonth)",
                        value: $startDayOfMonth,
                        in: 1...28
                    )
                } else {
                    Picker("Starts on", selection: $startDayOfWeek) {
                        ForEach(Self.weekdayOptions, id: \.value) { option in
                            Text(option.name).tag(option.value)
                        }
                    }
                }
            }

            Section {
                HStack {
                    TextField("Amount", text: $expectedIncomeText)
                        .keyboardType(.decimalPad)
                    CurrencyAmountPreview(
                        minorUnits: previewExpectedIncomeMinor,
                        currencyCode: appState.selectedCurrencyCode
                    )
                }
            } header: {
                Text("Expected income")
            } footer: {
                Text(
                    "Enter the normal currency amount for one budget period. For example, enter 60000 for ₹60,000."
                )
            }

            Section {
                budgetRow("Expected income", previewResult.expectedIncomeMinor)
                budgetRow("Recurring due", previewResult.recurringDueMinor)
                budgetRow("Goals remaining", previewResult.goalContributionMinor)
                budgetRow("Spent so far", previewResult.variableSpentMinor)
                budgetRow("You can spend", previewResult.safeToSpendMinor)
            } header: {
                Text("Home preview")
            } footer: {
                Text(
                    "Home uses expected income minus recurring expenses, unfinished goal targets, and expenses already recorded this period."
                )
            }

            if !message.isEmpty {
                Section {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Budget")
        .keyboardDismissControls()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
            }
        }
        .onAppear(perform: configure)
    }

    private static let weekdayOptions: [(name: String, value: Int)] = [
        ("Sunday", 1),
        ("Monday", 2),
        ("Tuesday", 3),
        ("Wednesday", 4),
        ("Thursday", 5),
        ("Friday", 6),
        ("Saturday", 7),
    ]

    private func budgetRow(_ title: String, _ amount: Int64) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(
                MoneyFormatter.string(
                    minorUnits: amount,
                    currencyCode: appState.selectedCurrencyCode
                )
            )
            .foregroundStyle(.secondary)
        }
    }

    private func configure() {
        guard let budget = activeBudget else {
            expectedIncomeText = ""
            return
        }
        cadence = budget.cadence
        startDayOfMonth = budget.startDayOfMonth ?? 1
        startDayOfWeek = budget.startDayOfWeek ?? Calendar.current.firstWeekday
        expectedIncomeText = BudgetAmountField.majorAmountString(
            minorUnits: budget.expectedIncomeMinor,
            currencyCode: budget.currencyCode
        )
    }

    private func save() {
        let budget = activeBudget ?? BudgetPeriodItem(
            currencyCode: appState.selectedCurrencyCode
        )
        if budget.modelContext == nil {
            modelContext.insert(budget)
        }
        for item in budgets where item.id != budget.id {
            item.isActive = false
        }
        budget.cadence = cadence
        budget.startDayOfMonth = cadence == .monthly ? startDayOfMonth : nil
        budget.startDayOfWeek = cadence == .weekly ? startDayOfWeek : nil
        budget.expectedIncomeMinor = previewExpectedIncomeMinor
        budget.currencyCode = appState.selectedCurrencyCode
        budget.isActive = true
        budget.updatedAt = Date()
        try? modelContext.save()
        message = "Budget saved."
    }
}

enum BudgetAmountField {
    static func minorUnits(fromMajorAmount text: String, currencyCode: String)
        -> Int64
    {
        let normalized = text.replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let decimal = Decimal(string: normalized), decimal > 0 else {
            return 0
        }
        let scale = Decimal(
            pow(10.0, Double(MoneyFormatter.fractionDigits(for: currencyCode)))
        )
        let minorDecimal = decimal * scale
        return NSDecimalNumber(decimal: minorDecimal).rounding(
            accordingToBehavior: nil
        ).int64Value
    }

    static func majorAmountString(minorUnits: Int64, currencyCode: String)
        -> String
    {
        let fractionDigits = MoneyFormatter.fractionDigits(for: currencyCode)
        let divisor = Decimal(pow(10.0, Double(fractionDigits)))
        let major = Decimal(minorUnits) / divisor
        return NSDecimalNumber(decimal: major).stringValue
    }
}

struct CategoryManagerView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CategoryItem.sortOrder) private var categories: [CategoryItem]
    @State private var showingEditor = false
    @State private var editingCategory: CategoryItem?

    var body: some View {
        List {
            ForEach(categories) { category in
                Button {
                    editingCategory = category
                    showingEditor = true
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(
                                    Color(hex: category.colorHex).opacity(0.16)
                                )
                            Image(systemName: category.iconKey)
                                .foregroundStyle(Color(hex: category.colorHex))
                        }
                        .frame(width: 36, height: 36)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(category.name)
                                .font(.headline)
                            Text(category.isIncome ? "Income" : "Expense")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if category.archived {
                            Text("Archived")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .onDelete {
                let repository = CategoryRepository(modelContext: modelContext)
                $0.map { categories[$0] }.forEach {
                    try? repository.deleteIfUnused($0)
                }
            }
        }
        .navigationTitle("Categories")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editingCategory = nil
                    showingEditor = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add category")
            }
        }
        .sheet(isPresented: $showingEditor) {
            CategoryEditorView(
                category: editingCategory,
                nextSortOrder: categories.count
            )
        }
    }
}

struct AccountManagerView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @Query(sort: \AccountItem.createdAt) private var accounts: [AccountItem]
    @State private var showingEditor = false
    @State private var editingAccount: AccountItem?

    var body: some View {
        List {
            ForEach(accounts) { account in
                Button {
                    editingAccount = account
                    showingEditor = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: account.type.icon)
                            .font(.headline)
                            .foregroundStyle(Color(hex: "#0E7C7B"))
                            .frame(width: 36, height: 36)
                            .background(
                                Color(hex: "#0E7C7B").opacity(0.14),
                                in: Circle()
                            )

                        VStack(alignment: .leading, spacing: 3) {
                            Text(account.name)
                                .font(.headline)
                            Text(
                                "\(account.type.title) • \(account.currencyCode)"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if account.archived {
                            Text("Archived")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .onDelete {
                let repository = AccountRepository(modelContext: modelContext)
                $0.map { accounts[$0] }.forEach {
                    try? repository.deleteIfUnused($0)
                }
            }
        }
        .navigationTitle("Accounts")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editingAccount = nil
                    showingEditor = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add account")
            }
        }
        .sheet(isPresented: $showingEditor) {
            AccountEditorView(
                account: editingAccount,
                defaultCurrencyCode: appState.selectedCurrencyCode
            )
        }
    }
}

private struct CategoryEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let category: CategoryItem?
    let nextSortOrder: Int

    @State private var name = ""
    @State private var iconKey = "square.grid.2x2.fill"
    @State private var colorHex = "#0E7C7B"
    @State private var isIncome = false
    @State private var archived = false

    private let iconOptions = [
        "fork.knife", "car.fill", "doc.text.fill", "basket.fill", "bag.fill",
        "cross.case.fill", "play.tv.fill", "banknote.fill", "house.fill",
        "gift.fill", "airplane", "square.grid.2x2.fill",
    ]

    private let colorOptions = [
        "#0E7C7B", "#1B8A5A", "#3B82F6", "#8B5CF6",
        "#B4613B", "#D08A62", "#EC4899", "#5A6B6B",
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Name", text: $name)
                    Toggle("Income category", isOn: $isIncome)
                    Toggle("Archived", isOn: $archived)
                }

                Section("Icon") {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 44))],
                        spacing: 12
                    ) {
                        ForEach(iconOptions, id: \.self) { icon in
                            Button {
                                iconKey = icon
                            } label: {
                                Image(systemName: icon)
                                    .font(.headline)
                                    .frame(width: 42, height: 42)
                                    .background(
                                        iconKey == icon
                                            ? Color(hex: colorHex).opacity(0.2)
                                            : Color.primary.opacity(0.06),
                                        in: Circle()
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Color") {
                    HStack(spacing: 12) {
                        ForEach(colorOptions, id: \.self) { color in
                            Button {
                                colorHex = color
                            } label: {
                                Circle()
                                    .fill(Color(hex: color))
                                    .frame(width: 30, height: 30)
                                    .overlay {
                                        if colorHex == color {
                                            Image(systemName: "checkmark")
                                                .font(.caption.bold())
                                                .foregroundStyle(.white)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    TextField("Hex color", text: $colorHex)
                        .textInputAutocapitalization(.characters)
                }
            }
            .navigationTitle(category == nil ? "New Category" : "Edit Category")
            .keyboardDismissControls()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(
                            name.trimmingCharacters(in: .whitespacesAndNewlines)
                                .isEmpty
                        )
                }
            }
            .onAppear(perform: configure)
        }
    }

    private func configure() {
        guard let category else { return }
        name = category.name
        iconKey = category.iconKey
        colorHex = category.colorHex
        isIncome = category.isIncome
        archived = category.archived
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let category {
            category.name = trimmedName
            category.iconKey = iconKey
            category.colorHex = colorHex
            category.isIncome = isIncome
            category.archived = archived
            category.updatedAt = Date()
        } else {
            modelContext.insert(
                CategoryItem(
                    name: trimmedName,
                    iconKey: iconKey,
                    colorHex: colorHex,
                    isIncome: isIncome,
                    sortOrder: nextSortOrder,
                    archived: archived,
                    isDefault: false
                )
            )
        }
        try? modelContext.save()
        dismiss()
    }
}

private struct AccountEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let account: AccountItem?
    let defaultCurrencyCode: String

    @State private var name = ""
    @State private var type: AccountType = .cash
    @State private var openingBalanceText = "0"
    @State private var currencyCode = ""
    @State private var archived = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Name", text: $name)
                    Picker("Type", selection: $type) {
                        ForEach(AccountType.allCases) { type in
                            Label(type.title, systemImage: type.icon).tag(type)
                        }
                    }
                    TextField("Currency code", text: $currencyCode)
                        .textInputAutocapitalization(.characters)
                    HStack {
                        TextField(
                            "Opening balance minor units",
                            text: $openingBalanceText
                        )
                        .keyboardType(.numberPad)
                        CurrencyAmountPreview(
                            minorUnits: openingBalanceMinor,
                            currencyCode: previewCurrencyCode
                        )
                    }
                    Toggle("Archived", isOn: $archived)
                }

                Section {
                    Text(
                        "Amounts are stored in minor units. Example: ₹123.45 is 12345."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(account == nil ? "New Account" : "Edit Account")
            .keyboardDismissControls()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(
                            name.trimmingCharacters(in: .whitespacesAndNewlines)
                                .isEmpty
                                || currencyCode.trimmingCharacters(
                                    in: .whitespacesAndNewlines
                                ).isEmpty
                        )
                }
            }
            .onAppear(perform: configure)
        }
    }

    private var openingBalanceMinor: Int64 {
        Int64(openingBalanceText) ?? 0
    }

    private var previewCurrencyCode: String {
        let trimmedCurrency = currencyCode.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).uppercased()
        return trimmedCurrency.isEmpty ? defaultCurrencyCode : trimmedCurrency
    }

    private func configure() {
        guard let account else {
            currencyCode = defaultCurrencyCode
            return
        }
        name = account.name
        type = account.type
        openingBalanceText = "\(account.openingBalanceMinor)"
        currencyCode = account.currencyCode
        archived = account.archived
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCurrency = currencyCode.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).uppercased()
        let openingBalance = openingBalanceMinor
        if let account {
            account.name = trimmedName
            account.type = type
            account.openingBalanceMinor = openingBalance
            account.currencyCode = trimmedCurrency
            account.archived = archived
            account.updatedAt = Date()
        } else {
            modelContext.insert(
                AccountItem(
                    name: trimmedName,
                    type: type,
                    openingBalanceMinor: openingBalance,
                    currencyCode: trimmedCurrency,
                    archived: archived
                )
            )
        }
        try? modelContext.save()
        dismiss()
    }
}
