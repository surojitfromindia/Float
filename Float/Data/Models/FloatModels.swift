import Foundation
import SwiftData

/// this is account type Enum
/// a enum can have fields.
enum AccountType: String, Codable, CaseIterable, Identifiable {
    case cash
    case bank
    case card
    case wallet

    // also enum can have variables or functional expression.
    var id: String { rawValue }
    var title: String {
        switch self {
        case .cash: String(localized: "Cash")
        case .bank: String(localized: "Bank")
        case .card: String(localized: "Card")
        case .wallet: String(localized: "Wallet")
        }
    }
    var icon: String {
        switch self {
        case .cash: "banknote.fill"
        case .bank: "building.columns.fill"
        case .card: "creditcard.fill"
        case .wallet: "wallet.pass.fill"
        }
    }
}

enum RecurringCadence: String, Codable, CaseIterable, Identifiable {
    case daily
    case weekly
    case monthly

    var id: String { rawValue }
    var title: String {
        switch self {
        case .daily: String(localized: "Daily")
        case .weekly: String(localized: "Weekly")
        case .monthly: String(localized: "Monthly")
        }
    }
}

enum BudgetCadence: String, Codable, CaseIterable, Identifiable {
    case weekly
    case monthly

    var id: String { rawValue }
    var title: String {
        switch self {
        case .weekly: String(localized: "Weekly")
        case .monthly: String(localized: "Monthly")
        }
    }
}

enum TransactionStatus: String, Codable, CaseIterable, Identifiable {
    case posted
    case pending

    var id: String { rawValue }
}

enum EventStatus: String, Codable, CaseIterable, Identifiable {
    case active
    case ended

    var id: String { rawValue }

    var title: String {
        switch self {
        case .active: String(localized: "Active")
        case .ended: String(localized: "Ended")
        }
    }
}

