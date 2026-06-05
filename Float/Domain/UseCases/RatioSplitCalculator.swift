import Foundation

enum RatioSplitCalculator {
    static func amounts(totalMinor: Int64, ratios: [Int]) -> [Int64] {
        guard totalMinor > 0,
              ratios.count >= 2,
              ratios.allSatisfy({ $0 > 0 })
        else {
            return []
        }

        let totalRatio = ratios.reduce(Int64(0)) { $0 + Int64($1) }
        guard totalRatio > 0 else { return [] }

        var amounts = ratios.map { ratio in
            totalMinor * Int64(ratio) / totalRatio
        }
        var remainder = totalMinor - amounts.reduce(Int64(0), +)
        var index = 0

        while remainder > 0 && !amounts.isEmpty {
            amounts[index] += 1
            remainder -= 1
            index = (index + 1) % amounts.count
        }

        return amounts
    }
}
