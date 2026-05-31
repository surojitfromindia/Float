import Foundation

struct CashFlowForecastItem: Identifiable, Equatable {
    let horizonDays: Int
    let safeToSpendMinor: Int64
    let dailySafeMinor: Int64
    let projectedBalanceMinor: Int64
    let recurringIncomeMinor: Int64
    let recurringExpenseMinor: Int64
    let goalReserveMinor: Int64
    let budgetAllowanceMinor: Int64

    var id: Int { horizonDays }
    var title: String { "\(horizonDays)d" }
}

enum CashFlowForecastUseCase {
    static func calculate(
        horizons: [Int] = [7, 14, 30],
        accounts: [AccountItem],
        transactions: [TransactionItem],
        budget: BudgetPeriodItem?,
        safeToSpend: SafeToSpendResult,
        goals: [GoalItem],
        recurringRules: [RecurringRuleItem],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [CashFlowForecastItem] {
        let balance = currentBalanceMinor(accounts: accounts, transactions: transactions)
        return horizons.map { days in
            let horizonEnd =
                calendar.date(byAdding: .day, value: max(1, days) - 1, to: now)
                ?? now
            let window = BudgetPeriod(
                start: calendar.startOfDay(for: now),
                end: calendar.startOfDay(for: horizonEnd)
            )
            let recurring = recurringTotals(
                rules: recurringRules,
                in: window,
                calendar: calendar
            )
            let goalReserve = goalReserveMinor(
                goals: goals,
                horizonDays: days,
                now: now,
                calendar: calendar
            )
            let budgetAllowance = safeToSpend.dailyAllowanceMinor
                * Int64(max(1, min(days, safeToSpend.daysRemaining)))
            let projectedBalance =
                balance + recurring.income - recurring.expense - goalReserve
            let plannedSafe =
                budgetAllowance > 0
                    ? min(max(0, projectedBalance), budgetAllowance)
                    : max(0, projectedBalance)

            return CashFlowForecastItem(
                horizonDays: days,
                safeToSpendMinor: plannedSafe,
                dailySafeMinor: plannedSafe / Int64(max(1, days)),
                projectedBalanceMinor: projectedBalance,
                recurringIncomeMinor: recurring.income,
                recurringExpenseMinor: recurring.expense,
                goalReserveMinor: goalReserve,
                budgetAllowanceMinor: budgetAllowance
            )
        }
    }

    private static func currentBalanceMinor(
        accounts: [AccountItem],
        transactions: [TransactionItem]
    ) -> Int64 {
        let opening = accounts
            .filter { !$0.archived }
            .reduce(Int64(0)) { $0 + $1.openingBalanceMinor }
        let netTransactions = transactions.reduce(Int64(0)) { total, transaction in
            total + (transaction.isExpense ? -transaction.amountMinor : transaction.amountMinor)
        }
        return opening + netTransactions
    }

    private static func recurringTotals(
        rules: [RecurringRuleItem],
        in period: BudgetPeriod,
        calendar: Calendar
    ) -> (income: Int64, expense: Int64) {
        rules.reduce((income: Int64(0), expense: Int64(0))) { totals, rule in
            guard rule.active, rule.amountMinor > 0 else { return totals }
            let count = recurringDates(
                for: rule,
                in: period,
                calendar: calendar
            ).count
            let amount = rule.amountMinor * Int64(count)
            if rule.isExpense {
                return (totals.income, totals.expense + amount)
            }
            return (totals.income + amount, totals.expense)
        }
    }

    private static func goalReserveMinor(
        goals: [GoalItem],
        horizonDays: Int,
        now: Date,
        calendar: Calendar
    ) -> Int64 {
        goals.reduce(Int64(0)) { total, goal in
            guard !goal.achieved, goal.targetMinor > goal.savedMinor else {
                return total
            }
            let remaining = goal.targetMinor - goal.savedMinor
            guard let targetDate = goal.targetDate else {
                return total + remaining
            }
            let today = calendar.startOfDay(for: now)
            let target = calendar.startOfDay(for: targetDate)
            guard target >= today else {
                return total + remaining
            }
            let daysUntilTarget =
                (calendar.dateComponents([.day], from: today, to: target).day ?? 0) + 1
            let dailyRequired = ceilDivide(
                remaining,
                by: Int64(max(1, daysUntilTarget))
            )
            return total + min(
                remaining,
                dailyRequired * Int64(max(1, min(horizonDays, daysUntilTarget)))
            )
        }
    }

    private static func recurringDates(
        for rule: RecurringRuleItem,
        in period: BudgetPeriod,
        calendar: Calendar
    ) -> [Date] {
        var dates: [Date] = []
        var date = calendar.startOfDay(for: rule.nextRunDate)
        let periodStart = calendar.startOfDay(for: period.start)
        let periodEnd = calendar.startOfDay(for: period.end)

        while date <= periodEnd {
            if let endDate = rule.endDate, date > calendar.startOfDay(for: endDate) {
                break
            }
            if date >= periodStart {
                dates.append(date)
            }
            guard
                let next = SafeToSpendUseCase.advance(
                    date,
                    cadence: rule.cadence,
                    intervalCount: rule.intervalCount,
                    calendar: calendar
                ),
                next > date
            else { break }
            date = calendar.startOfDay(for: next)
        }

        return dates
    }

    private static func ceilDivide(_ value: Int64, by divisor: Int64) -> Int64 {
        guard divisor > 0 else { return value }
        return (value + divisor - 1) / divisor
    }
}

struct BudgetAlertItem: Identifiable, Equatable {
    enum Severity: Int {
        case pace = 1
        case close = 2
        case over = 3
    }

