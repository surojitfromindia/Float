import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let floatBackup = UTType(exportedAs: "app.float.backup")
}

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.floatBackup] }
    var data: Data

    init(data: Data = Data()) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct FloatBackupDTO: Codable {
    var accounts: [AccountDTO]
    var categories: [CategoryDTO]
    var eventCategories: [EventCategoryDTO]
    var events: [EventDTO]
    var transactions: [TransactionDTO]
    var transactionTemplates: [TransactionTemplateDTO]
    var transactionTemplateGroups: [TransactionTemplateGroupDTO]
    var transfers: [TransferDTO]
    var goals: [GoalDTO]
    var recurringRules: [RecurringRuleDTO]
    var budgets: [BudgetDTO]
    var categoryBudgets: [CategoryBudgetDTO]
    var settings: SettingsDTO

    enum CodingKeys: String, CodingKey {
        case accounts
        case categories
        case eventCategories
        case events
        case transactions
        case transactionTemplates
        case transactionTemplateGroups
        case transfers
        case goals
        case recurringRules
        case budgets
        case categoryBudgets
        case settings
    }

    init(
        accounts: [AccountDTO],
        categories: [CategoryDTO],
        eventCategories: [EventCategoryDTO] = [],
        events: [EventDTO] = [],
        transactions: [TransactionDTO],
        transactionTemplates: [TransactionTemplateDTO] = [],
        transactionTemplateGroups: [TransactionTemplateGroupDTO] = [],
        transfers: [TransferDTO] = [],
        goals: [GoalDTO],
        recurringRules: [RecurringRuleDTO],
        budgets: [BudgetDTO],
        categoryBudgets: [CategoryBudgetDTO] = [],
        settings: SettingsDTO
    ) {
        self.accounts = accounts
        self.categories = categories
        self.eventCategories = eventCategories
        self.events = events
        self.transactions = transactions
        self.transactionTemplates = transactionTemplates
        self.transactionTemplateGroups = transactionTemplateGroups
        self.transfers = transfers
        self.goals = goals
        self.recurringRules = recurringRules
        self.budgets = budgets
        self.categoryBudgets = categoryBudgets
        self.settings = settings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accounts = try container.decode([AccountDTO].self, forKey: .accounts)
        categories = try container.decode([CategoryDTO].self, forKey: .categories)
        eventCategories = try container.decodeIfPresent([EventCategoryDTO].self, forKey: .eventCategories) ?? []
        events = try container.decodeIfPresent([EventDTO].self, forKey: .events) ?? []
        transactions = try container.decode([TransactionDTO].self, forKey: .transactions)
        transactionTemplates = try container.decodeIfPresent([TransactionTemplateDTO].self, forKey: .transactionTemplates) ?? []
        transactionTemplateGroups = try container.decodeIfPresent([TransactionTemplateGroupDTO].self, forKey: .transactionTemplateGroups) ?? []
        transfers = try container.decodeIfPresent([TransferDTO].self, forKey: .transfers) ?? []
        goals = try container.decode([GoalDTO].self, forKey: .goals)
        recurringRules = try container.decode([RecurringRuleDTO].self, forKey: .recurringRules)
        budgets = try container.decode([BudgetDTO].self, forKey: .budgets)
        categoryBudgets = try container.decodeIfPresent([CategoryBudgetDTO].self, forKey: .categoryBudgets) ?? []
        settings = try container.decode(SettingsDTO.self, forKey: .settings)
    }
}

