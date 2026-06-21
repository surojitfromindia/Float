import SwiftData
import SwiftUI

struct ScenarioPlannerView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @Query(sort: \ScenarioPlanItem.plannedDate) private var allScenarios: [ScenarioPlanItem]
    @Query(sort: \AccountItem.createdAt) private var allAccounts: [AccountItem]
    @Query(sort: \CategoryItem.sortOrder) private var allCategories: [CategoryItem]
    @Query private var allBudgets: [BudgetPeriodItem]
    @Query private var allGoals: [GoalItem]
    @Query private var allRecurringRules: [RecurringRuleItem]
    @Query private var allTransactions: [TransactionItem]
    @Query private var allTransfers: [TransferItem]

    @State private var editingScenario: ScenarioPlanItem?
    @State private var isCreatingScenario = false

    private var scenarios: [ScenarioPlanItem] {
        filterActiveProfile(allScenarios).filter { !$0.archived }
    }
    private var accounts: [AccountItem] { filterActiveProfile(allAccounts) }
    private var categories: [CategoryItem] { filterActiveProfile(allCategories) }
    private var budgets: [BudgetPeriodItem] { filterActiveProfile(allBudgets) }
    private var goals: [GoalItem] { filterActiveProfile(allGoals) }
    private var recurringRules: [RecurringRuleItem] { filterActiveProfile(allRecurringRules) }
    private var transactions: [TransactionItem] { filterActiveProfile(allTransactions) }
    private var transfers: [TransferItem] { filterActiveProfile(allTransfers) }

    private var activeBudget: BudgetPeriodItem? {
        budgets.first { $0.isActive } ?? budgets.first
    }

    private var forecast: ScenarioForecastSummary {
        ScenarioForecastUseCase.calculate(
            accounts: accounts,
            transactions: transactions,
            transfers: transfers,
            budget: activeBudget,
            goals: goals,
            recurringRules: recurringRules,
            scenarios: scenarios
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                overviewCard
                forecastCard
                scenarioList
            }
            .padding(20)
            .padding(.bottom, 40)
        }
        .navigationTitle("Planner")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isCreatingScenario = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(String(localized: "Add scenario"))
            }
        }
        .sheet(isPresented: $isCreatingScenario) {
            ScenarioPlanEditorView(
                scenario: nil,
                accounts: accounts,
                categories: categories,
                currencyCode: appState.selectedCurrencyCode
            )
        }
        .sheet(item: $editingScenario) { scenario in
            ScenarioPlanEditorView(
                scenario: scenario,
                accounts: accounts,
                categories: categories,
                currencyCode: appState.selectedCurrencyCode
            )
        }
        .floatBackground()
    }

    private var overviewCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    FloatIconBadge(
                        icon: "wand.and.stars",
                        tint: appState.themePalette.accent,
                        size: 42
                    )
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Scenario Planner")
                            .font(.headline.weight(.semibold))
                        Text("Test future spending or income without saving real transactions.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                ViewThatFits {
                    HStack(spacing: 10) {
                        summaryTile(
                            title: "Current safe",
                            value: money(forecast.baselineSafeToSpend.safeToSpendMinor),
                            icon: "checkmark.seal.fill",
                            tint: appState.themePalette.positive
                        )
                        summaryTile(
                            title: "After scenarios",
                            value: money(forecast.adjustedCurrentSafeToSpendMinor),
                            icon: "arrow.triangle.branch",
                            tint: forecast.currentPeriodImpactMinor < 0
                                ? appState.themePalette.caution
                                : appState.themePalette.positive
                        )
                    }

                    VStack(spacing: 10) {
                        summaryTile(
                            title: "Current safe",
                            value: money(forecast.baselineSafeToSpend.safeToSpendMinor),
                            icon: "checkmark.seal.fill",
                            tint: appState.themePalette.positive
                        )
                        summaryTile(
                            title: "After scenarios",
                            value: money(forecast.adjustedCurrentSafeToSpendMinor),
                            icon: "arrow.triangle.branch",
                            tint: forecast.currentPeriodImpactMinor < 0
                                ? appState.themePalette.caution
                                : appState.themePalette.positive
                        )
                    }
                }
            }
        }
    }

    private var forecastCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Scenario forecast")
            VStack(spacing: 12) {
                if forecast.forecastItems.isEmpty {
                    EmptyStateView(
                        icon: "calendar.badge.clock",
                        title: "No forecast yet",
                        message: "Add a budget and scenario to preview future cash flow."
                    )
                } else {
                    ForEach(forecast.forecastItems) { item in
                        ScenarioForecastRow(
                            item: item,
                            currencyCode: appState.selectedCurrencyCode,
                            tint: item.scenarioImpactMinor < 0
                                ? appState.themePalette.caution
                                : appState.themePalette.positive
                        )
                        if item.id != forecast.forecastItems.last?.id {
                            Divider()
                        }
                    }
                }
            }
            .padding(18)
            .transactionSectionGlassSurface(cornerRadius: 24)
        }
    }

    private var scenarioList: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Saved scenarios")
            if scenarios.isEmpty {
                GlassCard {
                    EmptyStateView(
                        icon: "plus.circle",
                        title: "No scenarios",
                        message: "Add a planned purchase, bill, trip, or income change to see its effect."
                    )
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(scenarios) { scenario in
                        Button {
                            editingScenario = scenario
                        } label: {
                            ScenarioPlanRow(
                                scenario: scenario,
                                currencyCode: appState.selectedCurrencyCode,
                                tint: appState.themePalette.accent
                            )
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button("Delete", role: .destructive) {
                                delete(scenario)
                            }
                        }
                        if scenario.id != scenarios.last?.id {
                            Divider()
                        }
                    }
                }
                .padding(16)
                .transactionSectionGlassSurface(cornerRadius: 24)
            }
        }
    }

    private func summaryTile(
        title: LocalizedStringResource,
        value: String,
        icon: String,
        tint: Color
    ) -> some View {
        SummaryMetricTile(
            title: title,
            value: value,
            captionText: impactText,
            icon: icon,
            tint: tint
        )
    }

    private var impactText: String {
        let impact = forecast.currentPeriodImpactMinor
        if impact == 0 {
            return String(localized: "No current-period impact")
        }
        return AppLocalization.format(
            "%@ impact this period",
            MoneyFormatter.string(
                minorUnits: abs(impact),
                currencyCode: appState.selectedCurrencyCode
            )
        )
    }

    private func delete(_ scenario: ScenarioPlanItem) {
        modelContext.delete(scenario)
        try? modelContext.save()
    }

    private func money(_ amount: Int64) -> String {
        MoneyFormatter.string(
            minorUnits: amount,
            currencyCode: appState.selectedCurrencyCode
        )
    }
}

