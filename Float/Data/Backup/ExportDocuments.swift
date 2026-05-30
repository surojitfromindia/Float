import CryptoKit
import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let floatBackup = UTType(exportedAs: "app.float.backup")
}

struct CSVDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [.commaSeparatedText, .plainText]
    }
    var text: String

    init(text: String = "") { self.text = text }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
            let text = String(data: data, encoding: .utf8)
        else { throw CocoaError(.fileReadCorruptFile) }
        self.text = text
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
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

enum CSVTransactionService {
    static func export(transactions: [TransactionItem], currencyCode: String)
        -> CSVDocument
    {
        var rows = [
            "id,timestamp,amountMinor,amountFormatted,currencyCode,isExpense,category,account,note,recurringRuleId"
        ]
        let iso = ISO8601DateFormatter()
        for item in transactions {
            let values = [
                item.id.uuidString,
                iso.string(from: item.timestamp),
                "\(item.amountMinor)",
                MoneyFormatter.string(
                    minorUnits: item.amountMinor,
                    currencyCode: currencyCode
                ),
                currencyCode,
                "\(item.isExpense)",
                item.category?.name ?? "",
                item.account?.name ?? "",
                item.note ?? "",
                item.recurringRule?.id.uuidString ?? "",
            ].map(csvEscape)
            rows.append(values.joined(separator: ","))
        }
        return CSVDocument(text: rows.joined(separator: "\n"))
    }

    private static func csvEscape(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
}

enum BackupCryptoService {
    static func encrypt(_ dto: FloatBackupDTO, password: String) throws
        -> BackupDocument
    {
        let payload = try JSONEncoder.floatEncoder.encode(dto)
        let salt = SymmetricKey(data: SHA256.hash(data: Data(password.utf8)))
        let sealed = try AES.GCM.seal(payload, using: salt)
        guard let combined = sealed.combined else {
            throw CocoaError(.fileWriteUnknown)
        }
        return BackupDocument(data: combined)
    }

    static func decrypt(_ document: BackupDocument, password: String) throws
        -> FloatBackupDTO
    {
        let key = SymmetricKey(data: SHA256.hash(data: Data(password.utf8)))
        let box = try AES.GCM.SealedBox(combined: document.data)
        let data = try AES.GCM.open(box, using: key)
        return try JSONDecoder.floatDecoder.decode(
            FloatBackupDTO.self,
            from: data
        )
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
