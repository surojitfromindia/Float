import LocalAuthentication
import SwiftData
import SwiftUI

struct AppRootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var appState: AppState
    @State private var isShowingSplash = true
    @State private var isUnlocked = false
    @State private var isAuthenticating = false
    @State private var lockMessage: String?

    var body: some View {
        ZStack {
            Group {
                if appState.hasCompletedOnboarding {
                    MainTabView()
                } else {
                    OnboardingView()
                }
            }
            .opacity(isShowingSplash ? 0 : 1)

            if isShowingSplash {
                LaunchSplashView(palette: appState.themePalette)
                    .transition(.opacity.combined(with: .scale(scale: 1.02)))
            }

            if shouldShowLock {
                AppLockView(
                    palette: appState.themePalette,
                    isAuthenticating: isAuthenticating,
                    message: lockMessage,
                    unlock: authenticate
                )
                .transition(.opacity)
            }
        }
        .preferredColorScheme(appState.colorScheme)
        .environment(\.locale, appState.selectedLanguage.locale)
        .task {
            refreshAppData()
            try? await Task.sleep(for: .milliseconds(950))
            withAnimation(.easeInOut(duration: 0.28)) {
                isShowingSplash = false
            }
            if appState.isAppLockEnabled {
                authenticate()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                MaterializeRecurringTransactionsUseCase.run(
                    modelContext: modelContext
                )
                publishWidgetSnapshot()
                if appState.isAppLockEnabled && !isShowingSplash {
                    authenticate()
                }
            } else if appState.isAppLockEnabled {
                isUnlocked = false
            }
        }
        .onChange(of: appState.selectedCurrencyCode) { _, _ in
            publishWidgetSnapshot()
        }
        .onChange(of: appState.isAppLockEnabled) { _, isEnabled in
            if isEnabled {
                isUnlocked = false
                authenticate()
            } else {
                isUnlocked = true
                lockMessage = nil
            }
        }
    }

    private var shouldShowLock: Bool {
        appState.isAppLockEnabled && !isUnlocked && !isShowingSplash
    }

    private func refreshAppData() {
        SeedData.ensureSeedData(
            modelContext: modelContext,
            currencyCode: appState.selectedCurrencyCode
        )
        MaterializeRecurringTransactionsUseCase.run(modelContext: modelContext)
        publishWidgetSnapshot()
    }

    private func publishWidgetSnapshot() {
        WidgetSnapshotPublisher.publish(
            modelContext: modelContext,
            currencyCode: appState.selectedCurrencyCode
        )
    }

    private func authenticate() {
        guard appState.isAppLockEnabled, !isUnlocked, !isAuthenticating else { return }
        isAuthenticating = true
        lockMessage = nil

        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            isAuthenticating = false
            lockMessage = "Device authentication is not available."
            return
        }

        context.evaluatePolicy(
            .deviceOwnerAuthentication,
            localizedReason: "Unlock Float to view your finances."
        ) { success, error in
            Task { @MainActor in
                isAuthenticating = false
                if success {
                    isUnlocked = true
                    lockMessage = nil
                } else {
                    isUnlocked = false
                    lockMessage = error?.localizedDescription
                        ?? "Authentication was not completed."
                }
            }
        }
    }
}

private struct AppLockView: View {
    let palette: FloatThemePalette
    let isAuthenticating: Bool
    let message: String?
    let unlock: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [palette.backgroundTop, palette.backgroundBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 18) {
                FloatIconBadge(
                    icon: "lock.fill",
                    tint: palette.accent,
                    size: 72
                )
                VStack(spacing: 6) {
                    Text("Float is locked")
                        .font(.title2.weight(.bold))
                    Text("Use Face ID, Touch ID, or your passcode to continue.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                if let message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(palette.caution)
                        .multilineTextAlignment(.center)
                }

                Button(action: unlock) {
                    Label(
                        isAuthenticating ? "Unlocking" : "Unlock",
                        systemImage: "faceid"
                    )
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isAuthenticating)
                .padding(.top, 4)
            }
            .padding(24)
            .frame(maxWidth: 360)
        }
    }
}

private struct LaunchSplashView: View {
    let palette: FloatThemePalette
    @State private var isAnimating = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    palette.backgroundTop,
                    palette.backgroundBottom,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(palette.accent.opacity(0.16))
                        .frame(width: 118, height: 118)
                        .scaleEffect(isAnimating ? 1.08 : 0.96)
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 86, height: 86)
                        .overlay(
                            Circle()
                                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                        )
                    Image(systemName: "creditcard.fill")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(palette.accent)
                        .scaleEffect(isAnimating ? 1 : 0.9)
                }

                VStack(spacing: 6) {
                    Text("Float")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text("Spend with clarity")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                ProgressView()
                    .tint(palette.accent)
                    .padding(.top, 8)
            }
            .padding(.bottom, 24)
        }
        .onAppear {
            withAnimation(
                .easeInOut(duration: 0.9)
                    .repeatForever(autoreverses: true)
            ) {
                isAnimating = true
            }
        }
    }
}
