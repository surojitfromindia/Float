import CoreSpotlight
import Foundation
import SwiftData
import UniformTypeIdentifiers

enum FloatSpotlightItemKind: String, Codable {
    case transaction
    case transfer
    case account
    case category
    case people
    case goal
    case settlement
    case template
    case recurring
}

struct FloatSpotlightTarget: Equatable {
    let kind: FloatSpotlightItemKind
    let id: UUID
}

struct FloatSpotlightNavigationRequest: Identifiable, Equatable {
    let id = UUID()
    let target: FloatSpotlightTarget
}

enum FloatSpotlightItemIdentifier {
    private static let separator = ":"

    static func make(kind: FloatSpotlightItemKind, id: UUID) -> String {
        "\(kind.rawValue)\(separator)\(id.uuidString)"
    }

    static func parse(_ identifier: String) -> FloatSpotlightTarget? {
        let components = identifier.split(separator: ":", maxSplits: 1)
        guard components.count == 2,
              let kind = FloatSpotlightItemKind(rawValue: String(components[0])),
              let id = UUID(uuidString: String(components[1]))
        else {
            return nil
        }
        return FloatSpotlightTarget(kind: kind, id: id)
    }
}

@MainActor
enum FloatSpotlightIndexer {
    private static let domainIdentifier = "com.reducer.Float.spotlight"
    private static var reindexTask: Task<Void, Never>?

