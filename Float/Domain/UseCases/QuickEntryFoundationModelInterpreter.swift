import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

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

#if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return await QuickEntryFoundationModelInterpreter.interpret(
                text,
                context: context,
                now: now,
                calendar: calendar
            )
        }
#endif

        return nil
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

        let session = LanguageModelSession(
            instructions: instructions(
                for: text,
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
                    maximumResponseTokens: 256
                )
            )
            return validated(
                response.content,
                originalText: text,
                context: context,
                now: now,
                calendar: calendar
            )
        } catch {
            debugPrint("Quick entry model interpretation failed: \(error)")
            return nil
        }
    }

    private static func instructions(
        for text: String,
        context: QuickEntryIntelligenceContext,
        now: Date,
        calendar: Calendar
    ) -> String {
        """
        You extract one personal finance transaction from short user text.
        Return only structured fields. Never invent IDs. Use only IDs listed here.
        Resolve relative dates from today: \(dateStamp(now, calendar: calendar)).
        Interpret common finance shorthand:
        - Resolve natural dates like today, yesterday, last sunday, and 2 weeks ago to dateISO.
        - coffee, cafe, restaurant, lunch, dinner, snacks usually map to the closest food/dining category.
        - cab, bus, train, fuel, ride usually map to transport/travel if present.
        - salary, refund, bonus, deposit are income.
        - If text says cash, card, bank, wallet, choose the matching account ID.
        - For quantity/unit text like "2 cups of coffee for 50 each", set quantityText=2, unitPriceText=50, amountText=50, and note=coffee.
        - Treat minor typos in unit-pricing words, such as "forr" meaning "for".
        - Copy amounts exactly as written in the text. Do not convert them to cents, paise, or minor units.
        - Choose category from the item or merchant name, not from units or prices.
        - Preserve merchant/item words as note, excluding amount, quantity, unit, and date words.
        - If unsure about category/account/person, leave the ID empty.

        Candidate categories:
        \(categoryLines(context.categories, query: text))

        Candidate accounts:
        \(accountLines(context.accounts, query: text))

        Candidate people:
        \(personLines(context.people, query: text))

        Matching merchant aliases:
        \(aliasLines(context.merchantAliases, query: text))

        Matching recent examples:
        \(historyLines(context.recentTransactions, query: text))
        """
    }

    private static func prompt(_ text: String) -> String {
        "Extract the transaction from: \(text)"
    }

    private static func validated(
        _ extraction: QuickEntryModelExtraction,
        originalText: String,
        context: QuickEntryIntelligenceContext,
        now: Date,
        calendar: Calendar
    ) -> QuickEntryParseResult {
        var result = QuickEntryParseResult()

        if let amountMinor = amountMinor(
            from: originalText,
            extraction: extraction,
            currencyCode: context.currencyCode
        ) {
            result.amountMinor = amountMinor
        }

        let parsedNote = extraction.note?.nilIfBlankForFoundationInterpreter

        if let note = parsedNote {
            result.note = note
        }

        if let date = relativeDate(
            from: originalText,
            now: now,
            calendar: calendar
        ) {
            result.timestamp = date
        } else if let date = date(
            from: extraction.dateISO ?? "",
            now: now,
            calendar: calendar
        ) {
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

        if let categoryID = extraction.categoryID,
           let id = UUID(uuidString: categoryID),
           context.categories.contains(where: {
               $0.id == id
                   && !$0.archived
                   && categoryMatchesDirection($0, isExpense: result.isExpense)
           }) {
            result.categoryID = id
        }

        if result.categoryID == nil,
           let categoryID = categoryID(
                matching: parsedNote ?? originalText,
                categories: context.categories,
                isExpense: result.isExpense
           ) {
            result.categoryID = categoryID
        }

        if let accountID = extraction.accountID,
           let id = UUID(uuidString: accountID),
           context.accounts.contains(where: { $0.id == id && !$0.archived }) {
            result.accountID = id
        }

        let validPeople = Set(context.people.filter { !$0.archived }.map(\.id))
        let people = (extraction.personIDs ?? []).compactMap(UUID.init(uuidString:))
            .filter { validPeople.contains($0) }
        if !people.isEmpty {
            result.personIDs = Set(people)
        }

        return result
    }

    private static func amountMinor(
        from originalText: String,
        extraction: QuickEntryModelExtraction,
        currencyCode: String
    ) -> Int64? {
        if let amountMinor = deterministicAmountMinor(
            from: originalText,
            currencyCode: currencyCode
        ) {
            return amountMinor
        }

        let quantity = extraction.quantityText
            .flatMap { decimalAmount(from: $0) }
        let unitPrice = extraction.unitPriceText
            .flatMap { decimalAmount(from: $0) }

        if let quantity, quantity > 0,
           let unitPrice, unitPrice > 0 {
            let total = quantity * unitPrice
            let minor = minorUnits(from: total, currencyCode: currencyCode)
            return minor > 0 ? minor : nil
        }

        if let amountText = extraction.amountText?.nilIfBlankForFoundationInterpreter {
            let amountMinor = MoneyParser.parseDisplayAmountMinor(
                from: amountText,
                currencyCode: currencyCode
            )
            return amountMinor > 0 ? amountMinor : nil
        }

        return nil
    }

    private static func deterministicAmountMinor(
        from text: String,
        currencyCode: String
    ) -> Int64? {
        let tokens = amountTokens(from: text)
        guard !tokens.isEmpty else { return nil }

        if let amountMinor = unitPriceAmountMinor(
            from: tokens,
            currencyCode: currencyCode
        ) {
            return amountMinor
        }

        let candidates = tokens.enumerated().compactMap { index, token -> AmountCandidate? in
            guard let amount = token.decimalAmount,
                  amount > 0,
                  !isDateNumber(at: index, in: tokens, originalText: text),
                  !isLikelyQuantityNumber(at: index, in: tokens) else {
                return nil
            }

            return AmountCandidate(
                amount: amount,
                score: amountScore(at: index, in: tokens)
            )
        }

        guard let best = candidates.sorted(by: {
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.amount > $1.amount
        }).first else {
            return nil
        }

        let minor = minorUnits(from: best.amount, currencyCode: currencyCode)
        return minor > 0 ? minor : nil
    }

    private static func unitPriceAmountMinor(
        from tokens: [AmountToken],
        currencyCode: String
    ) -> Int64? {
        for (quantityIndex, quantityToken) in tokens.enumerated() {
            guard let quantity = quantityToken.decimalAmount,
                  quantity > 0,
                  isLikelyQuantityNumber(at: quantityIndex, in: tokens) else {
                continue
            }

            let searchStart = min(quantityIndex + 2, tokens.endIndex)
            guard searchStart < tokens.endIndex else { continue }

            for priceIndex in searchStart..<tokens.endIndex {
                guard let unitPrice = tokens[priceIndex].decimalAmount,
                      unitPrice > 0,
                      !isDateNumber(at: priceIndex, in: tokens, originalText: "") else {
                    continue
                }

                let hasUnitPricingMarker =
                    tokenBefore(priceIndex, in: tokens).map(unitPricePrefixes.contains) == true
                        || tokenAfter(priceIndex, in: tokens).map(unitPriceSuffixes.contains) == true

                guard hasUnitPricingMarker else { continue }

                let total = quantity * unitPrice
                let minor = minorUnits(from: total, currencyCode: currencyCode)
                return minor > 0 ? minor : nil
            }
        }

        return nil
    }

    private static func amountTokens(from text: String) -> [AmountToken] {
        var tokens: [AmountToken] = []
        var tokenStart: String.Index?

        func appendToken(endingAt end: String.Index) {
            guard let start = tokenStart else { return }
            let rawText = String(text[start..<end])
            let normalizedText = rawText
                .lowercased()
                .trimmingCharacters(in: .punctuationCharacters)
            if !normalizedText.isEmpty {
                tokens.append(AmountToken(
                    rawText: rawText,
                    normalizedText: normalizedText,
                    range: start..<end
                ))
            }
            tokenStart = nil
        }

        for index in text.indices {
            if isAmountTokenCharacter(text[index]) {
                if tokenStart == nil {
                    tokenStart = index
                }
            } else {
                appendToken(endingAt: index)
            }
        }

        appendToken(endingAt: text.endIndex)
        return tokens
    }

    private static func isAmountTokenCharacter(_ character: Character) -> Bool {
        character.isLetter
            || character.isNumber
            || character == "."
            || character == ","
            || currencySymbols.contains(character)
    }

    private static func isDateNumber(
        at index: Int,
        in tokens: [AmountToken],
        originalText: String
    ) -> Bool {
        guard tokens[index].decimalAmount != nil else { return false }

        if !originalText.isEmpty,
           isAdjacentToDateSeparator(tokens[index], in: originalText) {
            return true
        }

        if let next = tokenAfter(index, in: tokens),
           relativeDateComponent(next) != nil {
            let afterComponent = tokenAfter(index + 1, in: tokens)
            if afterComponent.map(relativeDateSuffixes.contains) == true {
                return true
            }
        }

        let previous = tokenBefore(index, in: tokens)
        let next = tokenAfter(index, in: tokens)
        if previous.map(monthWords.contains) == true || next.map(monthWords.contains) == true {
            return true
        }

        return false
    }

    private static func isAdjacentToDateSeparator(
        _ token: AmountToken,
        in text: String
    ) -> Bool {
        if token.range.lowerBound > text.startIndex {
            let previousIndex = text.index(before: token.range.lowerBound)
            if dateSeparators.contains(text[previousIndex]) {
                return true
            }
        }

        if token.range.upperBound < text.endIndex,
           dateSeparators.contains(text[token.range.upperBound]) {
            return true
        }

        return false
    }

    private static func isLikelyQuantityNumber(
        at index: Int,
        in tokens: [AmountToken]
    ) -> Bool {
        guard let next = tokenAfter(index, in: tokens),
              quantityUnits.contains(next) else {
            return false
        }

        let previous = tokenBefore(index, in: tokens)
        return previous.map(amountMarkers.contains) != true
    }

    private static func amountScore(
        at index: Int,
        in tokens: [AmountToken]
    ) -> Int {
        var score = index
        let token = tokens[index]

        if token.rawText.contains(where: currencySymbols.contains) {
            score += 100
        }

        if tokenBefore(index, in: tokens).map(amountMarkers.contains) == true {
            score += 60
        }

        if tokenAfter(index, in: tokens).map(amountMarkers.contains) == true {
            score += 40
        }

        if tokenBefore(index, in: tokens).map(unitPricePrefixes.contains) == true {
            score += 20
        }

        if tokenAfter(index, in: tokens).map(unitPriceSuffixes.contains) == true {
            score += 20
        }

        return score
    }

    private static func tokenBefore(
        _ index: Int,
        in tokens: [AmountToken]
    ) -> String? {
        guard index > tokens.startIndex else { return nil }
        return tokens[index - 1].normalizedText
    }

    private static func tokenAfter(
        _ index: Int,
        in tokens: [AmountToken]
    ) -> String? {
        let nextIndex = index + 1
        guard nextIndex < tokens.endIndex else { return nil }
        return tokens[nextIndex].normalizedText
    }

    private struct AmountToken {
        let rawText: String
        let normalizedText: String
        let range: Range<String.Index>

        var decimalAmount: Decimal? {
            QuickEntryFoundationModelInterpreter.decimalAmount(from: rawText)
        }
    }

    private struct AmountCandidate {
        let amount: Decimal
        let score: Int
    }

    private static let amountMarkers: Set<String> = [
        "rs", "inr", "rupee", "rupees",
        "usd", "dollar", "dollars",
        "₹", "$", "€", "£", "¥",
        "paid", "spent", "cost", "costs", "amount", "total",
        "for", "forr", "at",
    ]

    private static let unitPricePrefixes: Set<String> = [
        "for", "forr", "at", "@",
    ]

    private static let unitPriceSuffixes: Set<String> = [
        "each", "ea", "per", "piece", "pc", "unit",
    ]

    private static let quantityUnits: Set<String> = [
        "bag", "bags", "bottle", "bottles", "box", "boxes",
        "cup", "cups", "dozen", "g", "gm", "gram", "grams",
        "item", "items", "kg", "kgs", "kilogram", "kilograms",
        "l", "liter", "liters", "litre", "litres", "ml",
        "pack", "packs", "packet", "packets", "pc", "pcs",
        "piece", "pieces", "plate", "plates", "serving", "servings",
        "coffee", "coffees", "tea", "teas",
    ]

    private static let relativeDateSuffixes: Set<String> = [
        "ago", "back", "before",
    ]

    private static let monthWords: Set<String> = [
        "jan", "january", "feb", "february", "mar", "march",
        "apr", "april", "may", "jun", "june", "jul", "july",
        "aug", "august", "sep", "sept", "september",
        "oct", "october", "nov", "november", "dec", "december",
    ]

    private static let currencySymbols: Set<Character> = [
        "₹", "$", "€", "£", "¥",
    ]

    private static let dateSeparators: Set<Character> = [
        "/", "-",
    ]

    private static func decimalAmount(from text: String) -> Decimal? {
        let normalized = normalizedDecimalText(text)
        guard !normalized.isEmpty else { return nil }
        return Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX"))
    }

    private static func normalizedDecimalText(_ text: String) -> String {
        let scalarText = text.filter {
            $0.isNumber || $0 == "." || $0 == ","
        }
        guard !scalarText.isEmpty else { return "" }

        if scalarText.contains(".") {
            return scalarText.replacingOccurrences(of: ",", with: "")
        }

        let commaParts = scalarText.split(separator: ",", omittingEmptySubsequences: false)
        if commaParts.count == 2,
           let fraction = commaParts.last,
           !fraction.isEmpty,
           fraction.count <= 2 {
            return commaParts.joined(separator: ".")
        }

        return scalarText.replacingOccurrences(of: ",", with: "")
    }

    private static func minorUnits(from amount: Decimal, currencyCode: String) -> Int64 {
        let fractionDigits = MoneyFormatter.fractionDigits(for: currencyCode)
        let multiplier = NSDecimalNumber(
            mantissa: 1,
            exponent: Int16(fractionDigits),
            isNegative: false
        )
        let minor = NSDecimalNumber(decimal: amount)
            .multiplying(by: multiplier)
            .rounding(accordingToBehavior: NSDecimalNumberHandler(
                roundingMode: .plain,
                scale: 0,
                raiseOnExactness: false,
                raiseOnOverflow: false,
                raiseOnUnderflow: false,
                raiseOnDivideByZero: false
            ))
        return max(0, minor.int64Value)
    }

    private static func date(from text: String, now: Date, calendar: Calendar) -> Date? {
        if let exact = isoDateFormatter.date(from: text) {
            return calendar.startOfDay(for: exact)
        }
        return nil
    }

    private static func relativeDate(
        from text: String,
        now: Date,
        calendar: Calendar
    ) -> Date? {
        let words = normalizedDateWords(from: text)
        guard !words.isEmpty else { return nil }

        let today = calendar.startOfDay(for: now)

        if containsPhrase(["day", "before", "yesterday"], in: words) {
            return calendar.date(byAdding: .day, value: -2, to: today)
        }
        if containsPhrase(["day", "after", "tomorrow"], in: words) {
            return calendar.date(byAdding: .day, value: 2, to: today)
        }
        if words.contains("today") {
            return today
        }
        if words.contains("yesterday") {
            return calendar.date(byAdding: .day, value: -1, to: today)
        }
        if words.contains("tomorrow") {
            return calendar.date(byAdding: .day, value: 1, to: today)
        }
        if let date = offsetDate(from: words, today: today, calendar: calendar) {
            return date
        }
        if let date = weekdayDate(from: words, today: today, calendar: calendar) {
            return date
        }

        return nil
    }

    private static func normalizedDateWords(from text: String) -> [String] {
        text.lowercased()
            .map { character in
                character.isLetter || character.isNumber ? character : " "
            }
            .reduce(into: "") { partial, character in
                partial.append(character)
            }
            .split(separator: " ")
            .map(String.init)
    }

    private static func containsPhrase(_ phrase: [String], in words: [String]) -> Bool {
        guard !phrase.isEmpty, words.count >= phrase.count else { return false }

        for startIndex in words.indices {
            let endIndex = startIndex + phrase.count
            guard endIndex <= words.count else { break }
            if Array(words[startIndex..<endIndex]) == phrase {
                return true
            }
        }

        return false
    }

    private static func offsetDate(
        from words: [String],
        today: Date,
        calendar: Calendar
    ) -> Date? {
        for index in words.indices {
            guard index + 2 < words.count,
                  let value = relativeDateNumber(words[index]),
                  let component = relativeDateComponent(words[index + 1]),
                  ["ago", "back", "before"].contains(words[index + 2]) else {
                continue
            }

            return calendar.date(
                byAdding: component,
                value: -value,
                to: today
            )
        }

        for index in words.indices {
            guard index + 1 < words.count,
                  words[index] == "last",
                  let component = relativeDateComponent(words[index + 1]) else {
                continue
            }

            return calendar.date(
                byAdding: component,
                value: -1,
                to: today
            )
        }

        return nil
    }

    private static func relativeDateNumber(_ word: String) -> Int? {
        if let value = Int(word), value > 0 {
            return value
        }

        switch word {
        case "a", "an", "one":
            return 1
        case "two":
            return 2
        case "three":
            return 3
        case "four":
            return 4
        case "five":
            return 5
        case "six":
            return 6
        case "seven":
            return 7
        case "eight":
            return 8
        case "nine":
            return 9
        case "ten":
            return 10
        case "eleven":
            return 11
        case "twelve":
            return 12
        default:
            return nil
        }
    }

    private static func relativeDateComponent(_ word: String) -> Calendar.Component? {
        switch word {
        case "day", "days":
            return .day
        case "week", "weeks", "wk", "wks":
            return .weekOfYear
        case "month", "months", "mo", "mos":
            return .month
        case "year", "years", "yr", "yrs":
            return .year
        default:
            return nil
        }
    }

    private static func weekdayDate(
        from words: [String],
        today: Date,
        calendar: Calendar
    ) -> Date? {
        for index in words.indices {
            guard let weekday = weekdayNumber(words[index]) else { continue }

            if index > words.startIndex {
                switch words[index - 1] {
                case "last":
                    return previousWeekday(
                        weekday,
                        before: today,
                        calendar: calendar
                    )
                case "this":
                    return weekdayInCurrentWeek(
                        weekday,
                        today: today,
                        calendar: calendar
                    )
                case "next":
                    return nextWeekday(
                        weekday,
                        after: today,
                        calendar: calendar
                    )
                default:
                    break
                }
            }

            return mostRecentWeekday(
                weekday,
                today: today,
                calendar: calendar
            )
        }

        return nil
    }

    private static func weekdayNumber(_ word: String) -> Int? {
        switch word {
        case "sunday", "sun":
            return 1
        case "monday", "mon":
            return 2
        case "tuesday", "tue", "tues":
            return 3
        case "wednesday", "wed":
            return 4
        case "thursday", "thu", "thur", "thurs":
            return 5
        case "friday", "fri":
            return 6
        case "saturday", "sat":
            return 7
        default:
            return nil
        }
    }

    private static func previousWeekday(
        _ weekday: Int,
        before today: Date,
        calendar: Calendar
    ) -> Date? {
        let currentWeekday = calendar.component(.weekday, from: today)
        var daysBack = (currentWeekday - weekday + 7) % 7
        if daysBack == 0 {
            daysBack = 7
        }
        return calendar.date(byAdding: .day, value: -daysBack, to: today)
    }

    private static func mostRecentWeekday(
        _ weekday: Int,
        today: Date,
        calendar: Calendar
    ) -> Date? {
        let currentWeekday = calendar.component(.weekday, from: today)
        let daysBack = (currentWeekday - weekday + 7) % 7
        return calendar.date(byAdding: .day, value: -daysBack, to: today)
    }

    private static func nextWeekday(
        _ weekday: Int,
        after today: Date,
        calendar: Calendar
    ) -> Date? {
        let currentWeekday = calendar.component(.weekday, from: today)
        var daysAhead = (weekday - currentWeekday + 7) % 7
        if daysAhead == 0 {
            daysAhead = 7
        }
        return calendar.date(byAdding: .day, value: daysAhead, to: today)
    }

    private static func weekdayInCurrentWeek(
        _ weekday: Int,
        today: Date,
        calendar: Calendar
    ) -> Date? {
        guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: today)?.start else {
            return mostRecentWeekday(weekday, today: today, calendar: calendar)
        }

        let weekStartWeekday = calendar.component(.weekday, from: weekStart)
        let daysFromWeekStart = (weekday - weekStartWeekday + 7) % 7
        return calendar.date(byAdding: .day, value: daysFromWeekStart, to: weekStart)
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

    private static func categoryLines(
        _ categories: [CategoryItem],
        query: String
    ) -> String {
        categories
            .filter { !$0.archived }
            .rankedForFoundationPrompt(query: query) { categoryPromptText($0) }
            .prefix(28)
            .map {
                [
                    $0.id.uuidString,
                    $0.name.limitedForFoundationPrompt,
                    $0.isIncome ? "income" : "expense",
                    categoryKeywordLine($0),
                ].joined(separator: " | ")
            }
            .joined(separator: "\n")
    }

    private static func accountLines(
        _ accounts: [AccountItem],
        query: String
    ) -> String {
        accounts
            .filter { !$0.archived }
            .rankedForFoundationPrompt(query: query) { $0.name }
            .prefix(12)
            .map {
                [
                    $0.id.uuidString,
                    $0.name.limitedForFoundationPrompt,
                    $0.type.title,
                ].joined(separator: " | ")
            }
            .joined(separator: "\n")
    }

    private static func personLines(
        _ people: [PersonItem],
        query: String
    ) -> String {
        people
            .filter { !$0.archived }
            .rankedForFoundationPrompt(query: query) {
                [$0.name, $0.alias].compactMap { $0 }.joined(separator: " ")
            }
            .prefix(12)
            .map {
                [
                    $0.id.uuidString,
                    [$0.name, $0.alias]
                        .compactMap { $0?.limitedForFoundationPrompt }
                        .joined(separator: " "),
                ].joined(separator: " | ")
            }
            .joined(separator: "\n")
    }

    private static func aliasLines(
        _ aliases: [MerchantAliasItem],
        query: String
    ) -> String {
        aliases
            .rankedForFoundationPrompt(query: query) {
                "\($0.displayName) \($0.alias)"
            }
            .prefix(8)
            .map {
                [
                    $0.displayName.limitedForFoundationPrompt,
                    "category=\($0.category?.id.uuidString ?? "")",
                    "account=\($0.account?.id.uuidString ?? "")",
                ].joined(separator: " | ")
            }
            .joined(separator: "\n")
    }

    private static func historyLines(
        _ transactions: [TransactionItem],
        query: String
    ) -> String {
        transactions
            .filter(\.isPosted)
            .rankedForFoundationPrompt(query: query) {
                [$0.note, $0.categoryName, $0.accountName]
                    .compactMap { $0 }
                    .joined(separator: " ")
            }
            .prefix(6)
            .map {
                [
                    ($0.note ?? $0.categoryName).limitedForFoundationPrompt,
                    $0.isExpense ? "expense" : "income",
                    "category=\($0.category?.id.uuidString ?? "")",
                    "account=\($0.account?.id.uuidString ?? "")",
                ].joined(separator: " | ")
            }
            .joined(separator: "\n")
    }

    private static func categoryID(
        matching note: String,
        categories: [CategoryItem],
        isExpense: Bool?
    ) -> UUID? {
        let query = note.normalizedMerchantAlias
        guard !query.isEmpty else { return nil }

        let matches = categories
            .filter {
                !$0.archived
                    && categoryMatchesDirection($0, isExpense: isExpense)
            }
            .map { category in
                (
                    category: category,
                    score: categoryMatchScore(query: query, category: category)
                )
            }
            .filter { $0.score > 0 }
            .sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                return $0.category.sortOrder < $1.category.sortOrder
            }

        return matches.first?.category.id
    }

    private static func categoryMatchesDirection(
        _ category: CategoryItem,
        isExpense: Bool?
    ) -> Bool {
        guard let isExpense else { return true }
        return category.isIncome != isExpense
    }

    private static func categoryMatchScore(
        query: String,
        category: CategoryItem
    ) -> Int {
        let candidate = categoryPromptText(category).normalizedMerchantAlias
        guard !candidate.isEmpty else { return 0 }

        let queryWords = Set(query.split(separator: " ").map(String.init))
        let candidateWords = Set(candidate.split(separator: " ").map(String.init))
        let exactScore = candidate == query ? 100 : 0
        let containmentScore = candidate.contains(query) || query.contains(candidate) ? 50 : 0
        let overlapScore = queryWords.intersection(candidateWords).count * 10
        return exactScore + containmentScore + overlapScore
    }

    private static func categoryPromptText(_ category: CategoryItem) -> String {
        ([category.name] + categoryKeywords(category))
            .joined(separator: " ")
    }

    private static func categoryKeywordLine(_ category: CategoryItem) -> String {
        let keywords = categoryKeywords(category)
        guard !keywords.isEmpty else { return "items=" }
        return "items=\(keywords.joined(separator: ","))"
    }

    private static func categoryKeywords(_ category: CategoryItem) -> [String] {
        let name = category.name.normalizedMerchantAlias

        if name.contains("food") {
            return ["coffee", "tea", "breakfast", "lunch", "snack", "meal"]
        }
        if name.contains("dining") || name.contains("restaurant") {
            return ["restaurant", "cafe", "dinner", "takeout", "delivery", "meal"]
        }
        if name.contains("grocery") {
            return ["milk", "bread", "rice", "fruit", "vegetable", "produce", "supermarket"]
        }
        if name.contains("transport") || name.contains("travel") {
            return ["cab", "taxi", "ride", "bus", "train", "metro", "parking", "toll"]
        }
        if name.contains("fuel") {
            return ["fuel", "petrol", "diesel", "gas", "charging", "vehicle"]
        }
        if name.contains("bill") {
            return ["phone", "water", "electricity", "service", "charge", "bill"]
        }
        if name.contains("utilit") {
            return ["electricity", "gas", "water", "maintenance"]
        }
        if name.contains("internet") {
            return ["broadband", "wifi", "mobile", "data", "internet"]
        }
        if name.contains("health") || name.contains("medical") {
            return ["pharmacy", "medicine", "doctor", "hospital", "vitamin"]
        }
        if name.contains("shopping") {
            return ["clothes", "accessory", "online", "order", "purchase"]
        }
        if name.contains("entertainment") {
            return ["movie", "streaming", "game", "concert", "show"]
        }
        if name.contains("rent") {
            return ["rent", "lease", "home"]
        }
        if name.contains("education") {
            return ["course", "book", "workshop", "class", "tuition"]
        }
        if name.contains("subscription") {
            return ["subscription", "music", "cloud", "app", "plan"]
        }
        if name.contains("fitness") {
            return ["gym", "yoga", "sport", "training"]
        }
        if name.contains("insurance") {
            return ["insurance", "premium", "policy"]
        }
        if name.contains("gift") {
            return ["gift", "donation", "birthday", "celebration"]
        }
        if name.contains("salary") {
            return ["salary", "payroll", "paycheck", "wage"]
        }
        if name.contains("refund") {
            return ["refund", "cashback", "reimbursement", "return"]
        }
        if name.contains("bonus") {
            return ["bonus", "incentive", "reward"]
        }

        return []
    }
}

