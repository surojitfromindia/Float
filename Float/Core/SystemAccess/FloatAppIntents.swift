import AppIntents
import Foundation

enum FloatShortcutDestination: String, AppEnum {
    case home
    case transactions
    case household
    case calendar
    case reports
    case settings
    case budget
    case goals
    case recurring
    case templates
    case templateGroups
    case categories
    case accounts
    case people
    case settlements
    case reviewQueue

    static var typeDisplayRepresentation = TypeDisplayRepresentation(
        name: "Float Destination"
    )

    static var caseDisplayRepresentations: [FloatShortcutDestination: DisplayRepresentation] = [
        .home: "Home",
        .transactions: "Transactions",
        .household: "Household",
        .calendar: "Calendar",
        .reports: "Reports",
        .settings: "Settings",
        .budget: "Budget",
        .goals: "Goals",
        .recurring: "Recurring",
        .templates: "Templates",
        .templateGroups: "Template Groups",
        .categories: "Categories",
        .accounts: "Accounts",
        .people: "People",
        .settlements: "Settlements",
        .reviewQueue: "Review Queue",
    ]

    var destination: FloatDestination {
        FloatDestination(rawValue: rawValue) ?? .home
    }
}

enum FloatTransactionIntentDirection: String, AppEnum {
    case expense
    case income

    static var typeDisplayRepresentation = TypeDisplayRepresentation(
        name: "Transaction Direction"
    )

    static var caseDisplayRepresentations: [FloatTransactionIntentDirection: DisplayRepresentation] = [
        .expense: "Expense",
        .income: "Income",
    ]
}

enum FloatObjectIntentKind: String, AppEnum {
    case transaction
    case transfer
    case account
    case category
    case person
    case goal
    case settlement
    case template
    case recurring

    static var typeDisplayRepresentation = TypeDisplayRepresentation(
        name: "Float Object"
    )

    static var caseDisplayRepresentations: [FloatObjectIntentKind: DisplayRepresentation] = [
        .transaction: "Transaction",
        .transfer: "Transfer",
        .account: "Account",
        .category: "Category",
        .person: "Person",
        .goal: "Goal",
        .settlement: "Settlement",
        .template: "Template",
        .recurring: "Recurring Rule",
    ]

    var spotlightKind: FloatSpotlightItemKind {
        switch self {
        case .transaction: .transaction
        case .transfer: .transfer
        case .account: .account
        case .category: .category
        case .person: .people
        case .goal: .goal
        case .settlement: .settlement
        case .template: .template
        case .recurring: .recurring
        }
    }
}

struct AddFloatExpenseIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Expense"
    static var description = IntentDescription("Open Float ready to add an expense.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        PendingFloatAction.save(PendingFloatAction(kind: .addExpense))
        return .result(dialog: "Opening Float to add an expense.")
    }
}

struct AddFloatIncomeIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Income"
    static var description = IntentDescription("Open Float ready to add income.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        PendingFloatAction.save(PendingFloatAction(kind: .addIncome))
        return .result(dialog: "Opening Float to add income.")
    }
}

struct AddFloatTransferIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Transfer"
    static var description = IntentDescription("Open Float ready to move money between accounts.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        PendingFloatAction.save(PendingFloatAction(kind: .addTransfer))
        return .result(dialog: "Opening Float to add a transfer.")
    }
}

struct AddFloatTransactionAmountIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Amount Transaction"
    static var description = IntentDescription("Open Float with an expense or income amount prefilled.")
    static var openAppWhenRun = true

    @Parameter(title: "Amount")
    var amount: Double

    @Parameter(title: "Direction")
    var direction: FloatTransactionIntentDirection

    @Parameter(title: "Note")
    var note: String?

    init() {
        amount = 0
        direction = .expense
        note = nil
    }

    init(amount: Double, direction: FloatTransactionIntentDirection, note: String? = nil) {
        self.amount = amount
        self.direction = direction
        self.note = note
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let amountMinor = WidgetSnapshotReader.minorUnits(from: amount)
        PendingFloatAction.save(
            PendingFloatAction(
                kind: direction == .expense ? .addExpense : .addIncome,
                amountMinor: amountMinor,
                note: note?.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        )
        return .result(dialog: "Opening Float with the amount prefilled.")
    }
}

