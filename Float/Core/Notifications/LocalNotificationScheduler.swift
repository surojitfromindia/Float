import Foundation
import UserNotifications

enum LocalNotificationScheduler {
    static func refresh(
        recurringRules: [RecurringRuleItem],
        budgetAlerts: [BudgetAlertItem],
        goals: [GoalItem],
        settlementCases: [SettlementCaseItem] = [],
        currencyCode: String,
        preferences: FloatReminderPreferences = FloatReminderPreferences(
            recurringEnabled: true,
            budgetEnabled: true,
            goalsEnabled: true,
            settlementsEnabled: true,
            recurringReminderMinutes: 9 * 60,
            goalReminderMinutes: 9 * 60 + 30,
            settlementReminderMinutes: 9 * 60,
            budgetAlertSensitivity: .closeAndOver
        ),
        now: Date = Date(),
        calendar: Calendar = .current
    ) {
        Task {
            let center = UNUserNotificationCenter.current()
            let granted = try? await center.requestAuthorization(
                options: [.alert, .badge, .sound]
            )
            guard granted == true else { return }

            let pending = await center.pendingNotificationRequests()
            let managedIDs = pending.map(\.identifier).filter {
                $0.hasPrefix("float.recurring.")
                    || $0.hasPrefix("float.budget.")
                    || $0.hasPrefix("float.goal.")
                    || $0.hasPrefix("float.settlement.")
            }
            center.removePendingNotificationRequests(withIdentifiers: managedIDs)

            if preferences.recurringEnabled {
                recurringRules
                    .filter { $0.active }
                    .prefix(8)
                    .forEach {
                        scheduleRecurring(
                            $0,
                            center: center,
                            now: now,
                            calendar: calendar,
                            currencyCode: currencyCode,
                            reminderMinutes: preferences.recurringReminderMinutes
                        )
                    }
            }

            if preferences.budgetEnabled {
                budgetAlerts
                    .filter { shouldSchedule($0, sensitivity: preferences.budgetAlertSensitivity) }
                    .prefix(4)
                    .forEach {
                        scheduleBudgetAlert(
                            $0,
                            center: center,
                            now: now,
                            currencyCode: currencyCode
                        )
                    }
            }

            if preferences.goalsEnabled {
                goals
                    .filter { !$0.achieved && $0.targetDate != nil }
                    .sorted { ($0.targetDate ?? .distantFuture) < ($1.targetDate ?? .distantFuture) }
                    .prefix(6)
                    .forEach {
                        scheduleGoal(
                            $0,
                            center: center,
                            now: now,
                            calendar: calendar,
                            currencyCode: currencyCode,
                            reminderMinutes: preferences.goalReminderMinutes
                        )
                    }
            }

            if preferences.settlementsEnabled {
                settlementCases
                    .filter { !$0.archived && $0.balanceSnapshot.remainingMinor > 0 }
                    .sorted {
                        ($0.operationalSnapshot.nextDueDate ?? .distantFuture)
                            < ($1.operationalSnapshot.nextDueDate ?? .distantFuture)
                    }
                    .prefix(8)
                    .forEach {
                        scheduleSettlement(
                            $0,
                            center: center,
                            now: now,
                            calendar: calendar,
                            fallbackCurrencyCode: currencyCode,
                            reminderMinutes: preferences.settlementReminderMinutes
                        )
                    }
            }
        }
    }

    private static func scheduleRecurring(
        _ rule: RecurringRuleItem,
        center: UNUserNotificationCenter,
        now: Date,
        calendar: Calendar,
        currencyCode: String,
        reminderMinutes: Int
    ) {
        let dueDate = calendar.startOfDay(for: rule.nextRunDate)
        guard dueDate >= calendar.startOfDay(for: now) else { return }
        let reminderDate = date(on: dueDate, minutesAfterStartOfDay: reminderMinutes, calendar: calendar)
        guard reminderDate > now else { return }

        let content = UNMutableNotificationContent()
        content.title = rule.isExpense
            ? String(localized: "Upcoming bill")
            : String(localized: "Upcoming income")
        content.body = String(
            localized: "\(ruleTitle(rule)) is due today for \(money(rule.amountMinor, currencyCode))."
        )
        content.sound = .default

        schedule(
            id: "float.recurring.\(rule.id.uuidString)",
            date: reminderDate,
            content: content,
            center: center,
            calendar: calendar
        )
    }

