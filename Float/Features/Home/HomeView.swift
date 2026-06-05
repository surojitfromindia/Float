import SwiftData
import SwiftUI

struct HomeView: View {
    // model context is database context, like database connection.
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @Query private var goals: [GoalItem]
    @Query private var recurringRules: [RecurringRuleItem]
    @Query private var budgets: [BudgetPeriodItem]
    @Query(sort: \AccountItem.createdAt) private var accounts: [AccountItem]
    @Query private var categoryBudgets: [CategoryBudgetItem]
    @State private var recurringRuleToEdit: RecurringRuleItem?
    @State private var contributionGoal: GoalItem?
    @State private var dashboardSnapshot = HomeDashboardSnapshot.placeholder
    @State private var isEntrySheetPresented = false
    @State private var isBulkEntrySheetPresented = false
    @State private var newTransactionIsExpense: Bool?

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
        dashboardSnapshot.result
    }

    // The "Today" tile is separate from the period calculation: it only sums
    // expense transactions whose timestamps fall on the current calendar day.
    private var todayExpenses: Int64 {
        dashboardSnapshot.todayExpensesMinor
    }

    private var yesterdayExpenses: Int64 {
        dashboardSnapshot.yesterdayExpensesMinor
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
        dashboardSnapshot.forecastItems
    }

    private var budgetAlerts: [BudgetAlertItem] {
        dashboardSnapshot.budgetAlerts
    }

    private var pendingMetrics: PendingTransactionMetrics {
        dashboardSnapshot.pendingMetrics
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
                budgetOverview
                cashFlowForecast
                budgetAlertsSection
                pendingQueueLink
                reviewQueueLink
                upcomingRecurring
                nearestGoal
                recentTransactionsSection
            }
            .padding(20)
            .padding(.bottom, 150)
        }
        .navigationTitle("Float")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    isBulkEntrySheetPresented = true
                } label: {
                    Image(systemName: "square.stack.3d.up.fill")
                }
                .accessibilityLabel("Bulk add transactions")

                Button {
                    presentNewTransaction()
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
        .sheet(isPresented: $isEntrySheetPresented) {
            QuickAddKeypadSheet(
                transactionToEdit: nil,
                initialIsExpense: newTransactionIsExpense
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isBulkEntrySheetPresented) {
            BulkTransactionEntrySheet()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .onAppear {
            MaterializeRecurringTransactionsUseCase.run(
                modelContext: modelContext
            )
        }
        .task(id: dashboardLoadKey) {
            await loadDashboardSnapshot()
        }
        .onChange(of: appState.isEntrySheetPresented) { _, isPresented in
            guard !isPresented else { return }
            Task { await loadDashboardSnapshot() }
        }
        .onChange(of: isEntrySheetPresented) { _, isPresented in
            guard !isPresented else { return }
            Task { await loadDashboardSnapshot() }
        }
        .onChange(of: isBulkEntrySheetPresented) { _, isPresented in
            guard !isPresented else { return }
            Task { await loadDashboardSnapshot() }
        }
        .onChange(of: appState.isTransferSheetPresented) { _, isPresented in
            guard !isPresented else { return }
            Task { await loadDashboardSnapshot() }
        }
    }

    private var quickActions: some View {
        HStack(spacing: 10) {
            HomeActionButton(
                title: "Expense",
                icon: "minus.circle.fill",
                tint: appState.themePalette.caution
            ) {
                presentNewTransaction(isExpense: true)
            }
            HomeActionButton(
                title: "Income",
                icon: "plus.circle.fill",
                tint: appState.themePalette.positive
            ) {
                presentNewTransaction(isExpense: false)
            }
            HomeActionButton(
                title: "Transfer",
                icon: "arrow.left.arrow.right.circle.fill",
                tint: appState.themePalette.accent,
                isEnabled: accounts.filter { !$0.archived }.count >= 2
            ) {
                appState.presentNewTransfer()
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
        .frame(maxWidth: .infinity)
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
        if !budgetAlerts.isEmpty || !pendingMetrics.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Budget alerts")
                GlassCard {
                    VStack(spacing: 12) {
                        if !pendingMetrics.isEmpty {
                            PendingMetricsRows(
                                metrics: pendingMetrics,
                                currencyCode: appState.selectedCurrencyCode,
                                tint: appState.themePalette.accent
                            )
                            if !budgetAlerts.isEmpty {
                                Divider()
                            }
                        }
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

    private var reviewQueueLink: some View {
        NavigationLink {
            ReviewQueueView()
        } label: {
            GlassCard {
                HStack(spacing: 12) {
                    FloatIconBadge(
                        icon: "checklist",
                        tint: appState.themePalette.accent,
                        size: 38
                    )
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Review queue")
                            .font(.subheadline.weight(.semibold))
                        Text("Find missing details, duplicates, and large transactions.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var pendingQueueLink: some View {
        NavigationLink {
            PendingTransactionsView()
        } label: {
            GlassCard {
                HStack(spacing: 12) {
                    FloatIconBadge(
                        icon: "clock.badge.exclamationmark.fill",
                        tint: appState.themePalette.accent,
                        size: 38
                    )
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Pending queue")
                            .font(.subheadline.weight(.semibold))
                        Text("Convert expected transactions when they post.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
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
        Task { await loadDashboardSnapshot() }
    }

    private func presentNewTransaction(isExpense: Bool? = nil) {
        newTransactionIsExpense = isExpense
        isEntrySheetPresented = true
    }

    private var recentTransactionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Recent")
            GlassCard {
                if dashboardSnapshot.recentTransactions.isEmpty {
                    EmptyStateView(
                        icon: "sparkles",
                        title: "No transactions yet",
                        message: "Add your first expense when you are ready."
                    )
                } else {
                    VStack(spacing: 8) {
                        ForEach(dashboardSnapshot.recentTransactions) { transaction in
                            TransactionRowView(
                                transaction: transaction,
                                currencyCode: appState.selectedCurrencyCode
                            )
                            if transaction.id != dashboardSnapshot.recentTransactions.last?.id
                            {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
    }

    private var dashboardLoadKey: HomeDashboardLoadKey {
        HomeDashboardLoadKey(
            currencyCode: appState.selectedCurrencyCode,
            budgetID: activeBudget?.id,
            budgetUpdatedAt: activeBudget?.updatedAt,
            goalsUpdatedAt: goals.map(\.updatedAt).max(),
            recurringRulesUpdatedAt: recurringRules.map(\.updatedAt).max(),
            accountsUpdatedAt: accounts.map(\.updatedAt).max(),
            categoryBudgetsUpdatedAt: categoryBudgets.map(\.updatedAt).max(),
            recurringRemindersEnabled: appState.recurringRemindersEnabled,
            budgetAlertsEnabled: appState.budgetAlertsEnabled,
            goalRemindersEnabled: appState.goalRemindersEnabled,
            recurringReminderMinutes: appState.recurringReminderMinutes,
            goalReminderMinutes: appState.goalReminderMinutes,
            budgetAlertSensitivityRaw: appState.budgetAlertSensitivityRaw
        )
    }

    private func loadDashboardSnapshot() async {
        await Task.yield()
        dashboardSnapshot = fetchDashboardSnapshot()
        LocalNotificationScheduler.refresh(
            recurringRules: recurringRules,
            budgetAlerts: dashboardSnapshot.budgetAlerts,
            goals: goals,
            currencyCode: appState.selectedCurrencyCode,
            preferences: appState.reminderPreferences
        )
    }

    private func fetchDashboardSnapshot() -> HomeDashboardSnapshot {
        let now = Date()
        let calendar = Calendar.current
        let budget = activeBudget
        let period = BudgetPeriodCalculator.currentPeriod(
            for: budget,
            now: now,
            calendar: calendar
        )
        let periodEnd = endOfDay(for: period.end, calendar: calendar)
        let allTransactions = fetchAllTransactionsForBalance()
        let periodTransactions = allTransactions.filter {
            $0.timestamp >= period.start && $0.timestamp <= periodEnd
        }
        let comparisonTransactions = fetchComparisonTransactions(now: now, calendar: calendar)
        let result = SafeToSpendUseCase.calculate(
            period: period,
            expectedIncomeMinor: budget?.expectedIncomeMinor ?? 0,
            transactions: periodTransactions,
            goals: goals,
            recurringRules: recurringRules,
            now: now,
            calendar: calendar
        )
        let alerts = BudgetAlertsUseCase.calculate(
            categoryBudgets: categoryBudgets,
            transactions: periodTransactions,
            period: period,
            now: now,
            calendar: calendar
        )
        let forecast = CashFlowForecastUseCase.calculate(
            currentBalanceMinor: fetchCurrentBalanceMinor(),
            budget: budget,
            safeToSpend: result,
            goals: goals,
            recurringRules: recurringRules,
            now: now,
            calendar: calendar
        )

        return HomeDashboardSnapshot(
            result: result,
            todayExpensesMinor: sumExpenses(
                comparisonTransactions,
                onSameDayAs: now,
                calendar: calendar
            ),
            yesterdayExpensesMinor: sumYesterdayExpenses(
                comparisonTransactions,
                now: now,
                calendar: calendar
            ),
            forecastItems: forecast,
            budgetAlerts: alerts,
            pendingMetrics: pendingMetrics(
                transactions: allTransactions,
                period: period,
                now: now,
                calendar: calendar
            ),
            recentTransactions: fetchRecentTransactions()
        )
    }

    private func pendingMetrics(
        transactions: [TransactionItem],
        period: BudgetPeriod,
        now: Date,
        calendar: Calendar
    ) -> PendingTransactionMetrics {
        let todayStart = calendar.startOfDay(for: now)
        let todayEnd = endOfDay(for: now, calendar: calendar)
        let upcomingEnd = min(
            endOfDay(for: period.end, calendar: calendar),
            calendar.date(byAdding: .day, value: 7, to: todayEnd) ?? todayEnd
        )
        let pending = transactions.filter(\.isPending)

        let overdue = pending.filter { $0.displayDate < todayStart }
        let dueToday = pending.filter {
            $0.displayDate >= todayStart && $0.displayDate <= todayEnd
        }
        let upcoming = pending.filter {
            $0.displayDate > todayEnd && $0.displayDate <= upcomingEnd
        }

        return PendingTransactionMetrics(
            overdueCount: overdue.count,
            overdueMinor: overdue.reduce(Int64(0)) { $0 + $1.amountMinor },
            dueTodayCount: dueToday.count,
            dueTodayMinor: dueToday.reduce(Int64(0)) { $0 + $1.amountMinor },
            upcomingCount: upcoming.count,
            upcomingMinor: upcoming.reduce(Int64(0)) { $0 + $1.amountMinor }
        )
    }

    private func fetchTransactions(from start: Date, through end: Date)
        -> [TransactionItem]
    {
        do {
            let descriptor = FetchDescriptor<TransactionItem>(
                predicate: #Predicate<TransactionItem> { transaction in
                    transaction.timestamp >= start && transaction.timestamp <= end
                },
                sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
            )
            return try modelContext.fetch(descriptor)
        } catch {
            return []
        }
    }

    private func fetchComparisonTransactions(now: Date, calendar: Calendar)
        -> [TransactionItem]
    {
        guard
            let yesterday = calendar.date(byAdding: .day, value: -1, to: now)
        else {
            return []
        }
        let start = calendar.startOfDay(for: yesterday)
        let end = endOfDay(for: now, calendar: calendar)

        do {
            let postedStatus = TransactionStatus.posted.rawValue
            let descriptor = FetchDescriptor<TransactionItem>(
                predicate: #Predicate<TransactionItem> { transaction in
                    transaction.statusRaw == postedStatus
                        && transaction.isExpense
                        && transaction.timestamp >= start
                        && transaction.timestamp <= end
                }
            )
            return try modelContext.fetch(descriptor)
        } catch {
            return []
        }
    }

    private func fetchRecentTransactions() -> [TransactionItem] {
        do {
            var descriptor = FetchDescriptor<TransactionItem>(
                sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
            )
            descriptor.fetchLimit = 4
            return try modelContext.fetch(descriptor)
        } catch {
            return []
        }
    }

    private func fetchCurrentBalanceMinor() -> Int64 {
        let activeAccountIDs = Set(accounts.filter { !$0.archived }.map(\.id))
        let openingBalance = accounts
            .filter { !$0.archived }
            .reduce(Int64(0)) { $0 + $1.openingBalanceMinor }
        guard !activeAccountIDs.isEmpty else { return 0 }

        let transactionNet = fetchAllTransactionsForBalance().reduce(Int64(0)) {
            total,
            transaction in
            guard
                let accountID = transaction.account?.id,
                activeAccountIDs.contains(accountID),
                transaction.isPosted
            else {
                return total
            }
            return total + (transaction.isExpense ? -transaction.amountMinor : transaction.amountMinor)
        }
        let transferNet = fetchAllTransfersForBalance().reduce(Int64(0)) {
            total,
            transfer in
            var net = total
            if
                let fromID = transfer.fromAccount?.id,
                activeAccountIDs.contains(fromID)
            {
                net -= transfer.amountMinor
            }
            if
                let toID = transfer.toAccount?.id,
                activeAccountIDs.contains(toID)
            {
                net += transfer.amountMinor
            }
            return net
        }

        return openingBalance + transactionNet + transferNet
    }

    private func fetchAllTransactionsForBalance() -> [TransactionItem] {
        do {
            return try modelContext.fetch(FetchDescriptor<TransactionItem>())
        } catch {
            return []
        }
    }

    private func fetchAllTransfersForBalance() -> [TransferItem] {
        do {
            return try modelContext.fetch(FetchDescriptor<TransferItem>())
        } catch {
            return []
        }
    }

    private func sumExpenses(
        _ transactions: [TransactionItem],
        onSameDayAs date: Date,
        calendar: Calendar
    ) -> Int64 {
        transactions
            .filter { calendar.isDate($0.timestamp, inSameDayAs: date) }
            .reduce(Int64(0)) { $0 + $1.amountMinor }
    }

    private func sumYesterdayExpenses(
        _ transactions: [TransactionItem],
        now: Date,
        calendar: Calendar
    ) -> Int64 {
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: now) else {
            return 0
        }
        return sumExpenses(transactions, onSameDayAs: yesterday, calendar: calendar)
    }

    private func endOfDay(for date: Date, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: date)
        return calendar.date(
            byAdding: DateComponents(day: 1, second: -1),
            to: start
        ) ?? date
    }
}

private struct HomeDashboardLoadKey: Equatable {
    let currencyCode: String
    let budgetID: UUID?
    let budgetUpdatedAt: Date?
    let goalsUpdatedAt: Date?
    let recurringRulesUpdatedAt: Date?
    let accountsUpdatedAt: Date?
    let categoryBudgetsUpdatedAt: Date?
    let recurringRemindersEnabled: Bool
    let budgetAlertsEnabled: Bool
    let goalRemindersEnabled: Bool
    let recurringReminderMinutes: Int
    let goalReminderMinutes: Int
    let budgetAlertSensitivityRaw: String
}

private struct HomeDashboardSnapshot {
    let result: SafeToSpendResult
    let todayExpensesMinor: Int64
    let yesterdayExpensesMinor: Int64
    let forecastItems: [CashFlowForecastItem]
    let budgetAlerts: [BudgetAlertItem]
    let pendingMetrics: PendingTransactionMetrics
    let recentTransactions: [TransactionItem]

    static var placeholder: HomeDashboardSnapshot {
        let result = SafeToSpendUseCase.calculate(
            budget: nil,
            transactions: [],
            goals: [],
            recurringRules: []
        )
        return HomeDashboardSnapshot(
            result: result,
            todayExpensesMinor: 0,
            yesterdayExpensesMinor: 0,
            forecastItems: [],
            budgetAlerts: [],
            pendingMetrics: .empty,
            recentTransactions: []
        )
    }
}

private struct PendingTransactionMetrics: Equatable {
    let overdueCount: Int
    let overdueMinor: Int64
    let dueTodayCount: Int
    let dueTodayMinor: Int64
    let upcomingCount: Int
    let upcomingMinor: Int64

    static let empty = PendingTransactionMetrics(
        overdueCount: 0,
        overdueMinor: 0,
        dueTodayCount: 0,
        dueTodayMinor: 0,
        upcomingCount: 0,
        upcomingMinor: 0
    )

    var isEmpty: Bool {
        overdueCount == 0 && dueTodayCount == 0 && upcomingCount == 0
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
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
            .background(
                tint.opacity(isEnabled ? 0.09 : 0.04),
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
                .strokeBorder(tint.opacity(isEnabled ? 0.14 : 0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.48)
        .accessibilityLabel(title)
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

private struct PendingMetricsRows: View {
    let metrics: PendingTransactionMetrics
    let currencyCode: String
    let tint: Color

    var body: some View {
        VStack(spacing: 10) {
            if metrics.overdueCount > 0 {
                row(
                    title: "Pending overdue",
                    count: metrics.overdueCount,
                    amountMinor: metrics.overdueMinor,
                    icon: "exclamationmark.triangle.fill",
                    tint: Color(hex: "#B4613B")
                )
            }
            if metrics.dueTodayCount > 0 {
                row(
                    title: "Pending due today",
                    count: metrics.dueTodayCount,
                    amountMinor: metrics.dueTodayMinor,
                    icon: "calendar.badge.exclamationmark",
                    tint: tint
                )
            }
            if metrics.upcomingCount > 0 {
                row(
                    title: "Pending upcoming",
                    count: metrics.upcomingCount,
                    amountMinor: metrics.upcomingMinor,
                    icon: "calendar.badge.clock",
                    tint: tint
                )
            }
        }
    }

    private func row(
        title: String,
        count: Int,
        amountMinor: Int64,
        icon: String,
        tint: Color
    ) -> some View {
        HStack(spacing: 12) {
            FloatIconBadge(icon: icon, tint: tint, size: 36)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text("\(count) pending")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(
                MoneyFormatter.string(
                    minorUnits: amountMinor,
                    currencyCode: currencyCode
                )
            )
            .moneyStyle(size: 14, weight: .semibold)
            .foregroundStyle(tint)
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
        .floatGlassSurface(
            cornerRadius: FloatTheme.controlRadius,
            material: .thinMaterial,
            tint: palette.accent,
            strokeOpacity: 0.1
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
