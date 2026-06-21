import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

struct QuickEntryIntelligenceContext {
    let currencyCode: String
    let categories: [CategoryItem]
    let accounts: [AccountItem]
    let people: [PersonItem]
    let recentTransactions: [TransactionItem]
    let merchantAliases: [MerchantAliasItem]
}

@MainActor
enum QuickEntrySemanticInterpreter {
    static func interpret(
        _ text: String,
        context: QuickEntryIntelligenceContext,
        now: Date = Date(),
        calendar: Calendar = .current
    ) async -> QuickEntryParseResult? {
        guard text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return nil
        }

        if #available(iOS 26.0, *) {
            if let result = await QuickEntryFoundationModelInterpreter.interpret(
                text,
                context: context,
                now: now,
                calendar: calendar
            ) {
                return result
            }
        }

        return QuickEntryIntelligenceUseCase.parse(
            text,
            currencyCode: context.currencyCode,
            categories: context.categories,
            accounts: context.accounts,
            people: context.people,
            now: now,
            calendar: calendar
        )
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@MainActor
private enum QuickEntryFoundationModelInterpreter {
    static func interpret(
        _ text: String,
        context: QuickEntryIntelligenceContext,
        now: Date,
        calendar: Calendar
    ) async -> QuickEntryParseResult? {
        let model = SystemLanguageModel.default
        guard model.availability == .available else { return nil }

        let fallback = QuickEntryIntelligenceUseCase.parse(
            text,
            currencyCode: context.currencyCode,
            categories: context.categories,
            accounts: context.accounts,
            people: context.people,
            now: now,
            calendar: calendar
        )

        let session = LanguageModelSession(
            instructions: instructions(
                context: context,
                now: now,
                calendar: calendar
            )
        )
        do {
            let response = try await session.respond(
                to: prompt(text),
                generating: QuickEntryModelExtraction.self,
                options: GenerationOptions(
                    sampling: .greedy,
                    temperature: 0,
                    maximumResponseTokens: 512
                )
            )
            return validated(
                response.content,
                fallback: fallback,
                context: context,
                now: now,
                calendar: calendar
            )
        } catch {
            return nil
        }
    }

    private static func instructions(
        context: QuickEntryIntelligenceContext,
        now: Date,
        calendar: Calendar
    ) -> String {
        """
        You extract one personal finance transaction from short user text.
        Return only structured fields. Never invent IDs. Use only IDs listed here.
        Resolve relative dates from today: \(dateStamp(now, calendar: calendar)).
        Interpret common finance shorthand:
        - coffee, cafe, restaurant, lunch, dinner, snacks usually map to the closest food/dining category.
        - cab, bus, train, fuel, ride usually map to transport/travel if present.
        - salary, refund, bonus, deposit are income.
        - If text says cash, card, bank, wallet, choose the matching account ID.
        - Preserve merchant/item words as note, excluding amount and date words.
        - If unsure about category/account/person, leave the ID empty.

        Categories:
        \(categoryLines(context.categories))

        Accounts:
        \(accountLines(context.accounts))

        People:
        \(personLines(context.people))

        Learned merchant aliases:
        \(aliasLines(context.merchantAliases))

        Recent examples:
        \(historyLines(context.recentTransactions, currencyCode: context.currencyCode))
        """
    }

    private static func prompt(_ text: String) -> String {
        "Extract the transaction from: \(text)"
    }

