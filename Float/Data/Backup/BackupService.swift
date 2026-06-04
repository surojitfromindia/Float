import Foundation
import SwiftData

@MainActor
enum BackupService {
    static func createDocument(
        accounts: [AccountItem],
        categories: [CategoryItem],
        transactions: [TransactionItem],
        transactionTemplates: [TransactionTemplateItem],
        transactionTemplateGroups: [TransactionTemplateGroupItem],
        transfers: [TransferItem],
        goals: [GoalItem],
        recurringRules: [RecurringRuleItem],
        budgets: [BudgetPeriodItem],
        categoryBudgets: [CategoryBudgetItem],
        currencyCode: String
    ) throws -> BackupDocument {
        let dto = FloatBackupDTO(
            accounts: accounts.map(AccountDTO.init),
            categories: categories.map(CategoryDTO.init),
            transactions: transactions.map(TransactionDTO.init),
            transactionTemplates: transactionTemplates.map(TransactionTemplateDTO.init),
            transactionTemplateGroups: transactionTemplateGroups.map(TransactionTemplateGroupDTO.init),
            transfers: transfers.map(TransferDTO.init),
            goals: goals.map(GoalDTO.init),
            recurringRules: recurringRules.map(RecurringRuleDTO.init),
            budgets: budgets.map(BudgetDTO.init),
            categoryBudgets: categoryBudgets.map(CategoryBudgetDTO.init),
            settings: SettingsDTO(
                currencyCode: currencyCode,
                exportedAt: Date()
            )
        )
        return try BackupArchiveService.document(from: dto)
    }

    static func restore(
        document: BackupDocument,
        modelContext: ModelContext
    ) throws -> String {
        let dto = try BackupArchiveService.dto(from: document)
        try deleteExistingData(in: modelContext)

        var categoryMap: [UUID: CategoryItem] = [:]
        var accountMap: [UUID: AccountItem] = [:]

        for item in dto.categories {
            let model = CategoryItem(dto: item)
            categoryMap[item.id] = model
            modelContext.insert(model)
        }

        for item in dto.accounts {
            let model = AccountItem(dto: item)
            accountMap[item.id] = model
            modelContext.insert(model)
        }

        for item in dto.goals {
            modelContext.insert(GoalItem(dto: item))
        }

        for item in dto.budgets {
            modelContext.insert(BudgetPeriodItem(dto: item))
        }

        for item in dto.categoryBudgets {
            modelContext.insert(
                CategoryBudgetItem(
                    dto: item,
                    category: item.categoryID.flatMap { categoryMap[$0] }
                )
            )
        }

        var templateMap: [UUID: TransactionTemplateItem] = [:]
        for item in dto.transactionTemplates {
            let template = TransactionTemplateItem(
                dto: item,
                category: item.categoryID.flatMap { categoryMap[$0] },
                account: item.accountID.flatMap { accountMap[$0] }
            )
            templateMap[item.id] = template
            modelContext.insert(template)
        }

        for item in dto.transactionTemplateGroups {
            let group = TransactionTemplateGroupItem(dto: item)
            modelContext.insert(group)
            for entryDTO in item.entries.sorted(by: { $0.sortOrder < $1.sortOrder }) {
                let entry = TransactionTemplateGroupEntryItem(
                    dto: entryDTO,
                    group: group,
                    template: entryDTO.templateID.flatMap { templateMap[$0] }
                )
                modelContext.insert(entry)
                group.entries.append(entry)
            }
        }

        for item in dto.transfers {
            modelContext.insert(
                TransferItem(
                    dto: item,
                    fromAccount: item.fromAccountID.flatMap { accountMap[$0] },
                    toAccount: item.toAccountID.flatMap { accountMap[$0] }
                )
            )
        }

        var recurringMap: [UUID: RecurringRuleItem] = [:]
        for item in dto.recurringRules {
            let model = RecurringRuleItem(
                dto: item,
                category: item.categoryID.flatMap { categoryMap[$0] },
                account: item.accountID.flatMap { accountMap[$0] }
            )
            recurringMap[item.id] = model
            modelContext.insert(model)
        }

        for item in dto.transactions {
            modelContext.insert(
                TransactionItem(
                    dto: item,
                    category: item.categoryID.flatMap { categoryMap[$0] },
                    account: item.accountID.flatMap { accountMap[$0] },
                    recurringRule: item.recurringRuleID.flatMap {
                        recurringMap[$0]
                    }
                )
            )
        }

        do {
            try modelContext.save()
            return dto.settings.currencyCode
        } catch {
            throw DataIntegrityError.saveFailed
        }
    }

