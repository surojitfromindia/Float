import Foundation
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
    @Query(sort: \EventItem.startDate, order: .reverse) private var events: [EventItem]
    @Query private var categoryBudgets: [CategoryBudgetItem]
    @State private var recurringRuleToEdit: RecurringRuleItem?
    @State private var recurringRulePendingPayment: RecurringRuleItem?
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

    private var pinnedEvents: [EventItem] {
        events.filter { $0.pinned }
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
            return AppLocalization.string("spent so far")
        }
        let difference = todayExpenses - yesterdayExpenses
        if difference == 0 {
            return AppLocalization.string("same as yesterday")
        }
        if difference > 0 {
            return localizedFormat("%@ over yesterday", money(abs(difference)))
        }
        return localizedFormat("%@ under yesterday", money(abs(difference)))
    }

    private func money(_ amount: Int64) -> String {
        MoneyFormatter.string(
            minorUnits: amount,
            currencyCode: appState.selectedCurrencyCode
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                SafeToSpendHeroCard(
                    result: result,
                    currencyCode: appState.selectedCurrencyCode,
                    palette: appState.themePalette.hero
                )

                quickActions
                queueLinksSection
                pinnedEventsSection
                cashFlowForecast
                budgetAlertsSection
                recentTransactionsSection
                budgetOverview
            }
            .padding(20)
            .padding(.bottom, 150)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Float")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.primary)
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    isBulkEntrySheetPresented = true
                } label: {
                    Image(systemName: "square.stack.3d.up.fill")
                }
                .accessibilityLabel(LocalizedStringResource("Bulk add transactions"))

                Button {
                    presentNewTransaction()
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(LocalizedStringResource("Add transaction"))
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .background {
            HomeCalmBackground()
                .ignoresSafeArea()
        }
        .sheet(item: $recurringRuleToEdit) { rule in
            RecurringEditorView(rule: rule)
        }
        .alert(
            LocalizedStringResource("Pay recurring?"),
            isPresented: Binding(
                get: { recurringRulePendingPayment != nil },
                set: { isPresented in
                    if !isPresented {
                        recurringRulePendingPayment = nil
                    }
                }
            ),
            presenting: recurringRulePendingPayment
        ) { rule in
            Button(LocalizedStringResource("Mark paid"), role: .destructive) {
                markUpcomingRecurringPaid(rule)
                recurringRulePendingPayment = nil
            }
            Button(LocalizedStringResource("Cancel"), role: .cancel) {
                recurringRulePendingPayment = nil
            }
        } message: { rule in
            Text(
                AppLocalization.string(
                    "This will create a posted transaction and advance the next recurring date."
                )
                    + "\n\n" + recurringTitle(for: rule)
            )
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
                title: LocalizedStringResource("Expense"),
                icon: "minus.circle.fill",
                tint: appState.themePalette.caution
            ) {
                presentNewTransaction(isExpense: true)
            }
            HomeActionButton(
                title: LocalizedStringResource("Income"),
                icon: "plus.circle.fill",
                tint: appState.themePalette.positive
            ) {
                presentNewTransaction(isExpense: false)
            }
            HomeActionButton(
                title: LocalizedStringResource("Transfer"),
                icon: "arrow.left.arrow.right.circle.fill",
                tint: appState.themePalette.accent,
                isEnabled: accounts.filter { !$0.archived }.count >= 2
            ) {
                appState.presentNewTransfer()
            }
            HomeActionButton(
                title: LocalizedStringResource("Add to goal"),
                icon: "target",
                tint: Color(hex: "#8B5CF6"),
                isEnabled: nearestOpenGoal != nil
            ) {
                contributionGoal = nearestOpenGoal
            }
            HomeActionButton(
                title: LocalizedStringResource("Pay recurring"),
                icon: "checkmark.circle.fill",
                tint: appState.themePalette.caution,
                isEnabled: upcomingRecurringExpense != nil
            ) {
                recurringRulePendingPayment = upcomingRecurringExpense
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var cashFlowForecast: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: LocalizedStringResource("Forecast"))
            ForecastStripCard(
                items: Array(forecastItems.prefix(3)),
                currencyCode: appState.selectedCurrencyCode,
                tint: appState.themePalette.accent
            )
        }
    }

    private var pendingQueueBadge: String? {
        let total = pendingMetrics.overdueCount
            + pendingMetrics.dueTodayCount
            + pendingMetrics.upcomingCount
        return total > 0 ? "\(total)" : nil
    }

    private var pendingQueueSubtitle: String {
        guard !pendingMetrics.isEmpty else {
            return AppLocalization.string(
                "Convert expected transactions when they post."
            )
        }
        let count = pendingMetrics.overdueCount
            + pendingMetrics.dueTodayCount
            + pendingMetrics.upcomingCount
        return localizedFormat(
            "%lld transaction%@ need attention.",
            Int64(count),
            count == 1 ? "" : "s"
        )
    }

    private var budgetOverview: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: LocalizedStringResource("Budget overview"))
            BudgetStatusChart(
                result: result,
                currencyCode: appState.selectedCurrencyCode
            )
        }
    }

    private var recentTransactionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: LocalizedStringResource("Recent"))
            HomeGlassPanel(padding: 18, tint: appState.themePalette.accent) {
                if dashboardSnapshot.recentTransactions.isEmpty {
                    EmptyStateView(
                        icon: "sparkles",
                        title: LocalizedStringResource("No transactions yet"),
                        message: LocalizedStringResource("Add your first expense when you are ready.")
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

    @ViewBuilder private var budgetAlertsSection: some View {
        if !budgetAlerts.isEmpty || !pendingMetrics.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: LocalizedStringResource("Budget alerts"))
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

    @ViewBuilder private var pinnedEventsSection: some View {
        if appState.showPinnedEventsInHomeView && !pinnedEvents.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: LocalizedStringResource("Pinned events"))
                VStack(spacing: 12) {
                    ForEach(pinnedEvents.prefix(3)) { event in
                        NavigationLink {
                            EventDetailView(event: event)
                        } label: {
                            EventRowView(event: event, showsDescription: false)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var queueLinksSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: LocalizedStringResource("Action center"))
            HomeGlassPanel(padding: 18, tint: appState.themePalette.accent) {
                VStack(spacing: 11) {
                    NavigationLink {
                        PendingTransactionsView()
                    } label: {
                        QueueLinkRow(
                            title: LocalizedStringResource("Pending queue"),
                            subtitle: pendingQueueSubtitle,
                            icon: "clock.badge.exclamationmark.fill",
                            tint: appState.themePalette.accent,
                            trailingText: pendingQueueBadge
                        )
                    }
                    .buttonStyle(.plain)

                    Divider()

                    NavigationLink {
                        ReviewQueueView()
                    } label: {
                        QueueLinkRow(
                            title: LocalizedStringResource("Review queue"),
                            subtitle: AppLocalization.string(
                                "Missing details, duplicates, and large transactions."
                            ),
                            icon: "checklist",
                            tint: appState.themePalette.accent
                        )
                    }
                    .buttonStyle(.plain)

                    Divider()

                    NavigationLink {
                        EventsView()
                    } label: {
                        QueueLinkRow(
                            title: LocalizedStringResource("View events"),
                            subtitle: AppLocalization.string(
                                "Timelines, charts, and linked transactions."
                            ),
                            icon: "calendar.badge.plus",
                            tint: appState.themePalette.accent
                        )
                    }
                    .buttonStyle(.plain)

                    if let rule = upcomingRecurringExpense {
                        Divider()

                        Button {
                            recurringRuleToEdit = rule
                        } label: {
                            QueueLinkRow(
                                title: LocalizedStringResource("Upcoming recurring"),
                                subtitle: recurringSubtitle(for: rule),
                                icon: rule.category?.iconKey ?? "repeat",
                                tint: appState.themePalette.accent,
                                trailingText: MoneyFormatter.string(
                                    minorUnits: rule.amountMinor,
                                    currencyCode: appState.selectedCurrencyCode
                                )
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(LocalizedStringResource("Edit upcoming recurring rule"))
                    }

                    if let goal = nearestOpenGoal {
                        Divider()

                        Button {
                            contributionGoal = goal
                        } label: {
                            QueueLinkRow(
                                title: LocalizedStringResource("Nearest goal"),
                                subtitle: goalSubtitle(for: goal),
                                icon: "target",
                                tint: appState.themePalette.accent,
                                trailingText: goalProgressText(for: goal)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(LocalizedStringResource("Add to nearest goal"))
                    }
                }
            }
        }
    }

    private func recurringSubtitle(for rule: RecurringRuleItem) -> String {
        let date = localizedAbbreviatedDate(rule.nextRunDate)
        return localizedFormat("%@ - %@", recurringTitle(for: rule), date)
    }

    private func recurringTitle(for rule: RecurringRuleItem) -> String {
        rule.note?.isEmpty == false
            ? rule.note ?? ""
            : rule.category?.name ?? AppLocalization.string("Unknown Category")
    }

    private func goalSubtitle(for goal: GoalItem) -> String {
        let saved = MoneyFormatter.string(
            minorUnits: goal.savedMinor,
            currencyCode: appState.selectedCurrencyCode
        )
        let target = MoneyFormatter.string(
            minorUnits: goal.targetMinor,
            currencyCode: appState.selectedCurrencyCode
        )
        return localizedFormat("%@ - %@ of %@", goal.name, saved, target)
    }

    private func goalProgressText(for goal: GoalItem) -> String {
        let progress = Double(goal.savedMinor) / Double(max(goal.targetMinor, 1))
        return "\(Int((progress * 100).rounded()))%"
    }

    private func markUpcomingRecurringPaid(_ rule: RecurringRuleItem) {
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

private func localizedFormat(_ key: String, _ arguments: CVarArg...) -> String {
    AppLocalization.format(key, arguments: arguments)
}

private func localizedAbbreviatedDate(_ date: Date) -> String {
    date.formatted(
        Date.FormatStyle(date: .abbreviated, time: .omitted)
            .locale(AppLocalization.locale)
    )
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
    let title: LocalizedStringResource
    let amountMinor: Int64
    let caption: LocalizedStringResource
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

private struct HomeCalmBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Color(colorScheme == .dark ? .systemBackground : .systemGroupedBackground)
    }
}

private struct HomeGlassPanel<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let padding: CGFloat
    let tint: Color
    let content: Content

    init(
        padding: CGFloat = 18,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) {
        self.padding = padding
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        let shape = RoundedRectangle(
            cornerRadius: 24,
            style: .continuous
        )

        content
            .padding(padding)
            .background(
                Color(colorScheme == .dark ? .secondarySystemGroupedBackground : .systemBackground),
                in: shape
            )
            .overlay(
                shape.strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.05), lineWidth: 1)
            )
            .shadow(
                color: .black.opacity(colorScheme == .dark ? 0.20 : 0.06),
                radius: colorScheme == .dark ? 18 : 20,
                x: 0,
                y: colorScheme == .dark ? 10 : 8
            )
    }
}

private struct HomeActionButton: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: LocalizedStringResource
    let icon: String
    let tint: Color
    var isEnabled = true
    let action: () -> Void

    private var fillOpacity: Double {
        colorScheme == .dark ? 0.14 : 0.08
    }

    private var strokeOpacity: Double {
        colorScheme == .dark ? 0.14 : 0.08
    }

    var body: some View {
        let shape = RoundedRectangle(
            cornerRadius: FloatTheme.controlRadius,
            style: .continuous
        )

        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                tint.opacity(fillOpacity),
                in: shape
            )
            .overlay(
                shape.strokeBorder(tint.opacity(strokeOpacity), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.48)
        .accessibilityLabel(title)
    }
}

private struct ForecastStripCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let items: [CashFlowForecastItem]
    let currencyCode: String
    let tint: Color

    var body: some View {
        HomeGlassPanel(padding: 12, tint: tint) {
            if items.isEmpty {
                EmptyStateView(
                    icon: "calendar.badge.clock",
                    title: LocalizedStringResource("No forecast yet"),
                    message: LocalizedStringResource("Add a budget to see the next cash-flow windows.")
                )
            } else {
                HStack(spacing: 0) {
                    ForEach(items) { item in
                        ForecastStripItem(
                            item: item,
                            currencyCode: currencyCode,
                            tint: tint
                        )
                        .frame(maxWidth: .infinity)

                        if item.id != items.last?.id {
                            Divider()
                                .padding(.vertical, 6)
                                .opacity(colorScheme == .dark ? 0.75 : 0.5)
                        }
                    }
                }
            }
        }
    }
}

private struct ForecastStripItem: View {
    let item: CashFlowForecastItem
    let currencyCode: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "calendar.badge.clock")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(tint)
                Text(localizedFormat("%lldd", Int64(item.horizonDays)))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            Text(money(item.safeToSpendMinor))
                .moneyStyle(size: 15, weight: .bold)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
            Text(LocalizedStringResource("safe"))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
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
                Text(localizedFormat("%@ of %@", money(alert.spentMinor), money(alert.budgetMinor)))
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
                    title: LocalizedStringResource("Pending overdue"),
                    count: metrics.overdueCount,
                    amountMinor: metrics.overdueMinor,
                    icon: "exclamationmark.triangle.fill",
                    tint: Color(hex: "#B4613B")
                )
            }
            if metrics.dueTodayCount > 0 {
                row(
                    title: LocalizedStringResource("Pending due today"),
                    count: metrics.dueTodayCount,
                    amountMinor: metrics.dueTodayMinor,
                    icon: "calendar.badge.exclamationmark",
                    tint: tint
                )
            }
            if metrics.upcomingCount > 0 {
                row(
                    title: LocalizedStringResource("Pending upcoming"),
                    count: metrics.upcomingCount,
                    amountMinor: metrics.upcomingMinor,
                    icon: "calendar.badge.clock",
                    tint: tint
                )
            }
        }
    }

    private func row(
        title: LocalizedStringResource,
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
                Text(localizedFormat("%lld pending", Int64(count)))
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

private struct QueueLinkRow: View {
    let title: LocalizedStringResource
    let subtitle: String
    let icon: String
    let tint: Color
    var trailingText: String?

    var body: some View {
        HStack(spacing: 12) {
            HomeRowIcon(icon: icon, tint: tint)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            if let trailingText {
                Text(trailingText)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(tint.opacity(0.11), in: Capsule())
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }
}

private struct HomeRowIcon: View {
    let icon: String
    let tint: Color

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 38, height: 38)
            .background(tint.opacity(0.10), in: Circle())
    }
}

struct SafeToSpendHeroCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let result: SafeToSpendResult
    let currencyCode: String
    let palette: FloatHeroPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(LocalizedStringResource("Spendable"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(
                        MoneyFormatter.string(
                            minorUnits: result.safeToSpendMinor,
                            currencyCode: currencyCode
                        )
                    )
                    .moneyStyle(size: 46, weight: .bold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.52)
                }
                Spacer(minLength: 12)
                statusPill
            }

            Text(statusCaption)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            HeroProgressRail(
                progress: result.spendingProgress,
                tint: statusTint,
                track: palette.railTrack
            )

            HStack(spacing: 0) {
                HeroMetricPill(
                    title: LocalizedStringResource("Daily"),
                    value: MoneyFormatter.string(
                        minorUnits: result.dailyAllowanceMinor,
                        currencyCode: currencyCode
                    )
                )
                Divider().padding(.vertical, 4)
                HeroMetricPill(
                    title: LocalizedStringResource("Left"),
                    value: localizedFormat("%lldd", Int64(result.daysRemaining))
                )
                Divider().padding(.vertical, 4)
                HeroMetricPill(
                    title: LocalizedStringResource("Spent"),
                    value: MoneyFormatter.string(
                        minorUnits: result.variableSpentMinor,
                        currencyCode: currencyCode
                    )
                )
            }
            .frame(height: 54)
            .padding(.horizontal, 4)
        }
        .padding(20)
        .heroSurface(
            palette: palette,
            status: statusTint,
            isDark: colorScheme == .dark
        )
    }

    private var positiveTint: Color {
        palette.positive
    }

    private var cautionTint: Color {
        palette.caution
    }

    private var statusTint: Color {
        result.overAmountMinor > 0 ? cautionTint : positiveTint
    }

    private var statusPill: some View {
        Text(
            result.overAmountMinor > 0
                ? LocalizedStringResource("Over budget")
                : LocalizedStringResource("Safe")
        )
        .font(.caption.weight(.semibold))
        .foregroundStyle(statusTint)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            statusTint.opacity(colorScheme == .dark ? 0.22 : 0.12),
            in: RoundedRectangle(
                cornerRadius: FloatTheme.tileRadius,
                style: .continuous
            )
        )
    }

    private var statusCaption: String {
        if result.overAmountMinor > 0 {
            return localizedFormat(
                "%@ over this period after recurring and goals.",
                MoneyFormatter.string(
                    minorUnits: result.overAmountMinor,
                    currencyCode: currencyCode
                )
            )
        }
        return AppLocalization.string(
            "After recurring, goals, and spending recorded this period."
        )
    }
}

