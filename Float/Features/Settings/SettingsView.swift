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
    @State private var exportingBackup = false
    @State private var importingBackup = false
    @State private var backupDocument = BackupDocument()
    @State private var message = ""
    @State private var showingResetConfirmation = false
    @State private var showingSeedConfirmation = false
    @State private var isSeedingData = false

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
        .alert("Seed sample data?", isPresented: $showingSeedConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Seed data") {
                seedSampleData()
            }
        } message: {
            Text(
                "This adds two years of varied sample transactions and transfers to your current data."
            )
        }
        .navigationDestination(item: $appState.pendingSettingsDestination) { destination in
            settingsDestination(destination)
        }
    }

    private var settingsList: some View {
        List {
            settingsSections
        }
        .keyboardDismissControls()
        .contentMargins(.top, 0, for: .scrollContent)
        .listStyle(.insetGrouped)
        .id(appState.selectedThemeMode)
    }

    @ViewBuilder
    private var settingsSections: some View {
        Section {
            SettingsPickerRow("Currency", selection: $appState.selectedCurrencyCode) {
                ForEach(Self.currencyOptions) { currency in
                    Text("\(currency.symbol) \(currency.code)")
                        .tag(currency.code)
                }
            }
            SettingsPickerRow("Appearance", selection: $appState.selectedAppearance) {
                Text("System").tag("system")
                Text("Light").tag("light")
                Text("Dark").tag("dark")
            }
            SettingsPickerRow("Language", selection: $appState.selectedLanguageCode) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.title)
                        .tag(language.rawValue)
                }
            }
            SettingsPickerRow("Theme", selection: $appState.selectedThemeMode) {
                ForEach(FloatColorTheme.allCases) { theme in
                    Text(theme.title)
                        .tag(theme.rawValue)
                }
            }
            Toggle("Privacy Lock", isOn: $appState.isAppLockEnabled)
        } header: {
            Text("Preferences")
                .textCase(nil)
                .padding(.top, -14)
        }

        Section("Reminders") {
            Toggle("Recurring due reminders", isOn: $appState.recurringRemindersEnabled)
            if appState.recurringRemindersEnabled {
                DatePicker(
                    "Recurring time",
                    selection: reminderTimeBinding(
                        get: { appState.recurringReminderMinutes },
                        set: { appState.recurringReminderMinutes = $0 }
                    ),
                    displayedComponents: .hourAndMinute
                )
            }

            Toggle("Goal target reminders", isOn: $appState.goalRemindersEnabled)
            if appState.goalRemindersEnabled {
                DatePicker(
                    "Goal time",
                    selection: reminderTimeBinding(
                        get: { appState.goalReminderMinutes },
                        set: { appState.goalReminderMinutes = $0 }
                    ),
                    displayedComponents: .hourAndMinute
                )
            }

            Toggle("Settlement due reminders", isOn: $appState.settlementRemindersEnabled)
            if appState.settlementRemindersEnabled {
                DatePicker(
                    "Settlement time",
                    selection: reminderTimeBinding(
                        get: { appState.settlementReminderMinutes },
                        set: { appState.settlementReminderMinutes = $0 }
                    ),
                    displayedComponents: .hourAndMinute
                )
            }

            Toggle("Budget alerts", isOn: $appState.budgetAlertsEnabled)
            if appState.budgetAlertsEnabled {
                SettingsPickerRow("Budget sensitivity", selection: $appState.budgetAlertSensitivityRaw) {
                    ForEach(BudgetAlertSensitivity.allCases) { sensitivity in
                        Text(sensitivity.title)
                            .tag(sensitivity.rawValue)
                    }
                }
            }
        }

        Section("Manage") {
            settingsNavigationLink("Calendar", destination: CalendarView())
            settingsNavigationLink("Budget", destination: BudgetSettingsView())
            settingsNavigationLink("Goals", destination: GoalsView())
            settingsNavigationLink("Recurring", destination: RecurringView())
            settingsNavigationLink("Templates", destination: TransactionTemplateManagerView())
            settingsNavigationLink("Template Groups", destination: TransactionTemplateGroupManagerView())
            settingsNavigationLink("Categories", destination: CategoryManagerView())
            settingsNavigationLink("Accounts", destination: AccountManagerView())
            settingsNavigationLink("People", destination: PeopleManagerView())
            settingsNavigationLink("Settlements", destination: SettlementsView())
            settingsNavigationLink("Review Queue", destination: ReviewQueueView())
        }

        Section("Portable data") {
            Button("Create backup", action: createBackup)
            Button("Restore backup", action: presentBackupImporter)
            if !message.isEmpty {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        Section("Sample data") {
            Button {
                showingSeedConfirmation = true
            } label: {
                Label("Seed data", systemImage: "tray.and.arrow.down.fill")
            }
            .disabled(isSeedingData)
            Text(
                isSeedingData
                    ? "Seeding two years of data."
                    : "Adds realistic expenses, income, and transfers for pagination testing."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Section("Privacy") {
            Text(
                "Data stays on device. Float has no backend, no account, no analytics, and no tracking SDKs. Backup files are created only when you choose them."
            )
            .font(.subheadline)
        }

        Section("About") {
            Text("Float 1.0")
        }

        Section {
            Button(
                "Reset all data",
                role: .destructive,
                action: { showingResetConfirmation = true }
            )
        }
    }

    private func settingsNavigationLink<Destination: View>(
        _ title: LocalizedStringKey,
        destination: Destination
    ) -> some View {
        NavigationLink {
            destination
        } label: {
            Text(title)
        }
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

    @ViewBuilder
    private func settingsDestination(_ destination: FloatSettingsDestination) -> some View {
        switch destination {
        case .calendar:
            CalendarView()
        case .budget:
            BudgetSettingsView()
        case .goals:
            GoalsView()
        case .recurring:
            RecurringView()
        case .templates:
            TransactionTemplateManagerView()
        case .templateGroups:
            TransactionTemplateGroupManagerView()
        case .categories:
            CategoryManagerView()
        case .accounts:
            AccountManagerView()
        case .people:
            PeopleManagerView()
        case .settlements:
            SettlementsView()
        case .reviewQueue:
            ReviewQueueView()
        }
    }

    private func reminderTimeBinding(
        get: @escaping () -> Int,
        set: @escaping (Int) -> Void
    ) -> Binding<Date> {
        Binding(
            get: { date(fromMinutes: get()) },
            set: { set(minutes(from: $0)) }
        )
    }

    private func date(fromMinutes minutes: Int) -> Date {
        let clamped = min(max(minutes, 0), 23 * 60 + 59)
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        return calendar.date(byAdding: .minute, value: clamped, to: start) ?? Date()
    }

    private func minutes(from date: Date) -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 9) * 60 + (components.minute ?? 0)
    }

    private func presentBackupImporter() {
        DispatchQueue.main.async {
            importingBackup = true
            message = "Opening backup picker."
        }
    }

    private func createBackup() {
        do {
            backupDocument = try BackupService.createDocument(
                accounts: fetchAll(AccountItem.self),
                categories: fetchAll(CategoryItem.self),
                people: fetchAll(PersonItem.self),
                eventCategories: fetchAll(EventCategoryItem.self),
                events: fetchAll(EventItem.self),
                transactions: fetchAll(TransactionItem.self),
                transactionPersonTags: fetchAll(TransactionPersonTagItem.self),
                transactionTemplates: fetchAll(TransactionTemplateItem.self),
                transactionTemplateGroups: fetchAll(TransactionTemplateGroupItem.self),
                transfers: fetchAll(TransferItem.self),
                goals: fetchAll(GoalItem.self),
                recurringRules: fetchAll(RecurringRuleItem.self),
                recurringRulePersonTags: fetchAll(RecurringRulePersonTagItem.self),
                budgets: fetchAll(BudgetPeriodItem.self),
                categoryBudgets: fetchAll(CategoryBudgetItem.self),
                settlementCases: fetchAll(SettlementCaseItem.self),
                settlementEntries: fetchAll(SettlementEntryItem.self),
                settlementMilestones: fetchAll(SettlementMilestoneItem.self),
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
            FloatSpotlightIndexer.scheduleReindex(modelContext: modelContext)
            message = "Backup restored."
        } catch { message = error.localizedDescription }
    }

    private func seedSampleData() {
        guard !isSeedingData else { return }
        isSeedingData = true
        message = "Seeding sample data."
        do {
            let summary = try SeedDataService.seedLargeTransactionHistory(
                modelContext: modelContext,
                currencyCode: appState.selectedCurrencyCode
            )
            FloatSpotlightIndexer.scheduleReindex(modelContext: modelContext)
            message =
                "Seeded \(summary.transactionCount) transactions and \(summary.transferCount) transfers."
        } catch {
            message = error.localizedDescription
        }
        isSeedingData = false
    }

    private func resetAllData(reseedDefaults: Bool = true) {
        for item in fetchAll(TransactionPersonTagItem.self) { modelContext.delete(item) }
        for item in fetchAll(RecurringRulePersonTagItem.self) { modelContext.delete(item) }
        for item in fetchAll(SettlementMilestoneItem.self) { modelContext.delete(item) }
        for item in fetchAll(SettlementEntryItem.self) { modelContext.delete(item) }
        for item in fetchAll(SettlementCaseItem.self) { modelContext.delete(item) }
        for item in fetchAll(TransactionItem.self) { modelContext.delete(item) }
        for item in fetchAll(TransactionTemplateGroupItem.self) { modelContext.delete(item) }
        for item in fetchAll(TransactionTemplateItem.self) { modelContext.delete(item) }
        for item in fetchAll(TransferItem.self) { modelContext.delete(item) }
        for item in fetchAll(EventItem.self) { modelContext.delete(item) }
        for item in fetchAll(EventCategoryItem.self) { modelContext.delete(item) }
        for item in fetchAll(RecurringRuleItem.self) { modelContext.delete(item) }
        for item in fetchAll(GoalItem.self) { modelContext.delete(item) }
        for item in fetchAll(CategoryBudgetItem.self) { modelContext.delete(item) }
        for item in fetchAll(BudgetPeriodItem.self) { modelContext.delete(item) }
        for item in fetchAll(AccountItem.self) { modelContext.delete(item) }
        for item in fetchAll(PersonItem.self) { modelContext.delete(item) }
        for item in fetchAll(CategoryItem.self) { modelContext.delete(item) }
        guard (try? modelContext.save()) != nil else { return }
        if reseedDefaults {
            SeedDataService.ensureSeedData(
                modelContext: modelContext,
                currencyCode: appState.selectedCurrencyCode
            )
        }
        FloatSpotlightIndexer.scheduleReindex(modelContext: modelContext)
    }

    private func fetchAll<T: PersistentModel>(_ type: T.Type) -> [T] {
        (try? modelContext.fetch(FetchDescriptor<T>())) ?? []
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

private struct SettingsPickerRow<SelectionValue: Hashable, Content: View>: View {
    private let title: LocalizedStringKey
    @Binding private var selection: SelectionValue
    private let content: Content

    init(
        _ title: LocalizedStringKey,
        selection: Binding<SelectionValue>,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self._selection = selection
        self.content = content()
    }

    var body: some View {
        LabeledContent {
            Picker("", selection: $selection) {
                content
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
        } label: {
            Text(title)
        }
    }
}

private struct ThemeOptionRow: View {
    let theme: FloatColorTheme

    private var palette: FloatThemePalette {
        FloatTheme.palette(for: theme)
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                palette.backgroundTop,
                                palette.backgroundBottom
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 42, height: 42)
                HStack(spacing: 3) {
                    ForEach(Array(palette.chartColors.prefix(3).enumerated()), id: \.offset) {
                        _, color in
                        Circle()
                            .fill(color)
                            .frame(width: 8, height: 8)
                    }
                }
                .padding(8)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(theme.title)
                    .font(.body.weight(.semibold))
                Text(theme.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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
