import Foundation
import SwiftData

struct ProfileDataCounts {
    var accounts = 0
    var categories = 0
    var people = 0
    var events = 0
    var transactions = 0
    var transfers = 0
    var recurringRules = 0
    var goals = 0
    var budgets = 0
    var settlements = 0
    var household = 0

    var total: Int {
        accounts + categories + people + events + transactions + transfers
            + recurringRules + goals + budgets + settlements + household
    }
}

@MainActor
enum ProfileDataService {
    static func ensureActiveProfile(
        modelContext: ModelContext,
        appState: AppState
    ) {
        let profiles = fetchProfiles(modelContext: modelContext)
        let selectedID = UUID(uuidString: appState.activeProfileID)
        let selectedProfile = selectedID.flatMap { id in
            profiles.first { $0.id == id && !$0.archived }
        }
        let profile = selectedProfile
            ?? profiles.first { $0.isDefault && !$0.archived }
            ?? profiles.first { !$0.archived }
            ?? createDefaultProfile(modelContext: modelContext, appState: appState)

        appState.applyProfile(profile)
        ActiveProfileRegistry.profileID = profile.id
        assignUnownedRecords(to: profile.id, modelContext: modelContext)
        SeedDataService.ensureSeedData(
            modelContext: modelContext,
            currencyCode: profile.currencyCode
        )
        try? modelContext.save()
    }

    static func createProfile(
        name: String,
        currencyCode: String,
        modelContext: ModelContext
    ) throws -> UserProfileItem {
        let profile = UserProfileItem(
            displayName: name,
            currencyCode: currencyCode,
            isDefault: fetchProfiles(modelContext: modelContext).isEmpty
        )
        modelContext.insert(profile)
        ActiveProfileRegistry.profileID = profile.id
        SeedDataService.ensureSeedData(
            modelContext: modelContext,
            currencyCode: currencyCode
        )
        try modelContext.save()
        return profile
    }

    static func updateProfile(
        _ profile: UserProfileItem,
        name: String,
        currencyCode: String
    ) throws {
        profile.displayName = name.trimmedNilIfBlank ?? String(localized: "Personal")
        profile.currencyCode = currencyCode
        profile.updatedAt = Date()
        try profile.modelContext?.save()
    }

    static func persistPreferences(
        from appState: AppState,
        modelContext: ModelContext
    ) {
        guard
            let id = UUID(uuidString: appState.activeProfileID),
            let profile = fetchProfile(id: id, modelContext: modelContext)
        else { return }
        appState.writePreferences(to: profile)
        try? modelContext.save()
    }

    static func counts(
        for profile: UserProfileItem,
        modelContext: ModelContext
    ) -> ProfileDataCounts {
        let id = profile.id
        return ProfileDataCounts(
            accounts: count(AccountItem.self, profileID: id, modelContext: modelContext),
            categories: count(CategoryItem.self, profileID: id, modelContext: modelContext),
            people: count(PersonItem.self, profileID: id, modelContext: modelContext),
            events: count(EventItem.self, profileID: id, modelContext: modelContext),
            transactions: count(TransactionItem.self, profileID: id, modelContext: modelContext),
            transfers: count(TransferItem.self, profileID: id, modelContext: modelContext),
            recurringRules: count(RecurringRuleItem.self, profileID: id, modelContext: modelContext),
            goals: count(GoalItem.self, profileID: id, modelContext: modelContext),
            budgets: count(BudgetPeriodItem.self, profileID: id, modelContext: modelContext)
                + count(CategoryBudgetItem.self, profileID: id, modelContext: modelContext)
                + count(BudgetCycleItem.self, profileID: id, modelContext: modelContext)
                + count(BudgetCycleCategoryItem.self, profileID: id, modelContext: modelContext),
            settlements: count(SettlementCaseItem.self, profileID: id, modelContext: modelContext),
            household: count(HouseholdMemberItem.self, profileID: id, modelContext: modelContext)
                + count(HouseholdExpenseItem.self, profileID: id, modelContext: modelContext)
                + count(HouseholdBillItem.self, profileID: id, modelContext: modelContext)
        )
    }

    static func deleteProfile(
        _ profile: UserProfileItem,
        modelContext: ModelContext
    ) throws {
        let activeProfiles = fetchProfiles(modelContext: modelContext)
            .filter { !$0.archived && $0.id != profile.id }
        guard !activeProfiles.isEmpty else {
            throw DataIntegrityError.invalidInput
        }
        let profileID = profile.id
        try deleteData(profileID: profileID, modelContext: modelContext)
        modelContext.delete(profile)
        try modelContext.save()
    }

