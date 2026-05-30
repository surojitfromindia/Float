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
    @State private var recurringRuleToEdit: RecurringRuleItem?

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

    private var upcomingRecurringExpense: RecurringRuleItem? {
        recurringRules
            .filter { $0.active && $0.isExpense }
            .sorted { $0.nextRunDate < $1.nextRunDate }
            .first
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
                            Text("This period")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(
                                MoneyFormatter.string(
                                    minorUnits: result.variableSpentMinor,
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
                }

                budgetOverview
                upcomingRecurring
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
        .sheet(item: $recurringRuleToEdit) { rule in
            RecurringEditorView(rule: rule)
        }
        .onAppear {
            MaterializeRecurringTransactionsUseCase.run(
                modelContext: modelContext
            )
        }
    }

    private var budgetOverview: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Budget overview")
            BudgetStatusChart(
                result: result,
                currencyCode: appState.selectedCurrencyCode
            )
        }
    }

    @ViewBuilder private var upcomingRecurring: some View {
        if let rule = upcomingRecurringExpense {
            Button {
                recurringRuleToEdit = rule
            } label: {
                GlassCard {
                    HStack(spacing: 14) {
                        Image(systemName: rule.category?.iconKey ?? "repeat")
                            .font(.headline)
                            .foregroundStyle(Color(hex: "#B4613B"))
                            .frame(width: 42, height: 42)
                            .background(
                                Color(hex: "#B4613B").opacity(0.14),
                                in: Circle()
                            )
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Upcoming recurring")
                                .font(.headline)
                            Text(
                                rule.note?.isEmpty == false
                                    ? rule.note ?? ""
                                    : rule.category?.name ?? "Unknown Category"
                            )
                            .font(.subheadline)
                            Text(
                                rule.nextRunDate.formatted(
                                    date: .abbreviated,
                                    time: .omitted
                                )
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(
                            MoneyFormatter.string(
                                minorUnits: rule.amountMinor,
                                currencyCode: appState.selectedCurrencyCode
                            )
                        )
                        .moneyStyle(size: 15, weight: .semibold)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit upcoming recurring rule")
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

struct SafeToSpendHeroCard: View {
    @AppStorage("selectedThemeMode") private var selectedThemeMode = "float"
    let result: SafeToSpendResult
    let currencyCode: String

    private var palette: FloatThemePalette {
        FloatTheme.palette(for: selectedThemeMode)
    }

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
                                ? palette.caution : palette.positive
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
    @AppStorage("selectedThemeMode") private var selectedThemeMode = "float"
    let result: SafeToSpendResult
    let currencyCode: String

    private var palette: FloatThemePalette {
        FloatTheme.palette(for: selectedThemeMode)
    }

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
            VStack(alignment: .leading, spacing: 12) {
                chartMetric(
                    title: "Period",
                    detail: "\(progressPercent(result.periodProgress)) elapsed",
                    note: periodSummary,
                    amount: nil,
                    progress: result.periodProgress,
                    tint: palette.accent
                )
                chartMetric(
                    title: "Spending",
                    detail: "\(progressPercent(result.spendingProgress)) used",
                    note: nil,
                    amount: result.variableSpentMinor,
                    progress: result.spendingProgress,
                    tint: palette.accent
                )
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
                    color: palette.positive
                )
                legendItem(
                    "Spent",
                    amount: result.variableSpentMinor,
                    total: chartTotal,
                    color: palette.accent
                )
                legendItem(
                    "Committed",
                    amount: committedMinor,
                    total: chartTotal,
                    color: palette.caution
                )
            }
        }
        .padding(16)
        .background(
            .thinMaterial,
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .background(
            palette.accent.opacity(0.06),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        )
    }

    private var periodSummary: String {
        let start = result.periodStart.formatted(
            date: .abbreviated,
            time: .omitted
        )
        let end = result.periodEnd.formatted(
            date: .abbreviated,
            time: .omitted
        )
        return "\(start) - \(end) · \(result.daysRemaining) days left"
    }

    private func chartMetric(
        title: String,
        detail: String,
        note: String?,
        amount: Int64?,
        progress: Double,
        tint: Color
    )
        -> some View
    {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle()
                    .fill(tint.gradient)
                    .frame(width: 9, height: 9)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
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
            if let note {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            GeometryReader { proxy in
                HStack(spacing: 6) {
                    Capsule()
                        .fill(tint.gradient)
                        .frame(
                            width: max(
                                6,
                                proxy.size.width
                                    * CGFloat(min(max(progress, 0), 1))
                            )
                        )
                    Spacer(minLength: 0)
                }
            }
            .frame(height: 8)
            .padding(2)
            .background(Color.primary.opacity(0.07), in: Capsule())
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: progress)
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
