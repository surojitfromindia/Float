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
    var title: String { rawValue.capitalized }
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
    var title: String { rawValue.capitalized }
}

enum BudgetCadence: String, Codable, CaseIterable, Identifiable {
    case weekly
    case monthly

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum TransactionStatus: String, Codable, CaseIterable, Identifiable {
    case posted
    case pending

    var id: String { rawValue }
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
final class TransactionItem {
    var id: UUID = UUID()
    var amountMinor: Int64 = 0
    var isExpense: Bool = true
    var statusRaw: String = TransactionStatus.posted.rawValue
    var timestamp: Date = Date()
    var expectedDueDate: Date?
    var category: CategoryItem?
    var account: AccountItem?
    var note: String?
    var recurringRule: RecurringRuleItem?
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
        note: String? = nil,
        recurringRule: RecurringRuleItem? = nil,
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
        self.note = note
        self.recurringRule = recurringRule
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

extension TransactionTemplateItem {
    var displayTitle: String {
        title.nilIfBlank ?? note?.nilIfBlank ?? category?.name ?? "Template"
    }
}

extension TransactionTemplateGroupItem {
    var displayName: String {
        name.nilIfBlank ?? "Group"
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
        if isPending { return "Pending" }
        return category?.name.nilIfBlank ?? "Unknown Category"
    }

    var accountName: String {
        if isPending { return "Not posted" }
        return account?.name.nilIfBlank ?? "Unknown Account"
    }

    var categoryIconKey: String {
        if isPending { return "clock.badge.exclamationmark.fill" }
        return category?.iconKey.nilIfBlank ?? "questionmark.circle.fill"
    }

    var categoryColorHex: String {
        if isPending { return "#6B7280" }
        return category?.colorHex.nilIfBlank ?? "#5A6B6B"
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
}

extension TransferItem {
    var fromAccountName: String {
        fromAccount?.name.nilIfBlank ?? "Unknown Account"
    }

    var toAccountName: String {
        toAccount?.name.nilIfBlank ?? "Unknown Account"
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