    static func deleteData(
        profileID: UUID,
        modelContext: ModelContext
    ) throws {
        deleteMatching(TransactionPersonTagItem.self, profileID: profileID, modelContext: modelContext)
        deleteMatching(RecurringRulePersonTagItem.self, profileID: profileID, modelContext: modelContext)
        deleteMatching(SettlementMilestoneItem.self, profileID: profileID, modelContext: modelContext)
        deleteMatching(SettlementEntryItem.self, profileID: profileID, modelContext: modelContext)
        deleteMatching(SettlementCaseItem.self, profileID: profileID, modelContext: modelContext)
        deleteMatching(AttachmentItem.self, profileID: profileID, modelContext: modelContext)
        deleteMatching(ReceiptLineItem.self, profileID: profileID, modelContext: modelContext)
        deleteMatching(ReceiptCaptureItem.self, profileID: profileID, modelContext: modelContext)
        deleteMatching(HouseholdAllowanceItem.self, profileID: profileID, modelContext: modelContext)
        deleteMatching(HouseholdExpenseSplitItem.self, profileID: profileID, modelContext: modelContext)
        deleteMatching(HouseholdExpenseItem.self, profileID: profileID, modelContext: modelContext)
        deleteMatching(HouseholdBillItem.self, profileID: profileID, modelContext: modelContext)
        deleteMatching(HouseholdMemberItem.self, profileID: profileID, modelContext: modelContext)
        deleteMatching(TransactionItem.self, profileID: profileID, modelContext: modelContext)
        deleteMatching(EventItem.self, profileID: profileID, modelContext: modelContext)
        deleteMatching(EventCategoryItem.self, profileID: profileID, modelContext: modelContext)
        deleteMatching(TransactionTemplateGroupEntryItem.self, profileID: profileID, modelContext: modelContext)
        deleteMatching(TransactionTemplateGroupItem.self, profileID: profileID, modelContext: modelContext)
        deleteMatching(TransactionTemplateItem.self, profileID: profileID, modelContext: modelContext)
        deleteMatching(TransferItem.self, profileID: profileID, modelContext: modelContext)
        deleteMatching(RecurringRuleItem.self, profileID: profileID, modelContext: modelContext)
        deleteMatching(PersonItem.self, profileID: profileID, modelContext: modelContext)
        deleteMatching(GoalItem.self, profileID: profileID, modelContext: modelContext)
        deleteMatching(InsightSignalItem.self, profileID: profileID, modelContext: modelContext)
        deleteMatching(MerchantAliasItem.self, profileID: profileID, modelContext: modelContext)
        deleteMatching(ScenarioPlanItem.self, profileID: profileID, modelContext: modelContext)
        deleteMatching(BudgetCycleCategoryItem.self, profileID: profileID, modelContext: modelContext)
        deleteMatching(BudgetCycleItem.self, profileID: profileID, modelContext: modelContext)
        deleteMatching(CategoryBudgetItem.self, profileID: profileID, modelContext: modelContext)
        deleteMatching(BudgetPeriodItem.self, profileID: profileID, modelContext: modelContext)
        deleteMatching(CategoryItem.self, profileID: profileID, modelContext: modelContext)
        deleteMatching(AccountItem.self, profileID: profileID, modelContext: modelContext)
    }

    private static func createDefaultProfile(
        modelContext: ModelContext,
        appState: AppState
    ) -> UserProfileItem {
        let profile = UserProfileItem(
            displayName: String(localized: "Personal"),
            currencyCode: appState.selectedCurrencyCode,
            lastUsedCategoryID: appState.lastUsedCategoryID,
            lastUsedAccountID: appState.lastUsedAccountID,
            recurringRemindersEnabled: appState.recurringRemindersEnabled,
            budgetAlertsEnabled: appState.budgetAlertsEnabled,
            goalRemindersEnabled: appState.goalRemindersEnabled,
            settlementRemindersEnabled: appState.settlementRemindersEnabled,
            recurringReminderMinutes: appState.recurringReminderMinutes,
            goalReminderMinutes: appState.goalReminderMinutes,
            settlementReminderMinutes: appState.settlementReminderMinutes,
            budgetAlertSensitivityRaw: appState.budgetAlertSensitivityRaw,
            isDefault: true
        )
        modelContext.insert(profile)
        return profile
    }

    private static func fetchProfiles(modelContext: ModelContext) -> [UserProfileItem] {
        (try? modelContext.fetch(
            FetchDescriptor<UserProfileItem>(
                sortBy: [SortDescriptor(\.createdAt)]
            )
        )) ?? []
    }

    private static func fetchProfile(
        id: UUID,
        modelContext: ModelContext
    ) -> UserProfileItem? {
        let descriptor = FetchDescriptor<UserProfileItem>(
            predicate: #Predicate<UserProfileItem> { $0.id == id }
        )
        return try? modelContext.fetch(descriptor).first
    }

    private static func assignUnownedRecords(
        to profileID: UUID,
        modelContext: ModelContext
    ) {
        assign(AccountItem.self, profileID: profileID, modelContext: modelContext)
        assign(CategoryItem.self, profileID: profileID, modelContext: modelContext)
        assign(PersonItem.self, profileID: profileID, modelContext: modelContext)
        assign(EventCategoryItem.self, profileID: profileID, modelContext: modelContext)
        assign(EventItem.self, profileID: profileID, modelContext: modelContext)
        assign(TransactionItem.self, profileID: profileID, modelContext: modelContext)
        assign(TransactionPersonTagItem.self, profileID: profileID, modelContext: modelContext)
        assign(TransactionTemplateItem.self, profileID: profileID, modelContext: modelContext)
        assign(TransactionTemplateGroupItem.self, profileID: profileID, modelContext: modelContext)
        assign(TransactionTemplateGroupEntryItem.self, profileID: profileID, modelContext: modelContext)
        assign(TransferItem.self, profileID: profileID, modelContext: modelContext)
        assign(RecurringRuleItem.self, profileID: profileID, modelContext: modelContext)
        assign(RecurringRulePersonTagItem.self, profileID: profileID, modelContext: modelContext)
        assign(GoalItem.self, profileID: profileID, modelContext: modelContext)
        assign(InsightSignalItem.self, profileID: profileID, modelContext: modelContext)
        assign(MerchantAliasItem.self, profileID: profileID, modelContext: modelContext)
        assign(ScenarioPlanItem.self, profileID: profileID, modelContext: modelContext)
        assign(BudgetPeriodItem.self, profileID: profileID, modelContext: modelContext)
        assign(CategoryBudgetItem.self, profileID: profileID, modelContext: modelContext)
        assign(BudgetCycleItem.self, profileID: profileID, modelContext: modelContext)
        assign(BudgetCycleCategoryItem.self, profileID: profileID, modelContext: modelContext)
        assign(SettlementCaseItem.self, profileID: profileID, modelContext: modelContext)
        assign(SettlementEntryItem.self, profileID: profileID, modelContext: modelContext)
        assign(SettlementMilestoneItem.self, profileID: profileID, modelContext: modelContext)
        assign(ReceiptCaptureItem.self, profileID: profileID, modelContext: modelContext)
        assign(ReceiptLineItem.self, profileID: profileID, modelContext: modelContext)
        assign(AttachmentItem.self, profileID: profileID, modelContext: modelContext)
        assign(HouseholdMemberItem.self, profileID: profileID, modelContext: modelContext)
        assign(HouseholdExpenseItem.self, profileID: profileID, modelContext: modelContext)
        assign(HouseholdExpenseSplitItem.self, profileID: profileID, modelContext: modelContext)
        assign(HouseholdBillItem.self, profileID: profileID, modelContext: modelContext)
        assign(HouseholdAllowanceItem.self, profileID: profileID, modelContext: modelContext)
    }

