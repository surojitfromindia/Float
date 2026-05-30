import SwiftData
import SwiftUI

struct BudgetSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @Query(sort: \TransactionItem.timestamp, order: .reverse) private
        var transactions: [TransactionItem]
    @Query private var goals: [GoalItem]
    @Query private var recurringRules: [RecurringRuleItem]
    @Query private var budgets: [BudgetPeriodItem]
    @Query(sort: \CategoryItem.sortOrder) private var categories: [CategoryItem]
    @Query private var categoryBudgets: [CategoryBudgetItem]

    @State private var cadence: BudgetCadence = .monthly
    @State private var startDayOfMonth = 1
    @State private var startDayOfWeek = Calendar.current.firstWeekday
    @State private var expectedIncomeText = ""
    @State private var categoryBudgetTexts: [UUID: String] = [:]
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

    private var expenseCategories: [CategoryItem] {
        categories.filter { !$0.isIncome && !$0.archived }
    }

    private var categoryBudgetTotalMinor: Int64 {
        expenseCategories.reduce(Int64(0)) { total, category in
            total + categoryBudgetMinor(for: category)
        }
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
                budgetRow("Category budgets", categoryBudgetTotalMinor)
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

            Section {
                if expenseCategories.isEmpty {
                    Text("Add expense categories before setting category budgets.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(expenseCategories) { category in
                        categoryBudgetRow(category)
                    }
                }
            } header: {
                Text("Category budgets")
            } footer: {
                Text("Set an amount for each expense category in one budget period. Leave a category blank or enter 0 to remove its budget.")
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

    private func categoryBudgetRow(_ category: CategoryItem) -> some View {
        HStack(spacing: 12) {
            Label {
                Text(category.name)
            } icon: {
                Image(systemName: category.iconKey)
                    .foregroundStyle(Color(hex: category.colorHex))
            }
            Spacer()
            TextField("0", text: binding(for: category))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(minWidth: 72, maxWidth: 110)
            CurrencyAmountPreview(
                minorUnits: categoryBudgetMinor(for: category),
                currencyCode: appState.selectedCurrencyCode
            )
            .frame(width: 82, alignment: .trailing)
        }
    }

    private func binding(for category: CategoryItem) -> Binding<String> {
        Binding(
            get: { categoryBudgetTexts[category.id, default: ""] },
            set: { categoryBudgetTexts[category.id] = $0 }
        )
    }

    private func categoryBudgetMinor(for category: CategoryItem) -> Int64 {
        BudgetAmountField.minorUnits(
            fromMajorAmount: categoryBudgetTexts[category.id, default: ""],
            currencyCode: appState.selectedCurrencyCode
        )
    }

    private func configure() {
        guard let budget = activeBudget else {
            expectedIncomeText = ""
            configureCategoryBudgets()
            return
        }
        cadence = budget.cadence
        startDayOfMonth = budget.startDayOfMonth ?? 1
        startDayOfWeek = budget.startDayOfWeek ?? Calendar.current.firstWeekday
        expectedIncomeText = BudgetAmountField.majorAmountString(
            minorUnits: budget.expectedIncomeMinor,
            currencyCode: budget.currencyCode
        )
        configureCategoryBudgets()
    }

    private func configureCategoryBudgets() {
        var values: [UUID: String] = [:]
        for budget in categoryBudgets where budget.isActive {
            guard let category = budget.category else { continue }
            values[category.id] = BudgetAmountField.majorAmountString(
                minorUnits: budget.amountMinor,
                currencyCode: budget.currencyCode
            )
        }
        categoryBudgetTexts = values
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
        saveCategoryBudgets()
        try? modelContext.save()
        message = "Budget saved."
    }

    private func saveCategoryBudgets() {
        let repository = CategoryBudgetRepository(modelContext: modelContext)
        for category in expenseCategories {
            try? repository.save(
                category: category,
                amountMinor: categoryBudgetMinor(for: category),
                currencyCode: appState.selectedCurrencyCode,
                existingBudgets: categoryBudgets
            )
        }
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
