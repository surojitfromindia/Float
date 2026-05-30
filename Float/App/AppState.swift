import SwiftUI
import Combine

@MainActor
final class AppState: ObservableObject {
    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding = false
    @AppStorage("selectedCurrencyCode") var selectedCurrencyCode = MoneyFormatter.currencyCodeFromLocale()
    @AppStorage("selectedAppearance") var selectedAppearance = "system"
    @AppStorage("selectedThemeMode") var selectedThemeMode = "float"
    @AppStorage("isBiometricLockEnabled") var isBiometricLockEnabled = false
    @AppStorage("lastUsedCategoryID") var lastUsedCategoryID = ""
    @AppStorage("lastUsedAccountID") var lastUsedAccountID = ""

    @Published var isEntrySheetPresented = false
    @Published var editingTransaction: TransactionItem?

    var colorScheme: ColorScheme? {
        switch selectedAppearance {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }

    func presentNewTransaction() {
        editingTransaction = nil
        isEntrySheetPresented = true
    }

    func presentEditTransaction(_ transaction: TransactionItem) {
        editingTransaction = transaction
        isEntrySheetPresented = true
    }
}
