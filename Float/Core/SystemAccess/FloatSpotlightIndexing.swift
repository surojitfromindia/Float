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

    static func scheduleReindex(modelContext: ModelContext) {
        reindexTask?.cancel()
        reindexTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            await reindexAll(modelContext: modelContext)
        }
    }

    static func reindexAll(modelContext: ModelContext) async {
        let items = makeSearchableItems(modelContext: modelContext)
        await deleteDomain()
        guard !items.isEmpty else { return }
        await index(items)
    }

    private static func makeSearchableItems(modelContext: ModelContext) -> [CSSearchableItem] {
        let transactions = (try? modelContext.fetch(FetchDescriptor<TransactionItem>())) ?? []
        let transfers = (try? modelContext.fetch(FetchDescriptor<TransferItem>())) ?? []
        let accounts = (try? modelContext.fetch(FetchDescriptor<AccountItem>())) ?? []
        let categories = (try? modelContext.fetch(FetchDescriptor<CategoryItem>())) ?? []
        let people = (try? modelContext.fetch(FetchDescriptor<PersonItem>())) ?? []

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

        return indexedTransactions + indexedTransfers + indexedAccounts + indexedCategories + indexedPeople
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
