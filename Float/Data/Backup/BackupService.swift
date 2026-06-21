import Foundation
import SwiftData

@MainActor
enum BackupService {
    static func createDocument(
        accounts: [AccountItem],
        categories: [CategoryItem],
        people: [PersonItem],
        eventCategories: [EventCategoryItem],
        events: [EventItem],
        transactions: [TransactionItem],
        transactionPersonTags: [TransactionPersonTagItem],
        transactionTemplates: [TransactionTemplateItem],
        transactionTemplateGroups: [TransactionTemplateGroupItem],
        transfers: [TransferItem],
        goals: [GoalItem],
        recurringRules: [RecurringRuleItem],
        recurringRulePersonTags: [RecurringRulePersonTagItem],
        budgets: [BudgetPeriodItem],
        categoryBudgets: [CategoryBudgetItem],
        scenarioPlans: [ScenarioPlanItem],
        settlementCases: [SettlementCaseItem],
        settlementEntries: [SettlementEntryItem],
        settlementMilestones: [SettlementMilestoneItem],
        currencyCode: String
    ) throws -> BackupDocument {
        let dto = FloatBackupDTO(
            accounts: accounts.map(AccountDTO.init),
            categories: categories.map(CategoryDTO.init),
            people: people.map(PersonDTO.init),
            eventCategories: eventCategories.map(EventCategoryDTO.init),
            events: events.map(EventDTO.init),
            transactions: transactions.map(TransactionDTO.init),
            transactionPersonTags: transactionPersonTags.map(TransactionPersonTagDTO.init),
            transactionTemplates: transactionTemplates.map(TransactionTemplateDTO.init),
            transactionTemplateGroups: transactionTemplateGroups.map(TransactionTemplateGroupDTO.init),
            transfers: transfers.map(TransferDTO.init),
            goals: goals.map(GoalDTO.init),
            recurringRules: recurringRules.map(RecurringRuleDTO.init),
            recurringRulePersonTags: recurringRulePersonTags.map(RecurringRulePersonTagDTO.init),
            budgets: budgets.map(BudgetDTO.init),
            categoryBudgets: categoryBudgets.map(CategoryBudgetDTO.init),
            scenarioPlans: scenarioPlans.map(ScenarioPlanDTO.init),
            settlementCases: settlementCases.map(SettlementCaseDTO.init),
            settlementEntries: settlementEntries.map(SettlementEntryDTO.init),
            settlementMilestones: settlementMilestones.map(SettlementMilestoneDTO.init),
            settings: SettingsDTO(
                currencyCode: currencyCode,
                exportedAt: Date()
            )
        )
        return try BackupArchiveService.document(from: dto)
    }