struct AccountDTO: Codable {
    var id: UUID
    var name: String
    var type: AccountType
    var openingBalanceMinor: Int64
    var currencyCode: String
    var archived: Bool
    var createdAt: Date
    var updatedAt: Date
}
struct CategoryDTO: Codable {
    var id: UUID
    var name: String
    var iconKey: String
    var colorHex: String
    var isIncome: Bool
    var sortOrder: Int
    var archived: Bool
    var isDefault: Bool
    var createdAt: Date?
    var updatedAt: Date?
}
struct EventCategoryDTO: Codable {
    var id: UUID
    var name: String
    var iconKey: String
    var colorHex: String
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date
}
struct EventDTO: Codable {
    var id: UUID
    var name: String
    var startDate: Date
    var endDate: Date
    var statusRaw: String
    var eventDescription: String?
    var pinned: Bool
    var categoryID: UUID?
    var createdAt: Date
    var updatedAt: Date
}
struct TransactionDTO: Codable {
    var id: UUID
    var amountMinor: Int64
    var isExpense: Bool
    var statusRaw: String
    var timestamp: Date
    var expectedDueDate: Date?
    var categoryID: UUID?
    var accountID: UUID?
    var eventID: UUID?
    var note: String?
    var recurringRuleID: UUID?
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case amountMinor
        case isExpense
        case statusRaw
        case timestamp
        case expectedDueDate
        case categoryID
        case accountID
        case eventID
        case note
        case recurringRuleID
        case createdAt
        case updatedAt
    }

    init(
        id: UUID,
        amountMinor: Int64,
        isExpense: Bool,
        statusRaw: String = TransactionStatus.posted.rawValue,
        timestamp: Date,
        expectedDueDate: Date? = nil,
        categoryID: UUID?,
        accountID: UUID?,
        eventID: UUID? = nil,
        note: String?,
        recurringRuleID: UUID?,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.amountMinor = amountMinor
        self.isExpense = isExpense
        self.statusRaw = statusRaw
        self.timestamp = timestamp
        self.expectedDueDate = expectedDueDate
        self.categoryID = categoryID
        self.accountID = accountID
        self.eventID = eventID
        self.note = note
        self.recurringRuleID = recurringRuleID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        amountMinor = try container.decode(Int64.self, forKey: .amountMinor)
        isExpense = try container.decode(Bool.self, forKey: .isExpense)
        statusRaw = try container.decodeIfPresent(String.self, forKey: .statusRaw)
            ?? TransactionStatus.posted.rawValue
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        expectedDueDate = try container.decodeIfPresent(Date.self, forKey: .expectedDueDate)
        categoryID = try container.decodeIfPresent(UUID.self, forKey: .categoryID)
        accountID = try container.decodeIfPresent(UUID.self, forKey: .accountID)
        eventID = try container.decodeIfPresent(UUID.self, forKey: .eventID)
        note = try container.decodeIfPresent(String.self, forKey: .note)
        recurringRuleID = try container.decodeIfPresent(UUID.self, forKey: .recurringRuleID)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}
struct TransactionTemplateDTO: Codable {
    var id: UUID
    var title: String
    var amountMinor: Int64
    var isExpense: Bool
    var categoryID: UUID?
    var accountID: UUID?
    var note: String?
    var createdAt: Date
    var updatedAt: Date
}
struct TransactionTemplateGroupDTO: Codable {
    var id: UUID
    var name: String
    var entries: [TransactionTemplateGroupEntryDTO]
    var createdAt: Date
    var updatedAt: Date
}
struct TransactionTemplateGroupEntryDTO: Codable {
    var id: UUID
    var templateID: UUID?
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date
}
struct TransferDTO: Codable {
    var id: UUID
    var amountMinor: Int64
    var fromAccountID: UUID?
    var toAccountID: UUID?
    var timestamp: Date
    var note: String?
    var createdAt: Date
    var updatedAt: Date
}
struct GoalDTO: Codable {
    var id: UUID
    var name: String
    var targetMinor: Int64
    var savedMinor: Int64
    var targetDate: Date?
    var colorHex: String
    var achieved: Bool
    var createdAt: Date
    var updatedAt: Date
}
struct RecurringRuleDTO: Codable {
    var id: UUID
    var amountMinor: Int64
    var isExpense: Bool
    var categoryID: UUID?
    var accountID: UUID?
    var note: String?
    var cadence: RecurringCadence
    var intervalCount: Int
    var nextRunDate: Date
    var endDate: Date?
    var active: Bool
    var createdAt: Date
    var updatedAt: Date
}
struct BudgetDTO: Codable {
    var id: UUID
    var cadence: BudgetCadence
    var startDayOfMonth: Int?
    var startDayOfWeek: Int?
    var expectedIncomeMinor: Int64
    var currencyCode: String
    var isActive: Bool
    var createdAt: Date
    var updatedAt: Date
}
struct CategoryBudgetDTO: Codable {
    var id: UUID
    var categoryID: UUID?
    var amountMinor: Int64
    var currencyCode: String
    var isActive: Bool
    var createdAt: Date
    var updatedAt: Date
}
struct SettingsDTO: Codable {
    var currencyCode: String
    var exportedAt: Date
}

enum BackupArchiveService {
    static func document(from dto: FloatBackupDTO) throws -> BackupDocument {
        let data = try JSONEncoder.floatEncoder.encode(dto)
        return BackupDocument(data: data)
    }

    static func dto(from document: BackupDocument) throws -> FloatBackupDTO {
        try JSONDecoder.floatDecoder.decode(FloatBackupDTO.self, from: document.data)
    }
}

extension JSONEncoder {
    static var floatEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    static var floatDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
