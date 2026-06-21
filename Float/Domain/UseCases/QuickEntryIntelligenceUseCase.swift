import Foundation

struct QuickEntryParseResult: Equatable {
    var amountMinor: Int64?
    var note: String?
    var timestamp: Date?
    var isExpense: Bool?
    var categoryID: UUID?
    var accountID: UUID?
    var personIDs: Set<UUID> = []

    var hasContent: Bool {
        amountMinor != nil
            || note != nil
            || timestamp != nil
            || isExpense != nil
            || categoryID != nil
            || accountID != nil
            || !personIDs.isEmpty
    }
}

struct QuickEntrySuggestion: Identifiable, Equatable {
    enum Source: String {
        case alias
        case history
        case parser
    }

    let id: String
    let title: String
    let subtitle: String
    let amountMinor: Int64?
    let isExpense: Bool
    let categoryID: UUID?
    let accountID: UUID?
    let personIDs: Set<UUID>
    let note: String?
    let icon: String
    let colorHex: String
    let source: Source
    let score: Int
}

enum QuickEntryIntelligenceUseCase {
    static func parse(
        _ text: String,
        currencyCode: String,
        categories: [CategoryItem],
        accounts: [AccountItem],
        people: [PersonItem],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> QuickEntryParseResult {
        let tokens = tokenize(text)
        guard !tokens.isEmpty else { return QuickEntryParseResult() }

        var result = QuickEntryParseResult()
        var consumed = Set<Int>()

        if let amount = amountToken(in: tokens, currencyCode: currencyCode) {
            result.amountMinor = amount.value
            consumed.insert(amount.index)
        }

        if let dateMatch = dateMatch(in: tokens, now: now, calendar: calendar) {
            result.timestamp = dateMatch.date
            consumed.formUnion(dateMatch.indexes)
        }

        if let direction = directionMatch(in: tokens) {
            result.isExpense = direction.isExpense
            consumed.insert(direction.index)
        }

        if let account = bestNameMatch(
            in: tokens,
            candidates: accounts.filter { !$0.archived }.map {
                NameCandidate(id: $0.id, name: $0.name)
            }
        ) {
            result.accountID = account.id
            consumed.formUnion(account.indexes)
        }

        if let category = bestNameMatch(
            in: tokens,
            candidates: categories.filter { !$0.archived }.map {
                NameCandidate(id: $0.id, name: $0.name)
            }
        ) {
            result.categoryID = category.id
            consumed.formUnion(category.indexes)
        }

        for person in people where !person.archived {
            let names = [person.name, person.alias].compactMap { $0?.nilIfBlankForQuickEntry }
            if let match = bestNameMatch(
                in: tokens,
                candidates: names.map { NameCandidate(id: person.id, name: $0) }
            ) {
                result.personIDs.insert(person.id)
                consumed.formUnion(match.indexes)
            }
        }

        let note = tokens.enumerated()
            .filter { !consumed.contains($0.offset) }
            .map(\.element.original)
            .joined(separator: " ")
            .nilIfBlankForQuickEntry
        result.note = note

        return result
    }

    static func suggestions(
        query: String,
        amountMinor: Int64,
        isExpense: Bool,
        recentTransactions: [TransactionItem],
        merchantAliases: [MerchantAliasItem],
        categories: [CategoryItem],
        accounts: [AccountItem],
        people: [PersonItem],
        currencyCode: String
    ) -> [QuickEntrySuggestion] {
        let normalizedQuery = query.normalizedMerchantAlias
        var suggestions: [QuickEntrySuggestion] = []

        suggestions.append(
            contentsOf: aliasSuggestions(
                normalizedQuery: normalizedQuery,
                amountMinor: amountMinor,
                isExpense: isExpense,
                aliases: merchantAliases,
                currencyCode: currencyCode
            )
        )
        suggestions.append(
            contentsOf: historySuggestions(
                normalizedQuery: normalizedQuery,
                amountMinor: amountMinor,
                isExpense: isExpense,
                transactions: recentTransactions,
                currencyCode: currencyCode
            )
        )

        return Array(
            suggestions
                .sorted {
                    if $0.score != $1.score { return $0.score > $1.score }
                    return ($0.amountMinor ?? 0) > ($1.amountMinor ?? 0)
                }
                .uniquedQuickSuggestions()
                .prefix(5)
        )
    }

    private static func aliasSuggestions(
        normalizedQuery: String,
        amountMinor: Int64,
        isExpense: Bool,
        aliases: [MerchantAliasItem],
        currencyCode: String
    ) -> [QuickEntrySuggestion] {
        aliases
            .filter { alias in
                alias.isExpense == isExpense
                    && !alias.alias.isEmpty
                    && (
                        normalizedQuery.isEmpty
                            || alias.alias.contains(normalizedQuery)
                            || normalizedQuery.contains(alias.alias)
                    )
            }
            .map { alias in
                QuickEntrySuggestion(
                    id: "alias-\(alias.id.uuidString)",
                    title: alias.displayName,
                    subtitle: aliasSubtitle(alias, currencyCode: currencyCode),
                    amountMinor: amountMinor > 0 ? amountMinor : nil,
                    isExpense: alias.isExpense,
                    categoryID: alias.category?.id,
                    accountID: alias.account?.id,
                    personIDs: [],
                    note: alias.displayName,
                    icon: alias.category?.iconKey ?? "sparkles",
                    colorHex: alias.category?.colorHex ?? "#0E7C7B",
                    source: .alias,
                    score: 120 + alias.usageCount
                )
            }
    }

    private static func historySuggestions(
        normalizedQuery: String,
        amountMinor: Int64,
        isExpense: Bool,
        transactions: [TransactionItem],
        currencyCode: String
    ) -> [QuickEntrySuggestion] {
        transactions.compactMap { transaction in
            guard transaction.isPosted, transaction.isExpense == isExpense else { return nil }
            let note = transaction.note?.nilIfBlankForQuickEntry
            let haystack = [note, transaction.categoryName, transaction.accountName]
                .compactMap { $0 }
                .joined(separator: " ")
                .normalizedMerchantAlias
            let queryMatches = normalizedQuery.isEmpty || haystack.contains(normalizedQuery)
            let amountMatches = amountMinor > 0 && amountMinor == transaction.amountMinor
            guard queryMatches || amountMatches else { return nil }

            let title = note ?? transaction.categoryName
            let amount = MoneyFormatter.string(
                minorUnits: transaction.amountMinor,
                currencyCode: currencyCode
            )
            let score = (queryMatches ? 70 : 0)
                + (amountMatches ? 45 : 0)
                + (transaction.note?.isEmpty == false ? 8 : 0)
            return QuickEntrySuggestion(
                id: "history-\(transaction.id.uuidString)",
                title: title,
                subtitle: AppLocalization.format(
                    "%@ - %@",
                    amount,
                    transaction.accountName
                ),
                amountMinor: transaction.amountMinor,
                isExpense: transaction.isExpense,
                categoryID: transaction.category?.id,
                accountID: transaction.account?.id,
                personIDs: Set(transaction.personTags.compactMap { $0.person?.id }),
                note: note,
                icon: transaction.categoryIconKey,
                colorHex: transaction.categoryColorHex,
                source: .history,
                score: score
            )
        }
    }

    private static func aliasSubtitle(
        _ alias: MerchantAliasItem,
        currencyCode: String
    ) -> String {
        let category = alias.category?.name ?? String(localized: "Category")
        let account = alias.account?.name ?? String(localized: "Account")
        return AppLocalization.format("%@ - %@", category, account)
    }

    private static func tokenize(_ text: String) -> [QuickEntryToken] {
        text.split(whereSeparator: \.isWhitespace).map {
            QuickEntryToken(original: String($0))
        }
    }

    private static func amountToken(
        in tokens: [QuickEntryToken],
        currencyCode: String
    ) -> (index: Int, value: Int64)? {
        tokens.enumerated()
            .compactMap { index, token -> (Int, Int64)? in
                guard token.normalized.contains(where: \.isNumber) else { return nil }
                let value = MoneyParser.parseDisplayAmountMinor(
                    from: token.original,
                    currencyCode: currencyCode
                )
                guard value > 0 else { return nil }
                return (index, value)
            }
            .max { $0.1 < $1.1 }
    }

    private static func dateMatch(
        in tokens: [QuickEntryToken],
        now: Date,
        calendar: Calendar
    ) -> (date: Date, indexes: Set<Int>)? {
        for (index, token) in tokens.enumerated() {
            switch token.normalized {
            case "today":
                return (now, [index])
            case "yesterday":
                return (calendar.date(byAdding: .day, value: -1, to: now) ?? now, [index])
            case "tomorrow":
                return (calendar.date(byAdding: .day, value: 1, to: now) ?? now, [index])
            default:
                continue
            }
        }
        return nil
    }

    private static func directionMatch(
        in tokens: [QuickEntryToken]
    ) -> (isExpense: Bool, index: Int)? {
        for (index, token) in tokens.enumerated() {
            if ["income", "salary", "paid", "refund", "deposit"].contains(token.normalized) {
                return (false, index)
            }
            if ["expense", "spent", "pay", "bought"].contains(token.normalized) {
                return (true, index)
            }
        }
        return nil
    }

    private static func bestNameMatch(
        in tokens: [QuickEntryToken],
        candidates: [NameCandidate]
    ) -> (id: UUID, indexes: Set<Int>)? {
        let tokenValues = tokens.map(\.normalized)
        var best: (id: UUID, indexes: Set<Int>, score: Int)?

        for candidate in candidates {
            let words = candidate.name.normalizedMerchantAlias
                .split(separator: " ")
                .map(String.init)
            guard !words.isEmpty else { continue }

            for start in tokenValues.indices {
                let end = min(tokenValues.count, start + words.count)
                let slice = Array(tokenValues[start..<end])
                guard slice == words else { continue }
                let score = words.joined().count + words.count * 4
                let indexes = Set(start..<end)
                if best == nil || score > best!.score {
                    best = (candidate.id, indexes, score)
                }
            }

            if words.count == 1,
               let word = words.first,
               let index = tokenValues.firstIndex(where: { $0 == word }) {
                let score = word.count
                if best == nil || score > best!.score {
                    best = (candidate.id, [index], score)
                }
            }
        }

        guard let best else { return nil }
        return (best.id, best.indexes)
    }
}

private struct QuickEntryToken {
    let original: String

    var normalized: String {
        original.normalizedMerchantAlias
    }
}

private struct NameCandidate {
    let id: UUID
    let name: String
}

private extension String {
    var nilIfBlankForQuickEntry: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension Array where Element == QuickEntrySuggestion {
    func uniquedQuickSuggestions() -> [QuickEntrySuggestion] {
        var seen = Set<String>()
        return filter { suggestion in
            let key = [
                suggestion.categoryID?.uuidString ?? "",
                suggestion.accountID?.uuidString ?? "",
                suggestion.note?.normalizedMerchantAlias ?? "",
                suggestion.amountMinor?.description ?? "",
            ].joined(separator: "|")
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }
}
