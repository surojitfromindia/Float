import Foundation

struct TransactionDuplicateGroup {
    let signature: String
    let transactions: [TransactionItem]

    var first: TransactionItem? {
        transactions.first
    }
}

enum TransactionDuplicateDetector {
    private static let matchingWindow: TimeInterval = 15 * 60

    static func groups(
        in transactions: [TransactionItem],
        calendar: Calendar = .current
    ) -> [TransactionDuplicateGroup] {
        let grouped = Dictionary(grouping: transactions) {
            DuplicateCandidateKey(transaction: $0, calendar: calendar)
        }

        return grouped.flatMap { key, candidates in
            clusteredGroups(from: candidates, key: key)
        }
    }

    static func duplicateTransactionIDs(
        in transactions: [TransactionItem],
        calendar: Calendar = .current
    ) -> Set<UUID> {
        groups(in: transactions, calendar: calendar).reduce(into: Set<UUID>()) { result, group in
            group.transactions.dropFirst().forEach { result.insert($0.id) }
        }
    }

    static func duplicateGroupSignaturesByTransactionID(
        in transactions: [TransactionItem],
        calendar: Calendar = .current
    ) -> [UUID: String] {
        groups(in: transactions, calendar: calendar).reduce(into: [UUID: String]()) { result, group in
            group.transactions.dropFirst().forEach { result[$0.id] = group.signature }
        }
    }

    private static func clusteredGroups(
        from candidates: [TransactionItem],
        key: DuplicateCandidateKey
    ) -> [TransactionDuplicateGroup] {
        let sorted = candidates.sorted { $0.timestamp < $1.timestamp }
        guard let first = sorted.first else { return [] }

        var previous = first
        var cluster = [first]
        var groups: [TransactionDuplicateGroup] = []

        for transaction in sorted.dropFirst() {
            let interval = transaction.timestamp.timeIntervalSince(previous.timestamp)
            if interval <= matchingWindow {
                cluster.append(transaction)
            } else {
                appendCluster(cluster, key: key, to: &groups)
                cluster = [transaction]
            }
            previous = transaction
        }

        appendCluster(cluster, key: key, to: &groups)

        return groups
    }

    private static func appendCluster(
        _ cluster: [TransactionItem],
        key: DuplicateCandidateKey,
        to groups: inout [TransactionDuplicateGroup]
    ) {
        guard cluster.count > 1 else { return }
        let signature = groupSignature(for: cluster, key: key)
        guard !cluster.contains(where: { $0.dismissedDuplicateGroupSignature == signature }) else {
            return
        }
        groups.append(
            TransactionDuplicateGroup(
                signature: signature,
                transactions: cluster
            )
        )
    }

    private static func groupSignature(
        for transactions: [TransactionItem],
        key: DuplicateCandidateKey
    ) -> String {
        let ids = transactions
            .map(\.id.uuidString)
            .sorted()
            .joined(separator: ",")
        return "\(key.id)|\(ids)"
    }
}

private struct DuplicateCandidateKey: Hashable {
    let amountMinor: Int64
    let isExpense: Bool
    let day: Date
    let categoryID: UUID?
    let accountID: UUID?
    let normalizedNote: String

    init(transaction: TransactionItem, calendar: Calendar) {
        amountMinor = transaction.amountMinor
        isExpense = transaction.isExpense
        day = calendar.startOfDay(for: transaction.timestamp)
        categoryID = transaction.category?.id
        accountID = transaction.account?.id
        normalizedNote = transaction.note?.normalizedDuplicateMatchText ?? ""
    }

    var id: String {
        [
            amountMinor.description,
            isExpense.description,
            String(day.timeIntervalSince1970),
            categoryID?.uuidString ?? "none",
            accountID?.uuidString ?? "none",
            normalizedNote,
        ].joined(separator: "|")
    }
}

private extension String {
    var normalizedDuplicateMatchText: String {
        let normalized = lowercased().map { character in
            character.isLetter || character.isNumber ? character : " "
        }
        return String(normalized)
            .split(separator: " ")
            .joined(separator: " ")
    }
}
