import CryptoKit
import Foundation
import Security
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
    static var writableContentTypes: [UTType] {
        [.commaSeparatedText]
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

enum CSVTransactionService {
    @MainActor
    static func export(transactions: [TransactionItem], currencyCode: String)
        -> CSVDocument
    {
        var rows = [
            "id,timestamp,amountMinor,amountFormatted,currencyCode,isExpense,category,account,note,recurringRuleId,createdAt,updatedAt"
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
                item.categoryName,
                item.accountName,
                item.note ?? "",
                item.recurringRule?.id.uuidString ?? "",
                iso.string(from: item.createdAt),
                iso.string(from: item.updatedAt),
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
    private static let magic = Data("FLOATBAK1".utf8)
    private static let saltByteCount = 16

    static func encrypt(_ dto: FloatBackupDTO, password: String) throws
        -> BackupDocument
    {
        let payload = try JSONEncoder.floatEncoder.encode(dto)
        let salt = randomSalt()
        let key = derivedKey(password: password, salt: salt)
        let sealed = try AES.GCM.seal(payload, using: key)
        guard let combined = sealed.combined else {
            throw CocoaError(.fileWriteUnknown)
        }
        return BackupDocument(data: magic + salt + combined)
    }

    static func decrypt(_ document: BackupDocument, password: String) throws
        -> FloatBackupDTO
    {
        let data = document.data
        let key: SymmetricKey
        let combined: Data

        if data.starts(with: magic), data.count > magic.count + saltByteCount {
            let saltStart = magic.count
            let saltEnd = saltStart + saltByteCount
            let salt = data.subdata(in: saltStart..<saltEnd)
            key = derivedKey(password: password, salt: salt)
            combined = data.subdata(in: saltEnd..<data.count)
        } else {
            key = SymmetricKey(data: SHA256.hash(data: Data(password.utf8)))
            combined = data
        }

        let box = try AES.GCM.SealedBox(combined: combined)
        let decryptedData = try AES.GCM.open(box, using: key)
        return try JSONDecoder.floatDecoder.decode(
            FloatBackupDTO.self,
            from: decryptedData
        )
    }

    private static func derivedKey(password: String, salt: Data) -> SymmetricKey {
        let inputKey = SymmetricKey(data: Data(password.utf8))
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: inputKey,
            salt: salt,
            info: Data("Float backup".utf8),
            outputByteCount: 32
        )
    }

    private static func randomSalt() -> Data {
        var bytes = [UInt8](repeating: 0, count: saltByteCount)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes)
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
