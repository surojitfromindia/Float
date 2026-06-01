import SwiftData
import SwiftUI

struct AppRootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var appState: AppState
    @State private var isShowingSplash = true

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
        }
        .preferredColorScheme(appState.colorScheme)
        .environment(\.locale, appState.selectedLanguage.locale)
        .task {
            refreshAppData()
            try? await Task.sleep(for: .milliseconds(950))
            withAnimation(.easeInOut(duration: 0.28)) {
                isShowingSplash = false
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            MaterializeRecurringTransactionsUseCase.run(
                modelContext: modelContext
            )
            publishWidgetSnapshot()
        }
        .onChange(of: appState.selectedCurrencyCode) { _, _ in
            publishWidgetSnapshot()
        }
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
