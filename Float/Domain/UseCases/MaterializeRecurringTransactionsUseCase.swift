import Foundation
import SwiftData

enum MaterializeRecurringTransactionsUseCase {
    @MainActor
    static func run(
        modelContext: ModelContext,
        profileID: UUID? = ActiveProfileRegistry.profileID,
        today: Date = Date(),
        calendar: Calendar = .current
    ) {
        let descriptor = FetchDescriptor<RecurringRuleItem>()
        guard let rules = try? modelContext.fetch(descriptor) else { return }
        for rule in rules where rule.active && (profileID == nil || rule.profileID == profileID) {
            materialize(
                rule: rule,
                modelContext: modelContext,
                today: today,
                calendar: calendar
            )
        }
        try? modelContext.save()
    }

    @MainActor
    private static func materialize(
        rule: RecurringRuleItem,
        modelContext: ModelContext,
        today: Date,
        calendar: Calendar
    ) {
        let todayStart = calendar.startOfDay(for: today)
        while calendar.startOfDay(for: rule.nextRunDate) <= todayStart {
            if let endDate = rule.endDate, rule.nextRunDate > endDate {
                rule.active = false
                break
            }
            if !transactionExists(
                for: rule,
                on: rule.nextRunDate,
                modelContext: modelContext,
                calendar: calendar
            ) {
                let transaction = TransactionItem(
                    profileID: rule.profileID,
                    amountMinor: rule.amountMinor,
                    isExpense: rule.isExpense,
                    timestamp: rule.nextRunDate,
                    category: rule.category,
                    account: rule.account,
                    note: rule.note,
                    recurringRule: rule
                )
                modelContext.insert(transaction)
                transaction.replacePeople(
                    rule.personTags.compactMap(\.person),
                    in: modelContext
                )
            }
            guard
                let next = SafeToSpendUseCase.advance(
                    rule.nextRunDate,
                    cadence: rule.cadence,
                    intervalCount: rule.intervalCount,
                    calendar: calendar
                )
            else { break }
            rule.nextRunDate = next
            rule.updatedAt = Date()
        }
    }

    @MainActor
    private static func transactionExists(
        for rule: RecurringRuleItem,
        on date: Date,
        modelContext: ModelContext,
        calendar: Calendar
    ) -> Bool {
        let descriptor = FetchDescriptor<TransactionItem>()
        let all = (try? modelContext.fetch(descriptor)) ?? []
        return all.contains { item in
            item.profileID == rule.profileID
                && item.recurringRule?.id == rule.id
                && calendar.isDate(item.timestamp, inSameDayAs: date)
                && item.amountMinor == rule.amountMinor
        }
    }
}