    private static func scheduleBudgetAlert(
        _ alert: BudgetAlertItem,
        center: UNUserNotificationCenter,
        now: Date,
        currencyCode: String
    ) {
        let fireDate = now.addingTimeInterval(90)
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = String(
            localized: "\(money(alert.spentMinor, currencyCode)) of \(money(alert.budgetMinor, currencyCode)) used."
        )
        content.sound = .default
        schedule(
            id: "float.budget.\(alert.id.uuidString)",
            date: fireDate,
            content: content,
            center: center
        )
    }

    private static func scheduleGoal(
        _ goal: GoalItem,
        center: UNUserNotificationCenter,
        now: Date,
        calendar: Calendar,
        currencyCode: String,
        reminderMinutes: Int
    ) {
        guard let targetDate = goal.targetDate else { return }
        let targetStart = calendar.startOfDay(for: targetDate)
        guard targetStart >= calendar.startOfDay(for: now) else { return }
        let reminderDate = date(on: targetStart, minutesAfterStartOfDay: reminderMinutes, calendar: calendar)
        guard reminderDate > now else { return }

        let content = UNMutableNotificationContent()
        content.title = String(localized: "Goal target today")
        content.body = String(
            localized: "\(goal.name) has \(money(max(0, goal.targetMinor - goal.savedMinor), currencyCode)) remaining."
        )
        content.sound = .default

        schedule(
            id: "float.goal.\(goal.id.uuidString)",
            date: reminderDate,
            content: content,
            center: center,
            calendar: calendar
        )
    }

    private static func scheduleSettlement(
        _ caseItem: SettlementCaseItem,
        center: UNUserNotificationCenter,
        now: Date,
        calendar: Calendar,
        fallbackCurrencyCode: String,
        reminderMinutes: Int
    ) {
        let snapshot = caseItem.operationalSnapshot
        guard let dueDate = snapshot.nextDueDate else { return }
        let dueStart = calendar.startOfDay(for: dueDate)
        guard dueStart >= calendar.startOfDay(for: now) else { return }
        let reminderDate = date(on: dueStart, minutesAfterStartOfDay: reminderMinutes, calendar: calendar)
        guard reminderDate > now else { return }

        let currencyCode = caseCurrencyCode(for: caseItem, fallbackCurrencyCode: fallbackCurrencyCode)
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Settlement due today")
        content.body = String(
            localized: "\(caseItem.displayTitle) has \(money(snapshot.amountDueNowMinor, currencyCode)) due."
        )
        content.sound = .default
        content.userInfo = [
            "destination": FloatDestination.settlements.rawValue
        ]

        schedule(
            id: "float.settlement.\(caseItem.id.uuidString)",
            date: reminderDate,
            content: content,
            center: center,
            calendar: calendar
        )
    }

    private static func schedule(
        id: String,
        date: Date,
        content: UNNotificationContent,
        center: UNUserNotificationCenter,
        calendar: Calendar = .current
    ) {
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: date
        )
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: components,
            repeats: false
        )
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    private static func ruleTitle(_ rule: RecurringRuleItem) -> String {
        rule.note?.isEmpty == false
            ? rule.note ?? String(localized: "Recurring item")
            : rule.category?.name ?? String(localized: "Recurring item")
    }

    private static func shouldSchedule(
        _ alert: BudgetAlertItem,
        sensitivity: BudgetAlertSensitivity
    ) -> Bool {
        switch sensitivity {
        case .off:
            return false
        case .urgentOnly:
            return alert.severity == .over
        case .closeAndOver:
            return alert.severity == .close || alert.severity == .over
        case .all:
            return true
        }
    }

    private static func date(
        on day: Date,
        minutesAfterStartOfDay minutes: Int,
        calendar: Calendar
    ) -> Date {
        let clamped = min(max(minutes, 0), 23 * 60 + 59)
        return calendar.date(
            byAdding: .minute,
            value: clamped,
            to: calendar.startOfDay(for: day)
        ) ?? day
    }

    private static func money(_ amount: Int64, _ currencyCode: String) -> String {
        MoneyFormatter.string(minorUnits: amount, currencyCode: currencyCode)
    }

    private static func caseCurrencyCode(
        for caseItem: SettlementCaseItem,
        fallbackCurrencyCode: String
    ) -> String {
        let trimmed = caseItem.currencyCode.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallbackCurrencyCode : trimmed
    }
}
