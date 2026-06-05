import Foundation
import SwiftData

struct TransactionDraft {
    let amountMinor: Int64
    let isExpense: Bool
    let timestamp: Date
    let category: CategoryItem
    let account: AccountItem
    let note: String?
}

struct PendingTransactionDraft {
    let amountMinor: Int64
    let expectedDueDate: Date
    let note: String?
}

@MainActor
struct TransactionRepository {
    let modelContext: ModelContext

    func create(
        amountMinor: Int64,
        isExpense: Bool,
        timestamp: Date,
        category: CategoryItem,
        account: AccountItem,
        note: String?
    ) throws -> TransactionItem {
        let transaction = TransactionItem(
            amountMinor: amountMinor,
            isExpense: isExpense,
            timestamp: timestamp,
            category: category,
            account: account,
            note: note?.trimmedNilIfBlank
        )
        modelContext.insert(transaction)
        try save()
        return transaction
    }

    func createPending(
        amountMinor: Int64,
        expectedDueDate: Date,
        note: String?
    ) throws -> TransactionItem {
        let transaction = TransactionItem(
            amountMinor: amountMinor,
            isExpense: true,
            status: .pending,
            timestamp: Date(),
            expectedDueDate: expectedDueDate,
            category: nil,
            account: nil,
            note: note?.trimmedNilIfBlank
        )
        modelContext.insert(transaction)
        try save()
        return transaction
    }

    func createMany(from templates: [TransactionTemplateItem], timestamp: Date) throws
        -> Int
    {
        let validTemplates = templates.filter {
            $0.amountMinor > 0 && $0.category != nil && $0.account != nil
        }
        guard !validTemplates.isEmpty else { return 0 }

        for template in validTemplates {
            modelContext.insert(
                TransactionItem(
                    amountMinor: template.amountMinor,
                    isExpense: template.isExpense,
                    timestamp: timestamp,
                    category: template.category,
                    account: template.account,
                    note: template.note
                )
            )
        }
        try save()
        return validTemplates.count
    }

    func createMany(from drafts: [TransactionDraft]) throws -> Int {
        let validDrafts = drafts.filter { $0.amountMinor > 0 }
        guard !validDrafts.isEmpty else { return 0 }

        for draft in validDrafts {
            modelContext.insert(
                TransactionItem(
                    amountMinor: draft.amountMinor,
                    isExpense: draft.isExpense,
                    timestamp: draft.timestamp,
                    category: draft.category,
                    account: draft.account,
                    note: draft.note?.trimmedNilIfBlank
                )
            )
        }
        try save()
        return validDrafts.count
    }

    func createManyPending(from drafts: [PendingTransactionDraft]) throws -> Int {
        let validDrafts = drafts.filter { $0.amountMinor > 0 }
        guard !validDrafts.isEmpty else { return 0 }

        for draft in validDrafts {
            modelContext.insert(
                TransactionItem(
                    amountMinor: draft.amountMinor,
                    isExpense: true,
                    status: .pending,
                    timestamp: Date(),
                    expectedDueDate: draft.expectedDueDate,
                    category: nil,
                    account: nil,
                    note: draft.note?.trimmedNilIfBlank
                )
            )
        }
        try save()
        return validDrafts.count
    }

    func replace(_ transaction: TransactionItem, with drafts: [TransactionDraft]) throws
        -> Int
    {
        let validDrafts = drafts.filter { $0.amountMinor > 0 }
        guard !validDrafts.isEmpty, validDrafts.count == drafts.count else {
            return 0
        }

        for draft in validDrafts {
            modelContext.insert(
                TransactionItem(
                    amountMinor: draft.amountMinor,
                    isExpense: draft.isExpense,
                    timestamp: draft.timestamp,
                    category: draft.category,
                    account: draft.account,
                    note: draft.note?.trimmedNilIfBlank
                )
            )
        }
        modelContext.delete(transaction)
        try save()
        return validDrafts.count
    }

    func update(
        _ transaction: TransactionItem,
        amountMinor: Int64,
        isExpense: Bool,
        timestamp: Date,
        category: CategoryItem,
        account: AccountItem,
        note: String?
    ) throws {
        transaction.apply(
            amountMinor: amountMinor,
            isExpense: isExpense,
            status: .posted,
            timestamp: timestamp,
            expectedDueDate: nil,
            category: category,
            account: account,
            note: note
        )
        try save()
    }

    func updatePending(
        _ transaction: TransactionItem,
        amountMinor: Int64,
        expectedDueDate: Date,
        note: String?
    ) throws {
        transaction.apply(
            amountMinor: amountMinor,
            isExpense: transaction.isExpense,
            status: .pending,
            timestamp: transaction.timestamp,
            expectedDueDate: expectedDueDate,
            category: nil,
            account: nil,
            note: note
        )
        try save()
    }

