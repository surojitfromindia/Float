import Foundation

enum MoneyParser {
    static func parseMinorUnits(from keypadText: String) -> Int64 {
        let digits = keypadText.filter(\.isNumber)
        guard !digits.isEmpty else { return 0 }
        let trimmed = String(digits.drop(while: { $0 == "0" }))
        guard !trimmed.isEmpty else { return 0 }
        return Int64(trimmed) ?? Int64.max
    }

    static func keypadText(afterAppending input: String, to current: String)
        -> String
    {
        guard input.allSatisfy(\.isNumber) else { return current }
        let raw = current.filter(\.isNumber) + input
        let trimmed = String(raw.drop(while: { $0 == "0" }))
        return String(trimmed.prefix(12))
    }

    static func deleteLast(from current: String) -> String {
        var digits = current.filter(\.isNumber)
        if !digits.isEmpty { digits.removeLast() }
        return String(digits)
    }

    static func parseDisplayAmountMinor(
        from text: String,
        currencyCode: String
    ) -> Int64 {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }

        let normalized = normalizedDecimalText(trimmed)
        guard let decimal = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")) else {
            return 0
        }

        let fractionDigits = MoneyFormatter.fractionDigits(for: currencyCode)
        let multiplier = NSDecimalNumber(
            mantissa: 1,
            exponent: Int16(fractionDigits),
            isNegative: false
        )
        let minor = NSDecimalNumber(decimal: decimal)
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
}

enum MoneyFormatter {
    static func currencyCodeFromLocale(_ locale: Locale = .current) -> String {
        if let code = locale.currency?.identifier { return code }
        return "USD"
    }

    static func string(
        minorUnits: Int64,
        currencyCode: String,
        locale: Locale = .current,
        showsSign: Bool = false
    ) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        formatter.locale = locale
        formatter.maximumFractionDigits = fractionDigits(for: currencyCode)
        formatter.minimumFractionDigits = fractionDigits(for: currencyCode)
        let divisor = pow(10.0, Double(fractionDigits(for: currencyCode)))
        let value = Decimal(minorUnits) / Decimal(divisor)
        let number = NSDecimalNumber(decimal: value)
        let formatted =
            formatter.string(from: number) ?? "\(currencyCode) \(minorUnits)"
        guard showsSign, minorUnits > 0 else { return formatted }
        return "+\(formatted)"
    }

    static func fractionDigits(for currencyCode: String) -> Int {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        return formatter.maximumFractionDigits
    }
}
