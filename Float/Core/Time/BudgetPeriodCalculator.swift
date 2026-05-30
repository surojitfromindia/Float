import Foundation

struct BudgetPeriod: Equatable {
    let start: Date
    let end: Date
}

enum BudgetPeriodCalculator {
    static func currentPeriod(
        for config: BudgetPeriodItem?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> BudgetPeriod {
        currentPeriod(
            cadence: config?.cadence ?? .monthly,
            startDayOfMonth: config?.startDayOfMonth,
            startDayOfWeek: config?.startDayOfWeek,
            now: now,
            calendar: calendar
        )
    }

    static func currentPeriod(
        cadence: BudgetCadence,
        startDayOfMonth: Int?,
        startDayOfWeek: Int?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> BudgetPeriod {
        switch cadence {
        case .weekly:
            return weeklyPeriod(
                startDayOfWeek: startDayOfWeek ?? calendar.firstWeekday,
                now: now,
                calendar: calendar
            )
        case .monthly:
            return monthlyPeriod(
                startDayOfMonth: startDayOfMonth ?? 1,
                now: now,
                calendar: calendar
            )
        }
    }

    static func daysRemaining(
        in period: BudgetPeriod,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Int {
        let today = calendar.startOfDay(for: now)
        let end = calendar.startOfDay(for: period.end)
        guard today <= end else { return 0 }
        return (calendar.dateComponents([.day], from: today, to: end).day ?? 0)
            + 1
    }

    static func progress(
        in period: BudgetPeriod,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Double {
        let start = calendar.startOfDay(for: period.start)
        let endExclusive =
            calendar.date(
                byAdding: .day,
                value: 1,
                to: calendar.startOfDay(for: period.end)
            ) ?? period.end
        let total = endExclusive.timeIntervalSince(start)
        guard total > 0 else { return 1 }
        let elapsed = max(0, min(now.timeIntervalSince(start), total))
        return elapsed / total
    }

    private static func weeklyPeriod(
        startDayOfWeek: Int,
        now: Date,
        calendar: Calendar
    ) -> BudgetPeriod {
        let today = calendar.startOfDay(for: now)
        let weekday = calendar.component(.weekday, from: today)
        let normalizedStart = min(max(startDayOfWeek, 1), 7)
        let delta = (weekday - normalizedStart + 7) % 7
        let start =
            calendar.date(byAdding: .day, value: -delta, to: today) ?? today
        let end = calendar.date(byAdding: .day, value: 6, to: start) ?? today
        return BudgetPeriod(start: start, end: end)
    }

    private static func monthlyPeriod(
        startDayOfMonth: Int,
        now: Date,
        calendar: Calendar
    ) -> BudgetPeriod {
        let day = min(max(startDayOfMonth, 1), 28)
        let today = calendar.startOfDay(for: now)
        var components = calendar.dateComponents([.year, .month], from: today)
        components.day = day
        let currentStartCandidate = calendar.date(from: components) ?? today
        let start: Date
        if currentStartCandidate <= today {
            start = currentStartCandidate
        } else {
            start =
                calendar.date(
                    byAdding: .month,
                    value: -1,
                    to: currentStartCandidate
                ) ?? currentStartCandidate
        }
        let nextStart =
            calendar.date(byAdding: .month, value: 1, to: start) ?? start
        let end =
            calendar.date(byAdding: .day, value: -1, to: nextStart) ?? start
        return BudgetPeriod(
            start: calendar.startOfDay(for: start),
            end: calendar.startOfDay(for: end)
        )
    }
}
