import Foundation

struct SafeToSpendResult: Equatable {
    let periodStart: Date
    let periodEnd: Date
    let expectedIncomeMinor: Int64
    let recurringDueMinor: Int64
    let goalContributionMinor: Int64
    let variableSpentMinor: Int64
    let safeToSpendMinor: Int64
    let dailyAllowanceMinor: Int64
    let overAmountMinor: Int64
    let daysRemaining: Int
    let periodProgress: Double
    let spendingProgress: Double
}

enum SafeToSpendUseCase {
    static func calculate(
        budget: BudgetPeriodItem?,
        transactions: [TransactionItem],
        goals: [GoalItem],
        recurringRules: [RecurringRuleItem],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> SafeToSpendResult {
        let period = BudgetPeriodCalculator.currentPeriod(for: budget, now: now, calendar: calendar)
        let expectedIncome = budget?.expectedIncomeMinor ?? 0
        let variableSpent = transactions
            .filter { $0.isExpense && period.start <= $0.timestamp && $0.timestamp <= calendar.endOfDay(for: now) && $0.recurringRule == nil }
            .reduce(Int64(0)) { $0 + $1.amountMinor }
        let recurringDue = recurringRules
            .filter { $0.active && $0.isExpense && isRuleDue($0, in: period, calendar: calendar) }
            .reduce(Int64(0)) { $0 + $1.amountMinor }
        let goalContribution = goals.reduce(Int64(0)) { partial, goal in
            guard !goal.achieved, goal.targetMinor > goal.savedMinor else { return partial }
            return partial + max(0, goal.targetMinor - goal.savedMinor)
        }
        let raw = expectedIncome - recurringDue - goalContribution - variableSpent
        let safe = max(0, raw)
        let over = max(0, -raw)
        let days = max(1, BudgetPeriodCalculator.daysRemaining(in: period, now: now, calendar: calendar))
        let spendingBase = max(Int64(1), expectedIncome - recurringDue - goalContribution)
        let spendingProgress = min(1, Double(variableSpent) / Double(spendingBase))
        return SafeToSpendResult(
            periodStart: period.start,
            periodEnd: period.end,
            expectedIncomeMinor: expectedIncome,
            recurringDueMinor: recurringDue,
            goalContributionMinor: goalContribution,
            variableSpentMinor: variableSpent,
            safeToSpendMinor: safe,
            dailyAllowanceMinor: safe / Int64(days),
            overAmountMinor: over,
            daysRemaining: days,
            periodProgress: BudgetPeriodCalculator.progress(in: period, now: now, calendar: calendar),
            spendingProgress: spendingProgress
        )
    }

    private static func isRuleDue(_ rule: RecurringRuleItem, in period: BudgetPeriod, calendar: Calendar) -> Bool {
        var date = calendar.startOfDay(for: rule.nextRunDate)
        let periodEnd = calendar.startOfDay(for: period.end)
        let periodStart = calendar.startOfDay(for: period.start)
        while date <= periodEnd {
            if date >= periodStart { return true }
            guard let advanced = advance(date, cadence: rule.cadence, intervalCount: rule.intervalCount, calendar: calendar) else { return false }
            date = advanced
        }
        return false
    }

    static func advance(_ date: Date, cadence: RecurringCadence, intervalCount: Int, calendar: Calendar = .current) -> Date? {
        let count = max(1, intervalCount)
        switch cadence {
        case .daily: return calendar.date(byAdding: .day, value: count, to: date)
        case .weekly: return calendar.date(byAdding: .weekOfYear, value: count, to: date)
        case .monthly: return calendar.date(byAdding: .month, value: count, to: date)
        }
    }
}

private extension Calendar {
    func endOfDay(for date: Date) -> Date {
        let start = startOfDay(for: date)
        return self.date(byAdding: DateComponents(day: 1, second: -1), to: start) ?? date
    }
}
