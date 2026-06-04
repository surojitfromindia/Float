import AppIntents
import Foundation

enum FloatShortcutDestination: String, AppEnum {
    case home
    case transactions
    case calendar
    case reports
    case settings
    case budget
    case goals
    case recurring
    case templates
    case categories
    case accounts
    case reviewQueue

    static var typeDisplayRepresentation = TypeDisplayRepresentation(
        name: "Float Destination"
    )

    static var caseDisplayRepresentations: [FloatShortcutDestination: DisplayRepresentation] = [
        .home: "Home",
        .transactions: "Transactions",
        .calendar: "Calendar",
        .reports: "Reports",
        .settings: "Settings",
        .budget: "Budget",
        .goals: "Goals",
        .recurring: "Recurring",
        .templates: "Templates",
        .categories: "Categories",
        .accounts: "Accounts",
        .reviewQueue: "Review Queue",
    ]

    var destination: FloatDestination {
        FloatDestination(rawValue: rawValue) ?? .home
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
            intent: GetFloatSafeToSpendIntent(),
            phrases: [
                "What is safe to spend in \(.applicationName)",
                "Get safe to spend from \(.applicationName)",
            ],
            shortTitle: "Safe to Spend",
            systemImageName: "checkmark.seal.fill"
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
    }

    static func safeToSpendSummary() -> String {
        guard
            let defaults = UserDefaults(suiteName: PendingFloatAction.appGroupIdentifier),
            let data = defaults.data(forKey: "float.safeToSpend.widgetSnapshot"),
            let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data)
        else {
            return "Open Float to update safe to spend."
        }

        let safe = MoneyFormatter.string(
            minorUnits: snapshot.safeToSpendMinor,
            currencyCode: snapshot.currencyCode
        )
        let daily = MoneyFormatter.string(
            minorUnits: snapshot.dailyAllowanceMinor,
            currencyCode: snapshot.currencyCode
        )
        return "\(safe) safe to spend, \(daily) per day, \(snapshot.daysRemaining) days left. \(snapshot.statusText)."
    }
}
