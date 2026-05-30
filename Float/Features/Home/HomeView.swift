import SwiftData
import SwiftUI

struct HomeView: View {
    // model context is database context, like database connection.
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @Query(sort: \TransactionItem.timestamp, order: .reverse) private
        var transactions: [TransactionItem]
    @Query private var goals: [GoalItem]
    @Query private var recurringRules: [RecurringRuleItem]
    @Query private var budgets: [BudgetPeriodItem]
    @State private var showingIncomeEditor = false

    // Prefer the active budget period for all home-screen math; fall back to the first
    // saved period so the dashboard can still render while setup data is incomplete.
    private var activeBudget: BudgetPeriodItem? {
        budgets.first { $0.isActive } ?? budgets.first
    }

    // SafeToSpendUseCase owns the calculation:
    // expected income - recurring expenses due this period - remaining goal targets
    // - variable spending already recorded through today. The returned result also
    // includes derived values such as daily allowance, days left, and progress.
    private var result: SafeToSpendResult {
        SafeToSpendUseCase.calculate(
            budget: activeBudget,
            transactions: transactions,
            goals: goals,
            recurringRules: recurringRules
        )
    }

    // The "Today" tile is separate from the period calculation: it only sums
    // expense transactions whose timestamps fall on the current calendar day.
    private var todayExpenses: Int64 {
        transactions.filter {
            $0.isExpense && Calendar.current.isDateInToday($0.timestamp)
        }.reduce(0) { $0 + $1.amountMinor }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                SafeToSpendHeroCard(
                    result: result,
                    currencyCode: appState.selectedCurrencyCode
                )

                HStack(spacing: 14) {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Today")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(
                                MoneyFormatter.string(
                                    minorUnits: todayExpenses,
                                    currencyCode: appState.selectedCurrencyCode
                                )
                            )
                            .moneyStyle(size: 24, weight: .bold)
                            Text("spent so far")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    GlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Days left")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("\(result.daysRemaining)")
                                .font(
                                    .system(
                                        size: 24,
                                        weight: .bold,
                                        design: .rounded
                                    )
                                )
                            Text("including today")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                budgetOverview
                nearestGoal
                recentTransactions
            }
            .padding(20)
            .padding(.bottom, 96)
        }
        .navigationTitle("Float")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    appState.presentNewTransaction()
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add transaction")
            }
        }
        .floatBackground()
        .onAppear {
            MaterializeRecurringTransactionsUseCase.run(
                modelContext: modelContext
            )
        }
    }

    private var budgetOverview: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(
                title: "Budget overview",
                actionTitle: "Income",
                action: { showingIncomeEditor = true }
            )
            BudgetStatusChart(
                result: result,
                currencyCode: appState.selectedCurrencyCode
            )
        }
        .sheet(isPresented: $showingIncomeEditor) {
            IncomeEditorSheet(budget: activeBudget)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder private var nearestGoal: some View {
        // Show the unfinished goal with the closest target date. Goals without a
        // date sort last because distantFuture is used as their comparison value.
        if let goal = goals.filter({ !$0.achieved }).sorted(by: {
            ($0.targetDate ?? .distantFuture)
                < ($1.targetDate ?? .distantFuture)
        }).first {
            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Nearest goal")
                    HStack(spacing: 16) {
                        // The goal chart is a progress ring. It fills by saved / target,
                        // with max(..., 1) preventing division by zero for invalid data.
                        FloatProgressRing(
                            progress: Double(goal.savedMinor)
                                / Double(max(goal.targetMinor, 1)),
                            tint: Color(hex: goal.colorHex),
                            lineWidth: 8
                        )
                        .frame(width: 56, height: 56)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(goal.name).font(.headline)
                            Text(
                                "\(MoneyFormatter.string(minorUnits: goal.savedMinor, currencyCode: appState.selectedCurrencyCode)) of \(MoneyFormatter.string(minorUnits: goal.targetMinor, currencyCode: appState.selectedCurrencyCode))"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
            }
        }
    }

    private var recentTransactions: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Recent")
            GlassCard {
                if transactions.isEmpty {
                    EmptyStateView(
                        icon: "sparkles",
                        title: "No transactions yet",
                        message: "Add your first expense when you are ready."
                    )
                } else {
                    VStack(spacing: 8) {
                        ForEach(transactions.prefix(4)) { transaction in
                            TransactionRowView(
                                transaction: transaction,
                                currencyCode: appState.selectedCurrencyCode
                            )
                            if transaction.id != transactions.prefix(4).last?.id
                            {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct IncomeEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @Query private var budgets: [BudgetPeriodItem]
    let budget: BudgetPeriodItem?
    @State private var incomeText = ""

    private var previewIncomeMinor: Int64 {
        BudgetAmountField.minorUnits(
            fromMajorAmount: incomeText,
            currencyCode: appState.selectedCurrencyCode
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("Amount", text: $incomeText)
                            .keyboardType(.decimalPad)
                        CurrencyAmountPreview(
                            minorUnits: previewIncomeMinor,
                            currencyCode: appState.selectedCurrencyCode
                        )
                    }
                } header: {
                    Text("Expected income")
                } footer: {
                    Text("Enter the amount you expect for the current budget period.")
                }
            }
            .navigationTitle("Update Income")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                }
            }
            .onAppear(perform: configure)
        }
    }

    private func configure() {
        guard let budget else {
            incomeText = ""
            return
        }

        incomeText = BudgetAmountField.majorAmountString(
            minorUnits: budget.expectedIncomeMinor,
            currencyCode: budget.currencyCode
        )
    }

    private func save() {
        let activeBudget = budget ?? BudgetPeriodItem(
            currencyCode: appState.selectedCurrencyCode
        )

        if activeBudget.modelContext == nil {
            modelContext.insert(activeBudget)
        }

        for item in budgets where item.id != activeBudget.id {
            item.isActive = false
        }

        activeBudget.expectedIncomeMinor = previewIncomeMinor
        activeBudget.currencyCode = appState.selectedCurrencyCode
        activeBudget.isActive = true
        activeBudget.updatedAt = Date()
        try? modelContext.save()
        dismiss()
    }
}

struct SafeToSpendHeroCard: View {
    let result: SafeToSpendResult
    let currencyCode: String

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("You can spend")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                        Text(
                            MoneyFormatter.string(
                                minorUnits: result.safeToSpendMinor,
                                currencyCode: currencyCode
                            )
                        )
                        .moneyStyle(size: 44, weight: .bold)
                        .minimumScaleFactor(0.65)
                        Text(
                            result.overAmountMinor > 0
                                ? "You’re \(MoneyFormatter.string(minorUnits: result.overAmountMinor, currencyCode: currencyCode)) over for this period."
                                : "You’re on track"
                        )
                        .font(.subheadline)
                        .foregroundStyle(
                            result.overAmountMinor > 0
                                ? Color(hex: "#B4613B") : Color(hex: "#1B8A5A")
                        )
                    }
                }
                Divider().opacity(0.5)
                HStack {
                    Label(
                        MoneyFormatter.string(
                            minorUnits: result.dailyAllowanceMinor,
                            currencyCode: currencyCode
                        ),
                        systemImage: "calendar"
                    )
                    .moneyStyle(size: 17, weight: .semibold)
                    Text("per day left this period")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct BudgetStatusChart: View {
    let result: SafeToSpendResult
    let currencyCode: String

    private var committedMinor: Int64 {
        result.recurringDueMinor + result.goalContributionMinor
    }

    private var chartTotal: Int64 {
        max(
            1,
            result.expectedIncomeMinor,
            result.safeToSpendMinor + result.variableSpentMinor + committedMinor
        )
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 20) {
                BudgetDial(result: result)
                    .frame(width: 108, height: 108)

                VStack(alignment: .leading, spacing: 12) {
                    chartMetric(
                        title: "Period",
                        detail: "\(progressPercent(result.periodProgress)) elapsed",
                        amount: nil,
                        tint: Color(hex: "#0E7C7B")
                    )
                    chartMetric(
                        title: "Spending",
                        detail: "\(progressPercent(result.spendingProgress)) used",
                        amount: result.variableSpentMinor,
                        tint: Color(hex: "#B4613B")
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            AllocationBar(
                safeMinor: result.safeToSpendMinor,
                spentMinor: result.variableSpentMinor,
                committedMinor: committedMinor,
                totalMinor: chartTotal
            )

            VStack(spacing: 9) {
                legendItem(
                    "Safe",
                    amount: result.safeToSpendMinor,
                    total: chartTotal,
                    color: Color(hex: "#1B8A5A")
                )
                legendItem(
                    "Spent",
                    amount: result.variableSpentMinor,
                    total: chartTotal,
                    color: Color(hex: "#0E7C7B")
                )
                legendItem(
                    "Committed",
                    amount: committedMinor,
                    total: chartTotal,
                    color: Color(hex: "#B4613B")
                )
            }
        }
        .padding(16)
        .background(
            .thinMaterial,
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .background(
            Color(hex: "#0E7C7B").opacity(0.06),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        )
    }

    private func chartMetric(
        title: String,
        detail: String,
        amount: Int64?,
        tint: Color
    )
        -> some View
    {
        HStack(spacing: 10) {
            Circle()
                .fill(tint.gradient)
                .frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text(detail)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                if let amount {
                    Text(
                        MoneyFormatter.string(
                            minorUnits: amount,
                            currencyCode: currencyCode
                        )
                    )
                    .moneyStyle(size: 15, weight: .semibold)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                }
            }
        }
    }

    private func legendItem(
        _ title: String,
        amount: Int64,
        total: Int64,
        color: Color
    ) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(sharePercent(amount, total: total))
                .font(.caption.weight(.semibold))
                .monospacedDigit()
        }
    }

    private func progressPercent(_ value: Double) -> String {
        "\(Int((min(max(value, 0), 1) * 100).rounded()))%"
    }

    private func sharePercent(_ amount: Int64, total: Int64) -> String {
        let value = Double(max(0, amount)) / Double(max(1, total))
        return "\(Int((value * 100).rounded()))%"
    }
}

