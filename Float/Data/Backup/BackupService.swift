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
        customFlows: [CustomFlowItem],
        customFlowObjectTypes: [CustomFlowObjectTypeItem],
        customFlowFields: [CustomFlowFieldItem],
        customFlowRelations: [CustomFlowRelationItem],
        customFlowRecords: [CustomFlowRecordItem],
        customFlowFieldValues: [CustomFlowFieldValueItem],
        customFlowTransactionActions: [CustomFlowTransactionActionItem],
        customFlowTransactionLinks: [CustomFlowTransactionLinkItem],
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
        receiptCaptures: [ReceiptCaptureItem],
        receiptLineItems: [ReceiptLineItem],
        attachments: [AttachmentItem],
        householdMembers: [HouseholdMemberItem],
        householdExpenses: [HouseholdExpenseItem],
        householdExpenseSplits: [HouseholdExpenseSplitItem],
        householdBills: [HouseholdBillItem],
        householdAllowances: [HouseholdAllowanceItem],
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
            customFlows: customFlows.map(CustomFlowDTO.init),
            customFlowObjectTypes: customFlowObjectTypes.map(CustomFlowObjectTypeDTO.init),
            customFlowFields: customFlowFields.map(CustomFlowFieldDTO.init),
            customFlowRelations: customFlowRelations.map(CustomFlowRelationDTO.init),
            customFlowRecords: customFlowRecords.map(CustomFlowRecordDTO.init),
            customFlowFieldValues: customFlowFieldValues.map(CustomFlowFieldValueDTO.init),
            customFlowTransactionActions: customFlowTransactionActions.map(CustomFlowTransactionActionDTO.init),
            customFlowTransactionLinks: customFlowTransactionLinks.map(CustomFlowTransactionLinkDTO.init),
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
            receiptCaptures: receiptCaptures.map(ReceiptCaptureDTO.init),
            receiptLineItems: receiptLineItems.map(ReceiptLineDTO.init),
            attachments: attachments.map(AttachmentDTO.init),
            householdMembers: householdMembers.map(HouseholdMemberDTO.init),
            householdExpenses: householdExpenses.map(HouseholdExpenseDTO.init),
            householdExpenseSplits: householdExpenseSplits.map(HouseholdExpenseSplitDTO.init),
            householdBills: householdBills.map(HouseholdBillDTO.init),
            householdAllowances: householdAllowances.map(HouseholdAllowanceDTO.init),
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

        var customFlowMap: [UUID: CustomFlowItem] = [:]
        for item in dto.customFlows {
            let flow = CustomFlowItem(dto: item)
            customFlowMap[item.id] = flow
            modelContext.insert(flow)
        }

        var customObjectMap: [UUID: CustomFlowObjectTypeItem] = [:]
        for item in dto.customFlowObjectTypes {
            let objectType = CustomFlowObjectTypeItem(
                dto: item,
                flow: item.flowID.flatMap { customFlowMap[$0] }
            )
            customObjectMap[item.id] = objectType
            modelContext.insert(objectType)
            objectType.flow?.objectTypes.append(objectType)
        }

        var customRelationMap: [UUID: CustomFlowRelationItem] = [:]
        for item in dto.customFlowRelations {
            let relation = CustomFlowRelationItem(
                dto: item,
                flow: item.flowID.flatMap { customFlowMap[$0] },
                sourceObjectType: item.sourceObjectTypeID.flatMap { customObjectMap[$0] },
                targetObjectType: item.targetObjectTypeID.flatMap { customObjectMap[$0] }
            )
            customRelationMap[item.id] = relation
            modelContext.insert(relation)
            relation.flow?.relations.append(relation)
        }

        var customFieldMap: [UUID: CustomFlowFieldItem] = [:]
        for item in dto.customFlowFields {
            let field = CustomFlowFieldItem(
                dto: item,
                objectType: item.objectTypeID.flatMap { customObjectMap[$0] },
                relation: item.relationID.flatMap { customRelationMap[$0] }
            )
            customFieldMap[item.id] = field
            modelContext.insert(field)
            field.objectType?.fields.append(field)
        }

        var customRecordMap: [UUID: CustomFlowRecordItem] = [:]
        for item in dto.customFlowRecords {
            let record = CustomFlowRecordItem(
                dto: item,
                objectType: item.objectTypeID.flatMap { customObjectMap[$0] }
            )
            customRecordMap[item.id] = record
            modelContext.insert(record)
            record.objectType?.records.append(record)
        }
        for item in dto.customFlowRecords {
            guard let record = customRecordMap[item.id] else { continue }
            record.parentRecord = item.parentRecordID.flatMap { customRecordMap[$0] }
            record.parentRelation = item.parentRelationID.flatMap { customRelationMap[$0] }
        }

        for item in dto.customFlowFieldValues {
            let value = CustomFlowFieldValueItem(
                dto: item,
                record: item.recordID.flatMap { customRecordMap[$0] },
                field: item.fieldID.flatMap { customFieldMap[$0] },
                relatedRecord: item.relatedRecordID.flatMap { customRecordMap[$0] },
                category: item.categoryID.flatMap { categoryMap[$0] },
                account: item.accountID.flatMap { accountMap[$0] },
                person: item.personID.flatMap { personMap[$0] }
            )
            modelContext.insert(value)
            value.record?.values.append(value)
        }

        var customActionMap: [UUID: CustomFlowTransactionActionItem] = [:]
        for item in dto.customFlowTransactionActions {
            let action = CustomFlowTransactionActionItem(
                dto: item,
                flow: item.flowID.flatMap { customFlowMap[$0] },
                sourceObjectType: item.sourceObjectTypeID.flatMap { customObjectMap[$0] },
                amountField: item.amountFieldID.flatMap { customFieldMap[$0] },
                categoryField: item.categoryFieldID.flatMap { customFieldMap[$0] },
                accountField: item.accountFieldID.flatMap { customFieldMap[$0] },
                dateField: item.dateFieldID.flatMap { customFieldMap[$0] },
                noteField: item.noteFieldID.flatMap { customFieldMap[$0] },
                fixedCategory: item.fixedCategoryID.flatMap { categoryMap[$0] },
                fixedAccount: item.fixedAccountID.flatMap { accountMap[$0] }
            )
            customActionMap[item.id] = action
            modelContext.insert(action)
            action.flow?.transactionActions.append(action)
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

        var receiptMap: [UUID: ReceiptCaptureItem] = [:]
        for item in dto.receiptCaptures {
            let model = ReceiptCaptureItem(dto: item)
            receiptMap[item.id] = model
            modelContext.insert(model)
        }

        var householdMemberMap: [UUID: HouseholdMemberItem] = [:]
        for item in dto.householdMembers {
            let model = HouseholdMemberItem(
                dto: item,
                person: item.personID.flatMap { personMap[$0] }
            )
            householdMemberMap[item.id] = model
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
                },
                receiptCapture: item.receiptCaptureID.flatMap { receiptMap[$0] }
            )
            transactionMap[item.id] = model
            modelContext.insert(model)
        }

        for item in dto.customFlowTransactionLinks {
            let link = CustomFlowTransactionLinkItem(
                dto: item,
                record: item.recordID.flatMap { customRecordMap[$0] },
                action: item.actionID.flatMap { customActionMap[$0] },
                transaction: item.transactionID.flatMap { transactionMap[$0] }
            )
            modelContext.insert(link)
            link.record?.transactionLinks.append(link)
            link.action?.links.append(link)
        }

        var householdExpenseMap: [UUID: HouseholdExpenseItem] = [:]
        for item in dto.householdExpenses {
            let expense = HouseholdExpenseItem(
                dto: item,
                payer: item.payerID.flatMap { householdMemberMap[$0] },
                category: item.categoryID.flatMap { categoryMap[$0] },
                account: item.accountID.flatMap { accountMap[$0] },
                transaction: item.transactionID.flatMap { transactionMap[$0] },
                receiptCapture: item.receiptCaptureID.flatMap { receiptMap[$0] }
            )
            householdExpenseMap[item.id] = expense
            modelContext.insert(expense)
        }

        for item in dto.householdExpenseSplits {
            guard let expense = item.expenseID.flatMap({ householdExpenseMap[$0] }) else {
                continue
            }
            let split = HouseholdExpenseSplitItem(
                dto: item,
                member: item.memberID.flatMap { householdMemberMap[$0] },
                expense: expense
            )
            modelContext.insert(split)
            expense.splits.append(split)
        }

        for item in dto.householdBills {
            modelContext.insert(
                HouseholdBillItem(
                    dto: item,
                    payer: item.payerID.flatMap { householdMemberMap[$0] },
                    category: item.categoryID.flatMap { categoryMap[$0] },
                    account: item.accountID.flatMap { accountMap[$0] }
                )
            )
        }

        for item in dto.householdAllowances {
            modelContext.insert(
                HouseholdAllowanceItem(
                    dto: item,
                    member: item.memberID.flatMap { householdMemberMap[$0] }
                )
            )
        }

        for item in dto.receiptLineItems {
            guard let receipt = item.receiptID.flatMap({ receiptMap[$0] }) else {
                continue
            }
            let line = ReceiptLineItem(
                dto: item,
                receipt: receipt,
                category: item.categoryID.flatMap { categoryMap[$0] },
                account: item.accountID.flatMap { accountMap[$0] },
                transaction: item.transactionID.flatMap { transactionMap[$0] }
            )
            modelContext.insert(line)
            receipt.lineItems.append(line)
        }

        for item in dto.attachments {
            guard let receipt = item.receiptID.flatMap({ receiptMap[$0] }) else {
                continue
            }
            let attachment = AttachmentItem(dto: item, receipt: receipt)
            modelContext.insert(attachment)
            receipt.attachments.append(attachment)
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
            try modelContext.delete(model: CustomFlowTransactionLinkItem.self)
            try modelContext.delete(model: CustomFlowFieldValueItem.self)
            try modelContext.delete(model: CustomFlowRecordItem.self)
            try modelContext.delete(model: CustomFlowTransactionActionItem.self)
            try modelContext.delete(model: CustomFlowFieldItem.self)
            try modelContext.delete(model: CustomFlowRelationItem.self)
            try modelContext.delete(model: CustomFlowObjectTypeItem.self)
            try modelContext.delete(model: CustomFlowItem.self)
            try modelContext.delete(model: SettlementMilestoneItem.self)
            try modelContext.delete(model: SettlementEntryItem.self)
            try modelContext.delete(model: SettlementCaseItem.self)
            try modelContext.delete(model: HouseholdAllowanceItem.self)
            try modelContext.delete(model: HouseholdExpenseSplitItem.self)
            try modelContext.delete(model: HouseholdExpenseItem.self)
            try modelContext.delete(model: HouseholdBillItem.self)
            try modelContext.delete(model: HouseholdMemberItem.self)
            try modelContext.delete(model: AttachmentItem.self)
            try modelContext.delete(model: ReceiptLineItem.self)
            try modelContext.delete(model: ReceiptCaptureItem.self)
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
            try modelContext.delete(model: BudgetCycleCategoryItem.self)
            try modelContext.delete(model: BudgetCycleItem.self)
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
            receiptCaptureID: item.receiptCapture?.id,
            dismissedReviewKindsRaw: item.dismissedReviewKindsRaw,
            dismissedDuplicateGroupSignatureRaw: item.dismissedDuplicateGroupSignatureRaw,
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
        recurringRule: RecurringRuleItem? = nil,
        receiptCapture: ReceiptCaptureItem? = nil
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
            receiptCapture: receiptCapture,
            dismissedReviewKindsRaw: dto.dismissedReviewKindsRaw,
            dismissedDuplicateGroupSignatureRaw: dto.dismissedDuplicateGroupSignatureRaw,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt
        )
    }
}

