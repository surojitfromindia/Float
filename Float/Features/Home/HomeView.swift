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
    @Query(sort: \AccountItem.createdAt) private var accounts: [AccountItem]
    @Query private var categoryBudgets: [CategoryBudgetItem]
    @State private var recurringRuleToEdit: RecurringRuleItem?
    @State private var contributionGoal: GoalItem?

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

    private var yesterdayExpenses: Int64 {
        guard let yesterday = Calendar.current.date(
            byAdding: .day,
            value: -1,
            to: Date()
        ) else {
            return 0
        }
        return transactions.filter {
            $0.isExpense && Calendar.current.isDate($0.timestamp, inSameDayAs: yesterday)
        }.reduce(0) { $0 + $1.amountMinor }
    }

    private var upcomingRecurringExpense: RecurringRuleItem? {
        recurringRules
            .filter { $0.active && $0.isExpense }
            .sorted { $0.nextRunDate < $1.nextRunDate }
            .first
    }

    private var nearestOpenGoal: GoalItem? {
        goals.filter { !$0.achieved }.sorted {
            ($0.targetDate ?? .distantFuture)
                < ($1.targetDate ?? .distantFuture)
        }.first
    }

    private var forecastItems: [CashFlowForecastItem] {
        CashFlowForecastUseCase.calculate(
            accounts: accounts,
            transactions: transactions,
            budget: activeBudget,
            safeToSpend: result,
            goals: goals,
            recurringRules: recurringRules
        )
    }

    private var budgetAlerts: [BudgetAlertItem] {
        BudgetAlertsUseCase.calculate(
            categoryBudgets: categoryBudgets,
            transactions: transactions,
            period: BudgetPeriod(start: result.periodStart, end: result.periodEnd)
        )
    }

    private var periodDailyAverageMinor: Int64 {
        result.variableSpentMinor / Int64(elapsedPeriodDays)
    }

    private var elapsedPeriodDays: Int {
        let today = min(Date(), result.periodEnd)
        let days = Calendar.current.dateComponents(
            [.day],
            from: result.periodStart,
            to: today
        ).day ?? 0
        return max(1, days + 1)
    }

    private var todayTrendCaption: String {
        if yesterdayExpenses == 0 {
            return "spent so far"
        }
        let difference = todayExpenses - yesterdayExpenses
        if difference == 0 {
            return "same as yesterday"
        }
        return "\(money(abs(difference))) \(difference > 0 ? "over" : "under") yesterday"
    }

    private func money(_ amount: Int64) -> String {
        MoneyFormatter.string(
            minorUnits: amount,
            currencyCode: appState.selectedCurrencyCode
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                SafeToSpendHeroCard(
                    result: result,
                    currencyCode: appState.selectedCurrencyCode
                )

                quickActions

                HStack(spacing: 14) {
                    HomeSummaryTile(
                        title: "Today",
                        amountMinor: todayExpenses,
                        caption: todayTrendCaption,
                        icon: "sun.max.fill",
                        tint: appState.themePalette.caution,
                        currencyCode: appState.selectedCurrencyCode
                    )
                    HomeSummaryTile(
                        title: "This period",
                        amountMinor: result.variableSpentMinor,
                        caption: "\(money(periodDailyAverageMinor))/day avg",
                        icon: "chart.bar.fill",
                        tint: appState.themePalette.accent,
                        currencyCode: appState.selectedCurrencyCode
                    )
                }

                cashFlowForecast
                budgetAlertsSection
                budgetOverview
                upcomingRecurring
                nearestGoal
                recentTransactions
            }
            .padding(20)
            .padding(.bottom, 150)
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
        .sheet(item: $contributionGoal) { goal in
            GoalContributionSheet(goal: goal)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .onAppear {
            MaterializeRecurringTransactionsUseCase.run(
                modelContext: modelContext
            )
            LocalNotificationScheduler.refresh(
                recurringRules: recurringRules,
                budgetAlerts: budgetAlerts,
                goals: goals,
                currencyCode: appState.selectedCurrencyCode
            )
        }
    }

    private var quickActions: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2),
            spacing: 10
        ) {
            HomeActionButton(
                title: "Expense",
                icon: "minus.circle.fill",
                tint: appState.themePalette.caution
            ) {
                appState.presentNewTransaction(isExpense: true)
            }
            HomeActionButton(
                title: "Income",
                icon: "plus.circle.fill",
                tint: appState.themePalette.positive
            ) {
                appState.presentNewTransaction(isExpense: false)
            }
            HomeActionButton(
                title: "Add to goal",
                icon: "target",
                tint: appState.themePalette.accent,
                isEnabled: nearestOpenGoal != nil
            ) {
                contributionGoal = nearestOpenGoal
            }
            HomeActionButton(
                title: "Pay recurring",
                icon: "checkmark.circle.fill",
                tint: appState.themePalette.caution,
                isEnabled: upcomingRecurringExpense != nil
            ) {
                markUpcomingRecurringPaid()
            }
        }
    }

    private var cashFlowForecast: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Cash-flow forecast")
            GlassCard {
                VStack(spacing: 12) {
                    ForEach(forecastItems) { item in
                        ForecastRow(
                            item: item,
                            currencyCode: appState.selectedCurrencyCode,
                            tint: appState.themePalette.accent
                        )
                        if item.id != forecastItems.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private var budgetAlertsSection: some View {
        if !budgetAlerts.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Budget alerts")
                GlassCard {
                    VStack(spacing: 12) {
                        ForEach(budgetAlerts.prefix(3)) { alert in
                            BudgetAlertRow(
                                alert: alert,
                                currencyCode: appState.selectedCurrencyCode
                            )
                            if alert.id != budgetAlerts.prefix(3).last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }
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
                        FloatIconBadge(
                            icon: rule.category?.iconKey ?? "repeat",
                            tint: Color(hex: "#B4613B"),
                            size: 42
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
        if let goal = nearestOpenGoal {
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

    private func markUpcomingRecurringPaid() {
        guard let rule = upcomingRecurringExpense else { return }
        let transaction = TransactionItem(
            amountMinor: rule.amountMinor,
            isExpense: rule.isExpense,
            timestamp: Date(),
            category: rule.category,
            account: rule.account,
            note: rule.note,
            recurringRule: rule
        )
        modelContext.insert(transaction)
        if let next = SafeToSpendUseCase.advance(
            rule.nextRunDate,
            cadence: rule.cadence,
            intervalCount: rule.intervalCount
        ) {
            rule.nextRunDate = next
            rule.updatedAt = Date()
        }
        try? modelContext.save()
        Haptics.confirm()
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

private struct HomeSummaryTile: View {
    let title: String
    let amountMinor: Int64
    let caption: String
    let icon: String
    let tint: Color
    let currencyCode: String

    var body: some View {
        SummaryMetricTile(
            title: title,
            value: MoneyFormatter.string(
                minorUnits: amountMinor,
                currencyCode: currencyCode
            ),
            caption: caption,
            icon: icon,
            tint: tint
        )
    }
}

private struct HomeActionButton: View {
    let title: String
    let icon: String
    let tint: Color
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity)
            .background(
                tint.opacity(isEnabled ? 0.09 : 0.04),
                in: RoundedRectangle(
                    cornerRadius: FloatTheme.tileRadius,
                    style: .continuous
                )
            )
            .overlay(
                RoundedRectangle(
                    cornerRadius: FloatTheme.tileRadius,
                    style: .continuous
                )
                .strokeBorder(tint.opacity(isEnabled ? 0.14 : 0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.48)
    }
}

private struct ForecastRow: View {
    let item: CashFlowForecastItem
    let currencyCode: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            FloatIconBadge(icon: "calendar.badge.clock", tint: tint, size: 36)
            VStack(alignment: .leading, spacing: 4) {
                Text("Next \(item.horizonDays) days")
                    .font(.subheadline.weight(.semibold))
                Text("\(money(item.dailySafeMinor))/day after recurring and goals")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                Text(money(item.safeToSpendMinor))
                    .moneyStyle(size: 15, weight: .semibold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text("safe")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func money(_ amount: Int64) -> String {
        MoneyFormatter.string(minorUnits: amount, currencyCode: currencyCode)
    }
}

private struct BudgetAlertRow: View {
    let alert: BudgetAlertItem
    let currencyCode: String

    private var tint: Color {
        Color(hex: alert.colorHex)
    }

    var body: some View {
        HStack(spacing: 12) {
            FloatIconBadge(icon: alert.icon, tint: tint, size: 36)
            VStack(alignment: .leading, spacing: 4) {
                Text(alert.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text("\(money(alert.spentMinor)) of \(money(alert.budgetMinor))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text("\(Int((alert.progress * 100).rounded()))%")
                .font(.caption.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(alert.severity == .over ? Color(hex: "#B4613B") : tint)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(
                    tint.opacity(0.1),
                    in: RoundedRectangle(
                        cornerRadius: FloatTheme.tileRadius,
                        style: .continuous
                    )
                )
        }
    }

    private func money(_ amount: Int64) -> String {
        MoneyFormatter.string(minorUnits: amount, currencyCode: currencyCode)
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
                HStack(alignment: .top, spacing: 16) {
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
                        .moneyStyle(size: 40, weight: .bold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.58)
                        statusPill
                    }
                    Spacer(minLength: 0)
                    FloatIconBadge(
                        icon: result.overAmountMinor > 0
                            ? "exclamationmark.triangle.fill"
                            : "checkmark.seal.fill",
                        tint: result.overAmountMinor > 0
                            ? palette.caution
                            : palette.positive,
                        size: 46
                    )
                }
                Divider().opacity(0.5)
                HStack(spacing: 10) {
                    HeroMetricPill(
                        title: "Daily",
                        value: MoneyFormatter.string(
                            minorUnits: result.dailyAllowanceMinor,
                            currencyCode: currencyCode
                        ),
                        icon: "calendar",
                        tint: palette.accent
                    )
                    HeroMetricPill(
                        title: "Left",
                        value: "\(result.daysRemaining)d",
                        icon: "hourglass",
                        tint: palette.positive
                    )
                    HeroMetricPill(
                        title: "Spent",
                        value: MoneyFormatter.string(
                            minorUnits: result.variableSpentMinor,
                            currencyCode: currencyCode
                        ),
                        icon: "chart.bar.fill",
                        tint: palette.caution
                    )
                }
            }
        }
    }

    private var statusPill: some View {
        Text(
            result.overAmountMinor > 0
                ? "\(MoneyFormatter.string(minorUnits: result.overAmountMinor, currencyCode: currencyCode)) over this period"
                : "On track this period"
        )
        .font(.caption.weight(.semibold))
        .foregroundStyle(result.overAmountMinor > 0 ? palette.caution : palette.positive)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            (result.overAmountMinor > 0 ? palette.caution : palette.positive)
                .opacity(0.12),
            in: RoundedRectangle(
                cornerRadius: FloatTheme.tileRadius,
                style: .continuous
            )
        )
    }
}

private struct HeroMetricPill: View {
    let title: String
    let value: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .moneyStyle(size: 13, weight: .semibold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            tint.opacity(0.08),
            in: RoundedRectangle(
                cornerRadius: FloatTheme.tileRadius,
                style: .continuous
            )
        )
        .overlay(
            RoundedRectangle(
                cornerRadius: FloatTheme.tileRadius,
                style: .continuous
            )
            .strokeBorder(tint.opacity(0.14), lineWidth: 1)
        )
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

    private var spendableBaseMinor: Int64 {
        max(
            1,
            result.safeToSpendMinor - result.overAmountMinor
                + result.variableSpentMinor
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 14) {
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
                    note: spendingSummary,
                    amount: result.variableSpentMinor,
                    progress: result.spendingProgress,
                    tint: palette.accent
                )
            }

            Divider().opacity(0.45)

            VStack(alignment: .leading, spacing: 12) {
                Text("Allocation")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                AllocationBar(
                    safeMinor: result.safeToSpendMinor,
                    spentMinor: result.variableSpentMinor,
                    committedMinor: committedMinor,
                    totalMinor: chartTotal,
                    safeColor: palette.positive,
                    spentColor: palette.accent,
                    committedColor: palette.caution
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
        }
        .padding(16)
        .background(
            .thinMaterial,
            in: RoundedRectangle(
                cornerRadius: FloatTheme.controlRadius,
                style: .continuous
            )
        )
        .background(
            palette.accent.opacity(0.06),
            in: RoundedRectangle(
                cornerRadius: FloatTheme.controlRadius,
                style: .continuous
            )
        )
        .overlay(
            RoundedRectangle(
                cornerRadius: FloatTheme.controlRadius,
                style: .continuous
            )
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

    private var spendingSummary: String {
        "\(money(result.variableSpentMinor)) of \(money(spendableBaseMinor)) used"
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
                    let clampedProgress = min(max(progress, 0), 1)
                    if roundedPercent(clampedProgress) > 0 {
                        Capsule()
                            .fill(tint.gradient)
                            .frame(
                                width: max(
                                    6,
                                    proxy.size.width * CGFloat(clampedProgress)
                                )
                            )
                    }
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
        percentText(for: value)
    }

    private func sharePercent(_ amount: Int64, total: Int64) -> String {
        let value = Double(max(0, amount)) / Double(max(1, total))
        return percentText(for: value)
    }

    private func money(_ amount: Int64) -> String {
        MoneyFormatter.string(minorUnits: amount, currencyCode: currencyCode)
    }

    private func percentText(for value: Double) -> String {
        let clamped = min(max(value, 0), 1)
        guard clamped > 0 else { return "0%" }
        let rounded = Int((clamped * 100).rounded())
        return rounded == 0 ? "<1%" : "\(rounded)%"
    }

    private func roundedPercent(_ value: Double) -> Int {
        Int((min(max(value, 0), 1) * 100).rounded())
    }
}

private struct AllocationBar: View {
    let safeMinor: Int64
    let spentMinor: Int64
    let committedMinor: Int64
    let totalMinor: Int64
    let safeColor: Color
    let spentColor: Color
    let committedColor: Color

    private var visibleSegments: [AllocationSegment] {
        [
            AllocationSegment(amount: safeMinor, color: safeColor),
            AllocationSegment(amount: spentMinor, color: spentColor),
            AllocationSegment(amount: committedMinor, color: committedColor),
        ]
        .filter { segment in
            segment.amount > 0
                && roundedPercent(Double(segment.amount) / Double(max(totalMinor, 1))) > 0
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let spacing: CGFloat = 4
            let segments = visibleSegments
            let availableWidth = max(
                0,
                proxy.size.width - spacing * CGFloat(max(0, segments.count - 1))
            )
            HStack(spacing: 4) {
                ForEach(segments) { segment in
                    Capsule()
                        .fill(segment.color.gradient)
                        .frame(
                            width: segmentWidth(
                                segment,
                                availableWidth: availableWidth
                            )
                        )
                }
                if segments.isEmpty {
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(height: 16)
        .padding(3)
        .background(Color.primary.opacity(0.07), in: Capsule())
    }

    private func segmentWidth(
        _ segment: AllocationSegment,
        availableWidth: CGFloat
    ) -> CGFloat {
        let percent = roundedPercent(Double(segment.amount) / Double(max(totalMinor, 1)))
        return availableWidth * CGFloat(percent) / 100
    }

    private func roundedPercent(_ value: Double) -> Int {
        Int((min(max(value, 0), 1) * 100).rounded())
    }
}

private struct AllocationSegment: Identifiable {
    let id = UUID()
    let amount: Int64
    let color: Color
}