    private static func assign<T: PersistentModel & ProfileOwned>(
        _ type: T.Type,
        profileID: UUID,
        modelContext: ModelContext
    ) {
        let items = (try? modelContext.fetch(FetchDescriptor<T>())) ?? []
        for item in items where item.profileID == nil {
            item.profileID = profileID
        }
    }

    private static func count<T: PersistentModel & ProfileOwned>(
        _ type: T.Type,
        profileID: UUID,
        modelContext: ModelContext
    ) -> Int {
        ((try? modelContext.fetch(FetchDescriptor<T>())) ?? [])
            .filter { $0.profileID == profileID }
            .count
    }

    private static func deleteMatching<T: PersistentModel & ProfileOwned>(
        _ type: T.Type,
        profileID: UUID,
        modelContext: ModelContext
    ) {
        for item in ((try? modelContext.fetch(FetchDescriptor<T>())) ?? [])
            where item.profileID == profileID {
            modelContext.delete(item)
        }
    }
}

struct TransactionDraft {
    let amountMinor: Int64
    let isExpense: Bool
    let timestamp: Date
    let category: CategoryItem
    let account: AccountItem
    let note: String?
}

struct ReceiptLineImportDraft {
    let title: String
    let quantityText: String?
    let amountMinor: Int64
    let category: CategoryItem
    let account: AccountItem
    let duplicateTransactionID: UUID?
}

struct ReceiptCaptureDraft {
    let merchantName: String
    let transactionDate: Date
    let totalAmountMinor: Int64
    let currencyCode: String
    let rawText: String
    let imageData: [Data]
    let lineItems: [ReceiptLineImportDraft]
}

struct PendingTransactionDraft {
    let amountMinor: Int64
    let expectedDueDate: Date
    let note: String?
}

enum TransactionCreationDraft {
    case posted(TransactionDraft)
    case pending(PendingTransactionDraft)

    var amountMinor: Int64 {
        switch self {
        case .posted(let draft):
            return draft.amountMinor
        case .pending(let draft):
            return draft.amountMinor
        }
    }
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
        event: EventItem? = nil,
        note: String?,
        receiptCapture: ReceiptCaptureItem? = nil,
        people: [PersonItem]? = nil
    ) throws -> TransactionItem {
        let transaction = TransactionItem(
            amountMinor: amountMinor,
            isExpense: isExpense,
            timestamp: timestamp,
            category: category,
            account: account,
            event: event,
            note: note?.trimmedNilIfBlank,
            receiptCapture: receiptCapture
        )
        modelContext.insert(transaction)
        if let people {
            transaction.replacePeople(people, in: modelContext)
        }
        try save()
        return transaction
    }

    func createPending(
        amountMinor: Int64,
        expectedDueDate: Date,
        event: EventItem? = nil,
        note: String?,
        people: [PersonItem]? = nil
    ) throws -> TransactionItem {
        let transaction = TransactionItem(
            amountMinor: amountMinor,
            isExpense: true,
            status: .pending,
            timestamp: Date(),
            expectedDueDate: expectedDueDate,
            category: nil,
            account: nil,
            event: event,
            note: note?.trimmedNilIfBlank
        )
        modelContext.insert(transaction)
        if let people {
            transaction.replacePeople(people, in: modelContext)
        }
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
                    event: nil,
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
                    event: nil,
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
            insertPending(draft)
        }
        try save()
        return validDrafts.count
    }

    func createMany(from drafts: [TransactionCreationDraft]) throws -> Int {
        guard !drafts.isEmpty,
              drafts.allSatisfy({ $0.amountMinor > 0 })
        else {
            return 0
        }

        for draft in drafts {
            insert(draft)
        }
        try save()
        return drafts.count
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
                event: nil,
                note: draft.note?.trimmedNilIfBlank
            )
        )
    }
        modelContext.delete(transaction)
        try save()
        return validDrafts.count
    }

    func replace(_ transaction: TransactionItem, with drafts: [TransactionCreationDraft]) throws
        -> Int
    {
        guard !drafts.isEmpty,
              drafts.allSatisfy({ $0.amountMinor > 0 })
        else {
            return 0
        }

        for draft in drafts {
            insert(draft)
        }
        modelContext.delete(transaction)
        try save()
        return drafts.count
    }

    func update(
        _ transaction: TransactionItem,
        amountMinor: Int64,
        isExpense: Bool,
        timestamp: Date,
        category: CategoryItem,
        account: AccountItem,
        event: EventItem? = nil,
        note: String?,
        people: [PersonItem]? = nil
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
        if let people {
            transaction.replacePeople(people, in: modelContext)
        }
        transaction.event = event ?? transaction.event
        try save()
    }

    func updatePending(
        _ transaction: TransactionItem,
        amountMinor: Int64,
        expectedDueDate: Date,
        event: EventItem? = nil,
        note: String?,
        people: [PersonItem]? = nil
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
        if let people {
            transaction.replacePeople(people, in: modelContext)
        }
        transaction.event = event ?? transaction.event
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
        return filterActiveProfile(try modelContext.fetch(descriptor))
    }

    private func save() throws {
        do {
            try modelContext.save()
            FloatSpotlightIndexer.scheduleReindex(modelContext: modelContext)
        } catch {
            throw DataIntegrityError.saveFailed
        }
    }

    private func insert(_ draft: TransactionCreationDraft) {
        switch draft {
        case .posted(let draft):
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
        case .pending(let draft):
            insertPending(draft)
        }
    }

    private func insertPending(_ draft: PendingTransactionDraft) {
        modelContext.insert(
            TransactionItem(
                amountMinor: draft.amountMinor,
                isExpense: true,
                status: .pending,
                timestamp: Date(),
                expectedDueDate: draft.expectedDueDate,
                category: nil,
                account: nil,
                event: nil,
                note: draft.note?.trimmedNilIfBlank
            )
        )
    }
}