private extension ReceiptCaptureDTO {
    init(_ item: ReceiptCaptureItem) {
        self.init(
            id: item.id,
            merchantName: item.merchantName,
            transactionDate: item.transactionDate,
            totalAmountMinor: item.totalAmountMinor,
            currencyCode: item.currencyCode,
            rawText: item.rawText,
            createdAt: item.createdAt,
            updatedAt: item.updatedAt
        )
    }
}

private extension ReceiptCaptureItem {
    convenience init(dto: ReceiptCaptureDTO) {
        self.init(
            id: dto.id,
            merchantName: dto.merchantName,
            transactionDate: dto.transactionDate,
            totalAmountMinor: dto.totalAmountMinor,
            currencyCode: dto.currencyCode,
            rawText: dto.rawText,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt
        )
    }
}

private extension ReceiptLineDTO {
    init(_ item: ReceiptLineItem) {
        self.init(
            id: item.id,
            sortOrder: item.sortOrder,
            title: item.title,
            quantityText: item.quantityText,
            amountMinor: item.amountMinor,
            selectedForImport: item.selectedForImport,
            receiptID: item.receipt?.id,
            categoryID: item.category?.id,
            accountID: item.account?.id,
            transactionID: item.transaction?.id,
            duplicateTransactionID: item.duplicateTransactionID,
            createdAt: item.createdAt,
            updatedAt: item.updatedAt
        )
    }
}