    static func restore(
        document: BackupDocument,
        modelContext: ModelContext,
        profileID: UUID? = ActiveProfileRegistry.profileID
    ) throws -> String {
        let dto = try BackupArchiveService.dto(from: document)
        try deleteExistingData(in: modelContext, profileID: profileID)

        var categoryMap: [UUID: CategoryItem] = [:]
        var personMap: [UUID: PersonItem] = [:]
        var eventCategoryMap: [UUID: EventCategoryItem] = [:]
        var eventMap: [UUID: EventItem] = [:]
        var accountMap: [UUID: AccountItem] = [:]

        for item in dto.categories {
            let model = CategoryItem(dto: item)
            categoryMap[item.id] = model
            modelContext.insert(model)
        }

        for item in dto.people {
            let model = PersonItem(dto: item)
            personMap[item.id] = model
            modelContext.insert(model)
        }

        for item in dto.eventCategories {
            let model = EventCategoryItem(dto: item)
            eventCategoryMap[item.id] = model
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

        for item in dto.scenarioPlans {
            modelContext.insert(
                ScenarioPlanItem(
                    dto: item,
                    category: item.categoryID.flatMap { categoryMap[$0] },
                    account: item.accountID.flatMap { accountMap[$0] }
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

        for item in dto.events {
            let model = EventItem(
                dto: item,
                category: item.categoryID.flatMap { eventCategoryMap[$0] }
            )
            eventMap[item.id] = model
            modelContext.insert(model)
        }

        var transactionMap: [UUID: TransactionItem] = [:]
        for item in dto.transactions {
            let model = TransactionItem(
                dto: item,
                category: item.categoryID.flatMap { categoryMap[$0] },
                account: item.accountID.flatMap { accountMap[$0] },
                event: item.eventID.flatMap { eventMap[$0] },
                recurringRule: item.recurringRuleID.flatMap {
                    recurringMap[$0]
                }
            )
            transactionMap[item.id] = model
            modelContext.insert(model)
        }

        var settlementCaseMap: [UUID: SettlementCaseItem] = [:]
        for item in dto.settlementCases {
            let restoredPersonName = item.counterpartyName?.trimmedBackupNilIfBlank
                ?? item.personID.flatMap { personMap[$0]?.name.trimmedBackupNilIfBlank }
                ?? String(localized: "No person")
            let model = SettlementCaseItem(
                dto: item,
                counterpartyName: restoredPersonName,
                person: item.personID.flatMap { personMap[$0] }
            )
            settlementCaseMap[item.id] = model
            modelContext.insert(model)
        }

        var settlementEntryMap: [UUID: SettlementEntryItem] = [:]
        for item in dto.settlementEntries {
            guard let caseItem = item.caseID.flatMap({ settlementCaseMap[$0] }) else {
                continue
            }
            let entry = SettlementEntryItem(
                dto: item,
                caseItem: caseItem,
                linkedTransaction: item.linkedTransactionID.flatMap { transactionMap[$0] }
            )
            settlementEntryMap[item.id] = entry
            modelContext.insert(entry)
            caseItem.entries.append(entry)
        }

        for item in dto.settlementMilestones {
            guard let caseItem = item.caseID.flatMap({ settlementCaseMap[$0] }) else {
                continue
            }
            let milestone = SettlementMilestoneItem(
                dto: item,
                caseItem: caseItem,
                linkedEntry: item.linkedEntryID.flatMap { settlementEntryMap[$0] }
            )
            modelContext.insert(milestone)
            caseItem.milestones.append(milestone)
        }

        for item in dto.transactionPersonTags {
            guard
                let person = item.personID.flatMap({ personMap[$0] }),
                let transaction = item.transactionID.flatMap({ transactionMap[$0] })
            else { continue }
            let tag = TransactionPersonTagItem(
                id: item.id,
                sortOrder: item.sortOrder,
                allocatedMinor: item.allocatedMinor,
                settledMinor: item.settledMinor,
                person: person,
                transaction: transaction,
                createdAt: item.createdAt,
                updatedAt: item.updatedAt
            )
            modelContext.insert(tag)
        }

        for item in dto.recurringRulePersonTags {
            guard
                let person = item.personID.flatMap({ personMap[$0] }),
                let recurringRule = item.recurringRuleID.flatMap({ recurringMap[$0] })
            else { continue }
            let tag = RecurringRulePersonTagItem(
                id: item.id,
                sortOrder: item.sortOrder,
                person: person,
                recurringRule: recurringRule,
                createdAt: item.createdAt,
                updatedAt: item.updatedAt
            )
            modelContext.insert(tag)
        }

        do {
            try modelContext.save()
            return dto.settings.currencyCode
        } catch {
            throw DataIntegrityError.saveFailed
        }
    }

    private static func deleteExistingData(
        in modelContext: ModelContext,
        profileID: UUID?
    ) throws {
        guard let profileID else {
            try modelContext.delete(model: TransactionPersonTagItem.self)
            try modelContext.delete(model: RecurringRulePersonTagItem.self)
            try modelContext.delete(model: SettlementMilestoneItem.self)
            try modelContext.delete(model: SettlementEntryItem.self)
            try modelContext.delete(model: SettlementCaseItem.self)
            try modelContext.delete(model: TransactionItem.self)
            try modelContext.delete(model: EventItem.self)
            try modelContext.delete(model: EventCategoryItem.self)
            try modelContext.delete(model: TransactionTemplateGroupEntryItem.self)
            try modelContext.delete(model: TransactionTemplateGroupItem.self)
            try modelContext.delete(model: TransactionTemplateItem.self)
            try modelContext.delete(model: TransferItem.self)
            try modelContext.delete(model: RecurringRuleItem.self)
            try modelContext.delete(model: PersonItem.self)
            try modelContext.delete(model: GoalItem.self)
            try modelContext.delete(model: InsightSignalItem.self)
            try modelContext.delete(model: MerchantAliasItem.self)
            try modelContext.delete(model: ScenarioPlanItem.self)
            try modelContext.delete(model: CategoryBudgetItem.self)
            try modelContext.delete(model: BudgetPeriodItem.self)
            try modelContext.delete(model: CategoryItem.self)
            try modelContext.delete(model: AccountItem.self)
            return
        }
        try ProfileDataService.deleteData(profileID: profileID, modelContext: modelContext)
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

private extension PersonDTO {
    init(_ item: PersonItem) {
        self.init(
            id: item.id,
            name: item.name,
            alias: item.alias,
            note: item.note,
            colorHex: item.colorHex,
            archived: item.archived,
            transactionCount: item.transactionCount,
            recurringRuleCount: item.recurringRuleCount,
            createdAt: item.createdAt,
            updatedAt: item.updatedAt
        )
    }
}

private extension SettlementCaseDTO {
    init(_ item: SettlementCaseItem) {
        self.init(
            id: item.id,
            title: item.title,
            counterpartyName: item.counterpartyName.trimmedBackupNilIfBlank,
            directionRaw: item.directionRaw,
            currencyCode: item.currencyCode,
            note: item.note,
            personID: item.person?.id,
            dueDate: item.dueDate,
            closedAt: item.closedAt,
            archived: item.archived,
            createdAt: item.createdAt,
            updatedAt: item.updatedAt
        )
    }
}

private extension SettlementCaseItem {
    convenience init(
        dto: SettlementCaseDTO,
        counterpartyName: String,
        person: PersonItem? = nil
    ) {
        self.init(
            id: dto.id,
            title: dto.title,
            counterpartyName: counterpartyName,
            direction: SettlementDirection(rawValue: dto.directionRaw) ?? .theyOweYou,
            currencyCode: dto.currencyCode,
            note: dto.note,
            person: person,
            dueDate: dto.dueDate,
            closedAt: dto.closedAt,
            archived: dto.archived,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt
        )
    }
}

private extension SettlementEntryDTO {
    init(_ item: SettlementEntryItem) {
        self.init(
            id: item.id,
            kindRaw: item.kindRaw,
            amountMinor: item.amountMinor,
            entryDate: item.entryDate,
            note: item.note,
            reference: item.reference,
            caseID: item.caseItem?.id,
            linkedTransactionID: item.linkedTransaction?.id,
            createdAt: item.createdAt,
            updatedAt: item.updatedAt
        )
    }
}

private extension SettlementEntryItem {
    convenience init(
        dto: SettlementEntryDTO,
        caseItem: SettlementCaseItem? = nil,
        linkedTransaction: TransactionItem? = nil
    ) {
        self.init(
            id: dto.id,
            kind: SettlementEntryKind(rawValue: dto.kindRaw) ?? .addition,
            amountMinor: dto.amountMinor,
            entryDate: dto.entryDate,
            note: dto.note,
            reference: dto.reference,
            caseItem: caseItem,
            linkedTransaction: linkedTransaction,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt
        )
    }
}

private extension SettlementMilestoneDTO {
    init(_ item: SettlementMilestoneItem) {
        self.init(
            id: item.id,
            title: item.title,
            amountMinor: item.amountMinor,
            dueDate: item.dueDate,
            note: item.note,
            statusRaw: item.statusRaw,
            caseID: item.caseItem?.id,
            linkedEntryID: item.linkedEntry?.id,
            createdAt: item.createdAt,
            updatedAt: item.updatedAt
        )
    }
}

private extension SettlementMilestoneItem {
    convenience init(
        dto: SettlementMilestoneDTO,
        caseItem: SettlementCaseItem? = nil,
        linkedEntry: SettlementEntryItem? = nil
    ) {
        self.init(
            id: dto.id,
            title: dto.title,
            amountMinor: dto.amountMinor,
            dueDate: dto.dueDate,
            note: dto.note,
            status: SettlementMilestoneStatus(rawValue: dto.statusRaw) ?? .pending,
            caseItem: caseItem,
            linkedEntry: linkedEntry,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt
        )
    }
}

private extension EventCategoryDTO {
    init(_ item: EventCategoryItem) {
        self.init(
            id: item.id,
            name: item.name,
            iconKey: item.iconKey,
            colorHex: item.colorHex,
            sortOrder: item.sortOrder,
            createdAt: item.createdAt,
            updatedAt: item.updatedAt
        )
    }
}

private extension EventCategoryItem {
    convenience init(dto: EventCategoryDTO) {
        self.init(
            id: dto.id,
            name: dto.name,
            iconKey: dto.iconKey,
            colorHex: dto.colorHex,
            sortOrder: dto.sortOrder,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt
        )
    }
}

private extension EventDTO {
    init(_ item: EventItem) {
        self.init(
            id: item.id,
            name: item.name,
            startDate: item.startDate,
            endDate: item.endDate,
            statusRaw: item.statusRaw,
            eventDescription: item.eventDescription,
            pinned: item.pinned,
            categoryID: item.category?.id,
            createdAt: item.createdAt,
            updatedAt: item.updatedAt
        )
    }
}

private extension EventItem {
    convenience init(
        dto: EventDTO,
        category: EventCategoryItem? = nil
    ) {
        self.init(
            id: dto.id,
            name: dto.name,
            startDate: dto.startDate,
            endDate: dto.endDate,
            status: EventStatus(rawValue: dto.statusRaw) ?? .active,
            eventDescription: dto.eventDescription,
            pinned: dto.pinned,
            category: category,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt
        )
    }
}

private extension TransactionDTO {
    init(_ item: TransactionItem) {
        self.init(
            id: item.id,
            amountMinor: item.amountMinor,
            isExpense: item.isExpense,
            statusRaw: item.statusRaw,
            timestamp: item.timestamp,
            expectedDueDate: item.expectedDueDate,
            categoryID: item.category?.id,
            accountID: item.account?.id,
            eventID: item.event?.id,
            note: item.note,
            recurringRuleID: item.recurringRule?.id,
            createdAt: item.createdAt,
            updatedAt: item.updatedAt
        )
    }
}

private extension TransactionPersonTagDTO {
    init(_ item: TransactionPersonTagItem) {
        self.init(
            id: item.id,
            sortOrder: item.sortOrder,
            allocatedMinor: item.allocatedMinor,
            settledMinor: item.settledMinor,
            personID: item.person?.id,
            transactionID: item.transaction?.id,
            createdAt: item.createdAt,
            updatedAt: item.updatedAt
        )
    }
}

private extension TransactionItem {
    convenience init(
        dto: TransactionDTO,
        category: CategoryItem? = nil,
        account: AccountItem? = nil,
        event: EventItem? = nil,
        recurringRule: RecurringRuleItem? = nil
    ) {
        self.init(
            id: dto.id,
            amountMinor: dto.amountMinor,
            isExpense: dto.isExpense,
            status: TransactionStatus(rawValue: dto.statusRaw) ?? .posted,
            timestamp: dto.timestamp,
            expectedDueDate: dto.expectedDueDate,
            category: category,
            account: account,
            event: event,
            note: dto.note,
            recurringRule: recurringRule,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt
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

private extension RecurringRulePersonTagDTO {
    init(_ item: RecurringRulePersonTagItem) {
        self.init(
            id: item.id,
            sortOrder: item.sortOrder,
            personID: item.person?.id,
            recurringRuleID: item.recurringRule?.id,
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

private extension ScenarioPlanDTO {
    init(_ item: ScenarioPlanItem) {
        self.init(
            id: item.id,
            title: item.title,
            amountMinor: item.amountMinor,
            isExpense: item.isExpense,
            plannedDate: item.plannedDate,
            recurrenceRaw: item.recurrenceRaw,
            occurrenceCount: item.occurrenceCount,
            categoryID: item.category?.id,
            accountID: item.account?.id,
            note: item.note,
            archived: item.archived,
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

private extension PersonItem {
    convenience init(dto: PersonDTO) {
        self.init(
            id: dto.id,
            name: dto.name,
            alias: dto.alias,
            note: dto.note,
            colorHex: dto.colorHex,
            archived: dto.archived,
            transactionCount: dto.transactionCount,
            recurringRuleCount: dto.recurringRuleCount,
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

private extension ScenarioPlanItem {
    convenience init(
        dto: ScenarioPlanDTO,
        category: CategoryItem?,
        account: AccountItem?
    ) {
        self.init(
            id: dto.id,
            title: dto.title,
            amountMinor: dto.amountMinor,
            isExpense: dto.isExpense,
            plannedDate: dto.plannedDate,
            recurrence: ScenarioRecurrence(rawValue: dto.recurrenceRaw) ?? .none,
            occurrenceCount: dto.occurrenceCount,
            category: category,
            account: account,
            note: dto.note,
            archived: dto.archived,
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

private extension TransactionPersonTagItem {
    convenience init(
        dto: TransactionPersonTagDTO,
        person: PersonItem?,
        transaction: TransactionItem?
    ) {
        self.init(
            id: dto.id,
            sortOrder: dto.sortOrder,
            allocatedMinor: dto.allocatedMinor,
            settledMinor: dto.settledMinor,
            person: person,
            transaction: transaction,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt
        )
    }
}

private extension RecurringRulePersonTagItem {
    convenience init(
        dto: RecurringRulePersonTagDTO,
        person: PersonItem?,
        recurringRule: RecurringRuleItem?
    ) {
        self.init(
            id: dto.id,
            sortOrder: dto.sortOrder,
            person: person,
            recurringRule: recurringRule,
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
            status: TransactionStatus(rawValue: dto.statusRaw) ?? .posted,
            timestamp: dto.timestamp,
            expectedDueDate: dto.expectedDueDate,
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

private extension String {
    var trimmedBackupNilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension Optional where Wrapped == String {
    var trimmedBackupNilIfBlank: String? {
        flatMap(\.trimmedBackupNilIfBlank)
    }
}
