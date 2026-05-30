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

enum CalculateSafeToSpendUseCase {
    static func calculate(
        budget: BudgetPeriodItem?,
        transactions: [TransactionItem],
        goals: [GoalItem],
        recurringRules: [RecurringRuleItem],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> SafeToSpendResult {
        SafeToSpendUseCase.calculate(
            budget: budget,
            transactions: transactions,
            goals: goals,
            recurringRules: recurringRules,
            now: now,
            calendar: calendar
        )
    }
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
        let period = BudgetPeriodCalculator.currentPeriod(
            for: budget,
            now: now,
            calendar: calendar
        )
        let expectedIncome = budget?.expectedIncomeMinor ?? 0
        return calculate(
            period: period,
            expectedIncomeMinor: expectedIncome,
            transactions: transactions,
            goals: goals,
            recurringRules: recurringRules,
            now: now,
            calendar: calendar
        )
    }

    static func calculate(
        period: BudgetPeriod,
        expectedIncomeMinor: Int64,
        transactions: [TransactionItem],
        goals: [GoalItem],
        recurringRules: [RecurringRuleItem],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> SafeToSpendResult {
        let expectedIncome = max(0, expectedIncomeMinor)
        let effectiveNow = min(now, calendar.endOfDay(for: period.end))
        let variableSpent = transactions
            .filter {
                $0.isExpense
                    && period.contains($0.timestamp, calendar: calendar)
                    && $0.timestamp <= calendar.endOfDay(for: effectiveNow)
                    && $0.recurringRule == nil
            }
            .reduce(Int64(0)) { $0 + $1.amountMinor }
        let recurringDue = RecurringDueCalculator.amountDue(
            rules: recurringRules,
            transactions: transactions,
            period: period,
            calendar: calendar
        )
        let goalContribution = GoalContributionCalculator.requiredContribution(
            goals: goals,
            period: period,
            now: now,
            calendar: calendar
        )
        let raw =
            expectedIncome - recurringDue - goalContribution - variableSpent
        let safe = max(0, raw)
        let over = max(0, -raw)
        let days = max(
            1,
            BudgetPeriodCalculator.daysRemaining(
                in: period,
                now: now,
                calendar: calendar
            )
        )
        let spendingBase = max(
            Int64(1),
            expectedIncome - recurringDue - goalContribution
        )
        let spendingProgress = min(
            1,
            Double(variableSpent) / Double(spendingBase)
        )
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
            periodProgress: BudgetPeriodCalculator.progress(
                in: period,
                now: now,
                calendar: calendar
            ),
            spendingProgress: spendingProgress
        )
    }

    static func advance(
        _ date: Date,
        cadence: RecurringCadence,
        intervalCount: Int,
        calendar: Calendar = .current
    ) -> Date? {
        let count = max(1, intervalCount)
        switch cadence {
        case .daily:
            return calendar.date(byAdding: .day, value: count, to: date)
        case .weekly:
            return calendar.date(byAdding: .weekOfYear, value: count, to: date)
        case .monthly:
            return calendar.date(byAdding: .month, value: count, to: date)
        }
    }
}

enum GoalContributionCalculator {
    static func requiredContribution(
        goals: [GoalItem],
        period: BudgetPeriod,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Int64 {
        goals.reduce(Int64(0)) { partial, goal in
            guard !goal.achieved, goal.targetMinor > goal.savedMinor else {
                return partial
            }

            let remaining = goal.targetMinor - goal.savedMinor
            guard let targetDate = goal.targetDate else {
                return partial + remaining
            }

            let today = calendar.startOfDay(for: now)
            let target = calendar.startOfDay(for: targetDate)
            guard target >= today else {
                return partial + remaining
            }

            let daysUntilTarget =
                (calendar.dateComponents([.day], from: today, to: target).day ?? 0) + 1
            let periodDays = BudgetPeriodCalculator.daysRemaining(
                in: period,
                now: now,
                calendar: calendar
            )
            let daysToFundThisPeriod = min(max(1, periodDays), max(1, daysUntilTarget))
            let dailyRequired = ceilDivide(remaining, by: Int64(max(1, daysUntilTarget)))
            return partial + min(remaining, dailyRequired * Int64(daysToFundThisPeriod))
        }
    }

    private static func ceilDivide(_ value: Int64, by divisor: Int64) -> Int64 {
        guard divisor > 0 else { return value }
        return (value + divisor - 1) / divisor
    }
}

enum RecurringDueCalculator {
    static func amountDue(
        rules: [RecurringRuleItem],
        transactions: [TransactionItem],
        period: BudgetPeriod,
        calendar: Calendar = .current
    ) -> Int64 {
        let materializedRecurring = transactions
            .filter {
                $0.isExpense
                    && $0.recurringRule != nil
                    && period.contains($0.timestamp, calendar: calendar)
            }
            .reduce(Int64(0)) { $0 + $1.amountMinor }

        let unmaterializedDue = rules.reduce(Int64(0)) { partial, rule in
            guard rule.active, rule.isExpense, rule.amountMinor > 0 else {
                return partial
            }

            return partial + dueDates(
                for: rule,
                in: period,
                calendar: calendar
            )
            .filter {
                !hasMaterializedTransaction(
                    for: rule,
                    on: $0,
                    transactions: transactions,
                    calendar: calendar
                )
            }
            .reduce(Int64(0)) { runningTotal, _ in
                runningTotal + rule.amountMinor
            }
        }
        return unmaterializedDue + materializedRecurring
    }

    private static func dueDates(
        for rule: RecurringRuleItem,
        in period: BudgetPeriod,
        calendar: Calendar
    ) -> [Date] {
        var dates: [Date] = []
        var date = calendar.startOfDay(for: rule.nextRunDate)
        let periodEnd = calendar.startOfDay(for: period.end)
        let periodStart = calendar.startOfDay(for: period.start)

        while date <= periodEnd {
            if let endDate = rule.endDate, date > calendar.startOfDay(for: endDate) {
                break
            }

            if date >= periodStart {
                dates.append(date)
            }

            guard
                let advanced = SafeToSpendUseCase.advance(
                    date,
                    cadence: rule.cadence,
                    intervalCount: rule.intervalCount,
                    calendar: calendar
                ),
                advanced > date
            else { break }

            date = calendar.startOfDay(for: advanced)
        }

        return dates
    }

    private static func hasMaterializedTransaction(
        for rule: RecurringRuleItem,
        on date: Date,
        transactions: [TransactionItem],
        calendar: Calendar
    ) -> Bool {
        transactions.contains {
            $0.recurringRule?.id == rule.id
                && calendar.isDate($0.timestamp, inSameDayAs: date)
                && $0.amountMinor == rule.amountMinor
                && $0.isExpense == rule.isExpense
        }
    }
}

extension BudgetPeriod {
    func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        start <= date && date <= calendar.endOfDay(for: end)
    }
}

extension Calendar {
    fileprivate func endOfDay(for date: Date) -> Date {
        let start = startOfDay(for: date)
        return self.date(
            byAdding: DateComponents(day: 1, second: -1),
            to: start
        ) ?? date
    }
}