struct ScanFloatReceiptIntent: AppIntent {
    static var title: LocalizedStringResource = "Scan Receipt"
    static var description = IntentDescription("Open Float's on-device receipt scanner.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        PendingFloatAction.save(PendingFloatAction(kind: .scanReceipt))
        return .result(dialog: "Opening Float to scan a receipt.")
    }
}

struct OpenFloatDestinationIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Float"
    static var description = IntentDescription("Open a specific area of Float.")
    static var openAppWhenRun = true

    @Parameter(title: "Destination")
    var destination: FloatShortcutDestination

    init() {
        destination = .home
    }

    init(destination: FloatShortcutDestination) {
        self.destination = destination
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        PendingFloatAction.save(
            PendingFloatAction(
                kind: .openDestination,
                destination: destination.destination
            )
        )
        return .result(dialog: "Opening \(destination.rawValue) in Float.")
    }
}

struct GetFloatSafeToSpendIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Safe to Spend"
    static var description = IntentDescription("Read the latest safe-to-spend amount from Float.")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let summary = WidgetSnapshotReader.safeToSpendSummary()
        return .result(value: summary, dialog: IntentDialog(stringLiteral: summary))
    }
}

struct GetFloatTodaySpendIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Today's Spend"
    static var description = IntentDescription("Read today's recorded expense total from Float.")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let summary = WidgetSnapshotReader.todaySpendSummary()
        return .result(value: summary, dialog: IntentDialog(stringLiteral: summary))
    }
}

struct GetFloatBudgetAlertIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Budget Alert"
    static var description = IntentDescription("Read the highest priority budget alert from Float.")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let summary = WidgetSnapshotReader.budgetAlertSummary()
        return .result(value: summary, dialog: IntentDialog(stringLiteral: summary))
    }
}

struct OpenFloatObjectIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Float Object"
    static var description = IntentDescription("Open a specific Float object by identifier.")
    static var openAppWhenRun = true

    @Parameter(title: "Object Type")
    var objectKind: FloatObjectIntentKind

    @Parameter(title: "Identifier")
    var identifier: String

    init() {
        objectKind = .transaction
        identifier = ""
    }

    init(objectKind: FloatObjectIntentKind, identifier: String) {
        self.objectKind = objectKind
        self.identifier = identifier
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let id = UUID(uuidString: identifier.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return .result(dialog: "Float could not read that identifier.")
        }
        PendingFloatAction.save(
            PendingFloatAction(
                kind: .openSearchResult,
                spotlightItemIdentifier: FloatSpotlightItemIdentifier.make(
                    kind: objectKind.spotlightKind,
                    id: id
                )
            )
        )
        return .result(dialog: "Opening the selected Float item.")
    }
}