    private static func deleteExistingData(in modelContext: ModelContext) throws {
        try modelContext.delete(model: TransactionItem.self)
        try modelContext.delete(model: TransactionTemplateGroupEntryItem.self)
        try modelContext.delete(model: TransactionTemplateGroupItem.self)
        try modelContext.delete(model: TransactionTemplateItem.self)
        try modelContext.delete(model: TransferItem.self)
        try modelContext.delete(model: RecurringRuleItem.self)
        try modelContext.delete(model: GoalItem.self)
        try modelContext.delete(model: CategoryBudgetItem.self)
        try modelContext.delete(model: BudgetPeriodItem.self)
        try modelContext.delete(model: CategoryItem.self)
        try modelContext.delete(model: AccountItem.self)
    }
}

private extension AccountDTO {
    init(_ item: AccountItem) {
        self.init(
            id: item.id,
            name: item.name,
            type: item.type,
            openingBalanceMinor: item.openingBalanceMinor,
            currencyCode: item.currencyCode,
            archived: item.archived,
            createdAt: item.createdAt,
            updatedAt: item.updatedAt
        )
    }
}

private extension CategoryDTO {
    init(_ item: CategoryItem) {
        self.init(
            id: item.id,
            name: item.name,
            iconKey: item.iconKey,
            colorHex: item.colorHex,
            isIncome: item.isIncome,
            sortOrder: item.sortOrder,
            archived: item.archived,
            isDefault: item.isDefault,
            createdAt: item.createdAt,
            updatedAt: item.updatedAt
        )
    }
}

private extension TransactionDTO {
    init(_ item: TransactionItem) {
        self.init(
            id: item.id,
            amountMinor: item.amountMinor,
            isExpense: item.isExpense,
            timestamp: item.timestamp,
            categoryID: item.category?.id,
            accountID: item.account?.id,
            note: item.note,
            recurringRuleID: item.recurringRule?.id,
            createdAt: item.createdAt,
            updatedAt: item.updatedAt
        )
    }
}

private extension TransactionTemplateDTO {
    init(_ item: TransactionTemplateItem) {
        self.init(
            id: item.id,
            title: item.title,
            amountMinor: item.amountMinor,
            isExpense: item.isExpense,
            categoryID: item.category?.id,
            accountID: item.account?.id,
            note: item.note,
            createdAt: item.createdAt,
            updatedAt: item.updatedAt
        )
    }
}

@MainActor
private extension TransactionTemplateGroupDTO {
    init(_ item: TransactionTemplateGroupItem) {
        self.init(
            id: item.id,
            name: item.name,
            entries: item.sortedEntries.map(TransactionTemplateGroupEntryDTO.init),
            createdAt: item.createdAt,
            updatedAt: item.updatedAt
        )
    }
}

private extension TransactionTemplateGroupEntryDTO {
    init(_ item: TransactionTemplateGroupEntryItem) {
        self.init(
            id: item.id,
            templateID: item.template?.id,
            sortOrder: item.sortOrder,
            createdAt: item.createdAt,
            updatedAt: item.updatedAt
        )
    }
}

private extension TransferDTO {
    init(_ item: TransferItem) {
        self.init(
            id: item.id,
            amountMinor: item.amountMinor,
            fromAccountID: item.fromAccount?.id,
            toAccountID: item.toAccount?.id,
            timestamp: item.timestamp,
            note: item.note,
            createdAt: item.createdAt,
            updatedAt: item.updatedAt
        )
    }
}

private extension GoalDTO {
    init(_ item: GoalItem) {
        self.init(
            id: item.id,
            name: item.name,
            targetMinor: item.targetMinor,
            savedMinor: item.savedMinor,
            targetDate: item.targetDate,
            colorHex: item.colorHex,
            achieved: item.achieved,
            createdAt: item.createdAt,
            updatedAt: item.updatedAt
        )
    }
}

private extension RecurringRuleDTO {
    init(_ item: RecurringRuleItem) {
        self.init(
            id: item.id,
            amountMinor: item.amountMinor,
            isExpense: item.isExpense,
            categoryID: item.category?.id,
            accountID: item.account?.id,
            note: item.note,
            cadence: item.cadence,
            intervalCount: item.intervalCount,
            nextRunDate: item.nextRunDate,
            endDate: item.endDate,
            active: item.active,
            createdAt: item.createdAt,
            updatedAt: item.updatedAt
        )
    }
}

private extension BudgetDTO {
    init(_ item: BudgetPeriodItem) {
        self.init(
            id: item.id,
            cadence: item.cadence,
            startDayOfMonth: item.startDayOfMonth,
            startDayOfWeek: item.startDayOfWeek,
            expectedIncomeMinor: item.expectedIncomeMinor,
            currencyCode: item.currencyCode,
            isActive: item.isActive,
            createdAt: item.createdAt,
            updatedAt: item.updatedAt
        )
    }
}

