import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @Query(sort: \TransactionItem.timestamp, order: .reverse) private var transactions: [TransactionItem]
    @Query private var accounts: [AccountItem]
    @Query private var categories: [CategoryItem]
    @Query private var goals: [GoalItem]
    @Query private var recurringRules: [RecurringRuleItem]
    @Query private var budgets: [BudgetPeriodItem]
    @State private var exportingCSV = false
    @State private var importingCSV = false
    @State private var exportingBackup = false
    @State private var importingBackup = false
    @State private var backupPassword = ""
    @State private var backupDocument = BackupDocument()
    @State private var message = ""

    var body: some View {
        List {
            Section("Preferences") {
                TextField("Currency", text: $appState.selectedCurrencyCode)
                    .textInputAutocapitalization(.characters)
                Picker("Appearance", selection: $appState.selectedAppearance) {
                    Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark")
                }
                Picker("Theme", selection: $appState.selectedThemeMode) {
                    Text("Float").tag("float"); Text("System dynamic").tag("system")
                }
                Toggle("Biometric lock", isOn: $appState.isBiometricLockEnabled)
            }
            Section("Manage") {
                NavigationLink("Goals", destination: GoalsView())
                NavigationLink("Recurring", destination: RecurringView())
                NavigationLink("Categories", destination: CategoryManagerView())
                NavigationLink("Accounts", destination: AccountManagerView())
            }
            Section("Portable data") {
                Button("Export CSV") { exportingCSV = true }
                Button("Import CSV") { importingCSV = true }
                TextField("Backup password", text: $backupPassword)
                    .textContentType(.password)
                Button("Create encrypted backup") { createBackup() }
                    .disabled(backupPassword.isEmpty)
                Button("Restore encrypted backup") { importingBackup = true }
                    .disabled(backupPassword.isEmpty)
                Text("Backup files are encrypted with your password. If you lose it, the backup cannot be restored.")
                    .font(.caption).foregroundStyle(.secondary)
                if !message.isEmpty { Text(message).font(.caption).foregroundStyle(.secondary) }
            }
            Section("Privacy") {
                Text("Data stays on device. Float has no backend, no account, no analytics, and no tracking SDKs. Data is not uploaded. Export and backup happen only when you choose them.")
                    .font(.subheadline)
            }
            Section("About") { Text("Float 1.0") }
            Section {
                Button("Reset all data", role: .destructive, action: resetAllData)
            }
        }
        .navigationTitle("Settings")
        .fileExporter(isPresented: $exportingCSV, document: CSVTransactionService.export(transactions: transactions, currencyCode: appState.selectedCurrencyCode), contentType: .commaSeparatedText, defaultFilename: "float-transactions.csv") { _ in }
        .fileImporter(isPresented: $importingCSV, allowedContentTypes: [.commaSeparatedText, .plainText]) { result in importCSV(result) }
        .fileExporter(isPresented: $exportingBackup, document: backupDocument, contentType: .floatBackup, defaultFilename: "float.floatbak") { result in message = resultMessage(result, success: "Backup exported.") }
        .fileImporter(isPresented: $importingBackup, allowedContentTypes: [.floatBackup]) { result in restoreBackup(result) }
    }

    private func createBackup() {
        let dto = FloatBackupDTO(
            accounts: accounts.map { AccountDTO(id: $0.id, name: $0.name, type: $0.type, openingBalanceMinor: $0.openingBalanceMinor, currencyCode: $0.currencyCode, archived: $0.archived, createdAt: $0.createdAt, updatedAt: $0.updatedAt) },
            categories: categories.map { CategoryDTO(id: $0.id, name: $0.name, iconKey: $0.iconKey, colorHex: $0.colorHex, isIncome: $0.isIncome, sortOrder: $0.sortOrder, archived: $0.archived, isDefault: $0.isDefault) },
            transactions: transactions.map { TransactionDTO(id: $0.id, amountMinor: $0.amountMinor, isExpense: $0.isExpense, timestamp: $0.timestamp, categoryID: $0.category?.id, accountID: $0.account?.id, note: $0.note, recurringRuleID: $0.recurringRule?.id, createdAt: $0.createdAt, updatedAt: $0.updatedAt) },
            goals: goals.map { GoalDTO(id: $0.id, name: $0.name, targetMinor: $0.targetMinor, savedMinor: $0.savedMinor, targetDate: $0.targetDate, colorHex: $0.colorHex, achieved: $0.achieved, createdAt: $0.createdAt, updatedAt: $0.updatedAt) },
            recurringRules: recurringRules.map { RecurringRuleDTO(id: $0.id, amountMinor: $0.amountMinor, isExpense: $0.isExpense, categoryID: $0.category?.id, accountID: $0.account?.id, note: $0.note, cadence: $0.cadence, intervalCount: $0.intervalCount, nextRunDate: $0.nextRunDate, endDate: $0.endDate, active: $0.active, createdAt: $0.createdAt, updatedAt: $0.updatedAt) },
            budgets: budgets.map { BudgetDTO(id: $0.id, cadence: $0.cadence, startDayOfMonth: $0.startDayOfMonth, startDayOfWeek: $0.startDayOfWeek, expectedIncomeMinor: $0.expectedIncomeMinor, currencyCode: $0.currencyCode, isActive: $0.isActive, createdAt: $0.createdAt, updatedAt: $0.updatedAt) },
            settings: SettingsDTO(currencyCode: appState.selectedCurrencyCode, exportedAt: Date())
        )
        do { backupDocument = try BackupCryptoService.encrypt(dto, password: backupPassword); exportingBackup = true } catch { message = error.localizedDescription }
    }

    private func restoreBackup(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            let document = BackupDocument(data: try Data(contentsOf: url))
            let dto = try BackupCryptoService.decrypt(document, password: backupPassword)
            restore(dto)
            message = "Backup restored."
        } catch { message = error.localizedDescription }
    }

    private func importCSV(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            let text = try String(contentsOf: url, encoding: .utf8)
            let summary = importCSVText(text)
            message = "Imported \(summary.imported). Skipped \(summary.skipped)."
        } catch {
            message = error.localizedDescription
        }
    }

    private func importCSVText(_ text: String) -> (imported: Int, skipped: Int) {
        let rows = text.split(whereSeparator: \.isNewline).dropFirst()
        let iso = ISO8601DateFormatter()
        var imported = 0
        var skipped = 0
        let existingKeys = Set(transactions.map { dedupeKey(timestamp: $0.timestamp, amountMinor: $0.amountMinor, note: $0.note) })
        var newKeys = Set<String>()
        let otherCategory = categories.first { $0.name == "Other" && !$0.isIncome } ?? categories.first
        let defaultAccount = accounts.first

        for row in rows {
            let columns = parseCSVLine(String(row))
            guard columns.count >= 9,
                  let timestamp = iso.date(from: columns[1]),
                  let amountMinor = Int64(columns[2]),
                  let isExpense = Bool(columns[5]) else {
                skipped += 1
                continue
            }
            let note = columns[8].isEmpty ? nil : columns[8]
            let key = dedupeKey(timestamp: timestamp, amountMinor: amountMinor, note: note)
            guard !existingKeys.contains(key), !newKeys.contains(key) else {
                skipped += 1
                continue
            }
            let categoryName = columns[6]
            let accountName = columns[7]
            let category = categories.first { $0.name.caseInsensitiveCompare(categoryName) == .orderedSame } ?? otherCategory
            let account = accounts.first { $0.name.caseInsensitiveCompare(accountName) == .orderedSame } ?? defaultAccount
            modelContext.insert(TransactionItem(amountMinor: amountMinor, isExpense: isExpense, timestamp: timestamp, category: category, account: account, note: note))
            newKeys.insert(key)
            imported += 1
        }
        try? modelContext.save()
        return (imported, skipped)
    }

    private func dedupeKey(timestamp: Date, amountMinor: Int64, note: String?) -> String {
        "\(Int(timestamp.timeIntervalSince1970))|\(amountMinor)|\(note ?? "")"
    }

    private func parseCSVLine(_ line: String) -> [String] {
        var result: [String] = []
        var value = ""
        var isQuoted = false
        var iterator = line.makeIterator()
        while let character = iterator.next() {
            if character == "\"" {
                if isQuoted, let next = iterator.next() {
                    if next == "\"" {
                        value.append(next)
                    } else {
                        isQuoted = false
                        if next == "," {
                            result.append(value)
                            value = ""
                        } else {
                            value.append(next)
                        }
                    }
                } else {
                    isQuoted.toggle()
                }
            } else if character == "," && !isQuoted {
                result.append(value)
                value = ""
            } else {
                value.append(character)
            }
        }
        result.append(value)
        return result
    }

    private func restore(_ dto: FloatBackupDTO) {
        resetAllData()
        var categoryMap: [UUID: CategoryItem] = [:]
        var accountMap: [UUID: AccountItem] = [:]
        for item in dto.categories { let model = CategoryItem(id: item.id, name: item.name, iconKey: item.iconKey, colorHex: item.colorHex, isIncome: item.isIncome, sortOrder: item.sortOrder, archived: item.archived, isDefault: item.isDefault); categoryMap[item.id] = model; modelContext.insert(model) }
        for item in dto.accounts { let model = AccountItem(id: item.id, name: item.name, type: item.type, openingBalanceMinor: item.openingBalanceMinor, currencyCode: item.currencyCode, archived: item.archived, createdAt: item.createdAt, updatedAt: item.updatedAt); accountMap[item.id] = model; modelContext.insert(model) }
        for item in dto.goals { modelContext.insert(GoalItem(id: item.id, name: item.name, targetMinor: item.targetMinor, savedMinor: item.savedMinor, targetDate: item.targetDate, colorHex: item.colorHex, achieved: item.achieved, createdAt: item.createdAt, updatedAt: item.updatedAt)) }
        for item in dto.budgets { modelContext.insert(BudgetPeriodItem(id: item.id, cadence: item.cadence, startDayOfMonth: item.startDayOfMonth, startDayOfWeek: item.startDayOfWeek, expectedIncomeMinor: item.expectedIncomeMinor, currencyCode: item.currencyCode, isActive: item.isActive, createdAt: item.createdAt, updatedAt: item.updatedAt)) }
        for item in dto.transactions { modelContext.insert(TransactionItem(id: item.id, amountMinor: item.amountMinor, isExpense: item.isExpense, timestamp: item.timestamp, category: item.categoryID.flatMap { categoryMap[$0] }, account: item.accountID.flatMap { accountMap[$0] }, note: item.note, createdAt: item.createdAt, updatedAt: item.updatedAt)) }
        appState.selectedCurrencyCode = dto.settings.currencyCode
        try? modelContext.save()
    }

    private func resetAllData() {
        for item in transactions { modelContext.delete(item) }
        for item in recurringRules { modelContext.delete(item) }
        for item in goals { modelContext.delete(item) }
        for item in budgets { modelContext.delete(item) }
        for item in accounts { modelContext.delete(item) }
        for item in categories { modelContext.delete(item) }
        try? modelContext.save()
    }

    private func resultMessage(_ result: Result<URL, Error>, success: String) -> String {
        switch result { case .success: success; case .failure(let error): error.localizedDescription }
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
                                .fill(Color(hex: category.colorHex).opacity(0.16))
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
                $0.map { categories[$0] }.forEach(modelContext.delete)
                try? modelContext.save()
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
            CategoryEditorView(category: editingCategory, nextSortOrder: categories.count)
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
                            .background(Color(hex: "#0E7C7B").opacity(0.14), in: Circle())

                        VStack(alignment: .leading, spacing: 3) {
                            Text(account.name)
                                .font(.headline)
                            Text("\(account.type.title) • \(account.currencyCode)")
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
                $0.map { accounts[$0] }.forEach(modelContext.delete)
                try? modelContext.save()
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
            AccountEditorView(account: editingAccount, defaultCurrencyCode: appState.selectedCurrencyCode)
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
        "gift.fill", "airplane", "square.grid.2x2.fill"
    ]

    private let colorOptions = [
        "#0E7C7B", "#1B8A5A", "#3B82F6", "#8B5CF6",
        "#B4613B", "#D08A62", "#EC4899", "#5A6B6B"
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
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 12) {
                        ForEach(iconOptions, id: \.self) { icon in
                            Button {
                                iconKey = icon
                            } label: {
                                Image(systemName: icon)
                                    .font(.headline)
                                    .frame(width: 42, height: 42)
                                    .background(iconKey == icon ? Color(hex: colorHex).opacity(0.2) : Color.primary.opacity(0.06), in: Circle())
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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
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
        } else {
            modelContext.insert(CategoryItem(name: trimmedName, iconKey: iconKey, colorHex: colorHex, isIncome: isIncome, sortOrder: nextSortOrder, archived: archived, isDefault: false))
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
                    TextField("Opening balance minor units", text: $openingBalanceText)
                        .keyboardType(.numberPad)
                    Toggle("Archived", isOn: $archived)
                }

                Section {
                    Text("Amounts are stored in minor units. Example: ₹123.45 is 12345.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(account == nil ? "New Account" : "Edit Account")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear(perform: configure)
        }
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
        let trimmedCurrency = currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let openingBalance = Int64(openingBalanceText) ?? 0
        if let account {
            account.name = trimmedName
            account.type = type
            account.openingBalanceMinor = openingBalance
            account.currencyCode = trimmedCurrency
            account.archived = archived
            account.updatedAt = Date()
        } else {
            modelContext.insert(AccountItem(name: trimmedName, type: type, openingBalanceMinor: openingBalance, currencyCode: trimmedCurrency, archived: archived))
        }
        try? modelContext.save()
        dismiss()
    }
}
