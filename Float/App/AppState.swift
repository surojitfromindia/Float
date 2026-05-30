import Combine
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    // User preferences persisted across app launches.
    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding = false
    @AppStorage("selectedCurrencyCode") var selectedCurrencyCode =
        MoneyFormatter.currencyCodeFromLocale()
    @AppStorage("selectedAppearance") var selectedAppearance = "system"
    @AppStorage("selectedThemeMode") var selectedThemeMode = "float"
    @AppStorage("isBiometricLockEnabled") var isBiometricLockEnabled = false
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