@Model
final class AccountItem {
    var id: UUID = UUID()
    var name: String = "" /// name of the account
    var type: AccountType = AccountType.cash /// default type is cash
    var openingBalanceMinor: Int64 = 0 /// opening balance is zero.
    var currencyCode: String = "USD"
    var archived: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        name: String,
        type: AccountType = .cash,
        openingBalanceMinor: Int64 = 0,
        currencyCode: String,
        archived: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.openingBalanceMinor = openingBalanceMinor
        self.currencyCode = currencyCode
        self.archived = archived
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class CategoryItem {
    var id: UUID = UUID()
    var name: String = ""
    var iconKey: String = "square.grid.2x2.fill"
    var colorHex: String = "#0E7C7B"
    var isIncome: Bool = false
    var sortOrder: Int = 0
    var archived: Bool = false
    var isDefault: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        name: String,
        iconKey: String,
        colorHex: String,
        isIncome: Bool = false,
        sortOrder: Int = 0,
        archived: Bool = false,
        isDefault: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.iconKey = iconKey
        self.colorHex = colorHex
        self.isIncome = isIncome
        self.sortOrder = sortOrder
        self.archived = archived
        self.isDefault = isDefault
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class PersonItem {
    var id: UUID = UUID()
    var name: String = ""
    var alias: String?
    var note: String?
    var colorHex: String = "#0E7C7B"
    var archived: Bool = false
    var transactionCount: Int = 0
    var recurringRuleCount: Int = 0
    @Relationship(deleteRule: .cascade, inverse: \TransactionPersonTagItem.person)
    var transactionTags: [TransactionPersonTagItem] = []
    @Relationship(deleteRule: .cascade, inverse: \RecurringRulePersonTagItem.person)
    var recurringRuleTags: [RecurringRulePersonTagItem] = []
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        name: String,
        alias: String? = nil,
        note: String? = nil,
        colorHex: String = "#0E7C7B",
        archived: Bool = false,
        transactionCount: Int = 0,
        recurringRuleCount: Int = 0,
        transactionTags: [TransactionPersonTagItem] = [],
        recurringRuleTags: [RecurringRulePersonTagItem] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.alias = alias?.nilIfBlank
        self.note = note?.nilIfBlank
        self.colorHex = colorHex
        self.archived = archived
        self.transactionCount = transactionCount
        self.recurringRuleCount = recurringRuleCount
        self.transactionTags = transactionTags
        self.recurringRuleTags = recurringRuleTags
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class TransactionItem {
    var id: UUID = UUID()
    var amountMinor: Int64 = 0
    var isExpense: Bool = true
    var statusRaw: String = TransactionStatus.posted.rawValue
    var timestamp: Date = Date()
    var expectedDueDate: Date?
    var category: CategoryItem?
    var account: AccountItem?
    var event: EventItem?
    var note: String?
    var recurringRule: RecurringRuleItem?
    @Relationship(deleteRule: .cascade, inverse: \TransactionPersonTagItem.transaction)
    var personTags: [TransactionPersonTagItem] = []
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        amountMinor: Int64,
        isExpense: Bool = true,
        status: TransactionStatus = .posted,
        timestamp: Date = Date(),
        expectedDueDate: Date? = nil,
        category: CategoryItem? = nil,
        account: AccountItem? = nil,
        event: EventItem? = nil,
        note: String? = nil,
        recurringRule: RecurringRuleItem? = nil,
        personTags: [TransactionPersonTagItem] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.amountMinor = normalizedMinorUnits(amountMinor)
        self.isExpense = isExpense
        self.statusRaw = status.rawValue
        self.timestamp = timestamp
        self.expectedDueDate = expectedDueDate
        self.category = category
        self.account = account
        self.event = event
        self.note = note
        self.recurringRule = recurringRule
        self.personTags = personTags
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class TransactionTemplateItem {
    var id: UUID = UUID()
    var title: String = ""
    var amountMinor: Int64 = 0
    var isExpense: Bool = true
    var category: CategoryItem?
    var account: AccountItem?
    var note: String?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        title: String,
        amountMinor: Int64,
        isExpense: Bool = true,
        category: CategoryItem? = nil,
        account: AccountItem? = nil,
        note: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.amountMinor = normalizedMinorUnits(amountMinor)
        self.isExpense = isExpense
        self.category = category
        self.account = account
        self.note = note?.nilIfBlank
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class TransactionTemplateGroupItem {
    var id: UUID = UUID()
    var name: String = ""
    @Relationship(
        deleteRule: .cascade,
        inverse: \TransactionTemplateGroupEntryItem.group
    )
    var entries: [TransactionTemplateGroupEntryItem] = []
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        name: String,
        entries: [TransactionTemplateGroupEntryItem] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.entries = entries
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class TransactionTemplateGroupEntryItem {
    var id: UUID = UUID()
    var sortOrder: Int = 0
    var group: TransactionTemplateGroupItem?
    var template: TransactionTemplateItem?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        sortOrder: Int,
        group: TransactionTemplateGroupItem? = nil,
        template: TransactionTemplateItem? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.sortOrder = sortOrder
        self.group = group
        self.template = template
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class TransferItem {
    var id: UUID = UUID()
    var amountMinor: Int64 = 0
    var fromAccount: AccountItem?
    var toAccount: AccountItem?
    var timestamp: Date = Date()
    var note: String?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        amountMinor: Int64,
        fromAccount: AccountItem? = nil,
        toAccount: AccountItem? = nil,
        timestamp: Date = Date(),
        note: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.amountMinor = normalizedMinorUnits(amountMinor)
        self.fromAccount = fromAccount
        self.toAccount = toAccount
        self.timestamp = timestamp
        self.note = note?.nilIfBlank
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class EventCategoryItem {
    var id: UUID = UUID()
    var name: String = ""
    var iconKey: String = "calendar"
    var colorHex: String = "#0E7C7B"
    var sortOrder: Int = 0
    @Relationship(deleteRule: .nullify, inverse: \EventItem.category)
    var events: [EventItem] = []
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        name: String,
        iconKey: String,
        colorHex: String,
        sortOrder: Int = 0,
        events: [EventItem] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.iconKey = iconKey
        self.colorHex = colorHex
        self.sortOrder = sortOrder
        self.events = events
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class EventItem {
    var id: UUID = UUID()
    var name: String = ""
    var startDate: Date = Date()
    var endDate: Date = Date()
    var statusRaw: String = EventStatus.active.rawValue
    var eventDescription: String?
    var pinned: Bool = false
    var category: EventCategoryItem?
    @Relationship(deleteRule: .nullify, inverse: \TransactionItem.event)
    var transactions: [TransactionItem] = []
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        name: String,
        startDate: Date,
        endDate: Date,
        status: EventStatus = .active,
        eventDescription: String? = nil,
        pinned: Bool = false,
        category: EventCategoryItem? = nil,
        transactions: [TransactionItem] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.startDate = startDate
        self.endDate = endDate
        self.statusRaw = status.rawValue
        self.eventDescription = eventDescription?.nilIfBlank
        self.pinned = pinned
        self.category = category
        self.transactions = transactions
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension TransactionTemplateItem {
    var displayTitle: String {
        title.nilIfBlank
            ?? note?.nilIfBlank
            ?? category?.name
            ?? String(localized: "Template")
    }
}

extension TransactionTemplateGroupItem {
    var displayName: String {
        name.nilIfBlank ?? String(localized: "Group")
    }

    var sortedEntries: [TransactionTemplateGroupEntryItem] {
        entries.sorted { lhs, rhs in
            if lhs.sortOrder == rhs.sortOrder {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.sortOrder < rhs.sortOrder
        }
    }

    var validTemplates: [TransactionTemplateItem] {
        sortedEntries.compactMap(\.template)
    }
}

@Model
final class RecurringRuleItem {
    var id: UUID = UUID()
    var amountMinor: Int64 = 0
    var isExpense: Bool = true
    var category: CategoryItem?
    var account: AccountItem?
    var note: String?
    @Relationship(deleteRule: .cascade, inverse: \RecurringRulePersonTagItem.recurringRule)
    var personTags: [RecurringRulePersonTagItem] = []
    var cadence: RecurringCadence = RecurringCadence.monthly
    var intervalCount: Int = 1
    var nextRunDate: Date = Date()
    var endDate: Date?
    var active: Bool = true
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        amountMinor: Int64,
        isExpense: Bool = true,
        category: CategoryItem? = nil,
        account: AccountItem? = nil,
        note: String? = nil,
        personTags: [RecurringRulePersonTagItem] = [],
        cadence: RecurringCadence = .monthly,
        intervalCount: Int = 1,
        nextRunDate: Date = Date(),
        endDate: Date? = nil,
        active: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.amountMinor = normalizedMinorUnits(amountMinor)
        self.isExpense = isExpense
        self.category = category
        self.account = account
        self.note = note
        self.personTags = personTags
        self.cadence = cadence
        self.intervalCount = max(1, intervalCount)
        self.nextRunDate = nextRunDate
        self.endDate = endDate
        self.active = active
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class GoalItem {
    var id: UUID = UUID()
    var name: String = ""
    var targetMinor: Int64 = 0
    var savedMinor: Int64 = 0
    var targetDate: Date?
    var colorHex: String = "#0E7C7B"
    var achieved: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        name: String,
        targetMinor: Int64,
        savedMinor: Int64 = 0,
        targetDate: Date? = nil,
        colorHex: String = "#0E7C7B",
        achieved: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.targetMinor = normalizedMinorUnits(targetMinor)
        self.savedMinor = normalizedMinorUnits(savedMinor)
        self.targetDate = targetDate
        self.colorHex = colorHex
        self.achieved = achieved
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class BudgetPeriodItem {
    var id: UUID = UUID()
    var cadence: BudgetCadence = BudgetCadence.monthly
    var startDayOfMonth: Int?
    var startDayOfWeek: Int?
    var expectedIncomeMinor: Int64 = 0
    var currencyCode: String = "USD"
    var isActive: Bool = true
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        cadence: BudgetCadence = .monthly,
        startDayOfMonth: Int? = 1,
        startDayOfWeek: Int? = nil,
        expectedIncomeMinor: Int64 = 0,
        currencyCode: String,
        isActive: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.cadence = cadence
        self.startDayOfMonth = startDayOfMonth
        self.startDayOfWeek = startDayOfWeek
        self.expectedIncomeMinor = normalizedMinorUnits(expectedIncomeMinor)
        self.currencyCode = currencyCode
        self.isActive = isActive
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class CategoryBudgetItem {
    var id: UUID = UUID()
    var category: CategoryItem?
    var amountMinor: Int64 = 0
    var currencyCode: String = "USD"
    var isActive: Bool = true
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        category: CategoryItem? = nil,
        amountMinor: Int64,
        currencyCode: String,
        isActive: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.category = category
        self.amountMinor = normalizedMinorUnits(amountMinor)
        self.currencyCode = currencyCode
        self.isActive = isActive
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class TransactionPersonTagItem {
    var id: UUID = UUID()
    var sortOrder: Int = 0
    var allocatedMinor: Int64?
    var settledMinor: Int64 = 0
    var person: PersonItem?
    var transaction: TransactionItem?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        sortOrder: Int = 0,
        allocatedMinor: Int64? = nil,
        settledMinor: Int64 = 0,
        person: PersonItem? = nil,
        transaction: TransactionItem? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.sortOrder = sortOrder
        self.allocatedMinor = allocatedMinor
        self.settledMinor = max(0, settledMinor)
        self.person = person
        self.transaction = transaction
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class RecurringRulePersonTagItem {
    var id: UUID = UUID()
    var sortOrder: Int = 0
    var person: PersonItem?
    var recurringRule: RecurringRuleItem?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        sortOrder: Int = 0,
        person: PersonItem? = nil,
        recurringRule: RecurringRuleItem? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.sortOrder = sortOrder
        self.person = person
        self.recurringRule = recurringRule
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension TransactionItem {
    var status: TransactionStatus {
        get { TransactionStatus(rawValue: statusRaw) ?? .posted }
        set { statusRaw = newValue.rawValue }
    }

    var isPending: Bool {
        status == .pending
    }

    var isPosted: Bool {
        status == .posted
    }

    var isPostedExpense: Bool {
        isPosted && isExpense
    }

    var isPostedIncome: Bool {
        isPosted && !isExpense
    }

    var displayDate: Date {
        isPending ? expectedDueDate ?? timestamp : timestamp
    }

    var categoryName: String {
        if isPending { return String(localized: "Pending") }
        return category?.name.nilIfBlank ?? String(localized: "Unknown Category")
    }

    var accountName: String {
        if isPending { return String(localized: "Not posted") }
        return account?.name.nilIfBlank ?? String(localized: "Unknown Account")
    }

    var categoryIconKey: String {
        if isPending { return "clock.badge.exclamationmark.fill" }
        return category?.iconKey.nilIfBlank ?? "questionmark.circle.fill"
    }

    var categoryColorHex: String {
        if isPending { return "#6B7280" }
        return category?.colorHex.nilIfBlank ?? "#5A6B6B"
    }

    var personNames: [String] {
        personTags
            .sorted { lhs, rhs in
                if lhs.sortOrder == rhs.sortOrder {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhs.sortOrder < rhs.sortOrder
            }
            .compactMap { $0.person?.name.nilIfBlank }
    }

    var personSummary: String? {
        let names = personNames
        guard !names.isEmpty else { return nil }
        return names.joined(separator: ", ")
    }

    var hasPeople: Bool {
        personSummary != nil
    }

    func apply(
        amountMinor: Int64,
        isExpense: Bool,
        status: TransactionStatus = .posted,
        timestamp: Date,
        expectedDueDate: Date? = nil,
        category: CategoryItem?,
        account: AccountItem?,
        note: String?
    ) {
        self.amountMinor = normalizedMinorUnits(amountMinor)
        self.isExpense = isExpense
        self.statusRaw = status.rawValue
        self.timestamp = timestamp
        self.expectedDueDate = expectedDueDate
        self.category = category
        self.account = account
        self.note = note?.nilIfBlank
        updatedAt = Date()
    }

    func replacePeople(_ people: [PersonItem]) {
        personTags.removeAll()
        for (index, person) in people.enumerated() {
            let tag = TransactionPersonTagItem(
                sortOrder: index,
                person: person,
                transaction: self
            )
            personTags.append(tag)
        }
    }

    func replacePeople(_ people: [PersonItem], in modelContext: ModelContext) {
        let oldTags = personTags
        personTags.removeAll()
        for tag in oldTags {
            modelContext.delete(tag)
        }
        for (index, person) in people.enumerated() {
            let tag = TransactionPersonTagItem(
                sortOrder: index,
                person: person,
                transaction: self
            )
            personTags.append(tag)
        }
    }
}

extension EventItem {
    var status: EventStatus {
        get { EventStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }

    var isActive: Bool {
        status == .active
    }

    var isEnded: Bool {
        status == .ended
    }
}

extension TransferItem {
    var fromAccountName: String {
        fromAccount?.name.nilIfBlank ?? String(localized: "Unknown Account")
    }

    var toAccountName: String {
        toAccount?.name.nilIfBlank ?? String(localized: "Unknown Account")
    }

    var currencyCode: String {
        fromAccount?.currencyCode.nilIfBlank
            ?? toAccount?.currencyCode.nilIfBlank
            ?? "USD"
    }

    func apply(
        amountMinor: Int64,
        fromAccount: AccountItem,
        toAccount: AccountItem,
        timestamp: Date,
        note: String?
    ) {
        self.amountMinor = normalizedMinorUnits(amountMinor)
        self.fromAccount = fromAccount
        self.toAccount = toAccount
        self.timestamp = timestamp
        self.note = note?.nilIfBlank
        updatedAt = Date()
    }
}

extension RecurringRuleItem {
    var personNames: [String] {
        personTags
            .sorted { lhs, rhs in
                if lhs.sortOrder == rhs.sortOrder {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhs.sortOrder < rhs.sortOrder
            }
            .compactMap { $0.person?.name.nilIfBlank }
    }

    var personSummary: String? {
        let names = personNames
        guard !names.isEmpty else { return nil }
        return names.joined(separator: ", ")
    }

    func replacePeople(_ people: [PersonItem]) {
        personTags.removeAll()
        for (index, person) in people.enumerated() {
            let tag = RecurringRulePersonTagItem(
                sortOrder: index,
                person: person,
                recurringRule: self
            )
            personTags.append(tag)
        }
    }

    func replacePeople(_ people: [PersonItem], in modelContext: ModelContext) {
        let oldTags = personTags
        personTags.removeAll()
        for tag in oldTags {
            modelContext.delete(tag)
        }
        for (index, person) in people.enumerated() {
            let tag = RecurringRulePersonTagItem(
                sortOrder: index,
                person: person,
                recurringRule: self
            )
            personTags.append(tag)
        }
    }
}

extension AccountItem {
    func archive() {
        archived = true
        updatedAt = Date()
    }
}

extension CategoryItem {
    func archive() {
        archived = true
        updatedAt = Date()
    }
}

extension String {
    fileprivate var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private func normalizedMinorUnits(_ value: Int64) -> Int64 {
    if value == Int64.min { return Int64.max }
    return abs(value)
}
