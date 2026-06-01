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
        let activeBudget = budgets.first { $0.isActive }
        let result = SafeToSpendUseCase.calculate(
            budget: activeBudget,
            transactions: transactions,
            goals: goals,
            recurringRules: recurringRules
        )
        let snapshot = FloatWidgetSnapshot(
            safeToSpendMinor: result.safeToSpendMinor,
            dailyAllowanceMinor: result.dailyAllowanceMinor,
            daysRemaining: result.daysRemaining,
            periodProgress: result.periodProgress,
            statusText: statusText(for: result),
            currencyCode: currencyCode,
            updatedAt: Date()
        )

        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        userDefaults.set(data, forKey: snapshotKey)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private static func statusText(for result: SafeToSpendResult) -> String {
        if result.overAmountMinor > 0 {
            return "Over budget"
        }
        if result.spendingProgress > result.periodProgress + 0.12 {
            return "Spending fast"
        }
        return "On track"
    }
}
