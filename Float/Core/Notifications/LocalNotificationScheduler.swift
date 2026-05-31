import Foundation
import UserNotifications

enum LocalNotificationScheduler {
    static func refresh(
        recurringRules: [RecurringRuleItem],
        budgetAlerts: [BudgetAlertItem],
        goals: [GoalItem],
        currencyCode: String,
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
            }
            center.removePendingNotificationRequests(withIdentifiers: managedIDs)

            recurringRules
                .filter { $0.active }
                .prefix(8)
                .forEach {
                    scheduleRecurring(
                        $0,
                        center: center,
                        now: now,
                        calendar: calendar,
                        currencyCode: currencyCode
                    )
                }

            budgetAlerts
                .prefix(4)
                .forEach {
                    scheduleBudgetAlert(
                        $0,
                        center: center,
                        now: now,
                        currencyCode: currencyCode
                    )
                }

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
                        currencyCode: currencyCode
                    )
                }
        }
    }

    private static func scheduleRecurring(
        _ rule: RecurringRuleItem,
        center: UNUserNotificationCenter,
        now: Date,
        calendar: Calendar,
        currencyCode: String
    ) {
        let dueDate = calendar.startOfDay(for: rule.nextRunDate)
        guard dueDate >= calendar.startOfDay(for: now) else { return }
        let reminderDate =
            calendar.date(bySettingHour: 9, minute: 0, second: 0, of: dueDate)
            ?? dueDate
        guard reminderDate > now else { return }

        let content = UNMutableNotificationContent()
        content.title = rule.isExpense ? "Upcoming bill" : "Upcoming income"
        content.body = "\(ruleTitle(rule)) is due today for \(money(rule.amountMinor, currencyCode))."
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
        content.body = "\(money(alert.spentMinor, currencyCode)) of \(money(alert.budgetMinor, currencyCode)) used."
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
        currencyCode: String
    ) {
        guard let targetDate = goal.targetDate else { return }
        let targetStart = calendar.startOfDay(for: targetDate)
        guard targetStart >= calendar.startOfDay(for: now) else { return }
        let reminderDate =
            calendar.date(bySettingHour: 9, minute: 30, second: 0, of: targetStart)
            ?? targetStart
        guard reminderDate > now else { return }

        let content = UNMutableNotificationContent()
        content.title = "Goal target today"
        content.body = "\(goal.name) has \(money(max(0, goal.targetMinor - goal.savedMinor), currencyCode)) remaining."
        content.sound = .default

        schedule(
            id: "float.goal.\(goal.id.uuidString)",
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
            ? rule.note ?? "Recurring item"
            : rule.category?.name ?? "Recurring item"
    }

    private static func money(_ amount: Int64, _ currencyCode: String) -> String {
        MoneyFormatter.string(minorUnits: amount, currencyCode: currencyCode)
    }
}
