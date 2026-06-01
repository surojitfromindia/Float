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
    var transactions: [TransactionDTO]
    var transactionTemplates: [TransactionTemplateDTO]
    var transfers: [TransferDTO]
    var goals: [GoalDTO]
    var recurringRules: [RecurringRuleDTO]
    var budgets: [BudgetDTO]
    var categoryBudgets: [CategoryBudgetDTO]
    var settings: SettingsDTO

    enum CodingKeys: String, CodingKey {
        case accounts
        case categories
        case transactions
        case transactionTemplates
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
        transactions: [TransactionDTO],
        transactionTemplates: [TransactionTemplateDTO] = [],
        transfers: [TransferDTO] = [],
        goals: [GoalDTO],
        recurringRules: [RecurringRuleDTO],
        budgets: [BudgetDTO],
        categoryBudgets: [CategoryBudgetDTO] = [],
        settings: SettingsDTO
    ) {
        self.accounts = accounts
        self.categories = categories
        self.transactions = transactions
        self.transactionTemplates = transactionTemplates
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
        transactions = try container.decode([TransactionDTO].self, forKey: .transactions)
        transactionTemplates = try container.decodeIfPresent([TransactionTemplateDTO].self, forKey: .transactionTemplates) ?? []
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
struct TransactionDTO: Codable {
    var id: UUID
    var amountMinor: Int64
    var isExpense: Bool
    var timestamp: Date
    var categoryID: UUID?
    var accountID: UUID?
    var note: String?
    var recurringRuleID: UUID?
    var createdAt: Date
    var updatedAt: Date
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
