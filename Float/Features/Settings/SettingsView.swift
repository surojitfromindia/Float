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
    @Query(sort: \TransactionTemplateItem.createdAt, order: .reverse) private
        var transactionTemplates: [TransactionTemplateItem]
    @Query(sort: \TransferItem.timestamp, order: .reverse) private
        var transfers: [TransferItem]
    @Query private var accounts: [AccountItem]
    @Query private var categories: [CategoryItem]
    @Query private var goals: [GoalItem]
    @Query private var recurringRules: [RecurringRuleItem]
    @Query private var budgets: [BudgetPeriodItem]
    @Query private var categoryBudgets: [CategoryBudgetItem]
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
                Picker("Language", selection: $appState.selectedLanguageCode) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.title).tag(language.rawValue)
                    }
                }
                Picker("Theme", selection: $appState.selectedThemeMode) {
                    ForEach(FloatColorTheme.allCases) { theme in
                        ThemeOptionRow(theme: theme)
                            .tag(theme.rawValue)
                    }
                }
                Toggle("Privacy Lock", isOn: $appState.isAppLockEnabled)
                ThemePreviewCard(palette: appState.themePalette)
            }
            Section("Manage") {
                NavigationLink("Budget", destination: BudgetSettingsView())
                NavigationLink("Goals", destination: GoalsView())
                NavigationLink("Recurring", destination: RecurringView())
                NavigationLink("Templates", destination: TransactionTemplateManagerView())
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
        .scrollContentBackground(.hidden)
        .floatBackground()
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
        do {
            backupDocument = try BackupService.createDocument(
                accounts: accounts,
                categories: categories,
                transactions: transactions,
                transactionTemplates: transactionTemplates,
                transfers: transfers,
                goals: goals,
                recurringRules: recurringRules,
                budgets: budgets,
                categoryBudgets: categoryBudgets,
                currencyCode: appState.selectedCurrencyCode
            )
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
            appState.selectedCurrencyCode = try BackupService.restore(
                document: document,
                modelContext: modelContext
            )
            message = "Backup restored."
        } catch { message = error.localizedDescription }
    }

    private func resetAllData(reseedDefaults: Bool = true) {
        for item in transactions { modelContext.delete(item) }
        for item in transactionTemplates { modelContext.delete(item) }
        for item in transfers { modelContext.delete(item) }
        for item in recurringRules { modelContext.delete(item) }
        for item in goals { modelContext.delete(item) }
        for item in categoryBudgets { modelContext.delete(item) }
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

private struct ThemeOptionRow: View {
    let theme: FloatColorTheme

    private var palette: FloatThemePalette {
        FloatTheme.palette(for: theme)
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(theme.title)
            Spacer()
            HStack(spacing: 4) {
                Circle()
                    .fill(palette.accent)
                    .frame(width: 12, height: 12)
                Circle()
                    .fill(palette.positive)
                    .frame(width: 12, height: 12)
                Circle()
                    .fill(palette.caution)
                    .frame(width: 12, height: 12)
            }
        }
    }
}

private struct ThemePreviewCard: View {
    let palette: FloatThemePalette

    var body: some View {
        HStack(spacing: 10) {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [palette.backgroundTop, palette.backgroundBottom],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 44, height: 28)
                .overlay(
                    Capsule()
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )
            VStack(alignment: .leading, spacing: 4) {
                Text("Theme preview")
                    .font(.subheadline.weight(.medium))
                HStack(spacing: 5) {
                    ForEach(Array(palette.chartColors.prefix(6).enumerated()), id: \.offset) {
                        _, color in
                        Circle()
                            .fill(color)
                            .frame(width: 11, height: 11)
                    }
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}