    func delete(_ transaction: TransactionItem) throws {
        modelContext.delete(transaction)
        try save()
    }

    func fetchAll() throws -> [TransactionItem] {
        var descriptor = FetchDescriptor<TransactionItem>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.includePendingChanges = true
        return try modelContext.fetch(descriptor)
    }

    private func save() throws {
        do {
            try modelContext.save()
        } catch {
            throw DataIntegrityError.saveFailed
        }
    }
}

@MainActor
struct TransactionTemplateRepository {
    let modelContext: ModelContext

    func create(
        title: String,
        amountMinor: Int64,
        isExpense: Bool,
        category: CategoryItem,
        account: AccountItem,
        note: String?
    ) throws -> TransactionTemplateItem {
        let template = TransactionTemplateItem(
            title: title.trimmedNilIfBlank ?? category.name,
            amountMinor: amountMinor,
            isExpense: isExpense,
            category: category,
            account: account,
            note: note?.trimmedNilIfBlank
        )
        modelContext.insert(template)
        try save()
        return template
    }

    func update(
        _ template: TransactionTemplateItem,
        title: String,
        amountMinor: Int64,
        isExpense: Bool,
        category: CategoryItem,
        account: AccountItem,
        note: String?
    ) throws {
        template.title = title.trimmedNilIfBlank ?? category.name
        template.amountMinor = max(0, amountMinor)
        template.isExpense = isExpense
        template.category = category
        template.account = account
        template.note = note?.trimmedNilIfBlank
        template.updatedAt = Date()
        try save()
    }

    func delete(_ template: TransactionTemplateItem) throws {
        modelContext.delete(template)
        try save()
    }

    private func save() throws {
        do {
            try modelContext.save()
        } catch {
            throw DataIntegrityError.saveFailed
        }
    }
}

@MainActor
struct TransactionTemplateGroupRepository {
    let modelContext: ModelContext

    func create(name: String, templates: [TransactionTemplateItem]) throws
        -> TransactionTemplateGroupItem
    {
        let group = TransactionTemplateGroupItem(
            name: name.trimmedNilIfBlank ?? "Group"
        )
        modelContext.insert(group)
        apply(templates: templates, to: group)
        try save()
        return group
    }

    func update(
        _ group: TransactionTemplateGroupItem,
        name: String,
        templates: [TransactionTemplateItem]
    ) throws {
        group.name = name.trimmedNilIfBlank ?? "Group"
        group.updatedAt = Date()
        for entry in group.entries {
            modelContext.delete(entry)
        }
        group.entries = []
        apply(templates: templates, to: group)
        try save()
    }

    func delete(_ group: TransactionTemplateGroupItem) throws {
        modelContext.delete(group)
        try save()
    }

    private func apply(
        templates: [TransactionTemplateItem],
        to group: TransactionTemplateGroupItem
    ) {
        for (index, template) in templates.enumerated() {
            let entry = TransactionTemplateGroupEntryItem(
                sortOrder: index,
                group: group,
                template: template
            )
            modelContext.insert(entry)
            group.entries.append(entry)
        }
    }

    private func save() throws {
        do {
            try modelContext.save()
        } catch {
            throw DataIntegrityError.saveFailed
        }
    }
}

@MainActor
struct TransferRepository {
    let modelContext: ModelContext

    func create(
        amountMinor: Int64,
        fromAccount: AccountItem,
        toAccount: AccountItem,
        timestamp: Date,
        note: String?
    ) throws -> TransferItem {
        let transfer = TransferItem(
            amountMinor: amountMinor,
            fromAccount: fromAccount,
            toAccount: toAccount,
            timestamp: timestamp,
            note: note?.trimmedNilIfBlank
        )
        modelContext.insert(transfer)
        try save()
        return transfer
    }

    func update(
        _ transfer: TransferItem,
        amountMinor: Int64,
        fromAccount: AccountItem,
        toAccount: AccountItem,
        timestamp: Date,
        note: String?
    ) throws {
        transfer.apply(
            amountMinor: amountMinor,
            fromAccount: fromAccount,
            toAccount: toAccount,
            timestamp: timestamp,
            note: note
        )
        try save()
    }

    func delete(_ transfer: TransferItem) throws {
        modelContext.delete(transfer)
        try save()
    }

    private func save() throws {
        do {
            try modelContext.save()
        } catch {
            throw DataIntegrityError.saveFailed
        }
    }
}

@MainActor
struct CategoryRepository {
    let modelContext: ModelContext

    func fetchAll() throws -> [CategoryItem] {
        try modelContext.fetch(
            FetchDescriptor<CategoryItem>(
                sortBy: [SortDescriptor(\.sortOrder)]
            )
        )
    }