    private static func validated(
        _ extraction: QuickEntryModelExtraction,
        fallback: QuickEntryParseResult,
        context: QuickEntryIntelligenceContext,
        now: Date,
        calendar: Calendar
    ) -> QuickEntryParseResult {
        var result = fallback

        if extraction.amountMinor > 0 {
            result.amountMinor = Int64(extraction.amountMinor)
        }

        if let date = date(from: extraction.dateISO, now: now, calendar: calendar) {
            result.timestamp = date
        }

        switch extraction.direction {
        case "expense":
            result.isExpense = true
        case "income":
            result.isExpense = false
        default:
            break
        }

        if let id = UUID(uuidString: extraction.categoryID),
           context.categories.contains(where: { $0.id == id && !$0.archived }) {
            result.categoryID = id
        }

        if let id = UUID(uuidString: extraction.accountID),
           context.accounts.contains(where: { $0.id == id && !$0.archived }) {
            result.accountID = id
        }

        let validPeople = Set(context.people.filter { !$0.archived }.map(\.id))
        let people = extraction.personIDs.compactMap(UUID.init(uuidString:))
            .filter { validPeople.contains($0) }
        if !people.isEmpty {
            result.personIDs = Set(people)
        }

        if let note = extraction.note.nilIfBlankForFoundationInterpreter {
            result.note = note
        }

        return result
    }

    private static func date(from text: String, now: Date, calendar: Calendar) -> Date? {
        if let exact = isoDateFormatter.date(from: text) {
            return exact
        }
        return nil
    }

    private static var isoDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    private static func dateStamp(_ date: Date, calendar: Calendar) -> String {
        date.formatted(
            Date.FormatStyle(date: .complete, time: .omitted)
                .locale(AppLocalization.locale)
        )
    }

    private static func categoryLines(_ categories: [CategoryItem]) -> String {
        categories
            .filter { !$0.archived }
            .prefix(60)
            .map { "\($0.id.uuidString) | \($0.name) | \($0.isIncome ? "income" : "expense")" }
            .joined(separator: "\n")
    }

    private static func accountLines(_ accounts: [AccountItem]) -> String {
        accounts
            .filter { !$0.archived }
            .prefix(30)
            .map { "\($0.id.uuidString) | \($0.name) | \($0.type.title)" }
            .joined(separator: "\n")
    }

    private static func personLines(_ people: [PersonItem]) -> String {
        people
            .filter { !$0.archived }
            .prefix(40)
            .map { "\($0.id.uuidString) | \($0.name) \($0.alias ?? "")" }
            .joined(separator: "\n")
    }

    private static func aliasLines(_ aliases: [MerchantAliasItem]) -> String {
        aliases
            .prefix(40)
            .map {
                "\($0.displayName) | \($0.alias) | category=\($0.category?.id.uuidString ?? "") | account=\($0.account?.id.uuidString ?? "")"
            }
            .joined(separator: "\n")
    }

    private static func historyLines(
        _ transactions: [TransactionItem],
        currencyCode: String
    ) -> String {
        transactions
            .filter(\.isPosted)
            .prefix(40)
            .map {
                let amount = MoneyFormatter.string(
                    minorUnits: $0.amountMinor,
                    currencyCode: currencyCode
                )
                return "\($0.note ?? $0.categoryName) | \(amount) | \($0.isExpense ? "expense" : "income") | category=\($0.category?.id.uuidString ?? "") | account=\($0.account?.id.uuidString ?? "")"
            }
            .joined(separator: "\n")
    }
}

@available(iOS 26.0, *)
@Generable
private struct QuickEntryModelExtraction {
    @Guide(description: "Amount in minor currency units. For 870 rupees/dollars, use 87000 if the currency has two fraction digits. Use 0 when missing.", .minimum(0))
    var amountMinor: Int

    @Guide(description: "Either expense, income, or unknown.")
    var direction: String

    @Guide(description: "Transaction date as yyyy-MM-dd. Empty string when missing.")
    var dateISO: String

    @Guide(description: "Category UUID from the provided category list. Empty string when unsure.")
    var categoryID: String

    @Guide(description: "Account UUID from the provided account list. Empty string when unsure.")
    var accountID: String

    @Guide(description: "Person UUIDs from the provided people list.")
    var personIDs: [String]

    @Guide(description: "Clean merchant or item note, excluding amount/date/account/person words.")
    var note: String

    @Guide(description: "Confidence from 0 to 100.", .range(0...100))
    var confidence: Int
}
#endif

private extension String {
    var nilIfBlankForFoundationInterpreter: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