private extension CategoryBudgetDTO {
    init(_ item: CategoryBudgetItem) {
        self.init(
            id: item.id,
            categoryID: item.category?.id,
            amountMinor: item.amountMinor,
            currencyCode: item.currencyCode,
            isActive: item.isActive,
            createdAt: item.createdAt,
            updatedAt: item.updatedAt
        )
    }
}

private extension AccountItem {
    convenience init(dto: AccountDTO) {
        self.init(
            id: dto.id,
            name: dto.name,
            type: dto.type,
            openingBalanceMinor: dto.openingBalanceMinor,
            currencyCode: dto.currencyCode,
            archived: dto.archived,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt
        )
    }
}

private extension CategoryItem {
    convenience init(dto: CategoryDTO) {
        self.init(
            id: dto.id,
            name: dto.name,
            iconKey: dto.iconKey,
            colorHex: dto.colorHex,
            isIncome: dto.isIncome,
            sortOrder: dto.sortOrder,
            archived: dto.archived,
            isDefault: dto.isDefault,
            createdAt: dto.createdAt ?? Date(),
            updatedAt: dto.updatedAt ?? dto.createdAt ?? Date()
        )
    }
}

private extension GoalItem {
    convenience init(dto: GoalDTO) {
        self.init(
            id: dto.id,
            name: dto.name,
            targetMinor: dto.targetMinor,
            savedMinor: dto.savedMinor,
            targetDate: dto.targetDate,
            colorHex: dto.colorHex,
            achieved: dto.achieved,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt
        )
    }
}

private extension BudgetPeriodItem {
    convenience init(dto: BudgetDTO) {
        self.init(
            id: dto.id,
            cadence: dto.cadence,
            startDayOfMonth: dto.startDayOfMonth,
            startDayOfWeek: dto.startDayOfWeek,
            expectedIncomeMinor: dto.expectedIncomeMinor,
            currencyCode: dto.currencyCode,
            isActive: dto.isActive,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt
        )
    }
}

private extension CategoryBudgetItem {
    convenience init(dto: CategoryBudgetDTO, category: CategoryItem?) {
        self.init(
            id: dto.id,
            category: category,
            amountMinor: dto.amountMinor,
            currencyCode: dto.currencyCode,
            isActive: dto.isActive,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt
        )
    }
}

private extension RecurringRuleItem {
    convenience init(
        dto: RecurringRuleDTO,
        category: CategoryItem?,
        account: AccountItem?
    ) {
        self.init(
            id: dto.id,
            amountMinor: dto.amountMinor,
            isExpense: dto.isExpense,
            category: category,
            account: account,
            note: dto.note,
            cadence: dto.cadence,
            intervalCount: dto.intervalCount,
            nextRunDate: dto.nextRunDate,
            endDate: dto.endDate,
            active: dto.active,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt
        )
    }
}

private extension TransactionItem {
    convenience init(
        dto: TransactionDTO,
        category: CategoryItem?,
        account: AccountItem?,
        recurringRule: RecurringRuleItem?
    ) {
        self.init(
            id: dto.id,
            amountMinor: dto.amountMinor,
            isExpense: dto.isExpense,
            timestamp: dto.timestamp,
            category: category,
            account: account,
            note: dto.note,
            recurringRule: recurringRule,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt
        )
    }
}

private extension TransactionTemplateItem {
    convenience init(
        dto: TransactionTemplateDTO,
        category: CategoryItem?,
        account: AccountItem?
    ) {
        self.init(
            id: dto.id,
            title: dto.title,
            amountMinor: dto.amountMinor,
            isExpense: dto.isExpense,
            category: category,
            account: account,
            note: dto.note,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt
        )
    }
}

private extension TransactionTemplateGroupItem {
    convenience init(dto: TransactionTemplateGroupDTO) {
        self.init(
            id: dto.id,
            name: dto.name,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt
        )
    }
}

private extension TransactionTemplateGroupEntryItem {
    convenience init(
        dto: TransactionTemplateGroupEntryDTO,
        group: TransactionTemplateGroupItem?,
        template: TransactionTemplateItem?
    ) {
        self.init(
            id: dto.id,
            sortOrder: dto.sortOrder,
            group: group,
            template: template,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt
        )
    }
}

private extension TransferItem {
    convenience init(
        dto: TransferDTO,
        fromAccount: AccountItem?,
        toAccount: AccountItem?
    ) {
        self.init(
            id: dto.id,
            amountMinor: dto.amountMinor,
            fromAccount: fromAccount,
            toAccount: toAccount,
            timestamp: dto.timestamp,
            note: dto.note,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt
        )
    }
}