private extension ReceiptLineItem {
    convenience init(
        dto: ReceiptLineDTO,
        receipt: ReceiptCaptureItem? = nil,
        category: CategoryItem? = nil,
        account: AccountItem? = nil,
        transaction: TransactionItem? = nil
    ) {
        self.init(
            id: dto.id,
            sortOrder: dto.sortOrder,
            title: dto.title,
            quantityText: dto.quantityText,
            amountMinor: dto.amountMinor,
            selectedForImport: dto.selectedForImport,
            receipt: receipt,
            category: category,
            account: account,
            transaction: transaction,
            duplicateTransactionID: dto.duplicateTransactionID,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt
        )
    }
}

private extension AttachmentDTO {
    init(_ item: AttachmentItem) {
        self.init(
            id: item.id,
            kindRaw: item.kindRaw,
            fileName: item.fileName,
            mimeType: item.mimeType,
            data: item.data,
            receiptID: item.receipt?.id,
            createdAt: item.createdAt,
            updatedAt: item.updatedAt
        )
    }
}

private extension AttachmentItem {
    convenience init(dto: AttachmentDTO, receipt: ReceiptCaptureItem? = nil) {
        self.init(
            id: dto.id,
            kind: AttachmentKind(rawValue: dto.kindRaw) ?? .receiptImage,
            fileName: dto.fileName,
            mimeType: dto.mimeType,
            data: dto.data,
            receipt: receipt,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt
        )
    }
}

