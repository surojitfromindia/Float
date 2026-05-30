import Foundation
import SwiftData

enum AccountType: String, Codable, CaseIterable, Identifiable {
    case cash
    case bank
    case card
    case wallet

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

@Model
final class AccountItem {
    @Attribute(.unique) var id: UUID
    var name: String
    var type: AccountType
    var openingBalanceMinor: Int64
    var currencyCode: String
    var archived: Bool
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), name: String, type: AccountType = .cash, openingBalanceMinor: Int64 = 0, currencyCode: String, archived: Bool = false, createdAt: Date = Date(), updatedAt: Date = Date()) {
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
    @Attribute(.unique) var id: UUID
    var name: String
    var iconKey: String
    var colorHex: String
    var isIncome: Bool
    var sortOrder: Int
    var archived: Bool
    var isDefault: Bool

    init(id: UUID = UUID(), name: String, iconKey: String, colorHex: String, isIncome: Bool = false, sortOrder: Int = 0, archived: Bool = false, isDefault: Bool = false) {
        self.id = id
        self.name = name
        self.iconKey = iconKey
        self.colorHex = colorHex
        self.isIncome = isIncome
        self.sortOrder = sortOrder
        self.archived = archived
        self.isDefault = isDefault
    }
}

@Model
final class TransactionItem {
    @Attribute(.unique) var id: UUID
    var amountMinor: Int64
    var isExpense: Bool
    var timestamp: Date
    var category: CategoryItem?
    var account: AccountItem?
    var note: String?
    var recurringRule: RecurringRuleItem?
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), amountMinor: Int64, isExpense: Bool = true, timestamp: Date = Date(), category: CategoryItem? = nil, account: AccountItem? = nil, note: String? = nil, recurringRule: RecurringRuleItem? = nil, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.amountMinor = max(0, amountMinor)
        self.isExpense = isExpense
        self.timestamp = timestamp
        self.category = category
        self.account = account
        self.note = note
        self.recurringRule = recurringRule
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class RecurringRuleItem {
    @Attribute(.unique) var id: UUID
    var amountMinor: Int64
    var isExpense: Bool
    var category: CategoryItem?
    var account: AccountItem?
    var note: String?
    var cadence: RecurringCadence
    var intervalCount: Int
    var nextRunDate: Date
    var endDate: Date?
    var active: Bool
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), amountMinor: Int64, isExpense: Bool = true, category: CategoryItem? = nil, account: AccountItem? = nil, note: String? = nil, cadence: RecurringCadence = .monthly, intervalCount: Int = 1, nextRunDate: Date = Date(), endDate: Date? = nil, active: Bool = true, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.amountMinor = max(0, amountMinor)
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
    @Attribute(.unique) var id: UUID
    var name: String
    var targetMinor: Int64
    var savedMinor: Int64
    var targetDate: Date?
    var colorHex: String
    var achieved: Bool
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), name: String, targetMinor: Int64, savedMinor: Int64 = 0, targetDate: Date? = nil, colorHex: String = "#0E7C7B", achieved: Bool = false, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.targetMinor = max(0, targetMinor)
        self.savedMinor = max(0, savedMinor)
        self.targetDate = targetDate
        self.colorHex = colorHex
        self.achieved = achieved
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class BudgetPeriodItem {
    @Attribute(.unique) var id: UUID
    var cadence: BudgetCadence
    var startDayOfMonth: Int?
    var startDayOfWeek: Int?
    var expectedIncomeMinor: Int64
    var currencyCode: String
    var isActive: Bool
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), cadence: BudgetCadence = .monthly, startDayOfMonth: Int? = 1, startDayOfWeek: Int? = nil, expectedIncomeMinor: Int64 = 0, currencyCode: String, isActive: Bool = true, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.cadence = cadence
        self.startDayOfMonth = startDayOfMonth
        self.startDayOfWeek = startDayOfWeek
        self.expectedIncomeMinor = max(0, expectedIncomeMinor)
        self.currencyCode = currencyCode
        self.isActive = isActive
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