private struct BudgetDial: View {
    let result: SafeToSpendResult

    private var tint: Color {
        result.overAmountMinor > 0 ? Color(hex: "#B4613B") : Color(hex: "#0E7C7B")
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: 13)
            Circle()
                .trim(from: 0, to: min(max(result.periodProgress, 0), 1))
                .stroke(
                    AngularGradient(
                        colors: [
                            Color(hex: "#0E7C7B"),
                            Color(hex: "#3FC1BE"),
                            Color(hex: "#1B8A5A"),
                        ],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 13, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            Circle()
                .stroke(Color.primary.opacity(0.07), lineWidth: 7)
                .padding(18)
            Circle()
                .trim(from: 0, to: min(max(result.spendingProgress, 0), 1))
                .stroke(
                    tint,
                    style: StrokeStyle(lineWidth: 7, lineCap: .round)
                )
                .padding(18)
                .rotationEffect(.degrees(-90))

            Circle()
                .fill(.thinMaterial)
                .frame(width: 54, height: 54)
                .overlay(
                    Circle()
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                )
        }
        .animation(.spring(response: 0.55, dampingFraction: 0.85), value: result)
        .accessibilityLabel("Budget progress")
        .accessibilityValue(
            "\(Int((result.periodProgress * 100).rounded())) percent of period elapsed"
        )
    }
}

private struct AllocationBar: View {
    let safeMinor: Int64
    let spentMinor: Int64
    let committedMinor: Int64
    let totalMinor: Int64

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 4) {
                segment(
                    amount: safeMinor,
                    total: totalMinor,
                    width: proxy.size.width,
                    color: Color(hex: "#1B8A5A")
                )
                segment(
                    amount: spentMinor,
                    total: totalMinor,
                    width: proxy.size.width,
                    color: Color(hex: "#0E7C7B")
                )
                segment(
                    amount: committedMinor,
                    total: totalMinor,
                    width: proxy.size.width,
                    color: Color(hex: "#B4613B")
                )
            }
        }
        .frame(height: 16)
        .padding(3)
        .background(Color.primary.opacity(0.07), in: Capsule())
    }

    private func segment(amount: Int64, total: Int64, width: CGFloat, color: Color)
        -> some View
    {
        let ratio = CGFloat(max(0, Double(amount) / Double(max(total, 1))))
        return Capsule()
            .fill(color.gradient)
            .frame(width: max(amount > 0 ? 8 : 0, width * ratio))
    }
}
