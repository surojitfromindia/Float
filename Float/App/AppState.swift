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

enum AppLocalization {
    private static let selectedLanguageDefaultsKey = "selectedLanguageCode"

    static var selectedLanguage: AppLanguage {
        let rawValue = UserDefaults.standard.string(
            forKey: selectedLanguageDefaultsKey
        ) ?? AppLanguage.system.rawValue
        return AppLanguage(rawValue: rawValue) ?? .system
    }

    static var locale: Locale {
        selectedLanguage.locale
    }

    static var bundle: Bundle {
        switch selectedLanguage {
        case .system:
            return .main
        default:
            guard
                let path = Bundle.main.path(
                    forResource: selectedLanguage.rawValue,
                    ofType: "lproj"
                ),
                let localizedBundle = Bundle(path: path)
            else {
                return .main
            }
            return localizedBundle
        }
    }

    static func string(_ key: String) -> String {
        bundle.localizedString(forKey: key, value: nil, table: nil)
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        format(key, arguments: arguments)
    }

    static func format(_ key: String, arguments: [CVarArg]) -> String {
        let format = string(key)
        return String(format: format, locale: locale, arguments: arguments)
    }
}

enum FloatTab: Hashable {
    case home
    case transactions
    case settlements
    case insights
    case settings
}

enum FloatSettingsDestination: String, Hashable, Identifiable {
    case calendar
    case planner
    case budget
    case goals
    case recurring
    case templates
    case templateGroups
    case categories
    case accounts
    case people
    case profiles
    case settlements
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
    var settlementsEnabled: Bool
    var recurringReminderMinutes: Int
    var goalReminderMinutes: Int
    var settlementReminderMinutes: Int
    var budgetAlertSensitivity: BudgetAlertSensitivity
}

@MainActor
final class AppState: ObservableObject {
    // User preferences persisted across app launches.
    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding = false
    @AppStorage("selectedCurrencyCode") var selectedCurrencyCode =
        MoneyFormatter.currencyCodeFromLocale()
    @AppStorage("selectedAppearance") var selectedAppearance = "system"
    @AppStorage("selectedThemeMode") var selectedThemeMode = "float" {
        didSet { objectWillChange.send() }
    }
    @AppStorage("selectedLanguageCode") var selectedLanguageCode = "system"
    @AppStorage("lastUsedCategoryID") var lastUsedCategoryID = ""
    @AppStorage("lastUsedAccountID") var lastUsedAccountID = ""
    @AppStorage("activeProfileID") var activeProfileID = ""
    @AppStorage("showPinnedEventsInHomeView") var showPinnedEventsInHomeView = false
    @AppStorage("isAppLockEnabled") var isAppLockEnabled = false
    @AppStorage("recurringRemindersEnabled") var recurringRemindersEnabled = true
    @AppStorage("budgetAlertsEnabled") var budgetAlertsEnabled = true
    @AppStorage("goalRemindersEnabled") var goalRemindersEnabled = true
    @AppStorage("settlementRemindersEnabled") var settlementRemindersEnabled = true
    @AppStorage("recurringReminderMinutes") var recurringReminderMinutes = 9 * 60
    @AppStorage("goalReminderMinutes") var goalReminderMinutes = 9 * 60 + 30
    @AppStorage("settlementReminderMinutes") var settlementReminderMinutes = 9 * 60
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
    @Published var pendingSpotlightRequest: FloatSpotlightNavigationRequest?
    @Published var activeProfileName = String(localized: "Personal")

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
            settlementsEnabled: settlementRemindersEnabled,
            recurringReminderMinutes: recurringReminderMinutes,
            goalReminderMinutes: goalReminderMinutes,
            settlementReminderMinutes: settlementReminderMinutes,
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

    func applyProfile(_ profile: UserProfileItem) {
        activeProfileID = profile.id.uuidString
        activeProfileName = profile.displayName
        selectedCurrencyCode = profile.currencyCode
        lastUsedCategoryID = profile.lastUsedCategoryID
        lastUsedAccountID = profile.lastUsedAccountID
        recurringRemindersEnabled = profile.recurringRemindersEnabled
        budgetAlertsEnabled = profile.budgetAlertsEnabled
        goalRemindersEnabled = profile.goalRemindersEnabled
        settlementRemindersEnabled = profile.settlementRemindersEnabled
        recurringReminderMinutes = profile.recurringReminderMinutes
        goalReminderMinutes = profile.goalReminderMinutes
        settlementReminderMinutes = profile.settlementReminderMinutes
        budgetAlertSensitivityRaw = profile.budgetAlertSensitivityRaw
        ActiveProfileRegistry.profileID = profile.id
        clearTransientProfileState()
    }

    func writePreferences(to profile: UserProfileItem) {
        let name = activeProfileName.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.displayName = name.isEmpty ? profile.displayName : name
        profile.currencyCode = selectedCurrencyCode
        profile.lastUsedCategoryID = lastUsedCategoryID
        profile.lastUsedAccountID = lastUsedAccountID
        profile.recurringRemindersEnabled = recurringRemindersEnabled
        profile.budgetAlertsEnabled = budgetAlertsEnabled
        profile.goalRemindersEnabled = goalRemindersEnabled
        profile.settlementRemindersEnabled = settlementRemindersEnabled
        profile.recurringReminderMinutes = recurringReminderMinutes
        profile.goalReminderMinutes = goalReminderMinutes
        profile.settlementReminderMinutes = settlementReminderMinutes
        profile.budgetAlertSensitivityRaw = budgetAlertSensitivityRaw
        profile.updatedAt = Date()
    }

    func clearTransientProfileState() {
        isEntrySheetPresented = false
        editingTransaction = nil
        newTransactionTimestamp = nil
        newTransactionIsExpense = nil
        isTransferSheetPresented = false
        editingTransfer = nil
        newTransferTimestamp = nil
        pendingSettingsDestination = nil
        pendingSpotlightRequest = nil
    }

    func route(to destination: FloatDestination) {
        switch destination {
        case .home:
            selectedTab = .home
        case .transactions:
            selectedTab = .transactions
        case .calendar:
            selectedTab = .settings
            pendingSettingsDestination = .calendar
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
        case .templateGroups:
            selectedTab = .settings
            pendingSettingsDestination = .templateGroups
        case .categories:
            selectedTab = .settings
            pendingSettingsDestination = .categories
        case .accounts:
            selectedTab = .settings
            pendingSettingsDestination = .accounts
        case .people:
            selectedTab = .settings
            pendingSettingsDestination = .people
        case .settlements:
            selectedTab = .settlements
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
        case .openSearchResult:
            guard let identifier = action.spotlightItemIdentifier,
                  let target = FloatSpotlightItemIdentifier.parse(identifier)
            else {
                return
            }
            presentSpotlightTarget(target)
        }
    }

    func consumeSpotlightRequest(_ request: FloatSpotlightNavigationRequest) {
        guard pendingSpotlightRequest?.id == request.id else { return }
        pendingSpotlightRequest = nil
    }

    private func presentSpotlightTarget(_ target: FloatSpotlightTarget) {
        pendingSpotlightRequest = FloatSpotlightNavigationRequest(target: target)
        switch target.kind {
        case .transaction, .transfer:
            selectedTab = .transactions
        case .account:
            selectedTab = .settings
            pendingSettingsDestination = .accounts
        case .category:
            selectedTab = .settings
            pendingSettingsDestination = .categories
        case .people:
            selectedTab = .settings
            pendingSettingsDestination = .people
        }
    }
}
