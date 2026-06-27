import Foundation

struct InsightSignal: Identifiable, Equatable {
    let id: String
    let kind: InsightSignalKind
    let severity: InsightSignalSeverity
    let title: String
    let message: String
    let icon: String
    let colorHex: String
    let amountMinor: Int64?
    let referenceID: String?

    var priority: Int {
        switch severity {
        case .critical: 4
        case .warning: 3
        case .notice: 2
        case .info: 1
        }
    }
}

enum InsightSignalsUseCase {
    static func generate(
        period: BudgetPeriod,
        transactions: [TransactionItem],
        previousTransactions: [TransactionItem],
        allTransactions: [TransactionItem],
        categoryBudgets: [CategoryBudgetItem],
        recurringRules: [RecurringRuleItem],
        activeBudget: BudgetPeriodItem?,
        budgetAlerts: [BudgetAlertItem] = [],
        currencyCode: String,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [InsightSignal] {
        var signals: [InsightSignal] = []

        signals.append(
            contentsOf: budgetRiskSignals(
                alerts: budgetAlerts,
                currencyCode: currencyCode
            )
        )
        signals.append(
            contentsOf: duplicateSignals(
                transactions: transactions,
                currencyCode: currencyCode,
                calendar: calendar
            )
        )
        if let signal = incomeDropSignal(
            transactions: transactions,
            previousTransactions: previousTransactions,
            currencyCode: currencyCode
        ) {
            signals.append(signal)
        }
        if let signal = unusualCategorySignal(
            transactions: transactions,
            previousTransactions: previousTransactions,
            currencyCode: currencyCode
        ) {
            signals.append(signal)
        }
        if let signal = largeTransactionSignal(
            transactions: transactions,
            currencyCode: currencyCode
        ) {
            signals.append(signal)
        }
        if let signal = recurringChangeSignal(
            period: period,
            allTransactions: allTransactions,
            recurringRules: recurringRules,
            currencyCode: currencyCode,
            calendar: calendar
        ) {
            signals.append(signal)
        }
        if let signal = recurringLoadSignal(
            recurringRules: recurringRules,
            activeBudget: activeBudget,
            currencyCode: currencyCode
        ) {
            signals.append(signal)
        }

        return Array(
            signals
                .uniquedByID()
                .sorted {
                    if $0.priority != $1.priority {
                        return $0.priority > $1.priority
                    }
                    return ($0.amountMinor ?? 0) > ($1.amountMinor ?? 0)
                }
                .prefix(8)
        )
    }

    private static func budgetRiskSignals(
        alerts: [BudgetAlertItem],
        currencyCode: String
    ) -> [InsightSignal] {
        alerts.prefix(3).map { alert in
            let severity: InsightSignalSeverity =
                alert.severity == .over ? .critical :
                alert.severity == .close ? .warning : .notice
            let title: String =
                alert.severity == .over ? AppLocalization.format("%@ needs attention", alert.title) :
                alert.severity == .close ? AppLocalization.format("%@ is close to its limit", alert.title) :
                AppLocalization.format("%@ is ahead of pace", alert.title)
            let used = MoneyFormatter.string(
                minorUnits: alert.spentMinor,
                currencyCode: currencyCode
            )
            let budget = MoneyFormatter.string(
                minorUnits: alert.budgetMinor,
                currencyCode: currencyCode
            )
            return InsightSignal(
                id: "budget-\(alert.id.uuidString)",
                kind: .budgetRisk,
                severity: severity,
                title: title,
                message: AppLocalization.format("%@ of %@ used.", used, budget),
                icon: alert.icon,
                colorHex: alert.colorHex,
                amountMinor: max(0, alert.spentMinor - alert.budgetMinor),
                referenceID: alert.id.uuidString
            )
        }
    }

    private static func duplicateSignals(
        transactions: [TransactionItem],
        currencyCode: String,
        calendar: Calendar
    ) -> [InsightSignal] {
        TransactionDuplicateDetector.groups(
            in: transactions.filter(\.isPosted),
            calendar: calendar
        )
        .compactMap { group in
            guard let first = group.first, first.amountMinor > 0 else { return nil }
            let amount = MoneyFormatter.string(
                minorUnits: first.amountMinor,
                currencyCode: currencyCode
            )
            let date = calendar.startOfDay(for: first.timestamp).formatted(
                Date.FormatStyle(date: .abbreviated, time: .omitted)
                    .locale(AppLocalization.locale)
            )
            return InsightSignal(
                id: "duplicate-\(first.id.uuidString)",
                kind: .duplicateCharge,
                severity: .warning,
                title: String(localized: "Possible duplicate"),
                message: AppLocalization.format(
                    "%lld matching %@ transactions for %@ on %@.",
                    Int64(group.transactions.count),
                    first.categoryName,
                    amount,
                    date
                ),
                icon: "doc.on.doc.fill",
                colorHex: "#B4613B",
                amountMinor: first.amountMinor,
                referenceID: first.id.uuidString
            )
        }
    }

    private static func incomeDropSignal(
        transactions: [TransactionItem],
        previousTransactions: [TransactionItem],
        currencyCode: String
    ) -> InsightSignal? {
        let current = transactions.filter(\.isPostedIncome).reduce(Int64(0)) { $0 + $1.amountMinor }
        let previous = previousTransactions.filter(\.isPostedIncome).reduce(Int64(0)) { $0 + $1.amountMinor }
        guard previous > 0, current * 100 < previous * 75 else { return nil }
        let difference = previous - current
        return InsightSignal(
            id: "income-drop",
            kind: .incomeDrop,
            severity: difference > previous / 2 ? .critical : .warning,
            title: String(localized: "Income is running lower"),
            message: AppLocalization.format(
                "Income is %@ below the previous comparable range.",
                MoneyFormatter.string(minorUnits: difference, currencyCode: currencyCode)
            ),
            icon: "arrow.down.forward.circle.fill",
            colorHex: "#B4613B",
            amountMinor: difference,
            referenceID: nil
        )
    }

    private static func unusualCategorySignal(
        transactions: [TransactionItem],
        previousTransactions: [TransactionItem],
        currencyCode: String
    ) -> InsightSignal? {
        let current = categoryTotals(from: transactions)
        let previous = categoryTotals(from: previousTransactions)
        let candidates = current.compactMap { key, amount -> (String, Int64, Int64)? in
            let prior = previous[key] ?? 0
            guard prior > 0, amount >= prior + max(prior / 2, 2_500) else { return nil }
            return (key.name, amount, amount - prior)
        }
        guard let top = candidates.max(by: { $0.2 < $1.2 }) else { return nil }
        return InsightSignal(
            id: "unusual-category-\(top.0)",
            kind: .unusualSpend,
            severity: .notice,
            title: AppLocalization.format("%@ is unusually high", top.0),
            message: AppLocalization.format(
                "Spending is %@ above the previous comparable range.",
                MoneyFormatter.string(minorUnits: top.2, currencyCode: currencyCode)
            ),
            icon: "chart.line.uptrend.xyaxis",
            colorHex: "#8A6DD7",
            amountMinor: top.2,
            referenceID: nil
        )
    }

    private static func largeTransactionSignal(
        transactions: [TransactionItem],
        currencyCode: String
    ) -> InsightSignal? {
        let expenses = transactions.filter(\.isPostedExpense)
        guard expenses.count >= 3 else { return nil }
        let total = expenses.reduce(Int64(0)) { $0 + $1.amountMinor }
        let average = total / Int64(max(1, expenses.count))
        guard
            let largest = expenses.max(by: { $0.amountMinor < $1.amountMinor }),
            largest.amountMinor >= max(average * 3, total / 3)
        else {
            return nil
        }
        return InsightSignal(
            id: "large-transaction-\(largest.id.uuidString)",
            kind: .largeTransaction,
            severity: .notice,
            title: String(localized: "Large transaction found"),
            message: AppLocalization.format(
                "%@ is much larger than your usual transaction in this range.",
                MoneyFormatter.string(minorUnits: largest.amountMinor, currencyCode: currencyCode)
            ),
            icon: largest.categoryIconKey,
            colorHex: largest.categoryColorHex,
            amountMinor: largest.amountMinor,
            referenceID: largest.id.uuidString
        )
    }

    private static func recurringChangeSignal(
        period: BudgetPeriod,
        allTransactions: [TransactionItem],
        recurringRules: [RecurringRuleItem],
        currencyCode: String,
        calendar: Calendar
    ) -> InsightSignal? {
        let activeRuleIDs = Set(recurringRules.filter(\.active).map(\.id))
        let grouped = Dictionary(grouping: allTransactions.filter {
            guard let ruleID = $0.recurringRule?.id else { return false }
            return $0.isPostedExpense && activeRuleIDs.contains(ruleID)
        }) {
            $0.recurringRule?.id
        }
        let candidates = grouped.compactMap { ruleID, items -> (TransactionItem, Int64, Bool)? in
            guard let ruleID, items.count >= 2 else { return nil }
            let sorted = items.sorted { $0.timestamp > $1.timestamp }
            guard
                let latest = sorted.first,
                let previous = sorted.dropFirst().first,
                period.contains(latest.timestamp, calendar: calendar),
                latest.amountMinor != previous.amountMinor
            else {
                return nil
            }
            _ = ruleID
            return (
                latest,
                abs(latest.amountMinor - previous.amountMinor),
                latest.amountMinor > previous.amountMinor
            )
        }
        guard let top = candidates.max(by: { $0.1 < $1.1 }) else { return nil }
        let direction = top.2
            ? String(localized: "higher")
            : String(localized: "lower")
        return InsightSignal(
            id: "recurring-change-\(top.0.id.uuidString)",
            kind: .recurringChange,
            severity: .warning,
            title: String(localized: "Recurring amount changed"),
            message: AppLocalization.format(
                "%@ is %@ by %@.",
                top.0.categoryName,
                direction,
                MoneyFormatter.string(minorUnits: top.1, currencyCode: currencyCode)
            ),
            icon: "repeat.circle.fill",
            colorHex: "#B4613B",
            amountMinor: top.1,
            referenceID: top.0.id.uuidString
        )
    }

    private static func recurringLoadSignal(
        recurringRules: [RecurringRuleItem],
        activeBudget: BudgetPeriodItem?,
        currencyCode: String
    ) -> InsightSignal? {
        guard let income = activeBudget?.expectedIncomeMinor, income > 0 else { return nil }
        let monthlyLoad = recurringRules
            .filter { $0.active && $0.isExpense }
            .reduce(Int64(0)) { $0 + normalizedMonthlyAmount(for: $1) }
        let comparableLoad = activeBudget?.cadence == .weekly ? monthlyLoad / 4 : monthlyLoad
        guard comparableLoad * 100 >= income * 40 else { return nil }
        return InsightSignal(
            id: "recurring-load",
            kind: .recurringChange,
            severity: .notice,
            title: String(localized: "Recurring costs are heavy"),
            message: AppLocalization.format(
                "Recurring expenses use about %@ of expected income.",
                percent(monthlyLoad, of: income)
            ),
            icon: "repeat.circle.fill",
            colorHex: "#8A6DD7",
            amountMinor: comparableLoad,
            referenceID: nil
        )
    }

    private static func categoryTotals(
        from transactions: [TransactionItem]
    ) -> [CategorySignalKey: Int64] {
        transactions.filter(\.isPostedExpense).reduce(into: [:]) { totals, transaction in
            let key = CategorySignalKey(
                id: transaction.category?.id.uuidString ?? transaction.categoryName,
                name: transaction.categoryName
            )
            totals[key, default: 0] += transaction.amountMinor
        }
    }

    private static func normalizedMonthlyAmount(for rule: RecurringRuleItem) -> Int64 {
        let interval = max(1, rule.intervalCount)
        switch rule.cadence {
        case .daily:
            return rule.amountMinor * Int64(max(1, 30 / interval))
        case .weekly:
            return rule.amountMinor * Int64(max(1, 4 / interval))
        case .monthly:
            return rule.amountMinor / Int64(interval)
        }
    }

    private static func percent(_ value: Int64, of total: Int64) -> String {
        guard total > 0 else { return "0%" }
        return "\(Int((Double(value) / Double(total) * 100).rounded()))%"
    }
}

private struct CategorySignalKey: Hashable {
    let id: String
    let name: String
}

private extension Array where Element == InsightSignal {
    func uniquedByID() -> [InsightSignal] {
        var seen = Set<String>()
        return filter { signal in
            guard !seen.contains(signal.id) else { return false }
            seen.insert(signal.id)
            return true
        }
    }
}
