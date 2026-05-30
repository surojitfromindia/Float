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
    var goals: [GoalDTO]
    var recurringRules: [RecurringRuleDTO]
    var budgets: [BudgetDTO]
    var settings: SettingsDTO
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
