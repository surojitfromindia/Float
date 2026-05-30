import Foundation
import SwiftData

enum DataIntegrityError: LocalizedError {
    case saveFailed
    case missingRequiredAccount
    case missingRequiredCategory

    var errorDescription: String? {
        switch self {
        case .saveFailed:
            "Float could not save the latest changes."
        case .missingRequiredAccount:
            "Float could not find an account for this transaction."
        case .missingRequiredCategory:
            "Float could not find a category for this transaction."
        }
    }
}

enum DefaultAccountResolver {
    @MainActor
    static func resolve(
        preferredID: String?,
        accounts: [AccountItem],
        modelContext: ModelContext,
        currencyCode: String
    ) -> AccountItem {
        if let preferredID,
           let match = accounts.first(where: {
               !$0.archived && $0.id.uuidString == preferredID
           }) {
            return match
        }

        if let cash = accounts.first(where: {
            !$0.archived && $0.name.localizedCaseInsensitiveCompare("Cash") == .orderedSame
        }) {
            return cash
        }

        if let firstActive = accounts.first(where: { !$0.archived }) {
            return firstActive
        }

        let account = AccountItem(
            name: "Cash",
            type: .cash,
            currencyCode: currencyCode
        )
        modelContext.insert(account)
        return account
    }
}

enum DefaultCategoryResolver {
    @MainActor
    static func resolve(
        isExpense: Bool,
        preferredID: String?,
        categories: [CategoryItem],
        modelContext: ModelContext
    ) -> CategoryItem {
        let wantsIncome = !isExpense

        if let preferredID,
           let match = categories.first(where: {
               !$0.archived && $0.isIncome == wantsIncome && $0.id.uuidString == preferredID
           }) {
            return match
        }

        if isExpense,
           let other = categories.first(where: {
               !$0.archived && !$0.isIncome
                   && $0.name.localizedCaseInsensitiveCompare("Other") == .orderedSame
           }) {
            return other
        }

        if !isExpense,
           let salary = categories.first(where: {
               !$0.archived && $0.isIncome
                   && $0.name.localizedCaseInsensitiveCompare("Salary") == .orderedSame
           }) {
            return salary
        }

        if let firstActive = categories.first(where: {
            !$0.archived && $0.isIncome == wantsIncome
        }) {
            return firstActive
        }

        let fallback = fallbackCategory(isExpense: isExpense, sortOrder: categories.count)
        modelContext.insert(fallback)
        return fallback
    }

    private static func fallbackCategory(
        isExpense: Bool,
        sortOrder: Int
    ) -> CategoryItem {
        CategoryItem(
            name: isExpense ? "Other" : "Salary",
            iconKey: isExpense ? "square.grid.2x2.fill" : "banknote.fill",
            colorHex: isExpense ? "#5A6B6B" : "#57C98C",
            isIncome: !isExpense,
            sortOrder: sortOrder,
            isDefault: true
        )
    }
}

enum SeedDataService {
    @MainActor
    static func ensureSeedData(modelContext: ModelContext, currencyCode: String) {
        DataIntegrityService.repair(modelContext: modelContext, currencyCode: currencyCode)
    }
}

enum DataIntegrityService {
    @MainActor
    static func repair(modelContext: ModelContext, currencyCode: String) {
        let now = Date()
        let categories = (try? modelContext.fetch(FetchDescriptor<CategoryItem>())) ?? []
        ensureDefaultCategories(
            existingCategories: categories,
            modelContext: modelContext
        )

        let accounts = (try? modelContext.fetch(FetchDescriptor<AccountItem>())) ?? []
        _ = DefaultAccountResolver.resolve(
            preferredID: nil,
            accounts: accounts,
            modelContext: modelContext,
            currencyCode: currencyCode
        )

        let budgets = (try? modelContext.fetch(FetchDescriptor<BudgetPeriodItem>())) ?? []
        if budgets.isEmpty {
            modelContext.insert(BudgetPeriodItem(currencyCode: currencyCode))
        } else if budgets.allSatisfy({ !$0.isActive }), let first = budgets.first {
            first.isActive = true
            first.updatedAt = now
        }

        repairAmountsAndDates(modelContext: modelContext, now: now)
        try? modelContext.save()
    }

    @MainActor
    private static func ensureDefaultCategories(
        existingCategories: [CategoryItem],
        modelContext: ModelContext
    ) {
        for (index, item) in SeedData.defaultCategories.enumerated() {
            let exists = existingCategories.contains {
                $0.name.localizedCaseInsensitiveCompare(item.0) == .orderedSame
                    && $0.isIncome == item.3
            }

            guard !exists else { continue }
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

    @MainActor
    private static func repairAmountsAndDates(modelContext: ModelContext, now: Date) {
        let transactions = (try? modelContext.fetch(FetchDescriptor<TransactionItem>())) ?? []
        for transaction in transactions {
            transaction.amountMinor = normalizedMoney(transaction.amountMinor)
            if transaction.updatedAt < transaction.createdAt {
                transaction.updatedAt = transaction.createdAt
            }
        }

        let recurringRules = (try? modelContext.fetch(FetchDescriptor<RecurringRuleItem>())) ?? []
        for rule in recurringRules {
            rule.amountMinor = normalizedMoney(rule.amountMinor)
            rule.intervalCount = max(1, rule.intervalCount)
            if rule.updatedAt < rule.createdAt {
                rule.updatedAt = rule.createdAt
            }
            if let endDate = rule.endDate, endDate < rule.nextRunDate {
                rule.active = false
                rule.updatedAt = now
            }
        }

        let goals = (try? modelContext.fetch(FetchDescriptor<GoalItem>())) ?? []
        for goal in goals {
            goal.targetMinor = normalizedMoney(goal.targetMinor)
            goal.savedMinor = normalizedMoney(goal.savedMinor)
            goal.achieved = goal.savedMinor >= goal.targetMinor && goal.targetMinor > 0
            if goal.updatedAt < goal.createdAt {
                goal.updatedAt = goal.createdAt
            }
        }

        let budgets = (try? modelContext.fetch(FetchDescriptor<BudgetPeriodItem>())) ?? []
        for budget in budgets {
            budget.expectedIncomeMinor = normalizedMoney(budget.expectedIncomeMinor)
            if budget.updatedAt < budget.createdAt {
                budget.updatedAt = budget.createdAt
            }
        }

        let categoryBudgets = (try? modelContext.fetch(FetchDescriptor<CategoryBudgetItem>())) ?? []
        for budget in categoryBudgets {
            budget.amountMinor = normalizedMoney(budget.amountMinor)
            if budget.updatedAt < budget.createdAt {
                budget.updatedAt = budget.createdAt
            }
        }
    }

    private static func normalizedMoney(_ value: Int64) -> Int64 {
        if value == Int64.min { return Int64.max }
        return abs(value)
    }
}