@available(iOS 26.0, *)
@Generable
private struct QuickEntryModelExtraction {
    @Guide(description: "Exact amount text copied from the input, such as 870, 12.50, or ₹870. Empty when missing.")
    var amountText: String?

    @Guide(description: "Quantity copied from unit pricing text, such as 2 from '2 cups of coffee'. Empty when no quantity is present.")
    var quantityText: String?

    @Guide(description: "Per-unit price copied from text, such as 50 from '50 each'. Empty when no per-unit price is present.")
    var unitPriceText: String?

    @Guide(description: "Either expense, income, or unknown.")
    var direction: String?

    @Guide(description: "Transaction date as yyyy-MM-dd. Empty string when missing.")
    var dateISO: String?

    @Guide(description: "Category UUID from the provided category list. Empty string when unsure.")
    var categoryID: String?

    @Guide(description: "Account UUID from the provided account list. Empty string when unsure.")
    var accountID: String?

    @Guide(description: "Person UUIDs from the provided people list.")
    var personIDs: [String]?

    @Guide(description: "Clean merchant or item note, excluding amount, quantity, unit, date, account, and person words.")
    var note: String?
}
#endif

private extension String {
    var nilIfBlankForFoundationInterpreter: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var limitedForFoundationPrompt: String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 48 else { return trimmed }
        return String(trimmed.prefix(48))
    }
}

private extension Array {
    func rankedForFoundationPrompt(
        query: String,
        text: (Element) -> String
    ) -> [Element] {
        let query = query.normalizedMerchantAlias
        guard !query.isEmpty else { return self }
        let queryWords = Set(query.split(separator: " ").map(String.init))

        return enumerated()
            .map { offset, element in
                let candidate = text(element).normalizedMerchantAlias
                let candidateWords = Set(candidate.split(separator: " ").map(String.init))
                let exactScore = candidate == query ? 100 : 0
                let containmentScore = candidate.contains(query) || query.contains(candidate) ? 50 : 0
                let overlapScore = queryWords.intersection(candidateWords).count * 10
                return (
                    offset: offset,
                    element: element,
                    score: exactScore + containmentScore + overlapScore
                )
            }
            .sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                return $0.offset < $1.offset
            }
            .map(\.element)
    }
}