@MainActor
struct ReceiptCaptureRepository {
    let modelContext: ModelContext

    func createImportedReceipt(from draft: ReceiptCaptureDraft) throws -> ReceiptCaptureItem {
        let receipt = ReceiptCaptureItem(
            merchantName: draft.merchantName.trimmedNilIfBlank ?? String(localized: "Receipt"),
            transactionDate: draft.transactionDate,
            totalAmountMinor: draft.totalAmountMinor,
            currencyCode: draft.currencyCode,
            rawText: draft.rawText
        )
        modelContext.insert(receipt)

        for (index, data) in draft.imageData.enumerated() {
            let attachment = AttachmentItem(
                fileName: "receipt-\(index + 1).jpg",
                data: data,
                receipt: receipt
            )
            modelContext.insert(attachment)
            receipt.attachments.append(attachment)
        }

        for (index, lineDraft) in draft.lineItems.enumerated() {
            let transaction = TransactionItem(
                amountMinor: lineDraft.amountMinor,
                isExpense: true,
                timestamp: draft.transactionDate,
                category: lineDraft.category,
                account: lineDraft.account,
                note: lineDraft.title,
                receiptCapture: receipt
            )
            modelContext.insert(transaction)

            let line = ReceiptLineItem(
                sortOrder: index,
                title: lineDraft.title,
                quantityText: lineDraft.quantityText,
                amountMinor: lineDraft.amountMinor,
                selectedForImport: true,
                receipt: receipt,
                category: lineDraft.category,
                account: lineDraft.account,
                transaction: transaction,
                duplicateTransactionID: lineDraft.duplicateTransactionID
            )
            modelContext.insert(line)
            receipt.lineItems.append(line)
            receipt.transactions.append(transaction)
        }

        do {
            try modelContext.save()
            FloatSpotlightIndexer.scheduleReindex(modelContext: modelContext)
            return receipt
        } catch {
            throw DataIntegrityError.saveFailed
        }
    }
}

@MainActor
struct EventCategoryRepository {
    let modelContext: ModelContext

    func create(
        name: String,
        iconKey: String,
        colorHex: String,
        sortOrder: Int
    ) throws -> EventCategoryItem {
        let category = EventCategoryItem(
            name: name.trimmedNilIfBlank ?? "Event Category",
            iconKey: iconKey,
            colorHex: colorHex,
            sortOrder: sortOrder
        )
        modelContext.insert(category)
        try save()
        return category
    }

    func update(
        _ category: EventCategoryItem,
        name: String,
        iconKey: String,
        colorHex: String
    ) throws {
        category.name = name.trimmedNilIfBlank ?? "Event Category"
        category.iconKey = iconKey
        category.colorHex = colorHex
        category.updatedAt = Date()
        try save()
    }

    func deleteIfUnused(_ category: EventCategoryItem) throws -> Bool {
        let events = (try? modelContext.fetch(FetchDescriptor<EventItem>())) ?? []
        guard !events.contains(where: { $0.category?.id == category.id }) else {
            return false
        }
        modelContext.delete(category)
        try save()
        return true
    }

    private func save() throws {
        do {
            try modelContext.save()
            FloatSpotlightIndexer.scheduleReindex(modelContext: modelContext)
        } catch {
            throw DataIntegrityError.saveFailed
        }
    }
}

@MainActor
struct EventRepository {
    let modelContext: ModelContext

    func create(
        name: String,
        startDate: Date,
        endDate: Date,
        status: EventStatus = .active,
        category: EventCategoryItem? = nil,
        eventDescription: String? = nil,
        pinned: Bool = false
    ) throws -> EventItem {
        let event = EventItem(
            name: name.trimmedNilIfBlank ?? "Event",
            startDate: startDate,
            endDate: endDate,
            status: status,
            eventDescription: eventDescription?.trimmedNilIfBlank,
            pinned: pinned,
            category: category
        )
        modelContext.insert(event)
        try save()
        return event
    }

    func update(
        _ event: EventItem,
        name: String,
        startDate: Date,
        endDate: Date,
        status: EventStatus,
        category: EventCategoryItem?,
        eventDescription: String?,
        pinned: Bool
    ) throws {
        event.name = name.trimmedNilIfBlank ?? "Event"
        event.startDate = startDate
        event.endDate = endDate
        event.statusRaw = status.rawValue
        event.category = category
        event.eventDescription = eventDescription?.trimmedNilIfBlank
        event.pinned = pinned
        event.updatedAt = Date()
        try save()
    }

    func delete(_ event: EventItem) throws {
        modelContext.delete(event)
        try save()
    }