private struct ScenarioForecastRow: View {
    let item: ScenarioForecastItem
    let currencyCode: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            FloatIconBadge(icon: "calendar.badge.clock", tint: tint, size: 36)
            VStack(alignment: .leading, spacing: 4) {
                Text(AppLocalization.format("%lldd outlook", Int64(item.horizonDays)))
                    .font(.subheadline.weight(.semibold))
                Text(AppLocalization.format(
                    "%@ baseline",
                    money(item.baselineSafeToSpendMinor)
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                Text(money(item.adjustedSafeToSpendMinor))
                    .moneyStyle(size: 15, weight: .bold)
                Text(impactText)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(tint)
            }
        }
    }

    private var impactText: String {
        let sign = item.scenarioImpactMinor < 0 ? "-" : "+"
        return "\(sign)\(money(abs(item.scenarioImpactMinor)))"
    }

    private func money(_ amount: Int64) -> String {
        MoneyFormatter.string(minorUnits: amount, currencyCode: currencyCode)
    }
}

private struct ScenarioPlanRow: View {
    let scenario: ScenarioPlanItem
    let currencyCode: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            FloatIconBadge(
                icon: scenario.isExpense ? "minus.circle.fill" : "plus.circle.fill",
                tint: scenario.isExpense ? Color(hex: "#B4613B") : tint,
                size: 36
            )
            VStack(alignment: .leading, spacing: 4) {
                Text(scenario.displayTitle)
                    .font(.subheadline.weight(.semibold))
                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(money(scenario.amountMinor))
                .moneyStyle(size: 15, weight: .bold)
        }
        .padding(.vertical, 8)
    }

    private var detailText: String {
        let date = scenario.plannedDate.formatted(date: .abbreviated, time: .omitted)
        if scenario.recurrence == .none {
            return date
        }
        return AppLocalization.format(
            "%@ - %lld times",
            scenario.recurrence.title,
            Int64(scenario.occurrenceCount)
        )
    }

    private func money(_ amount: Int64) -> String {
        MoneyFormatter.string(minorUnits: amount, currencyCode: currencyCode)
    }
}

