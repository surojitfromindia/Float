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

    // Controls the shared transaction entry sheet and whether it opens in create or edit mode.
    @Published var isEntrySheetPresented = false
    @Published var editingTransaction: TransactionItem?

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

    // Opens the entry sheet with empty state for a new transaction.
    func presentNewTransaction() {
        editingTransaction = nil
        isEntrySheetPresented = true
    }

    // Opens the entry sheet preloaded with an existing transaction.
    func presentEditTransaction(_ transaction: TransactionItem) {
        editingTransaction = transaction
        isEntrySheetPresented = true
    }
}