private extension View {
    @ViewBuilder
    func heroSurface(
        palette: FloatHeroPalette,
        status: Color,
        isDark: Bool
    ) -> some View {
        let shape = RoundedRectangle(
            cornerRadius: 30,
            style: .continuous
        )

        self
            .background(
                LinearGradient(
                    colors: [
                        palette.backgroundTop,
                        palette.backgroundBottom,
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: shape
            )
            .overlay(alignment: .topTrailing) {
                Circle()
                    .fill(palette.glow.opacity(isDark ? 0.24 : 0.12))
                    .frame(width: 112, height: 112)
                    .blur(radius: 28)
                    .offset(x: 26, y: -34)
                    .allowsHitTesting(false)
                Circle()
                    .fill(status.opacity(isDark ? 0.14 : 0.08))
                    .frame(width: 78, height: 78)
                    .blur(radius: 20)
                    .offset(x: -2, y: -10)
                    .allowsHitTesting(false)
            }
            .overlay(
                shape.strokeBorder(
                    palette.accent.opacity(isDark ? 0.22 : 0.12),
                    lineWidth: 1
                )
            )
            .shadow(
                color: .black.opacity(isDark ? 0.26 : 0.075),
                radius: 24,
                x: 0,
                y: 14
            )
    }
}

private struct HeroMetricPill: View {
    let title: LocalizedStringResource
    let value: String

    var body: some View {
        VStack(alignment: .center, spacing: 3) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .moneyStyle(size: 13, weight: .semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct HeroProgressRail: View {
    @Environment(\.colorScheme) private var colorScheme
    let progress: Double
    let tint: Color
    let track: Color

    private var clampedProgress: Double {
        min(max(progress, 0), 1)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(track.opacity(colorScheme == .dark ? 0.65 : 0.52))
                Capsule()
                    .fill(tint.gradient)
                    .frame(
                        width: max(
                            8,
                            proxy.size.width * CGFloat(clampedProgress)
                        )
                    )
                    .shadow(
                        color: tint.opacity(colorScheme == .dark ? 0.32 : 0.18),
                        radius: 8,
                        y: 2
                    )
            }
        }
        .frame(height: 7)
        .padding(2)
        .background(track.opacity(colorScheme == .dark ? 0.22 : 0.34), in: Capsule())
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
                    title: LocalizedStringResource("Period"),
                    detail: localizedFormat(
                        "%@ elapsed",
                        progressPercent(value: result.periodProgress)
                    ),
                    note: periodSummary,
                    amount: nil,
                    progress: result.periodProgress,
                    tint: palette.accent
                )
                chartMetric(
                    title: LocalizedStringResource("Spending"),
                    detail: localizedFormat(
                        "%@ used",
                        progressPercent(value: result.spendingProgress)
                    ),
                    note: spendingSummary,
                    amount: result.variableSpentMinor,
                    progress: result.spendingProgress,
                    tint: palette.accent
                )
            }

            Divider().opacity(0.45)

            VStack(alignment: .leading, spacing: 12) {
                Text(LocalizedStringResource("Allocation"))
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
                        LocalizedStringResource("Safe"),
                        amount: result.safeToSpendMinor,
                        total: chartTotal,
                        color: palette.positive
                    )
                    legendItem(
                        LocalizedStringResource("Spent"),
                        amount: result.variableSpentMinor,
                        total: chartTotal,
                        color: palette.accent
                    )
                    legendItem(
                        LocalizedStringResource("Committed"),
                        amount: committedMinor,
                        total: chartTotal,
                        color: palette.caution
                    )
                }
            }
        }
        .padding(16)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
    }

    private var periodSummary: String {
        let start = localizedAbbreviatedDate(result.periodStart)
        let end = localizedAbbreviatedDate(result.periodEnd)
        return localizedFormat(
            "%@ - %@ · %lld days left",
            start,
            end,
            Int64(result.daysRemaining)
        )
    }

    private var spendingSummary: String {
        localizedFormat(
            "%@ of %@ used",
            money(result.variableSpentMinor),
            money(spendableBaseMinor)
        )
    }

    private func chartMetric(
        title: LocalizedStringResource,
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
        _ title: LocalizedStringResource,
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

    private func progressPercent(value: Double) -> String {
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
