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
