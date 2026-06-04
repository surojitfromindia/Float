import Combine
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case en
    case es
    case hi
    case bn

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .system: "Use device language"
        case .en: "English"
        case .es: "Spanish"
        case .hi: "Hindi"
        case .bn: "Bengali"
        }
    }

    var locale: Locale {
        switch self {
        case .system:
            Locale.autoupdatingCurrent
        default:
            Locale(identifier: rawValue)
        }
    }
}

enum FloatTab: Hashable {
    case home
    case transactions
    case calendar
    case insights
    case settings
}

enum FloatSettingsDestination: String, Hashable, Identifiable {
    case budget
    case goals
    case recurring
    case templates
    case categories
    case accounts
    case reviewQueue

    var id: String { rawValue }
}

enum BudgetAlertSensitivity: String, CaseIterable, Identifiable {
    case off
    case urgentOnly
    case closeAndOver
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: "Off"
        case .urgentOnly: "Over budget only"
        case .closeAndOver: "Close and over"
        case .all: "All alerts"
        }
    }
}

struct FloatReminderPreferences {
    var recurringEnabled: Bool
    var budgetEnabled: Bool
    var goalsEnabled: Bool
    var recurringReminderMinutes: Int
    var goalReminderMinutes: Int
    var budgetAlertSensitivity: BudgetAlertSensitivity
}

@MainActor
final class AppState: ObservableObject {
    // User preferences persisted across app launches.
    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding = false
    @AppStorage("selectedCurrencyCode") var selectedCurrencyCode =
        MoneyFormatter.currencyCodeFromLocale()
    @AppStorage("selectedAppearance") var selectedAppearance = "system"
    @AppStorage("selectedThemeMode") var selectedThemeMode = "float"
    @AppStorage("selectedLanguageCode") var selectedLanguageCode = "system"
    @AppStorage("lastUsedCategoryID") var lastUsedCategoryID = ""
    @AppStorage("lastUsedAccountID") var lastUsedAccountID = ""
    @AppStorage("isAppLockEnabled") var isAppLockEnabled = false
    @AppStorage("recurringRemindersEnabled") var recurringRemindersEnabled = true
    @AppStorage("budgetAlertsEnabled") var budgetAlertsEnabled = true
    @AppStorage("goalRemindersEnabled") var goalRemindersEnabled = true
    @AppStorage("recurringReminderMinutes") var recurringReminderMinutes = 9 * 60
    @AppStorage("goalReminderMinutes") var goalReminderMinutes = 9 * 60 + 30
    @AppStorage("budgetAlertSensitivity") var budgetAlertSensitivityRaw =
        BudgetAlertSensitivity.closeAndOver.rawValue

    @Published var selectedTab: FloatTab = .home
    @Published var pendingSettingsDestination: FloatSettingsDestination?
    // Controls the shared transaction entry sheet and whether it opens in create or edit mode.
    @Published var isEntrySheetPresented = false
    @Published var editingTransaction: TransactionItem?
    @Published var newTransactionTimestamp: Date?
    @Published var newTransactionIsExpense: Bool?
    @Published var isTransferSheetPresented = false
    @Published var editingTransfer: TransferItem?
    @Published var newTransferTimestamp: Date?

    // Converts the stored appearance preference into the optional SwiftUI color scheme override.
    var colorScheme: ColorScheme? {
        switch selectedAppearance {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }

    var themePalette: FloatThemePalette {
        FloatTheme.palette(for: selectedThemeMode)
    }

    var selectedLanguage: AppLanguage {
        AppLanguage(rawValue: selectedLanguageCode) ?? .system
    }

    var reminderPreferences: FloatReminderPreferences {
        FloatReminderPreferences(
            recurringEnabled: recurringRemindersEnabled,
            budgetEnabled: budgetAlertsEnabled,
            goalsEnabled: goalRemindersEnabled,
            recurringReminderMinutes: recurringReminderMinutes,
            goalReminderMinutes: goalReminderMinutes,
            budgetAlertSensitivity: BudgetAlertSensitivity(rawValue: budgetAlertSensitivityRaw)
                ?? .closeAndOver
        )
    }

    // Opens the entry sheet with empty state for a new transaction.
    func presentNewTransaction(timestamp: Date? = nil, isExpense: Bool? = nil) {
        editingTransaction = nil
        newTransactionTimestamp = timestamp
        newTransactionIsExpense = isExpense
        isEntrySheetPresented = true
    }

    // Opens the entry sheet preloaded with an existing transaction.
    func presentEditTransaction(_ transaction: TransactionItem) {
        editingTransaction = transaction
        newTransactionTimestamp = nil
        newTransactionIsExpense = nil
        isEntrySheetPresented = true
    }

    func presentNewTransfer(timestamp: Date? = nil) {
        editingTransfer = nil
        newTransferTimestamp = timestamp
        isTransferSheetPresented = true
    }

    func presentEditTransfer(_ transfer: TransferItem) {
        editingTransfer = transfer
        newTransferTimestamp = nil
        isTransferSheetPresented = true
    }

    func route(to destination: FloatDestination) {
        switch destination {
        case .home:
            selectedTab = .home
        case .transactions:
            selectedTab = .transactions
        case .calendar:
            selectedTab = .calendar
        case .reports:
            selectedTab = .insights
        case .settings:
            selectedTab = .settings
        case .budget:
            selectedTab = .settings
            pendingSettingsDestination = .budget
        case .goals:
            selectedTab = .settings
            pendingSettingsDestination = .goals
        case .recurring:
            selectedTab = .settings
            pendingSettingsDestination = .recurring
        case .templates:
            selectedTab = .settings
            pendingSettingsDestination = .templates
        case .categories:
            selectedTab = .settings
            pendingSettingsDestination = .categories
        case .accounts:
            selectedTab = .settings
            pendingSettingsDestination = .accounts
        case .reviewQueue:
            selectedTab = .settings
            pendingSettingsDestination = .reviewQueue
        }
    }

    func handlePendingAction(_ action: PendingFloatAction) {
        switch action.kind {
        case .addExpense:
            selectedTab = .home
            presentNewTransaction(isExpense: true)
        case .addIncome:
            selectedTab = .home
            presentNewTransaction(isExpense: false)
        case .addTransfer:
            selectedTab = .home
            presentNewTransfer()
        case .openDestination:
            route(to: action.destination ?? .home)
        }
    }
}
