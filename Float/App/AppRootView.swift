import SwiftData
import SwiftUI

struct AppRootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var appState: AppState
    @StateObject private var authManager = BiometricAuthManager()

    var body: some View {
        Group {
            if !appState.hasCompletedOnboarding {
                OnboardingView()
                    .environmentObject(authManager)
            } else if appState.isBiometricLockEnabled && !authManager.isUnlocked
            {
                LockScreenView()
                    .environmentObject(authManager)
            } else {
                MainTabView()
                    .environmentObject(authManager)
            }
        }
        .preferredColorScheme(appState.colorScheme)
        .task {
            SeedData.ensureSeedData(
                modelContext: modelContext,
                currencyCode: appState.selectedCurrencyCode
            )
            MaterializeRecurringTransactionsUseCase.run(
                modelContext: modelContext
            )
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background, appState.isBiometricLockEnabled {
                authManager.lock()
            }
            if newPhase == .active {
                MaterializeRecurringTransactionsUseCase.run(
                    modelContext: modelContext
                )
                if appState.isBiometricLockEnabled
                    && !authManager.isUnlocked
                    && !authManager.isAuthenticating {
                    Task {
                        await Task.yield()
                        guard !authManager.isUnlocked,
                            !authManager.isAuthenticating
                        else { return }
                        _ = await authManager.authenticate()
                    }
                }
            }
        }
    }
}

struct LockScreenView: View {
    @EnvironmentObject private var authManager: BiometricAuthManager

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 54, weight: .semibold))
                .foregroundStyle(Color(hex: "#0E7C7B"))
            Text("Float is locked")
                .font(.largeTitle.bold())
            Text("Authenticate to continue. Your data stays on this device.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                Task { _ = await authManager.authenticate() }
            } label: {
                Label("Unlock", systemImage: "lock.open.fill")
                    .font(.headline)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 14)
                    .background(Color(hex: "#0E7C7B"), in: Capsule())
                    .foregroundStyle(.white)
            }
            if let message = authManager.lastErrorMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(32)
        .floatBackground()
    }
}
