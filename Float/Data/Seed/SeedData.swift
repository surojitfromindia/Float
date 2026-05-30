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
        let categoryFetch = FetchDescriptor<CategoryItem>()
        let existingCategories = (try? modelContext.fetch(categoryFetch)) ?? []
        if existingCategories.isEmpty {
            for (index, item) in defaultCategories.enumerated() {
                modelContext.insert(
                    CategoryItem(
                        name: item.0,
                        iconKey: item.1,
                        colorHex: item.2,
                        isIncome: item.3,
                        sortOrder: index,
                        isDefault: true
                    )
                )
            }
        }

        let accountFetch = FetchDescriptor<AccountItem>()
        let existingAccounts = (try? modelContext.fetch(accountFetch)) ?? []
        if existingAccounts.isEmpty {
            modelContext.insert(
                AccountItem(
                    name: "Cash",
                    type: .cash,
                    currencyCode: currencyCode
                )
            )
        }

        let budgetFetch = FetchDescriptor<BudgetPeriodItem>()
        let existingBudgets = (try? modelContext.fetch(budgetFetch)) ?? []
        if existingBudgets.isEmpty {
            modelContext.insert(BudgetPeriodItem(currencyCode: currencyCode))
        }

        try? modelContext.save()
    }
}