    func archive(_ category: CategoryItem) throws {
        category.archive()
        try save()
    }

    func deleteIfUnused(_ category: CategoryItem) throws {
        if isCategoryInUse(category) {
            category.archive()
        } else {
            modelContext.delete(category)
        }
        try save()
    }

    private func save() throws {
        do {
            try modelContext.save()
        } catch {
            throw DataIntegrityError.saveFailed
        }
    }

    private func isCategoryInUse(_ category: CategoryItem) -> Bool {
        let transactions = (try? modelContext.fetch(FetchDescriptor<TransactionItem>())) ?? []
        if transactions.contains(where: { $0.category?.id == category.id }) {
            return true
        }

        let rules = (try? modelContext.fetch(FetchDescriptor<RecurringRuleItem>())) ?? []
        if rules.contains(where: { $0.category?.id == category.id }) {
            return true
        }

        let budgets = (try? modelContext.fetch(FetchDescriptor<CategoryBudgetItem>())) ?? []
        return budgets.contains { $0.category?.id == category.id }
    }
}

@MainActor
struct AccountRepository {
    let modelContext: ModelContext

    func fetchAll() throws -> [AccountItem] {
        try modelContext.fetch(
            FetchDescriptor<AccountItem>(
                sortBy: [SortDescriptor(\.createdAt)]
            )
        )
    }

    func archive(_ account: AccountItem) throws {
        account.archive()
        try save()
    }

    func deleteIfUnused(_ account: AccountItem) throws {
        if isAccountInUse(account) {
            account.archive()
        } else {
            modelContext.delete(account)
        }
        try save()
    }

    private func save() throws {
        do {
            try modelContext.save()
        } catch {
            throw DataIntegrityError.saveFailed
        }
    }

    private func isAccountInUse(_ account: AccountItem) -> Bool {
        let transactions = (try? modelContext.fetch(FetchDescriptor<TransactionItem>())) ?? []
        if transactions.contains(where: { $0.account?.id == account.id }) {
            return true
        }

        let transfers = (try? modelContext.fetch(FetchDescriptor<TransferItem>())) ?? []
        if transfers.contains(where: {
            $0.fromAccount?.id == account.id || $0.toAccount?.id == account.id
        }) {
            return true
        }

        let rules = (try? modelContext.fetch(FetchDescriptor<RecurringRuleItem>())) ?? []
        return rules.contains { $0.account?.id == account.id }
    }
}

@MainActor
struct GoalRepository {
    let modelContext: ModelContext

    func create(
        name: String,
        targetMinor: Int64,
        savedMinor: Int64,
        targetDate: Date?,
        colorHex: String
    ) throws -> GoalItem {
        let goal = GoalItem(
            name: name,
            targetMinor: targetMinor,
            savedMinor: savedMinor,
            targetDate: targetDate,
            colorHex: colorHex,
            achieved: savedMinor >= targetMinor && targetMinor > 0
        )
        modelContext.insert(goal)
        try save()
        return goal
    }

    func update(
        _ goal: GoalItem,
        name: String,
        targetMinor: Int64,
        savedMinor: Int64,
        targetDate: Date?,
        colorHex: String
    ) throws {
        goal.name = name
        goal.targetMinor = max(0, targetMinor)
        goal.savedMinor = max(0, savedMinor)
        goal.targetDate = targetDate
        goal.colorHex = colorHex
        goal.achieved = goal.savedMinor >= goal.targetMinor && goal.targetMinor > 0
        goal.updatedAt = Date()
        try save()
    }

    func addContribution(_ amountMinor: Int64, to goal: GoalItem) throws {
        goal.savedMinor = max(0, goal.savedMinor + max(0, amountMinor))
        goal.achieved = goal.savedMinor >= goal.targetMinor && goal.targetMinor > 0
        goal.updatedAt = Date()
        try save()
    }

    func reduceContribution(_ amountMinor: Int64, from goal: GoalItem) throws {
        goal.savedMinor = max(0, goal.savedMinor - max(0, amountMinor))
        goal.achieved = goal.savedMinor >= goal.targetMinor && goal.targetMinor > 0
        goal.updatedAt = Date()
        try save()
    }

    func fetchAll() throws -> [GoalItem] {
        try modelContext.fetch(FetchDescriptor<GoalItem>())
    }

    func delete(_ goal: GoalItem) throws {
        modelContext.delete(goal)
        try save()
    }

    private func save() throws {
        do {
            try modelContext.save()
        } catch {
            throw DataIntegrityError.saveFailed
        }
    }
}

@MainActor
struct RecurringRepository {
    let modelContext: ModelContext

