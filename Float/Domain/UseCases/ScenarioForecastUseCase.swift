import Foundation

struct ScenarioForecastItem: Identifiable, Equatable {
    let horizonDays: Int
    let baselineSafeToSpendMinor: Int64
    let adjustedSafeToSpendMinor: Int64
    let scenarioImpactMinor: Int64
    let adjustedDailySafeMinor: Int64
    let adjustedProjectedBalanceMinor: Int64

    var id: Int { horizonDays }
}

struct ScenarioForecastSummary: Equatable {
    let baselineSafeToSpend: SafeToSpendResult
    let currentPeriodImpactMinor: Int64
    let adjustedCurrentSafeToSpendMinor: Int64
    let forecastItems: [ScenarioForecastItem]

    static var empty: ScenarioForecastSummary {
        let baseline = SafeToSpendUseCase.calculate(
            budget: nil,
            transactions: [],
            goals: [],
            recurringRules: []
        )
        return ScenarioForecastSummary(
            baselineSafeToSpend: baseline,
            currentPeriodImpactMinor: 0,
            adjustedCurrentSafeToSpendMinor: baseline.safeToSpendMinor,
            forecastItems: []
        )
    }
}

enum ScenarioForecastUseCase {
    static func calculate(
        horizons: [Int] = [7, 14, 30],
        accounts: [AccountItem],
        transactions: [TransactionItem],
        transfers: [TransferItem],
        budget: BudgetPeriodItem?,
        goals: [GoalItem],
        recurringRules: [RecurringRuleItem],
        scenarios: [ScenarioPlanItem],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> ScenarioForecastSummary {
        let period = BudgetPeriodCalculator.currentPeriod(
            for: budget,
            now: now,
            calendar: calendar
        )
        let baseline = SafeToSpendUseCase.calculate(
            budget: budget,
            transactions: transactions,
            goals: goals,
            recurringRules: recurringRules,
            now: now,
            calendar: calendar
        )
        let baselineForecast = CashFlowForecastUseCase.calculate(
            horizons: horizons,
            accounts: accounts,
            transactions: transactions,
            transfers: transfers,
            budget: budget,
            safeToSpend: baseline,
            goals: goals,
            recurringRules: recurringRules,
            now: now,
            calendar: calendar
        )
        let activeScenarios = scenarios.filter { !$0.archived && $0.amountMinor > 0 }
        let currentPeriodImpact = impact(
            of: activeScenarios,
            from: period.start,
            through: period.end,
            calendar: calendar
        )
        let adjustedCurrentSafe = max(
            0,
            baseline.safeToSpendMinor + currentPeriodImpact
        )

        let forecastItems = baselineForecast.map { item in
            let horizonEnd = calendar.date(
                byAdding: .day,
                value: max(1, item.horizonDays) - 1,
                to: now
            ) ?? now
            let scenarioImpact = impact(
                of: activeScenarios,
                from: calendar.startOfDay(for: now),
                through: horizonEnd,
                calendar: calendar
            )
            let adjustedSafe = max(0, item.safeToSpendMinor + scenarioImpact)
            return ScenarioForecastItem(
                horizonDays: item.horizonDays,
                baselineSafeToSpendMinor: item.safeToSpendMinor,
                adjustedSafeToSpendMinor: adjustedSafe,
                scenarioImpactMinor: scenarioImpact,
                adjustedDailySafeMinor: adjustedSafe / Int64(max(1, item.horizonDays)),
                adjustedProjectedBalanceMinor: item.projectedBalanceMinor + scenarioImpact
            )
        }

        return ScenarioForecastSummary(
            baselineSafeToSpend: baseline,
            currentPeriodImpactMinor: currentPeriodImpact,
            adjustedCurrentSafeToSpendMinor: adjustedCurrentSafe,
            forecastItems: forecastItems
        )
    }

    static func occurrences(
        for scenario: ScenarioPlanItem,
        through endDate: Date,
        calendar: Calendar = .current
    ) -> [Date] {
        guard !scenario.archived, scenario.amountMinor > 0 else { return [] }
        var dates: [Date] = []
        var cursor = calendar.startOfDay(for: scenario.plannedDate)
        let end = calendar.startOfDay(for: endDate)
        let maxCount = scenario.recurrence == .none ? 1 : max(1, scenario.occurrenceCount)

        while dates.count < maxCount && cursor <= end {
            dates.append(cursor)
            guard let next = nextDate(
                after: cursor,
                recurrence: scenario.recurrence,
                calendar: calendar
            ) else {
                break
            }
            cursor = next
        }

        return dates
    }

    private static func impact(
        of scenarios: [ScenarioPlanItem],
        from startDate: Date,
        through endDate: Date,
        calendar: Calendar
    ) -> Int64 {
        let start = calendar.startOfDay(for: startDate)
        let end = calendar.startOfDay(for: endDate)
        return scenarios.reduce(Int64(0)) { total, scenario in
            let occurrenceCount = occurrences(
                for: scenario,
                through: end,
                calendar: calendar
            )
            .filter { $0 >= start && $0 <= end }
            .count
            let signedAmount = scenario.isExpense
                ? -scenario.amountMinor
                : scenario.amountMinor
            return total + signedAmount * Int64(occurrenceCount)
        }
    }

    private static func nextDate(
        after date: Date,
        recurrence: ScenarioRecurrence,
        calendar: Calendar
    ) -> Date? {
        switch recurrence {
        case .none:
            return nil
        case .weekly:
            return calendar.date(byAdding: .weekOfYear, value: 1, to: date)
        case .monthly:
            return calendar.date(byAdding: .month, value: 1, to: date)
        }
    }
}
