import SwiftData
import SwiftUI

struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @State private var page = 0
    @State private var expectedIncomeText = ""
    @State private var cadence: BudgetCadence = .monthly
    @State private var startDay = 1

    var body: some View {
        TabView(selection: $page) {
            onboardingPage(
                icon: "sparkles",
                title: "Float",
                message:
                    "A private, local-only way to know what is safe to spend today."
            ).tag(0)
            VStack(spacing: 20) {
                onboardingHeader(
                    icon: "indianrupeesign.circle.fill",
                    title: "Currency",
                    message:
                        "Use the currency that matches your day-to-day spending."
                )
                TextField("Currency code", text: $appState.selectedCurrencyCode)
                    .textInputAutocapitalization(.characters)
                    .font(.title3.monospaced())
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(
                        .thinMaterial,
                        in: RoundedRectangle(cornerRadius: 18)
                    )
            }.padding(28).tag(1)
            VStack(spacing: 20) {
                onboardingHeader(
                    icon: "calendar",
                    title: "Pay cycle",
                    message: "Float uses this to calculate your current period."
                )
                Picker("Cadence", selection: $cadence) {
                    ForEach(BudgetCadence.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented)
                Stepper(
                    "Starts on day \(startDay)",
                    value: $startDay,
                    in: 1...28
                )
            }.padding(28).tag(2)
            VStack(spacing: 20) {
                onboardingHeader(
                    icon: "banknote.fill",
                    title: "Expected income",
                    message: "You can set this to zero and update it later."
                )
                HStack {
                    TextField("Amount in minor units", text: $expectedIncomeText)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                    CurrencyAmountPreview(
                        minorUnits: expectedIncomeMinor,
                        currencyCode: appState.selectedCurrencyCode
                    )
                }
            }.padding(28).tag(3)
            VStack(spacing: 20) {
                onboardingHeader(
                    icon: "checkmark.circle.fill",
                    title: "Ready",
                    message: "Finish setup and start tracking your spending."
                )
                Button("Start using Float", action: complete).buttonStyle(
                    .borderedProminent
                ).controlSize(.large)
            }.padding(28).tag(4)
        }
        .tabViewStyle(.page)
        .keyboardDismissControls()
        .safeAreaInset(edge: .bottom) {
            if page < 4 {
                Button("Continue") { withAnimation { page += 1 } }.buttonStyle(
                    .borderedProminent
                ).controlSize(.large).padding()
            }
        }
        .floatBackground()
    }

    private func onboardingPage(icon: String, title: String, message: String)
        -> some View
    {
        VStack(spacing: 20) {
            onboardingHeader(icon: icon, title: title, message: message)
        }.padding(28)
    }

    private func onboardingHeader(icon: String, title: String, message: String)
        -> some View
    {
        VStack(spacing: 18) {
            Image(systemName: icon).font(.system(size: 56, weight: .semibold))
                .foregroundStyle(appState.themePalette.accent)
            Text(title).font(.largeTitle.bold())
            Text(message).font(.body).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var expectedIncomeMinor: Int64 {
        Int64(expectedIncomeText) ?? 0
    }

    private func complete() {
        SeedData.ensureSeedData(
            modelContext: modelContext,
            currencyCode: appState.selectedCurrencyCode
        )
        let descriptor = FetchDescriptor<BudgetPeriodItem>()
        let budget =
            (try? modelContext.fetch(descriptor))?.first
            ?? BudgetPeriodItem(currencyCode: appState.selectedCurrencyCode)
        if budget.modelContext == nil { modelContext.insert(budget) }
        budget.cadence = cadence
        budget.startDayOfMonth = cadence == .monthly ? startDay : nil
        budget.startDayOfWeek = cadence == .weekly ? startDay : nil
        budget.expectedIncomeMinor = expectedIncomeMinor
        budget.currencyCode = appState.selectedCurrencyCode
        budget.isActive = true
        try? modelContext.save()
        appState.hasCompletedOnboarding = true
    }
}