private extension HouseholdMemberDTO {
    init(_ item: HouseholdMemberItem) {
        self.init(
            id: item.id,
            displayName: item.displayName,
            roleRaw: item.roleRaw,
            colorHex: item.colorHex,
            monthlyAllowanceMinor: item.monthlyAllowanceMinor,
            personID: item.person?.id,
            archived: item.archived,
            createdAt: item.createdAt,
            updatedAt: item.updatedAt
        )
    }
}

private extension HouseholdMemberItem {
    convenience init(dto: HouseholdMemberDTO, person: PersonItem? = nil) {
        self.init(
            id: dto.id,
            displayName: dto.displayName,
            role: HouseholdMemberRole(rawValue: dto.roleRaw) ?? .adult,
            colorHex: dto.colorHex,
            monthlyAllowanceMinor: dto.monthlyAllowanceMinor,
            person: person,
            archived: dto.archived,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt
        )
    }
}

private extension HouseholdExpenseDTO {
    init(_ item: HouseholdExpenseItem) {
        self.init(
            id: item.id,
            title: item.title,
            amountMinor: item.amountMinor,
            currencyCode: item.currencyCode,
            expenseDate: item.expenseDate,
            splitMethodRaw: item.splitMethodRaw,
            approvalStatusRaw: item.approvalStatusRaw,
            reimbursementRequired: item.reimbursementRequired,
            note: item.note,
            payerID: item.payer?.id,
            categoryID: item.category?.id,
            accountID: item.account?.id,
            transactionID: item.transaction?.id,
            receiptCaptureID: item.receiptCapture?.id,
            approvedAt: item.approvedAt,
            rejectedAt: item.rejectedAt,
            settledAt: item.settledAt,
            createdAt: item.createdAt,
            updatedAt: item.updatedAt
        )
    }
}

private extension HouseholdExpenseItem {
    convenience init(
        dto: HouseholdExpenseDTO,
        payer: HouseholdMemberItem? = nil,
        category: CategoryItem? = nil,
        account: AccountItem? = nil,
        transaction: TransactionItem? = nil,
        receiptCapture: ReceiptCaptureItem? = nil
    ) {
        self.init(
            id: dto.id,
            title: dto.title,
            amountMinor: dto.amountMinor,
            currencyCode: dto.currencyCode,
            expenseDate: dto.expenseDate,
            splitMethod: HouseholdSplitMethod(rawValue: dto.splitMethodRaw) ?? .equal,
            approvalStatus: HouseholdApprovalStatus(rawValue: dto.approvalStatusRaw) ?? .pending,
            reimbursementRequired: dto.reimbursementRequired,
            note: dto.note,
            payer: payer,
            category: category,
            account: account,
            transaction: transaction,
            receiptCapture: receiptCapture,
            approvedAt: dto.approvedAt,
            rejectedAt: dto.rejectedAt,
            settledAt: dto.settledAt,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt
        )
    }
}

