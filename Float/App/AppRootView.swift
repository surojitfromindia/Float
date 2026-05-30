import SwiftData
import SwiftUI

struct AppRootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            if appState.hasCompletedOnboarding {
                MainTabView()
            } else {
                OnboardingView()
            }
        }
        .preferredColorScheme(appState.colorScheme)
        .environment(\.locale, appState.selectedLanguage.locale)
        .task {
            refreshAppData()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            MaterializeRecurringTransactionsUseCase.run(
                modelContext: modelContext
            )
        }
    }

    private func refreshAppData() {
        SeedData.ensureSeedData(
            modelContext: modelContext,
            currencyCode: appState.selectedCurrencyCode
        )
        MaterializeRecurringTransactionsUseCase.run(modelContext: modelContext)
    }
}