    func create(
        amountMinor: Int64,
        isExpense: Bool,
        category: CategoryItem,
        account: AccountItem,
        note: String?,
        cadence: RecurringCadence,
        intervalCount: Int,
        nextRunDate: Date,
        endDate: Date?
    ) throws -> RecurringRuleItem {
        let rule = RecurringRuleItem(
            amountMinor: amountMinor,
            isExpense: isExpense,
            category: category,
            account: account,
            note: note?.trimmedNilIfBlank,
            cadence: cadence,
            intervalCount: intervalCount,
            nextRunDate: nextRunDate,
            endDate: endDate
        )
        modelContext.insert(rule)
        try save()
        return rule
    }

    func update(
        _ rule: RecurringRuleItem,
        amountMinor: Int64,
        isExpense: Bool,
        category: CategoryItem,
        account: AccountItem,
        note: String?,
        cadence: RecurringCadence,
        intervalCount: Int,
        nextRunDate: Date,
        endDate: Date?,
        active: Bool
    ) throws {
        rule.amountMinor = max(0, amountMinor)
        rule.isExpense = isExpense
        rule.category = category
        rule.account = account
        rule.note = note?.trimmedNilIfBlank
        rule.cadence = cadence
        rule.intervalCount = max(1, intervalCount)
        rule.nextRunDate = nextRunDate
        rule.endDate = endDate
        rule.active = active
        rule.updatedAt = Date()
        try save()
    }

    func fetchAll() throws -> [RecurringRuleItem] {
        try modelContext.fetch(FetchDescriptor<RecurringRuleItem>())
    }

    func deactivate(_ rule: RecurringRuleItem) throws {
        rule.active = false
        rule.updatedAt = Date()
        try save()
    }

    func delete(_ rule: RecurringRuleItem) throws {
        modelContext.delete(rule)
        try save()
    }

    private func save() throws {
        do {
            try modelContext.save()
        } catch {
            throw DataIntegrityError.saveFailed
        }
    }
}

@MainActor
struct BudgetPeriodRepository {
    let modelContext: ModelContext

    func activeBudget(from budgets: [BudgetPeriodItem]) -> BudgetPeriodItem? {
        budgets.first { $0.isActive } ?? budgets.first
    }

    func saveActiveBudget(
        _ budget: BudgetPeriodItem,
        among budgets: [BudgetPeriodItem],
        expectedIncomeMinor: Int64,
        currencyCode: String
    ) throws {
        if budget.modelContext == nil {
            modelContext.insert(budget)
        }

        for item in budgets where item.id != budget.id {
            item.isActive = false
            item.updatedAt = Date()
        }

        budget.expectedIncomeMinor = max(0, expectedIncomeMinor)
        budget.currencyCode = currencyCode
        budget.isActive = true
        budget.updatedAt = Date()
        try save()
    }

    private func save() throws {
        do {
            try modelContext.save()
        } catch {
            throw DataIntegrityError.saveFailed
        }
    }
}

@MainActor
struct CategoryBudgetRepository {
    let modelContext: ModelContext

    func save(
        category: CategoryItem,
        amountMinor: Int64,
        currencyCode: String,
        existingBudgets: [CategoryBudgetItem]
    ) throws {
        if let existing = existingBudgets.first(where: { $0.category?.id == category.id }) {
            if amountMinor > 0 {
                existing.amountMinor = amountMinor
                existing.currencyCode = currencyCode
                existing.isActive = true
                existing.updatedAt = Date()
            } else {
                modelContext.delete(existing)
            }
        } else if amountMinor > 0 {
            modelContext.insert(
                CategoryBudgetItem(
                    category: category,
                    amountMinor: amountMinor,
                    currencyCode: currencyCode
                )
            )
        }
        try save()
    }

    private func save() throws {
        do {
            try modelContext.save()
        } catch {
            throw DataIntegrityError.saveFailed
        }
    }
}

@MainActor
struct SettingsRepository {
    let modelContext: ModelContext

    func resetAllData(currencyCode: String) throws {
        try modelContext.delete(model: TransactionItem.self)
        try modelContext.delete(model: TransactionTemplateItem.self)
        try modelContext.delete(model: TransferItem.self)
        try modelContext.delete(model: RecurringRuleItem.self)
        try modelContext.delete(model: GoalItem.self)
        try modelContext.delete(model: CategoryBudgetItem.self)
        try modelContext.delete(model: BudgetPeriodItem.self)
        try modelContext.delete(model: CategoryItem.self)
        try modelContext.delete(model: AccountItem.self)
        SeedDataService.ensureSeedData(
            modelContext: modelContext,
            currencyCode: currencyCode
        )
        do {
            try modelContext.save()
        } catch {
            throw DataIntegrityError.saveFailed
        }
    }
}

private extension String {
    var trimmedNilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