private extension HouseholdExpenseSplitDTO {
    init(_ item: HouseholdExpenseSplitItem) {
        self.init(
            id: item.id,
            sortOrder: item.sortOrder,
            amountMinor: item.amountMinor,
            reimbursedMinor: item.reimbursedMinor,
            memberID: item.member?.id,
            expenseID: item.expense?.id,
            createdAt: item.createdAt,
            updatedAt: item.updatedAt
        )
    }
}

private extension HouseholdExpenseSplitItem {
    convenience init(
        dto: HouseholdExpenseSplitDTO,
        member: HouseholdMemberItem? = nil,
        expense: HouseholdExpenseItem? = nil
    ) {
        self.init(
            id: dto.id,
            sortOrder: dto.sortOrder,
            amountMinor: dto.amountMinor,
            reimbursedMinor: dto.reimbursedMinor,
            member: member,
            expense: expense,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt
        )
    }
}

private extension HouseholdBillDTO {
    init(_ item: HouseholdBillItem) {
        self.init(
            id: item.id,
            title: item.title,
            amountMinor: item.amountMinor,
            currencyCode: item.currencyCode,
            dueDate: item.dueDate,
            cadence: item.cadence,
            payerID: item.payer?.id,
            categoryID: item.category?.id,
            accountID: item.account?.id,
            active: item.active,
            autoCreateApproval: item.autoCreateApproval,
            note: item.note,
            createdAt: item.createdAt,
            updatedAt: item.updatedAt
        )
    }
}

private extension HouseholdBillItem {
    convenience init(
        dto: HouseholdBillDTO,
        payer: HouseholdMemberItem? = nil,
        category: CategoryItem? = nil,
        account: AccountItem? = nil
    ) {
        self.init(
            id: dto.id,
            title: dto.title,
            amountMinor: dto.amountMinor,
            currencyCode: dto.currencyCode,
            dueDate: dto.dueDate,
            cadence: dto.cadence,
            payer: payer,
            category: category,
            account: account,
            active: dto.active,
            autoCreateApproval: dto.autoCreateApproval,
            note: dto.note,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt
        )
    }
}

private extension HouseholdAllowanceDTO {
    init(_ item: HouseholdAllowanceItem) {
        self.init(
            id: item.id,
            memberID: item.member?.id,
            periodStart: item.periodStart,
            periodEnd: item.periodEnd,
            allowanceMinor: item.allowanceMinor,
            spentMinor: item.spentMinor,
            currencyCode: item.currencyCode,
            note: item.note,
            createdAt: item.createdAt,
            updatedAt: item.updatedAt
        )
    }
}