    static func scheduleReindex(
        modelContext: ModelContext,
        profileID: UUID? = ActiveProfileRegistry.profileID
    ) {
        reindexTask?.cancel()
        reindexTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            await reindexAll(modelContext: modelContext, profileID: profileID)
        }
    }

    static func reindexAll(
        modelContext: ModelContext,
        profileID: UUID? = ActiveProfileRegistry.profileID
    ) async {
        let items = makeSearchableItems(modelContext: modelContext, profileID: profileID)
        await deleteDomain()
        guard !items.isEmpty else { return }
        await index(items)
    }

    private static func makeSearchableItems(
        modelContext: ModelContext,
        profileID: UUID?
    ) -> [CSSearchableItem] {
        let transactions = ((try? modelContext.fetch(FetchDescriptor<TransactionItem>())) ?? [])
            .filter { profileID == nil || $0.profileID == profileID }
        let transfers = ((try? modelContext.fetch(FetchDescriptor<TransferItem>())) ?? [])
            .filter { profileID == nil || $0.profileID == profileID }
        let accounts = ((try? modelContext.fetch(FetchDescriptor<AccountItem>())) ?? [])
            .filter { profileID == nil || $0.profileID == profileID }
        let categories = ((try? modelContext.fetch(FetchDescriptor<CategoryItem>())) ?? [])
            .filter { profileID == nil || $0.profileID == profileID }
        let people = ((try? modelContext.fetch(FetchDescriptor<PersonItem>())) ?? [])
            .filter { profileID == nil || $0.profileID == profileID }
        let goals = ((try? modelContext.fetch(FetchDescriptor<GoalItem>())) ?? [])
            .filter { profileID == nil || $0.profileID == profileID }
        let settlements = ((try? modelContext.fetch(FetchDescriptor<SettlementCaseItem>())) ?? [])
            .filter { profileID == nil || $0.profileID == profileID }
        let templates = ((try? modelContext.fetch(FetchDescriptor<TransactionTemplateItem>())) ?? [])
            .filter { profileID == nil || $0.profileID == profileID }
        let recurringRules = ((try? modelContext.fetch(FetchDescriptor<RecurringRuleItem>())) ?? [])
            .filter { profileID == nil || $0.profileID == profileID }

        let indexedTransactions = spotlightTransactions(from: transactions)
        let indexedTransfers = spotlightTransfers(from: transfers)
        let indexedAccounts = spotlightAccounts(
            from: accounts,
            transactions: transactions,
            transfers: transfers
        )
        let indexedCategories = spotlightCategories(
            from: categories,
            transactions: transactions
        )
        let indexedPeople = spotlightPeople(
            from: people,
            transactions: transactions
        )
        let indexedGoals = spotlightGoals(from: goals)
        let indexedSettlements = spotlightSettlements(from: settlements)
        let indexedTemplates = spotlightTemplates(from: templates)
        let indexedRecurring = spotlightRecurring(from: recurringRules)

        return indexedTransactions + indexedTransfers + indexedAccounts
            + indexedCategories + indexedPeople + indexedGoals
            + indexedSettlements + indexedTemplates + indexedRecurring
    }

    private static func spotlightTransactions(
        from transactions: [TransactionItem]
    ) -> [CSSearchableItem] {
        let calendar = Calendar.current
        let now = Date()
        let monthInterval = calendar.dateInterval(of: .month, for: now)
        let recentStart = calendar.startOfDay(
            for: calendar.date(byAdding: .day, value: -6, to: now) ?? now
        )

        let postedTransactions = transactions.filter(\.isPosted)
        let topThisMonth = postedTransactions
            .filter { transaction in
                guard let monthInterval else { return false }
                return monthInterval.contains(transaction.timestamp)
            }
            .sorted { lhs, rhs in
                if lhs.amountMinor == rhs.amountMinor {
                    return lhs.timestamp > rhs.timestamp
                }
                return lhs.amountMinor > rhs.amountMinor
            }
            .prefix(20)

        let lastSevenDays = postedTransactions.filter { $0.timestamp >= recentStart }

        var uniqueTransactions: [UUID: TransactionItem] = [:]
        for transaction in topThisMonth {
            uniqueTransactions[transaction.id] = transaction
        }
        for transaction in lastSevenDays {
            uniqueTransactions[transaction.id] = transaction
        }

        return uniqueTransactions.values
            .sorted { $0.timestamp > $1.timestamp }
            .map(transactionItem)
    }

    private static func spotlightTransfers(
        from transfers: [TransferItem]
    ) -> [CSSearchableItem] {
        let calendar = Calendar.current
        let now = Date()
        let recentStart = calendar.startOfDay(
            for: calendar.date(byAdding: .day, value: -6, to: now) ?? now
        )

        return transfers
            .filter { $0.timestamp >= recentStart }
            .sorted { $0.timestamp > $1.timestamp }
            .map(transferItem)
    }

    private static func spotlightAccounts(
        from accounts: [AccountItem],
        transactions: [TransactionItem],
        transfers: [TransferItem]
    ) -> [CSSearchableItem] {
        AccountBalanceUseCase.balances(
            accounts: accounts.filter { !$0.archived },
            transactions: transactions,
            transfers: transfers
        )
        .map(accountItem)
    }

    private static func spotlightCategories(
        from categories: [CategoryItem],
        transactions: [TransactionItem]
    ) -> [CSSearchableItem] {
        let recentTransactions = transactions.filter {
            $0.isPosted && $0.category != nil
        }

        return categories
            .filter { !$0.archived }
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { category in
                let transactionCount = recentTransactions.filter {
                    $0.category?.id == category.id
                }.count
                return categoryItem(category, transactionCount: transactionCount)
            }
    }

    private static func spotlightPeople(
        from people: [PersonItem],
        transactions: [TransactionItem]
    ) -> [CSSearchableItem] {
        let taggedTransactions = transactions.filter { !$0.personTags.isEmpty }

        return people
            .filter { !$0.archived }
            .sorted { $0.createdAt < $1.createdAt }
            .map { person in
                let transactionCount = taggedTransactions.filter {
                    $0.personTags.contains(where: { $0.person?.id == person.id })
                }.count
                return personItem(person, transactionCount: transactionCount)
            }
    }

    private static func spotlightGoals(from goals: [GoalItem]) -> [CSSearchableItem] {
        goals
            .filter { !$0.achieved }
            .sorted {
                ($0.targetDate ?? .distantFuture) < ($1.targetDate ?? .distantFuture)
            }
            .map(goalItem)
    }

    private static func spotlightSettlements(
        from settlements: [SettlementCaseItem]
    ) -> [CSSearchableItem] {
        settlements
            .filter { !$0.archived }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(80)
            .map(settlementItem)
    }

    private static func spotlightTemplates(
        from templates: [TransactionTemplateItem]
    ) -> [CSSearchableItem] {
        templates
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(100)
            .map(templateItem)
    }

    private static func spotlightRecurring(
        from rules: [RecurringRuleItem]
    ) -> [CSSearchableItem] {
        rules
            .filter(\.active)
            .sorted { $0.nextRunDate < $1.nextRunDate }
            .prefix(100)
            .map(recurringItem)
    }

    private static func transactionItem(_ transaction: TransactionItem) -> CSSearchableItem {
        let attributeSet = CSSearchableItemAttributeSet(
            itemContentType: UTType.item.identifier
        )
        let note = transaction.note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let amount = MoneyFormatter.string(
            minorUnits: transaction.amountMinor,
            currencyCode: transaction.account?.currencyCode ?? "USD"
        )
        let direction = transaction.isExpense
            ? String(localized: "Expense")
            : String(localized: "Income")
        let detail = [
            direction,
            amount,
            transaction.categoryName,
            transaction.accountName,
        ]
        .joined(separator: " • ")

        attributeSet.title = note?.isEmpty == false ? note : transaction.categoryName
        attributeSet.contentDescription = String(
            localized: "\(detail) • \(transaction.timestamp.formatted(date: .abbreviated, time: .shortened))"
        )
        attributeSet.contentCreationDate = transaction.timestamp
        attributeSet.keywords = sanitizedKeywords([
            transaction.categoryName,
            transaction.accountName,
            note,
            amount,
            direction,
        ])

        return CSSearchableItem(
            uniqueIdentifier: FloatSpotlightItemIdentifier.make(
                kind: .transaction,
                id: transaction.id
            ),
            domainIdentifier: domainIdentifier,
            attributeSet: attributeSet
        )
    }

    private static func transferItem(_ transfer: TransferItem) -> CSSearchableItem {
        let attributeSet = CSSearchableItemAttributeSet(
            itemContentType: UTType.item.identifier
        )
        let amount = MoneyFormatter.string(
            minorUnits: transfer.amountMinor,
            currencyCode: transfer.currencyCode
        )
        let title = transfer.note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let route = "\(transfer.fromAccountName) -> \(transfer.toAccountName)"

        attributeSet.title = title?.isEmpty == false ? title : String(localized: "Transfer")
        attributeSet.contentDescription = String(
            localized: "\(route) • \(transfer.timestamp.formatted(date: .abbreviated, time: .shortened))"
        )
        attributeSet.contentCreationDate = transfer.timestamp
        attributeSet.keywords = sanitizedKeywords([
            transfer.fromAccountName,
            transfer.toAccountName,
            title,
            amount,
            String(localized: "Transfer"),
        ])

        return CSSearchableItem(
            uniqueIdentifier: FloatSpotlightItemIdentifier.make(
                kind: .transfer,
                id: transfer.id
            ),
            domainIdentifier: domainIdentifier,
            attributeSet: attributeSet
        )
    }

    private static func accountItem(
        _ snapshot: AccountBalanceSnapshot
    ) -> CSSearchableItem {
        let attributeSet = CSSearchableItemAttributeSet(
            itemContentType: UTType.item.identifier
        )
        let account = snapshot.account
        let balance = MoneyFormatter.string(
            minorUnits: snapshot.balanceMinor,
            currencyCode: account.currencyCode
        )

        attributeSet.title = account.name
        attributeSet.contentDescription = String(
            localized: "\(balance) • \(account.type.title) account • \(account.currencyCode)"
        )
        attributeSet.keywords = [
            account.name,
            account.type.title,
            account.currencyCode,
            balance,
        ]

        return CSSearchableItem(
            uniqueIdentifier: FloatSpotlightItemIdentifier.make(
                kind: .account,
                id: account.id
            ),
            domainIdentifier: domainIdentifier,
            attributeSet: attributeSet
        )
    }

    private static func categoryItem(
        _ category: CategoryItem,
        transactionCount: Int
    ) -> CSSearchableItem {
        let attributeSet = CSSearchableItemAttributeSet(
            itemContentType: UTType.item.identifier
        )
        let kindTitle = category.isIncome
            ? String(localized: "Income")
            : String(localized: "Expense")

        attributeSet.title = category.name
        attributeSet.contentDescription = transactionCount > 0
            ? AppLocalization.format(
                "%@ category • %lld posted transactions",
                kindTitle,
                Int64(transactionCount)
            )
            : AppLocalization.format(
                "%@ category • No posted transactions yet",
                kindTitle
            )
        attributeSet.keywords = [
            category.name,
            kindTitle,
        ]

        return CSSearchableItem(
            uniqueIdentifier: FloatSpotlightItemIdentifier.make(
                kind: .category,
                id: category.id
            ),
            domainIdentifier: domainIdentifier,
            attributeSet: attributeSet
        )
    }

    private static func personItem(
        _ person: PersonItem,
        transactionCount: Int
    ) -> CSSearchableItem {
        let attributeSet = CSSearchableItemAttributeSet(
            itemContentType: UTType.item.identifier
        )
        attributeSet.title = person.name
        attributeSet.contentDescription = AppLocalization.format(
            "%lld tagged transactions",
            Int64(transactionCount)
        )
        attributeSet.keywords = sanitizedKeywords([
            person.name,
            person.alias,
            person.note,
        ])

        return CSSearchableItem(
            uniqueIdentifier: FloatSpotlightItemIdentifier.make(
                kind: .people,
                id: person.id
            ),
            domainIdentifier: domainIdentifier,
            attributeSet: attributeSet
        )
    }

    private static func goalItem(_ goal: GoalItem) -> CSSearchableItem {
        let attributeSet = CSSearchableItemAttributeSet(
            itemContentType: UTType.item.identifier
        )
        let target = MoneyFormatter.string(
            minorUnits: goal.targetMinor,
            currencyCode: Locale.current.currency?.identifier ?? "USD"
        )
        let saved = MoneyFormatter.string(
            minorUnits: goal.savedMinor,
            currencyCode: Locale.current.currency?.identifier ?? "USD"
        )
        attributeSet.title = goal.name
        if let targetDate = goal.targetDate {
            attributeSet.contentDescription = AppLocalization.format(
                "%@ saved of %@ • Target %@",
                saved,
                target,
                targetDate.formatted(date: .abbreviated, time: .omitted)
            )
        } else {
            attributeSet.contentDescription = AppLocalization.format(
                "%@ saved of %@",
                saved,
                target
            )
        }
        attributeSet.keywords = sanitizedKeywords([
            goal.name,
            String(localized: "Goal"),
            target,
            saved,
        ])

        return CSSearchableItem(
            uniqueIdentifier: FloatSpotlightItemIdentifier.make(
                kind: .goal,
                id: goal.id
            ),
            domainIdentifier: domainIdentifier,
            attributeSet: attributeSet
        )
    }

    private static func settlementItem(_ settlement: SettlementCaseItem) -> CSSearchableItem {
        let attributeSet = CSSearchableItemAttributeSet(
            itemContentType: UTType.item.identifier
        )
        attributeSet.title = settlement.displayTitle
        attributeSet.contentDescription = [
            settlement.personName,
            settlement.status.title,
            settlement.direction.title,
        ].joined(separator: " • ")
        attributeSet.contentModificationDate = settlement.updatedAt
        attributeSet.keywords = sanitizedKeywords([
            settlement.displayTitle,
            settlement.personName,
            settlement.status.title,
            settlement.direction.title,
            String(localized: "Settlement"),
        ])

        return CSSearchableItem(
            uniqueIdentifier: FloatSpotlightItemIdentifier.make(
                kind: .settlement,
                id: settlement.id
            ),
            domainIdentifier: domainIdentifier,
            attributeSet: attributeSet
        )
    }

    private static func templateItem(_ template: TransactionTemplateItem) -> CSSearchableItem {
        let attributeSet = CSSearchableItemAttributeSet(
            itemContentType: UTType.item.identifier
        )
        let amount = MoneyFormatter.string(
            minorUnits: template.amountMinor,
            currencyCode: template.account?.currencyCode ?? "USD"
        )
        attributeSet.title = template.displayTitle
        attributeSet.contentDescription = [
            amount,
            template.category?.name,
            template.account?.name,
        ]
        .compactMap { $0 }
        .joined(separator: " • ")
        attributeSet.contentModificationDate = template.updatedAt
        attributeSet.keywords = sanitizedKeywords([
            template.displayTitle,
            template.note,
            template.category?.name,
            template.account?.name,
            String(localized: "Template"),
        ])

        return CSSearchableItem(
            uniqueIdentifier: FloatSpotlightItemIdentifier.make(
                kind: .template,
                id: template.id
            ),
            domainIdentifier: domainIdentifier,
            attributeSet: attributeSet
        )
    }

    private static func recurringItem(_ rule: RecurringRuleItem) -> CSSearchableItem {
        let attributeSet = CSSearchableItemAttributeSet(
            itemContentType: UTType.item.identifier
        )
        let amount = MoneyFormatter.string(
            minorUnits: rule.amountMinor,
            currencyCode: rule.account?.currencyCode ?? "USD"
        )
        let title = rule.note?.trimmingCharacters(in: .whitespacesAndNewlines)
        attributeSet.title = title?.isEmpty == false
            ? title
            : rule.category?.name ?? String(localized: "Recurring")
        attributeSet.contentDescription = AppLocalization.format(
            "%@ • %@ • Next %@",
            amount,
            rule.cadence.title,
            rule.nextRunDate.formatted(date: .abbreviated, time: .omitted)
        )
        attributeSet.contentCreationDate = rule.createdAt
        attributeSet.keywords = sanitizedKeywords([
            title,
            rule.category?.name,
            rule.account?.name,
            rule.cadence.title,
            String(localized: "Recurring"),
        ])

        return CSSearchableItem(
            uniqueIdentifier: FloatSpotlightItemIdentifier.make(
                kind: .recurring,
                id: rule.id
            ),
            domainIdentifier: domainIdentifier,
            attributeSet: attributeSet
        )
    }

    private static func deleteDomain() async {
        await withCheckedContinuation { continuation in
            CSSearchableIndex.default().deleteSearchableItems(
                withDomainIdentifiers: [domainIdentifier]
            ) { _ in
                continuation.resume()
            }
        }
    }

    private static func index(_ items: [CSSearchableItem]) async {
        await withCheckedContinuation { continuation in
            CSSearchableIndex.default().indexSearchableItems(items) { _ in
                continuation.resume()
            }
        }
    }

    private static func sanitizedKeywords(_ values: [String?]) -> [String] {
        values.compactMap { value in
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let trimmed, !trimmed.isEmpty else { return nil }
            return trimmed
        }
    }
}