    let id: UUID
    let title: String
    let message: String
    let icon: String
    let colorHex: String
    let spentMinor: Int64
    let budgetMinor: Int64
    let progress: Double
    let severity: Severity
}

enum BudgetAlertsUseCase {
    static func calculate(
        categoryBudgets: [CategoryBudgetItem],
        transactions: [TransactionItem],
        period: BudgetPeriod,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [BudgetAlertItem] {
        let periodProgress = BudgetPeriodCalculator.progress(
            in: period,
            now: now,
            calendar: calendar
        )

        return categoryBudgets.compactMap { budget in
            guard
                budget.isActive,
                budget.amountMinor > 0,
                let category = budget.category,
                !category.archived,
                !category.isIncome
            else {
                return nil
            }

            let spent = transactions
                .filter {
                    $0.isExpense
                        && $0.category?.id == category.id
                        && period.contains($0.timestamp, calendar: calendar)
                }
                .reduce(Int64(0)) { $0 + $1.amountMinor }
            let progress = Double(spent) / Double(max(1, budget.amountMinor))

            if spent > budget.amountMinor {
                return BudgetAlertItem(
                    id: category.id,
                    title: "\(category.name) is over budget",
                    message: "Over by \(spent - budget.amountMinor) minor units.",
                    icon: category.iconKey,
                    colorHex: category.colorHex,
                    spentMinor: spent,
                    budgetMinor: budget.amountMinor,
                    progress: progress,
                    severity: .over
                )
            }

            if progress >= 0.85 {
                return BudgetAlertItem(
                    id: category.id,
                    title: "\(category.name) is close",
                    message: "\(Int((progress * 100).rounded()))% of budget used.",
                    icon: category.iconKey,
                    colorHex: category.colorHex,
                    spentMinor: spent,
                    budgetMinor: budget.amountMinor,
                    progress: progress,
                    severity: .close
                )
            }

            if progress > periodProgress + 0.15 && progress > 0.25 {
                return BudgetAlertItem(
                    id: category.id,
                    title: "\(category.name) is moving fast",
                    message: "\(Int((progress * 100).rounded()))% used with \(Int((periodProgress * 100).rounded()))% of the period elapsed.",
                    icon: category.iconKey,
                    colorHex: category.colorHex,
                    spentMinor: spent,
                    budgetMinor: budget.amountMinor,
                    progress: progress,
                    severity: .pace
                )
            }

            return nil
        }
        .sorted {
            if $0.severity.rawValue != $1.severity.rawValue {
                return $0.severity.rawValue > $1.severity.rawValue
            }
            return $0.progress > $1.progress
        }
    }
}
