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
    var people: [PersonDTO]
    var eventCategories: [EventCategoryDTO]
    var events: [EventDTO]
    var transactions: [TransactionDTO]
    var transactionPersonTags: [TransactionPersonTagDTO]
    var transactionTemplates: [TransactionTemplateDTO]
    var transactionTemplateGroups: [TransactionTemplateGroupDTO]
    var transfers: [TransferDTO]
    var goals: [GoalDTO]
    var recurringRules: [RecurringRuleDTO]
    var recurringRulePersonTags: [RecurringRulePersonTagDTO]
    var budgets: [BudgetDTO]
    var categoryBudgets: [CategoryBudgetDTO]
    var scenarioPlans: [ScenarioPlanDTO]
    var settlementCases: [SettlementCaseDTO]
    var settlementEntries: [SettlementEntryDTO]
    var settlementMilestones: [SettlementMilestoneDTO]
    var receiptCaptures: [ReceiptCaptureDTO]
    var receiptLineItems: [ReceiptLineDTO]
    var attachments: [AttachmentDTO]
    var householdMembers: [HouseholdMemberDTO]
    var householdExpenses: [HouseholdExpenseDTO]
    var householdExpenseSplits: [HouseholdExpenseSplitDTO]
    var householdBills: [HouseholdBillDTO]
    var householdAllowances: [HouseholdAllowanceDTO]
    var settings: SettingsDTO

    enum CodingKeys: String, CodingKey {
        case accounts
        case categories
        case people
        case eventCategories
        case events
        case transactions
        case transactionPersonTags
        case transactionTemplates
        case transactionTemplateGroups
        case transfers
        case goals
        case recurringRules
        case recurringRulePersonTags
        case budgets
        case categoryBudgets
        case scenarioPlans
        case settlementCases
        case settlementEntries
        case settlementMilestones
        case receiptCaptures
        case receiptLineItems
        case attachments
        case householdMembers
        case householdExpenses
        case householdExpenseSplits
        case householdBills
        case householdAllowances
        case settings
    }

    init(
        accounts: [AccountDTO],
        categories: [CategoryDTO],
        people: [PersonDTO] = [],
        eventCategories: [EventCategoryDTO] = [],
        events: [EventDTO] = [],
        transactions: [TransactionDTO],
        transactionPersonTags: [TransactionPersonTagDTO] = [],
        transactionTemplates: [TransactionTemplateDTO] = [],
        transactionTemplateGroups: [TransactionTemplateGroupDTO] = [],
        transfers: [TransferDTO] = [],
        goals: [GoalDTO],
        recurringRules: [RecurringRuleDTO],
        recurringRulePersonTags: [RecurringRulePersonTagDTO] = [],
        budgets: [BudgetDTO],
        categoryBudgets: [CategoryBudgetDTO] = [],
        scenarioPlans: [ScenarioPlanDTO] = [],
        settlementCases: [SettlementCaseDTO] = [],
        settlementEntries: [SettlementEntryDTO] = [],
        settlementMilestones: [SettlementMilestoneDTO] = [],
        receiptCaptures: [ReceiptCaptureDTO] = [],
        receiptLineItems: [ReceiptLineDTO] = [],
        attachments: [AttachmentDTO] = [],
        householdMembers: [HouseholdMemberDTO] = [],
        householdExpenses: [HouseholdExpenseDTO] = [],
        householdExpenseSplits: [HouseholdExpenseSplitDTO] = [],
        householdBills: [HouseholdBillDTO] = [],
        householdAllowances: [HouseholdAllowanceDTO] = [],
        settings: SettingsDTO
    ) {
        self.accounts = accounts
        self.categories = categories
        self.people = people
        self.eventCategories = eventCategories
        self.events = events
        self.transactions = transactions
        self.transactionPersonTags = transactionPersonTags
        self.transactionTemplates = transactionTemplates
        self.transactionTemplateGroups = transactionTemplateGroups
        self.transfers = transfers
        self.goals = goals
        self.recurringRules = recurringRules
        self.recurringRulePersonTags = recurringRulePersonTags
        self.budgets = budgets
        self.categoryBudgets = categoryBudgets
        self.scenarioPlans = scenarioPlans
        self.settlementCases = settlementCases
        self.settlementEntries = settlementEntries
        self.settlementMilestones = settlementMilestones
        self.receiptCaptures = receiptCaptures
        self.receiptLineItems = receiptLineItems
        self.attachments = attachments
        self.householdMembers = householdMembers
        self.householdExpenses = householdExpenses
        self.householdExpenseSplits = householdExpenseSplits
        self.householdBills = householdBills
        self.householdAllowances = householdAllowances
        self.settings = settings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accounts = try container.decode([AccountDTO].self, forKey: .accounts)
        categories = try container.decode([CategoryDTO].self, forKey: .categories)
        people = try container.decodeIfPresent([PersonDTO].self, forKey: .people) ?? []
        eventCategories = try container.decodeIfPresent([EventCategoryDTO].self, forKey: .eventCategories) ?? []
        events = try container.decodeIfPresent([EventDTO].self, forKey: .events) ?? []
        transactions = try container.decode([TransactionDTO].self, forKey: .transactions)
        transactionPersonTags = try container.decodeIfPresent([TransactionPersonTagDTO].self, forKey: .transactionPersonTags) ?? []
        transactionTemplates = try container.decodeIfPresent([TransactionTemplateDTO].self, forKey: .transactionTemplates) ?? []
        transactionTemplateGroups = try container.decodeIfPresent([TransactionTemplateGroupDTO].self, forKey: .transactionTemplateGroups) ?? []
        transfers = try container.decodeIfPresent([TransferDTO].self, forKey: .transfers) ?? []
        goals = try container.decode([GoalDTO].self, forKey: .goals)
        recurringRules = try container.decode([RecurringRuleDTO].self, forKey: .recurringRules)
        recurringRulePersonTags = try container.decodeIfPresent([RecurringRulePersonTagDTO].self, forKey: .recurringRulePersonTags) ?? []
        budgets = try container.decode([BudgetDTO].self, forKey: .budgets)
        categoryBudgets = try container.decodeIfPresent([CategoryBudgetDTO].self, forKey: .categoryBudgets) ?? []
        scenarioPlans = try container.decodeIfPresent([ScenarioPlanDTO].self, forKey: .scenarioPlans) ?? []
        settlementCases = try container.decodeIfPresent([SettlementCaseDTO].self, forKey: .settlementCases) ?? []
        settlementEntries = try container.decodeIfPresent([SettlementEntryDTO].self, forKey: .settlementEntries) ?? []
        settlementMilestones = try container.decodeIfPresent([SettlementMilestoneDTO].self, forKey: .settlementMilestones) ?? []
        receiptCaptures = try container.decodeIfPresent([ReceiptCaptureDTO].self, forKey: .receiptCaptures) ?? []
        receiptLineItems = try container.decodeIfPresent([ReceiptLineDTO].self, forKey: .receiptLineItems) ?? []
        attachments = try container.decodeIfPresent([AttachmentDTO].self, forKey: .attachments) ?? []
        householdMembers = try container.decodeIfPresent([HouseholdMemberDTO].self, forKey: .householdMembers) ?? []
        householdExpenses = try container.decodeIfPresent([HouseholdExpenseDTO].self, forKey: .householdExpenses) ?? []
        householdExpenseSplits = try container.decodeIfPresent([HouseholdExpenseSplitDTO].self, forKey: .householdExpenseSplits) ?? []
        householdBills = try container.decodeIfPresent([HouseholdBillDTO].self, forKey: .householdBills) ?? []
        householdAllowances = try container.decodeIfPresent([HouseholdAllowanceDTO].self, forKey: .householdAllowances) ?? []
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
struct PersonDTO: Codable {
    var id: UUID
    var name: String
    var alias: String?
    var note: String?
    var colorHex: String
    var archived: Bool
    var transactionCount: Int
    var recurringRuleCount: Int
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case alias
        case note
        case colorHex
        case archived
        case transactionCount
        case recurringRuleCount
        case createdAt
        case updatedAt
    }

    init(
        id: UUID,
        name: String,
        alias: String?,
        note: String?,
        colorHex: String,
        archived: Bool,
        transactionCount: Int = 0,
        recurringRuleCount: Int = 0,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.name = name
        self.alias = alias
        self.note = note
        self.colorHex = colorHex
        self.archived = archived
        self.transactionCount = transactionCount
        self.recurringRuleCount = recurringRuleCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        alias = try container.decodeIfPresent(String.self, forKey: .alias)
        note = try container.decodeIfPresent(String.self, forKey: .note)
        colorHex = try container.decode(String.self, forKey: .colorHex)
        archived = try container.decode(Bool.self, forKey: .archived)
        transactionCount = try container.decodeIfPresent(Int.self, forKey: .transactionCount) ?? 0
        recurringRuleCount = try container.decodeIfPresent(Int.self, forKey: .recurringRuleCount) ?? 0
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}
struct SettlementCaseDTO: Codable {
    var id: UUID
    var title: String
    var counterpartyName: String?
    var directionRaw: String
    var currencyCode: String
    var note: String?
    var personID: UUID?
    var dueDate: Date?
    var closedAt: Date?
    var archived: Bool
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case counterpartyName
        case directionRaw
        case currencyCode
        case note
        case personID
        case dueDate
        case closedAt
        case archived
        case createdAt
        case updatedAt
    }

    init(
        id: UUID,
        title: String,
        counterpartyName: String?,
        directionRaw: String,
        currencyCode: String,
        note: String?,
        personID: UUID?,
        dueDate: Date? = nil,
        closedAt: Date? = nil,
        archived: Bool = false,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.title = title
        self.counterpartyName = counterpartyName
        self.directionRaw = directionRaw
        self.currencyCode = currencyCode
        self.note = note
        self.personID = personID
        self.dueDate = dueDate
        self.closedAt = closedAt
        self.archived = archived
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        counterpartyName = try container.decodeIfPresent(String.self, forKey: .counterpartyName)
        directionRaw = try container.decode(String.self, forKey: .directionRaw)
        currencyCode = try container.decode(String.self, forKey: .currencyCode)
        note = try container.decodeIfPresent(String.self, forKey: .note)
        personID = try container.decodeIfPresent(UUID.self, forKey: .personID)
        dueDate = try container.decodeIfPresent(Date.self, forKey: .dueDate)
        closedAt = try container.decodeIfPresent(Date.self, forKey: .closedAt)
        archived = try container.decodeIfPresent(Bool.self, forKey: .archived) ?? false
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}
struct SettlementEntryDTO: Codable {
    var id: UUID
    var kindRaw: String
    var amountMinor: Int64
    var entryDate: Date
    var note: String?
    var reference: String?
    var caseID: UUID?
    var linkedTransactionID: UUID?
    var createdAt: Date
    var updatedAt: Date
}
struct SettlementMilestoneDTO: Codable {
    var id: UUID
    var title: String
    var amountMinor: Int64
    var dueDate: Date
    var note: String?
    var statusRaw: String
    var caseID: UUID?
    var linkedEntryID: UUID?
    var createdAt: Date
    var updatedAt: Date
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
    var receiptCaptureID: UUID?
    var dismissedReviewKindsRaw: String?
    var dismissedDuplicateGroupSignatureRaw: String?
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
        case receiptCaptureID
        case dismissedReviewKindsRaw
        case dismissedDuplicateGroupSignatureRaw
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
        receiptCaptureID: UUID? = nil,
        dismissedReviewKindsRaw: String? = nil,
        dismissedDuplicateGroupSignatureRaw: String? = nil,
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
        self.receiptCaptureID = receiptCaptureID
        self.dismissedReviewKindsRaw = dismissedReviewKindsRaw
        self.dismissedDuplicateGroupSignatureRaw = dismissedDuplicateGroupSignatureRaw
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
        receiptCaptureID = try container.decodeIfPresent(UUID.self, forKey: .receiptCaptureID)
        dismissedReviewKindsRaw = try container.decodeIfPresent(
            String.self,
            forKey: .dismissedReviewKindsRaw
        )
        dismissedDuplicateGroupSignatureRaw = try container.decodeIfPresent(
            String.self,
            forKey: .dismissedDuplicateGroupSignatureRaw
        )
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}
struct TransactionPersonTagDTO: Codable {
    var id: UUID
    var sortOrder: Int
    var allocatedMinor: Int64?
    var settledMinor: Int64
    var personID: UUID?
    var transactionID: UUID?
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
struct RecurringRulePersonTagDTO: Codable {
    var id: UUID
    var sortOrder: Int
    var personID: UUID?
    var recurringRuleID: UUID?
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
struct ScenarioPlanDTO: Codable {
    var id: UUID
    var title: String
    var amountMinor: Int64
    var isExpense: Bool
    var plannedDate: Date
    var recurrenceRaw: String
    var occurrenceCount: Int
    var categoryID: UUID?
    var accountID: UUID?
    var note: String?
    var archived: Bool
    var createdAt: Date
    var updatedAt: Date
}
struct ReceiptCaptureDTO: Codable {
    var id: UUID
    var merchantName: String
    var transactionDate: Date
    var totalAmountMinor: Int64
    var currencyCode: String
    var rawText: String
    var createdAt: Date
    var updatedAt: Date
}
struct ReceiptLineDTO: Codable {
    var id: UUID
    var sortOrder: Int
    var title: String
    var quantityText: String?
    var amountMinor: Int64
    var selectedForImport: Bool
    var receiptID: UUID?
    var categoryID: UUID?
    var accountID: UUID?
    var transactionID: UUID?
    var duplicateTransactionID: UUID?
    var createdAt: Date
    var updatedAt: Date
}
struct AttachmentDTO: Codable {
    var id: UUID
    var kindRaw: String
    var fileName: String
    var mimeType: String
    var data: Data
    var receiptID: UUID?
    var createdAt: Date
    var updatedAt: Date
}
struct HouseholdMemberDTO: Codable {
    var id: UUID
    var displayName: String
    var roleRaw: String
    var colorHex: String
    var monthlyAllowanceMinor: Int64
    var personID: UUID?
    var archived: Bool
    var createdAt: Date
    var updatedAt: Date
}
struct HouseholdExpenseDTO: Codable {
    var id: UUID
    var title: String
    var amountMinor: Int64
    var currencyCode: String
    var expenseDate: Date
    var splitMethodRaw: String
    var approvalStatusRaw: String
    var reimbursementRequired: Bool
    var note: String?
    var payerID: UUID?
    var categoryID: UUID?
    var accountID: UUID?
    var transactionID: UUID?
    var receiptCaptureID: UUID?
    var approvedAt: Date?
    var rejectedAt: Date?
    var settledAt: Date?
    var createdAt: Date
    var updatedAt: Date
}
struct HouseholdExpenseSplitDTO: Codable {
    var id: UUID
    var sortOrder: Int
    var amountMinor: Int64
    var reimbursedMinor: Int64
    var memberID: UUID?
    var expenseID: UUID?
    var createdAt: Date
    var updatedAt: Date
}
struct HouseholdBillDTO: Codable {
    var id: UUID
    var title: String
    var amountMinor: Int64
    var currencyCode: String
    var dueDate: Date
    var cadence: RecurringCadence
    var payerID: UUID?
    var categoryID: UUID?
    var accountID: UUID?
    var active: Bool
    var autoCreateApproval: Bool
    var note: String?
    var createdAt: Date
    var updatedAt: Date
}
struct HouseholdAllowanceDTO: Codable {
    var id: UUID
    var memberID: UUID?
    var periodStart: Date
    var periodEnd: Date
    var allowanceMinor: Int64
    var spentMinor: Int64
    var currencyCode: String
    var note: String?
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