private struct ScenarioPlanEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let scenario: ScenarioPlanItem?
    let accounts: [AccountItem]
    let categories: [CategoryItem]
    let currencyCode: String

    @State private var title = ""
    @State private var amountText = ""
    @State private var isExpense = true
    @State private var plannedDate = Date()
    @State private var recurrence = ScenarioRecurrence.none
    @State private var occurrenceCount = 3
    @State private var categoryID = ""
    @State private var accountID = ""
    @State private var note = ""
    @State private var validationMessage: String?

    private var amountMinor: Int64 {
        MoneyParser.parseDisplayAmountMinor(
            from: amountText,
            currencyCode: currencyCode
        )
    }

    private var visibleCategories: [CategoryItem] {
        categories.filter { !$0.archived && $0.isIncome != isExpense }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Scenario") {
                    Picker("Type", selection: $isExpense) {
                        Text("Expense").tag(true)
                        Text("Income").tag(false)
                    }
                    TextField("Title", text: $title)
                    TextField("Amount", text: $amountText)
                        .keyboardType(.decimalPad)
                    DatePicker("Date", selection: $plannedDate, displayedComponents: [.date])
                }

                Section("Repeat") {
                    Picker("Repeats", selection: $recurrence) {
                        ForEach(ScenarioRecurrence.allCases) { recurrence in
                            Text(recurrence.title).tag(recurrence)
                        }
                    }
                    if recurrence != .none {
                        Stepper(
                            AppLocalization.format("%lld times", Int64(occurrenceCount)),
                            value: $occurrenceCount,
                            in: 1...60
                        )
                    }
                }

                Section("Details") {
                    Picker("Category", selection: $categoryID) {
                        Text("None").tag("")
                        ForEach(visibleCategories) { category in
                            Text(category.name).tag(category.id.uuidString)
                        }
                    }
                    Picker("Account", selection: $accountID) {
                        Text("None").tag("")
                        ForEach(accounts.filter { !$0.archived }) { account in
                            Text(account.name).tag(account.id.uuidString)
                        }
                    }
                    TextField("Note", text: $note, axis: .vertical)
                        .lineLimit(1...3)
                }

                if let validationMessage {
                    Section {
                        Text(validationMessage)
                            .font(.footnote)
                            .foregroundStyle(Color(hex: "#B4613B"))
                    }
                }
            }
            .navigationTitle(scenario == nil ? "Add scenario" : "Edit scenario")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                }
            }
            .onAppear(perform: configure)
        }
    }

    private func configure() {
        guard title.isEmpty, amountText.isEmpty else { return }
        guard let scenario else {
            plannedDate = Date()
            return
        }
        title = scenario.title
        amountText = MoneyFormatter.string(
            minorUnits: scenario.amountMinor,
            currencyCode: currencyCode
        )
        isExpense = scenario.isExpense
        plannedDate = scenario.plannedDate
        recurrence = scenario.recurrence
        occurrenceCount = scenario.occurrenceCount
        categoryID = scenario.category?.id.uuidString ?? ""
        accountID = scenario.account?.id.uuidString ?? ""
        note = scenario.note ?? ""
    }

    private func save() {
        guard amountMinor > 0 else {
            validationMessage = String(localized: "Enter an amount greater than zero.")
            return
        }
        let category = visibleCategories.first { $0.id.uuidString == categoryID }
        let account = accounts.first { $0.id.uuidString == accountID && !$0.archived }
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanNote = note.trimmingCharacters(in: .whitespacesAndNewlines)

        if let scenario {
            scenario.title = cleanTitle.isEmpty
                ? String(localized: "Scenario")
                : cleanTitle
            scenario.amountMinor = amountMinor
            scenario.isExpense = isExpense
            scenario.plannedDate = plannedDate
            scenario.recurrence = recurrence
            scenario.occurrenceCount = recurrence == .none ? 1 : occurrenceCount
            scenario.category = category
            scenario.account = account
            scenario.note = cleanNote.isEmpty ? nil : cleanNote
            scenario.updatedAt = Date()
        } else {
            modelContext.insert(
                ScenarioPlanItem(
                    title: cleanTitle.isEmpty
                        ? String(localized: "Scenario")
                        : cleanTitle,
                    amountMinor: amountMinor,
                    isExpense: isExpense,
                    plannedDate: plannedDate,
                    recurrence: recurrence,
                    occurrenceCount: occurrenceCount,
                    category: category,
                    account: account,
                    note: cleanNote
                )
            )
        }
        try? modelContext.save()
        dismiss()
    }
}
