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