struct FloatShortcutsProvider: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor = .teal

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddFloatExpenseIntent(),
            phrases: [
                "Add expense in \(.applicationName)",
                "Log expense in \(.applicationName)",
            ],
            shortTitle: "Add Expense",
            systemImageName: "minus.circle.fill"
        )
        AppShortcut(
            intent: AddFloatIncomeIntent(),
            phrases: [
                "Add income in \(.applicationName)",
                "Log income in \(.applicationName)",
            ],
            shortTitle: "Add Income",
            systemImageName: "plus.circle.fill"
        )
        AppShortcut(
            intent: AddFloatTransferIntent(),
            phrases: [
                "Add transfer in \(.applicationName)",
                "Move money in \(.applicationName)",
            ],
            shortTitle: "Transfer",
            systemImageName: "arrow.left.arrow.right.circle.fill"
        )
        AppShortcut(
            intent: AddFloatTransactionAmountIntent(),
            phrases: [
                "Add amount in \(.applicationName)",
                "Log amount in \(.applicationName)",
            ],
            shortTitle: "Add Amount",
            systemImageName: "number.circle.fill"
        )
        AppShortcut(
            intent: ScanFloatReceiptIntent(),
            phrases: [
                "Scan receipt in \(.applicationName)",
                "Capture receipt in \(.applicationName)",
            ],
            shortTitle: "Scan Receipt",
            systemImageName: "doc.viewfinder.fill"
        )
        AppShortcut(
            intent: GetFloatSafeToSpendIntent(),
            phrases: [
                "What is safe to spend in \(.applicationName)",
                "Get safe to spend from \(.applicationName)",
            ],
            shortTitle: "Safe to Spend",
            systemImageName: "checkmark.seal.fill"
        )
        AppShortcut(
            intent: GetFloatTodaySpendIntent(),
            phrases: [
                "What did I spend today in \(.applicationName)",
                "Get today's spend from \(.applicationName)",
            ],
            shortTitle: "Today Spend",
            systemImageName: "calendar"
        )
        AppShortcut(
            intent: GetFloatBudgetAlertIntent(),
            phrases: [
                "Get budget alert from \(.applicationName)",
                "Check budgets in \(.applicationName)",
            ],
            shortTitle: "Budget Alert",
            systemImageName: "exclamationmark.triangle.fill"
        )
        AppShortcut(
            intent: OpenFloatDestinationIntent(destination: .reviewQueue),
            phrases: [
                "Open review queue in \(.applicationName)",
                "Review transactions in \(.applicationName)",
            ],
            shortTitle: "Review Queue",
            systemImageName: "checklist"
        )
    }
}

private enum WidgetSnapshotReader {
    private struct Snapshot: Codable {
        let safeToSpendMinor: Int64
        let dailyAllowanceMinor: Int64
        let daysRemaining: Int
        let statusText: String
        let currencyCode: String
        let todayExpensesMinor: Int64?
        let topBudgetAlertTitle: String?
        let topBudgetAlertProgress: Double?
    }

    static func safeToSpendSummary() -> String {
        guard let snapshot = snapshot() else {
            return String(localized: "Open Float to update safe to spend.")
        }

        let safe = MoneyFormatter.string(
            minorUnits: snapshot.safeToSpendMinor,
            currencyCode: snapshot.currencyCode
        )
        let daily = MoneyFormatter.string(
            minorUnits: snapshot.dailyAllowanceMinor,
            currencyCode: snapshot.currencyCode
        )
        return String(
            localized: "\(safe) safe to spend, \(daily) per day, \(snapshot.daysRemaining) days left. \(snapshot.statusText)."
        )
    }

    static func todaySpendSummary() -> String {
        guard let snapshot = snapshot() else {
            return String(localized: "Open Float to update today's spend.")
        }
        let amount = MoneyFormatter.string(
            minorUnits: snapshot.todayExpensesMinor ?? 0,
            currencyCode: snapshot.currencyCode
        )
        return String(localized: "\(amount) spent today.")
    }

    static func budgetAlertSummary() -> String {
        guard let snapshot = snapshot() else {
            return String(localized: "Open Float to update budget alerts.")
        }
        guard let title = snapshot.topBudgetAlertTitle, !title.isEmpty else {
            return String(localized: "No budget alerts right now.")
        }
        if let progress = snapshot.topBudgetAlertProgress {
            return String(localized: "\(title) is at \(Int((progress * 100).rounded()))%.")
        }
        return title
    }

    static func minorUnits(from amount: Double) -> Int64 {
        let currencyCode = snapshot()?.currencyCode
            ?? Locale.current.currency?.identifier
            ?? "USD"
        let multiplier = pow(10.0, Double(MoneyFormatter.fractionDigits(for: currencyCode)))
        return max(0, Int64((amount * multiplier).rounded()))
    }

    private static func snapshot() -> Snapshot? {
        guard
            let defaults = UserDefaults(suiteName: PendingFloatAction.appGroupIdentifier),
            let data = defaults.data(forKey: "float.safeToSpend.widgetSnapshot")
        else {
            return nil
        }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }
}
