import Foundation
import SwiftData
import WidgetKit

private struct FloatWidgetSnapshot: Codable {
    let safeToSpendMinor: Int64
    let dailyAllowanceMinor: Int64
    let daysRemaining: Int
    let periodProgress: Double
    let statusText: String
    let currencyCode: String
    let updatedAt: Date
    let todayExpensesMinor: Int64
    let nextRecurringTitle: String?
    let nextRecurringAmountMinor: Int64?
    let topBudgetAlertTitle: String?
    let topBudgetAlertProgress: Double?
}

enum WidgetSnapshotPublisher {
    private static let appGroupIdentifier = "group.com.reducer.Float"
    private static let snapshotKey = "float.safeToSpend.widgetSnapshot"

    @MainActor
    static func publish(
        modelContext: ModelContext,
        currencyCode: String
    ) {
        guard let userDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            return
        }

        let budgets = (try? modelContext.fetch(FetchDescriptor<BudgetPeriodItem>())) ?? []
        let transactions =
            (try? modelContext.fetch(FetchDescriptor<TransactionItem>())) ?? []
        let goals = (try? modelContext.fetch(FetchDescriptor<GoalItem>())) ?? []
        let recurringRules =
            (try? modelContext.fetch(FetchDescriptor<RecurringRuleItem>())) ?? []
        let categoryBudgets =
            (try? modelContext.fetch(FetchDescriptor<CategoryBudgetItem>())) ?? []
        let activeBudget = budgets.first { $0.isActive }
        let period = BudgetPeriodCalculator.currentPeriod(for: activeBudget)
        let result = SafeToSpendUseCase.calculate(
            period: period,
            expectedIncomeMinor: activeBudget?.expectedIncomeMinor ?? 0,
            transactions: transactions.filter {
                $0.isPosted && period.contains($0.timestamp, calendar: .current)
            },
            goals: goals,
            recurringRules: recurringRules
        )
        let alerts = BudgetAlertsUseCase.calculate(
            categoryBudgets: categoryBudgets,
            transactions: transactions,
            period: period
        )
        let nextRecurring = recurringRules
            .filter { $0.active && $0.isExpense }
            .sorted { $0.nextRunDate < $1.nextRunDate }
            .first
        let snapshot = FloatWidgetSnapshot(
            safeToSpendMinor: result.safeToSpendMinor,
            dailyAllowanceMinor: result.dailyAllowanceMinor,
            daysRemaining: result.daysRemaining,
            periodProgress: result.periodProgress,
            statusText: statusText(for: result),
            currencyCode: currencyCode,
            updatedAt: Date(),
            todayExpensesMinor: todayExpensesMinor(transactions),
            nextRecurringTitle: nextRecurringTitle(nextRecurring),
            nextRecurringAmountMinor: nextRecurring?.amountMinor,
            topBudgetAlertTitle: alerts.first?.title,
            topBudgetAlertProgress: alerts.first?.progress
        )

        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        userDefaults.set(data, forKey: snapshotKey)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private static func statusText(for result: SafeToSpendResult) -> String {
        if result.overAmountMinor > 0 {
            return String(localized: "Over budget")
        }
        if result.spendingProgress > result.periodProgress + 0.12 {
            return String(localized: "Spending fast")
        }
        return String(localized: "On track")
    }

    private static func todayExpensesMinor(_ transactions: [TransactionItem]) -> Int64 {
        let calendar = Calendar.current
        let today = Date()
        return transactions
            .filter { $0.isPostedExpense && calendar.isDate($0.timestamp, inSameDayAs: today) }
            .reduce(Int64(0)) { $0 + $1.amountMinor }
    }

    private static func nextRecurringTitle(_ rule: RecurringRuleItem?) -> String? {
        guard let rule else { return nil }
        return rule.note?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? rule.note
            : rule.category?.name
    }
}