private extension HouseholdAllowanceItem {
    convenience init(dto: HouseholdAllowanceDTO, member: HouseholdMemberItem? = nil) {
        self.init(
            id: dto.id,
            member: member,
            periodStart: dto.periodStart,
            periodEnd: dto.periodEnd,
            allowanceMinor: dto.allowanceMinor,
            spentMinor: dto.spentMinor,
            currencyCode: dto.currencyCode,
            note: dto.note,
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

private extension CustomFlowDTO {
    init(_ item: CustomFlowItem) {
        self.init(
            id: item.id,
            name: item.name,
            iconKey: item.iconKey,
            colorHex: item.colorHex,
            sortOrder: item.sortOrder,
            archived: item.archived,
            starterIdentifier: item.starterIdentifier,
            createdAt: item.createdAt,
            updatedAt: item.updatedAt
        )
    }
}

private extension CustomFlowObjectTypeDTO {
    init(_ item: CustomFlowObjectTypeItem) {
        self.init(
            id: item.id,
            flowID: item.flow?.id,
            name: item.name,
            singularName: item.singularName,
            iconKey: item.iconKey,
            sortOrder: item.sortOrder,
            archived: item.archived,
            hiddenInFlow: item.hiddenInFlow,
            createdAt: item.createdAt,
            updatedAt: item.updatedAt
        )
    }
}

private extension CustomFlowFieldDTO {
    init(_ item: CustomFlowFieldItem) {
        self.init(
            id: item.id,
            objectTypeID: item.objectType?.id,
            relationID: item.relation?.id,
            name: item.name,
            key: item.key,
            kindRaw: item.kindRaw,
            sortOrder: item.sortOrder,
            required: item.required,
            archived: item.archived,
            choiceOptionsRaw: item.choiceOptionsRaw,
            defaultValueRaw: item.defaultValueRaw,
            formulaDefinitionRaw: item.formulaDefinitionRaw,
            createdAt: item.createdAt,
            updatedAt: item.updatedAt
        )
    }
}

private extension CustomFlowRelationDTO {
    init(_ item: CustomFlowRelationItem) {
        self.init(
            id: item.id,
            flowID: item.flow?.id,
            sourceObjectTypeID: item.sourceObjectType?.id,
            targetObjectTypeID: item.targetObjectType?.id,
            name: item.name,
            kindRaw: item.kindRaw,
            sortOrder: item.sortOrder,
            archived: item.archived,
            createdAt: item.createdAt,
            updatedAt: item.updatedAt
        )
    }
}

private extension CustomFlowRecordDTO {
    init(_ item: CustomFlowRecordItem) {
        self.init(
            id: item.id,
            objectTypeID: item.objectType?.id,
            parentRecordID: item.parentRecord?.id,
            parentRelationID: item.parentRelation?.id,
            title: item.title,
            statusRaw: item.statusRaw,
            sortOrder: item.sortOrder,
            createdAt: item.createdAt,
            updatedAt: item.updatedAt,
            finalizedAt: item.finalizedAt
        )
    }
}

private extension CustomFlowFieldValueDTO {
    init(_ item: CustomFlowFieldValueItem) {
        self.init(
            id: item.id,
            recordID: item.record?.id,
            fieldID: item.field?.id,
            relatedRecordID: item.relatedRecord?.id,
            categoryID: item.category?.id,
            accountID: item.account?.id,
            personID: item.person?.id,
            valueRaw: item.valueRaw,
            numberValue: item.numberValue,
            amountMinor: item.amountMinor,
            dateValue: item.dateValue,
            boolValue: item.boolValue,
            createdAt: item.createdAt,
            updatedAt: item.updatedAt
        )
    }
}

private extension CustomFlowTransactionActionDTO {
    init(_ item: CustomFlowTransactionActionItem) {
        self.init(
            id: item.id,
            flowID: item.flow?.id,
            sourceObjectTypeID: item.sourceObjectType?.id,
            amountFieldID: item.amountField?.id,
            categoryFieldID: item.categoryField?.id,
            accountFieldID: item.accountField?.id,
            dateFieldID: item.dateField?.id,
            noteFieldID: item.noteField?.id,
            fixedCategoryID: item.fixedCategory?.id,
            fixedAccountID: item.fixedAccount?.id,
            fixedAmountMinor: item.fixedAmountMinor,
            fixedDate: item.fixedDate,
            name: item.name,
            triggerRaw: item.triggerRaw,
            isExpense: item.isExpense,
            active: item.active,
            fixedNote: item.fixedNote,
            createdAt: item.createdAt,
            updatedAt: item.updatedAt
        )
    }
}

private extension CustomFlowTransactionLinkDTO {
    init(_ item: CustomFlowTransactionLinkItem) {
        self.init(
            id: item.id,
            recordID: item.record?.id,
            actionID: item.action?.id,
            transactionID: item.transaction?.id,
            lastSyncedSnapshotRaw: item.lastSyncedSnapshotRaw,
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

private extension CustomFlowItem {
    convenience init(dto: CustomFlowDTO) {
        self.init(
            id: dto.id,
            name: dto.name,
            iconKey: dto.iconKey,
            colorHex: dto.colorHex,
            sortOrder: dto.sortOrder,
            archived: dto.archived,
            starterIdentifier: dto.starterIdentifier,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt
        )
    }
}

private extension CustomFlowObjectTypeItem {
    convenience init(
        dto: CustomFlowObjectTypeDTO,
        flow: CustomFlowItem?
    ) {
        self.init(
            id: dto.id,
            name: dto.name,
            singularName: dto.singularName,
            iconKey: dto.iconKey,
            sortOrder: dto.sortOrder,
            archived: dto.archived,
            hiddenInFlow: dto.hiddenInFlow ?? false,
            flow: flow,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt
        )
    }
}

private extension CustomFlowRelationItem {
    convenience init(
        dto: CustomFlowRelationDTO,
        flow: CustomFlowItem?,
        sourceObjectType: CustomFlowObjectTypeItem?,
        targetObjectType: CustomFlowObjectTypeItem?
    ) {
        self.init(
            id: dto.id,
            name: dto.name,
            kind: CustomFlowRelationKind(rawValue: dto.kindRaw) ?? .hasMany,
            sortOrder: dto.sortOrder,
            archived: dto.archived,
            flow: flow,
            sourceObjectType: sourceObjectType,
            targetObjectType: targetObjectType,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt
        )
    }
}

private extension CustomFlowFieldItem {
    convenience init(
        dto: CustomFlowFieldDTO,
        objectType: CustomFlowObjectTypeItem?,
        relation: CustomFlowRelationItem?
    ) {
        self.init(
            id: dto.id,
            name: dto.name,
            key: dto.key,
            kind: CustomFlowFieldKind(rawValue: dto.kindRaw) ?? .text,
            sortOrder: dto.sortOrder,
            required: dto.required,
            archived: dto.archived,
            choiceOptionsRaw: dto.choiceOptionsRaw,
            defaultValueRaw: dto.defaultValueRaw,
            formulaDefinitionRaw: dto.formulaDefinitionRaw,
            objectType: objectType,
            relation: relation,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt
        )
    }
}

private extension CustomFlowRecordItem {
    convenience init(
        dto: CustomFlowRecordDTO,
        objectType: CustomFlowObjectTypeItem?
    ) {
        self.init(
            id: dto.id,
            title: dto.title,
            status: CustomFlowRecordStatus(rawValue: dto.statusRaw) ?? .draft,
            sortOrder: dto.sortOrder,
            objectType: objectType,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt,
            finalizedAt: dto.finalizedAt
        )
    }
}

private extension CustomFlowFieldValueItem {
    convenience init(
        dto: CustomFlowFieldValueDTO,
        record: CustomFlowRecordItem?,
        field: CustomFlowFieldItem?,
        relatedRecord: CustomFlowRecordItem?,
        category: CategoryItem?,
        account: AccountItem?,
        person: PersonItem?
    ) {
        self.init(
            id: dto.id,
            record: record,
            field: field,
            valueRaw: dto.valueRaw,
            numberValue: dto.numberValue,
            amountMinor: dto.amountMinor,
            dateValue: dto.dateValue,
            boolValue: dto.boolValue,
            relatedRecord: relatedRecord,
            category: category,
            account: account,
            person: person,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt
        )
    }
}

private extension CustomFlowTransactionActionItem {
    convenience init(
        dto: CustomFlowTransactionActionDTO,
        flow: CustomFlowItem?,
        sourceObjectType: CustomFlowObjectTypeItem?,
        amountField: CustomFlowFieldItem?,
        categoryField: CustomFlowFieldItem?,
        accountField: CustomFlowFieldItem?,
        dateField: CustomFlowFieldItem?,
        noteField: CustomFlowFieldItem?,
        fixedCategory: CategoryItem?,
        fixedAccount: AccountItem?
    ) {
        self.init(
            id: dto.id,
            name: dto.name,
            trigger: CustomFlowTransactionActionTrigger(rawValue: dto.triggerRaw) ?? .finalize,
            isExpense: dto.isExpense,
            active: dto.active,
            flow: flow,
            sourceObjectType: sourceObjectType,
            amountField: amountField,
            categoryField: categoryField,
            accountField: accountField,
            dateField: dateField,
            noteField: noteField,
            fixedAmountMinor: dto.fixedAmountMinor,
            fixedDate: dto.fixedDate,
            fixedCategory: fixedCategory,
            fixedAccount: fixedAccount,
            fixedNote: dto.fixedNote,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt
        )
    }
}

private extension CustomFlowTransactionLinkItem {
    convenience init(
        dto: CustomFlowTransactionLinkDTO,
        record: CustomFlowRecordItem?,
        action: CustomFlowTransactionActionItem?,
        transaction: TransactionItem?
    ) {
        self.init(
            id: dto.id,
            record: record,
            action: action,
            transaction: transaction,
            lastSyncedSnapshotRaw: dto.lastSyncedSnapshotRaw,
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
