import Foundation
import SwiftData

enum SeedData {
    static let defaultCategories: [(String, String, String, Bool)] = [
        ("Food", "fork.knife", "#0E7C7B", false),
        ("Transport", "car.fill", "#3B82F6", false),
        ("Bills", "doc.text.fill", "#B4613B", false),
        ("Groceries", "basket.fill", "#1B8A5A", false),
        ("Shopping", "bag.fill", "#8B5CF6", false),
        ("Health", "cross.case.fill", "#D08A62", false),
        ("Entertainment", "play.tv.fill", "#EC4899", false),
        ("Salary", "banknote.fill", "#57C98C", true),
        ("Other", "square.grid.2x2.fill", "#5A6B6B", false),
    ]

    @MainActor
    static func ensureSeedData(modelContext: ModelContext, currencyCode: String)
    {
        SeedDataService.ensureSeedData(
            modelContext: modelContext,
            currencyCode: currencyCode
        )
    }
}
