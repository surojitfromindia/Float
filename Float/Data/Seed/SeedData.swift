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
        ("Rent", "house.fill", "#2563EB", false),
        ("Utilities", "bolt.fill", "#F59E0B", false),
        ("Internet", "wifi", "#0EA5E9", false),
        ("Fuel", "fuelpump.fill", "#EF4444", false),
        ("Travel", "airplane", "#14B8A6", false),
        ("Education", "graduationcap.fill", "#7C3AED", false),
        ("Subscriptions", "repeat.circle.fill", "#DB2777", false),
        ("Dining", "cup.and.saucer.fill", "#A855F7", false),
        ("Fitness", "dumbbell.fill", "#16A34A", false),
        ("Maintenance", "wrench.adjustable.fill", "#64748B", false),
        ("Insurance", "shield.fill", "#0891B2", false),
        ("Gifts", "gift.fill", "#F43F5E", false),
        ("Salary", "banknote.fill", "#57C98C", true),
        ("Bonus", "sparkles", "#22C55E", true),
        ("Freelance", "briefcase.fill", "#0F766E", true),
        ("Investment", "chart.line.uptrend.xyaxis", "#059669", true),
        ("Refund", "arrow.uturn.backward.circle.fill", "#10B981", true),
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