    private func save() throws {
        do {
            try modelContext.save()
            FloatSpotlightIndexer.scheduleReindex(modelContext: modelContext)
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
            FloatSpotlightIndexer.scheduleReindex(modelContext: modelContext)
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
            FloatSpotlightIndexer.scheduleReindex(modelContext: modelContext)
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
            FloatSpotlightIndexer.scheduleReindex(modelContext: modelContext)
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
        let transactions = filterActiveProfile(
            (try? modelContext.fetch(FetchDescriptor<TransactionItem>())) ?? []
        )
        if transactions.contains(where: { $0.category?.id == category.id }) {
            return true
        }

        let rules = filterActiveProfile(
            (try? modelContext.fetch(FetchDescriptor<RecurringRuleItem>())) ?? []
        )
        if rules.contains(where: { $0.category?.id == category.id }) {
            return true
        }

        let budgets = filterActiveProfile(
            (try? modelContext.fetch(FetchDescriptor<CategoryBudgetItem>())) ?? []
        )
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
        let transactions = filterActiveProfile(
            (try? modelContext.fetch(FetchDescriptor<TransactionItem>())) ?? []
        )
        if transactions.contains(where: { $0.account?.id == account.id }) {
            return true
        }

        let transfers = filterActiveProfile(
            (try? modelContext.fetch(FetchDescriptor<TransferItem>())) ?? []
        )
        if transfers.contains(where: {
            $0.fromAccount?.id == account.id || $0.toAccount?.id == account.id
        }) {
            return true
        }

        let rules = filterActiveProfile(
            (try? modelContext.fetch(FetchDescriptor<RecurringRuleItem>())) ?? []
        )
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
        endDate: Date?,
        people: [PersonItem]? = nil
    ) throws -> RecurringRuleItem {
        let rule = RecurringRuleItem(
            amountMinor: amountMinor,
            isExpense: isExpense,
            category: category,
            account: account,
            note: note?.trimmedNilIfBlank,
            personTags: [],
            cadence: cadence,
            intervalCount: intervalCount,
            nextRunDate: nextRunDate,
            endDate: endDate
        )
        if let people {
            rule.replacePeople(people, in: modelContext)
        }
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
        active: Bool,
        people: [PersonItem]? = nil
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
        if let people {
            rule.replacePeople(people, in: modelContext)
        }
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
        rolloverPolicy: BudgetRolloverPolicy,
        currencyCode: String,
        existingBudgets: [CategoryBudgetItem]
    ) throws {
        if let existing = existingBudgets.first(where: { $0.category?.id == category.id }) {
            if amountMinor > 0 {
                existing.amountMinor = amountMinor
                existing.rolloverPolicy = rolloverPolicy
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
                    rolloverPolicy: rolloverPolicy,
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
struct SettlementCaseRepository {
    let modelContext: ModelContext

    func create(
        title: String,
        personName: String,
        direction: SettlementDirection,
        initialAmountMinor: Int64,
        date: Date,
        currencyCode: String,
        note: String?,
        person: PersonItem? = nil,
        dueDate: Date? = nil
    ) throws -> SettlementCaseItem {
        guard initialAmountMinor > 0 else {
            throw DataIntegrityError.invalidInput
        }
        let caseItem = SettlementCaseItem(
            title: title.trimmedNilIfBlank ?? String(localized: "Settlement"),
            counterpartyName: person?.name.trimmedNilIfBlank
                ?? personName.trimmedNilIfBlank
                ?? String(localized: "No person"),
            direction: direction,
            currencyCode: currencyCode,
            note: note?.trimmedNilIfBlank,
            person: person,
            dueDate: dueDate,
            createdAt: date,
            updatedAt: date
        )
        let entry = SettlementEntryItem(
            kind: .initialAmount,
            amountMinor: initialAmountMinor,
            entryDate: date,
            note: note?.trimmedNilIfBlank,
            caseItem: caseItem,
            createdAt: date,
            updatedAt: date
        )
        caseItem.entries.append(entry)
        modelContext.insert(caseItem)
        modelContext.insert(entry)
        try save()
        return caseItem
    }

    func update(
        _ caseItem: SettlementCaseItem,
        title: String,
        personName: String,
        direction: SettlementDirection,
        currencyCode: String,
        initialAmountMinor: Int64,
        date: Date,
        note: String?,
        person: PersonItem? = nil,
        dueDate: Date? = nil
    ) throws {
        guard initialAmountMinor > 0 else {
            throw DataIntegrityError.invalidInput
        }
        caseItem.title = title.trimmedNilIfBlank ?? String(localized: "Settlement")
        caseItem.counterpartyName = person?.name.trimmedNilIfBlank
            ?? personName.trimmedNilIfBlank
            ?? String(localized: "No person")
        caseItem.person = person
        caseItem.direction = direction
        caseItem.currencyCode = currencyCode
        caseItem.createdAt = date
        caseItem.dueDate = dueDate
        caseItem.note = note?.trimmedNilIfBlank
        caseItem.updatedAt = Date()

        if let initialEntry = caseItem.entries.first(where: { $0.kind == .initialAmount }) {
            initialEntry.apply(
                kind: .initialAmount,
                amountMinor: initialAmountMinor,
                entryDate: date,
                note: note?.trimmedNilIfBlank,
                reference: initialEntry.reference
            )
        } else {
            let initialEntry = SettlementEntryItem(
                kind: .initialAmount,
                amountMinor: initialAmountMinor,
                entryDate: date,
                note: note?.trimmedNilIfBlank,
                caseItem: caseItem,
                createdAt: date,
                updatedAt: Date()
            )
            caseItem.entries.append(initialEntry)
            modelContext.insert(initialEntry)
        }
        refreshClosureState(for: caseItem)
        try save()
    }

    func addEntry(
        to caseItem: SettlementCaseItem,
        kind: SettlementEntryKind,
        amountMinor: Int64,
        entryDate: Date,
        note: String?,
        reference: String?
    ) throws -> SettlementEntryItem {
        guard amountMinor > 0, kind != .initialAmount else {
            throw DataIntegrityError.invalidInput
        }
        let entry = SettlementEntryItem(
            kind: kind,
            amountMinor: amountMinor,
            entryDate: entryDate,
            note: note?.trimmedNilIfBlank,
            reference: reference?.trimmedNilIfBlank,
            caseItem: caseItem
        )
        caseItem.entries.append(entry)
        caseItem.updatedAt = Date()
        modelContext.insert(entry)
        refreshClosureState(for: caseItem)
        try save()
        return entry
    }

    func addEntryAndCreateTransaction(
        to caseItem: SettlementCaseItem,
        kind: SettlementEntryKind,
        amountMinor: Int64,
        entryDate: Date,
        note: String?,
        reference: String?,
        category: CategoryItem,
        account: AccountItem
    ) throws -> SettlementEntryItem {
        guard amountMinor > 0, kind != .initialAmount else {
            throw DataIntegrityError.invalidInput
        }

        let transaction = TransactionItem(
            amountMinor: amountMinor,
            isExpense: linkedTransactionIsExpense(for: caseItem, kind: kind),
            timestamp: entryDate,
            category: category,
            account: account,
            note: linkedTransactionNote(
                title: caseItem.displayTitle,
                note: note?.trimmedNilIfBlank,
                reference: reference?.trimmedNilIfBlank
            )
        )
        modelContext.insert(transaction)
        let entry = SettlementEntryItem(
            kind: kind,
            amountMinor: amountMinor,
            entryDate: entryDate,
            note: note?.trimmedNilIfBlank,
            reference: reference?.trimmedNilIfBlank,
            caseItem: caseItem,
            linkedTransaction: transaction
        )
        caseItem.entries.append(entry)
        caseItem.updatedAt = Date()
        modelContext.insert(entry)
        refreshClosureState(for: caseItem)
        try save()
        return entry
    }

    func updateEntry(
        _ entry: SettlementEntryItem,
        kind: SettlementEntryKind,
        amountMinor: Int64,
        entryDate: Date,
        note: String?,
        reference: String?
    ) throws {
        guard amountMinor > 0, kind != .initialAmount else {
            throw DataIntegrityError.invalidInput
        }
        entry.apply(
            kind: kind,
            amountMinor: amountMinor,
            entryDate: entryDate,
            note: note?.trimmedNilIfBlank,
            reference: reference?.trimmedNilIfBlank
        )
        if let transaction = entry.linkedTransaction {
            transaction.amountMinor = entry.amountMinor
            transaction.isExpense = entry.caseItem.map {
                linkedTransactionIsExpense(for: $0, kind: kind)
            } ?? transaction.isExpense
            transaction.timestamp = entryDate
            transaction.note = linkedTransactionNote(
                title: entry.caseItem?.displayTitle ?? String(localized: "Settlement"),
                note: note?.trimmedNilIfBlank,
                reference: reference?.trimmedNilIfBlank
            )
        }
        if let caseItem = entry.caseItem {
            refreshClosureState(for: caseItem)
        }
        try save()
    }

    func deleteEntry(_ entry: SettlementEntryItem) throws {
        guard entry.kind != .initialAmount else {
            throw DataIntegrityError.invalidInput
        }
        entry.caseItem?.updatedAt = Date()
        entry.caseItem?.milestones
            .filter { $0.linkedEntry?.id == entry.id }
            .forEach {
                $0.linkedEntry = nil
                $0.status = .pending
                $0.updatedAt = Date()
            }
        if let caseItem = entry.caseItem {
            refreshClosureState(for: caseItem)
        }
        modelContext.delete(entry)
        try save()
    }

    func delete(_ caseItem: SettlementCaseItem) throws {
        modelContext.delete(caseItem)
        try save()
    }

    func close(_ caseItem: SettlementCaseItem) throws {
        caseItem.closedAt = Date()
        caseItem.archived = false
        caseItem.updatedAt = Date()
        try save()
    }

    func reopen(_ caseItem: SettlementCaseItem) throws {
        caseItem.closedAt = nil
        caseItem.archived = false
        caseItem.updatedAt = Date()
        try save()
    }

    func archive(_ caseItem: SettlementCaseItem) throws {
        caseItem.archived = true
        if caseItem.closedAt == nil {
            caseItem.closedAt = Date()
        }
        caseItem.updatedAt = Date()
        try save()
    }

    func addMilestone(
        to caseItem: SettlementCaseItem,
        title: String,
        amountMinor: Int64,
        dueDate: Date,
        note: String?
    ) throws -> SettlementMilestoneItem {
        guard amountMinor > 0 else {
            throw DataIntegrityError.invalidInput
        }
        let milestone = SettlementMilestoneItem(
            title: title.trimmedNilIfBlank ?? String(localized: "Payment"),
            amountMinor: amountMinor,
            dueDate: dueDate,
            note: note?.trimmedNilIfBlank,
            caseItem: caseItem
        )
        caseItem.milestones.append(milestone)
        caseItem.updatedAt = Date()
        modelContext.insert(milestone)
        try save()
        return milestone
    }

    func updateMilestone(
        _ milestone: SettlementMilestoneItem,
        title: String,
        amountMinor: Int64,
        dueDate: Date,
        note: String?,
        status: SettlementMilestoneStatus
    ) throws {
        guard amountMinor > 0 else {
            throw DataIntegrityError.invalidInput
        }
        milestone.apply(
            title: title.trimmedNilIfBlank ?? String(localized: "Payment"),
            amountMinor: amountMinor,
            dueDate: dueDate,
            note: note?.trimmedNilIfBlank,
            status: status
        )
        try save()
    }

    func deleteMilestone(_ milestone: SettlementMilestoneItem) throws {
        milestone.caseItem?.updatedAt = Date()
        modelContext.delete(milestone)
        try save()
    }

    func recordPayment(
        to caseItem: SettlementCaseItem,
        milestone: SettlementMilestoneItem?,
        amountMinor: Int64,
        entryDate: Date,
        note: String?,
        reference: String?
    ) throws -> SettlementEntryItem {
        let entry = try addEntry(
            to: caseItem,
            kind: .payment,
            amountMinor: amountMinor,
            entryDate: entryDate,
            note: note,
            reference: reference
        )
        if let milestone {
            milestone.linkedEntry = entry
            milestone.status = entry.amountMinor >= milestone.amountMinor ? .paid : .pending
            milestone.updatedAt = Date()
        }
        refreshClosureState(for: caseItem)
        try save()
        return entry
    }

    func linkTransaction(
        _ transaction: TransactionItem?,
        to entry: SettlementEntryItem
    ) throws {
        entry.linkedTransaction = transaction
        entry.updatedAt = Date()
        entry.caseItem?.updatedAt = Date()
        try save()
    }

    private func linkedTransactionIsExpense(
        for caseItem: SettlementCaseItem,
        kind: SettlementEntryKind
    ) -> Bool {
        switch kind {
        case .payment:
            return caseItem.direction == .youOweThem
        case .addition, .adjustment:
            return caseItem.direction == .youOweThem
        case .discount, .waived, .correctionDown:
            return false
        case .initialAmount:
            return caseItem.direction == .youOweThem
        }
    }

    private func linkedTransactionNote(
        title: String,
        note: String?,
        reference: String?
    ) -> String {
        [title, note, reference]
            .compactMap { $0?.trimmedNilIfBlank }
            .joined(separator: " - ")
    }

    private func refreshClosureState(for caseItem: SettlementCaseItem) {
        if caseItem.archived {
            return
        }
        let snapshot = caseItem.balanceSnapshot
        if snapshot.remainingMinor == 0 && snapshot.creditMinor == 0 {
            caseItem.closedAt = caseItem.closedAt ?? Date()
        } else if caseItem.closedAt != nil {
            caseItem.closedAt = nil
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
struct HouseholdExpenseDraft {
    var title: String
    var amountMinor: Int64
    var currencyCode: String
    var expenseDate: Date
    var payer: HouseholdMemberItem?
    var members: [HouseholdMemberItem]
    var splitMethod: HouseholdSplitMethod
    var reimbursementRequired: Bool
    var category: CategoryItem?
    var account: AccountItem?
    var receiptCapture: ReceiptCaptureItem?
    var note: String?
    var customAmounts: [UUID: Int64]
}

@MainActor
struct HouseholdRepository {
    let modelContext: ModelContext

    func saveMember(
        _ member: HouseholdMemberItem?,
        displayName: String,
        role: HouseholdMemberRole,
        colorHex: String,
        monthlyAllowanceMinor: Int64
    ) throws -> HouseholdMemberItem {
        if let member {
            member.apply(
                displayName: displayName,
                role: role,
                colorHex: colorHex,
                monthlyAllowanceMinor: monthlyAllowanceMinor
            )
            try save()
            return member
        }

        let model = HouseholdMemberItem(
            displayName: displayName,
            role: role,
            colorHex: colorHex,
            monthlyAllowanceMinor: monthlyAllowanceMinor
        )
        modelContext.insert(model)
        try save()
        return model
    }

    func archiveMember(_ member: HouseholdMemberItem) throws {
        member.archived = true
        member.updatedAt = Date()
        try save()
    }

    func createExpense(_ draft: HouseholdExpenseDraft) throws -> HouseholdExpenseItem {
        guard draft.amountMinor > 0 else { throw DataIntegrityError.invalidInput }
        let selectedMembers = draft.members.filter { !$0.archived }
        guard !selectedMembers.isEmpty else { throw DataIntegrityError.invalidInput }

        let expense = HouseholdExpenseItem(
            title: draft.title,
            amountMinor: draft.amountMinor,
            currencyCode: draft.currencyCode,
            expenseDate: draft.expenseDate,
            splitMethod: draft.splitMethod,
            reimbursementRequired: draft.reimbursementRequired,
            note: draft.note,
            payer: draft.payer,
            category: draft.category,
            account: draft.account,
            receiptCapture: draft.receiptCapture
        )
        modelContext.insert(expense)

        let splitAmounts = splitAmounts(
            total: draft.amountMinor,
            members: selectedMembers,
            method: draft.splitMethod,
            customAmounts: draft.customAmounts
        )
        for (index, member) in selectedMembers.enumerated() {
            let split = HouseholdExpenseSplitItem(
                sortOrder: index,
                amountMinor: splitAmounts[member.id] ?? 0,
                member: member,
                expense: expense
            )
            modelContext.insert(split)
            expense.splits.append(split)
        }

        try save()
        return expense
    }

    func approveExpense(_ expense: HouseholdExpenseItem) throws {
        guard expense.approvalStatus == .pending else { return }
        expense.approvalStatus = .approved
        expense.approvedAt = Date()
        expense.updatedAt = Date()

        if expense.transaction == nil {
            let transaction = TransactionItem(
                amountMinor: expense.amountMinor,
                isExpense: true,
                status: .posted,
                timestamp: expense.expenseDate,
                category: expense.category,
                account: expense.account,
                note: expense.note?.trimmedNilIfBlank ?? expense.title,
                receiptCapture: expense.receiptCapture
            )
            modelContext.insert(transaction)
            transaction.replacePeople(
                expense.sortedSplits.compactMap { $0.member?.person },
                in: modelContext
            )
            expense.transaction = transaction
        }

        try save()
        FloatSpotlightIndexer.scheduleReindex(modelContext: modelContext)
    }

    func rejectExpense(_ expense: HouseholdExpenseItem) throws {
        guard expense.approvalStatus == .pending else { return }
        expense.approvalStatus = .rejected
        expense.rejectedAt = Date()
        expense.updatedAt = Date()
        try save()
    }

    func saveBill(
        title: String,
        amountMinor: Int64,
        currencyCode: String,
        dueDate: Date,
        cadence: RecurringCadence,
        payer: HouseholdMemberItem?,
        category: CategoryItem?,
        account: AccountItem?,
        autoCreateApproval: Bool,
        note: String?
    ) throws -> HouseholdBillItem {
        guard amountMinor > 0 else { throw DataIntegrityError.invalidInput }
        let bill = HouseholdBillItem(
            title: title,
            amountMinor: amountMinor,
            currencyCode: currencyCode,
            dueDate: dueDate,
            cadence: cadence,
            payer: payer,
            category: category,
            account: account,
            autoCreateApproval: autoCreateApproval,
            note: note
        )
        modelContext.insert(bill)
        try save()
        return bill
    }

    func createMonthlyCloseout(
        expenses: [HouseholdExpenseItem],
        currencyCode: String
    ) throws -> Int {
        let approved = expenses.filter {
            $0.approvalStatus == .approved
                && $0.reimbursementRequired
                && $0.settledAt == nil
        }
        let balances = reimbursementBalances(from: approved)
        guard !balances.isEmpty else { return 0 }

        for balance in balances where balance.amountMinor > 0 {
            let caseItem = SettlementCaseItem(
                title: AppLocalization.format(
                    "Household closeout: %@",
                    balance.member.displayName
                ),
                counterpartyName: balance.member.displayName,
                direction: .theyOweYou,
                currencyCode: currencyCode,
                note: AppLocalization.format(
                    "Household reimbursement owed to %@.",
                    balance.payer.displayName
                ),
                person: balance.member.person,
                dueDate: Calendar.current.date(byAdding: .day, value: 7, to: Date())
            )
            modelContext.insert(caseItem)

            let entry = SettlementEntryItem(
                kind: .initialAmount,
                amountMinor: balance.amountMinor,
                entryDate: Date(),
                note: AppLocalization.format(
                    "Household closeout payable to %@.",
                    balance.payer.displayName
                ),
                caseItem: caseItem
            )
            modelContext.insert(entry)
            caseItem.entries.append(entry)
        }

        for expense in approved {
            expense.approvalStatus = .settled
            expense.settledAt = Date()
            expense.updatedAt = Date()
        }

        try save()
        return balances.count
    }

    private func splitAmounts(
        total: Int64,
        members: [HouseholdMemberItem],
        method: HouseholdSplitMethod,
        customAmounts: [UUID: Int64]
    ) -> [UUID: Int64] {
        guard !members.isEmpty else { return [:] }
        switch method {
        case .equal:
            let base = total / Int64(members.count)
            let remainder = total - base * Int64(members.count)
            return Dictionary(uniqueKeysWithValues: members.enumerated().map { index, member in
                (member.id, base + (index == 0 ? remainder : 0))
            })
        case .custom:
            return Dictionary(uniqueKeysWithValues: members.map { member in
                (member.id, max(0, customAmounts[member.id] ?? 0))
            })
        case .singleMember:
            return Dictionary(uniqueKeysWithValues: members.enumerated().map { index, member in
                (member.id, index == 0 ? total : 0)
            })
        }
    }

    private func reimbursementBalances(
        from expenses: [HouseholdExpenseItem]
    ) -> [HouseholdReimbursementBalance] {
        var keyed: [HouseholdReimbursementBalanceKey: Int64] = [:]
        for expense in expenses {
            guard let payer = expense.payer else { continue }
            for split in expense.sortedSplits {
                guard let member = split.member, member.id != payer.id else { continue }
                let outstanding = split.outstandingMinor
                guard outstanding > 0 else { continue }
                let key = HouseholdReimbursementBalanceKey(
                    payerID: payer.id,
                    memberID: member.id,
                    payer: payer,
                    member: member
                )
                keyed[key, default: 0] += outstanding
            }
        }
        return keyed.map { key, amount in
            HouseholdReimbursementBalance(
                payer: key.payer,
                member: key.member,
                amountMinor: amount
            )
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

private struct HouseholdReimbursementBalanceKey: Hashable {
    let payerID: UUID
    let memberID: UUID
    let payer: HouseholdMemberItem
    let member: HouseholdMemberItem

    func hash(into hasher: inout Hasher) {
        hasher.combine(payerID)
        hasher.combine(memberID)
    }

    static func == (
        lhs: HouseholdReimbursementBalanceKey,
        rhs: HouseholdReimbursementBalanceKey
    ) -> Bool {
        lhs.payerID == rhs.payerID && lhs.memberID == rhs.memberID
    }
}

private struct HouseholdReimbursementBalance {
    let payer: HouseholdMemberItem
    let member: HouseholdMemberItem
    let amountMinor: Int64
}

@MainActor
struct SettingsRepository {
    let modelContext: ModelContext

    func resetAllData(currencyCode: String) throws {
        try modelContext.delete(model: SettlementMilestoneItem.self)
        try modelContext.delete(model: SettlementEntryItem.self)
        try modelContext.delete(model: SettlementCaseItem.self)
        try modelContext.delete(model: HouseholdAllowanceItem.self)
        try modelContext.delete(model: HouseholdExpenseSplitItem.self)
        try modelContext.delete(model: HouseholdExpenseItem.self)
        try modelContext.delete(model: HouseholdBillItem.self)
        try modelContext.delete(model: HouseholdMemberItem.self)
        try modelContext.delete(model: TransactionItem.self)
        try modelContext.delete(model: TransactionTemplateItem.self)
        try modelContext.delete(model: TransferItem.self)
        try modelContext.delete(model: RecurringRuleItem.self)
        try modelContext.delete(model: GoalItem.self)
        try modelContext.delete(model: BudgetCycleCategoryItem.self)
        try modelContext.delete(model: BudgetCycleItem.self)
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
            FloatSpotlightIndexer.scheduleReindex(modelContext: modelContext)
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
