import Charts
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct InsightsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @Query private var budgets: [BudgetPeriodItem]
    @Query private var categoryBudgets: [CategoryBudgetItem]
    @Query private var goals: [GoalItem]
    @Query private var recurringRules: [RecurringRuleItem]

    @State private var selectedRange = InsightRange.currentPeriod
    @State private var customStart = Calendar.current.date(
        byAdding: .month,
        value: -1,
        to: Date()
    ) ?? Date()
    @State private var customEnd = Date()
    @State private var exportingReport = false
    @State private var reportDocument = ReportPDFDocument()
    @State private var selectedCategory: CategoryDrillDown?
    @State private var spendActivityMode = SpendActivityMode.daily
    @State private var report = InsightReport.placeholder
    @State private var isLoadingReport = false
    @State private var reportError: String?
    @State private var hasLoadedReport = false

    private var palette: [Color] {
        appState.themePalette.chartColors
    }

    private var activeBudget: BudgetPeriodItem? {
        budgets.first { $0.isActive } ?? budgets.first
    }

    private var currentPeriod: BudgetPeriod {
        BudgetPeriodCalculator.currentPeriod(for: activeBudget)
    }

    private var activeRange: BudgetPeriod {
        let calendar = Calendar.current
        switch selectedRange {
        case .currentPeriod:
            return currentPeriod
        case .lastPeriod:
            let length = rangeDayCount(currentPeriod)
            let end = calendar.date(byAdding: .day, value: -1, to: currentPeriod.start)
                ?? currentPeriod.start
            let start = calendar.date(byAdding: .day, value: -length + 1, to: end)
                ?? end
            return BudgetPeriod(start: calendar.startOfDay(for: start), end: calendar.startOfDay(for: end))
        case .lastThreePeriods:
            let length = rangeDayCount(currentPeriod)
            let start = calendar.date(byAdding: .day, value: -(length * 2), to: currentPeriod.start)
                ?? currentPeriod.start
            return BudgetPeriod(start: calendar.startOfDay(for: start), end: currentPeriod.end)
        case .thisYear:
            let start = calendar.date(from: calendar.dateComponents([.year], from: Date()))
                ?? currentPeriod.start
            return BudgetPeriod(start: start, end: Date())
        case .custom:
            return BudgetPeriod(
                start: calendar.startOfDay(for: min(customStart, customEnd)),
                end: calendar.startOfDay(for: max(customStart, customEnd))
            )
        }
    }

    private var previousRange: BudgetPeriod {
        let calendar = Calendar.current
        let days = rangeDayCount(activeRange)
        let previousEnd = calendar.date(byAdding: .day, value: -1, to: activeRange.start)
            ?? activeRange.start
        let previousStart = calendar.date(byAdding: .day, value: -days + 1, to: previousEnd)
            ?? previousEnd
        return BudgetPeriod(
            start: calendar.startOfDay(for: previousStart),
            end: calendar.startOfDay(for: previousEnd)
        )
    }

    private var reportLoadKey: InsightReportLoadKey {
        InsightReportLoadKey(
            range: selectedRange,
            customStart: Calendar.current.startOfDay(for: customStart),
            customEnd: Calendar.current.startOfDay(for: customEnd),
            activeBudgetID: activeBudget?.id,
            activeBudgetUpdatedAt: activeBudget?.updatedAt,
            categoryBudgetUpdatedAt: categoryBudgets.map(\.updatedAt).max(),
            goalUpdatedAt: goals.map(\.updatedAt).max(),
            recurringUpdatedAt: recurringRules.map(\.updatedAt).max(),
            themeMode: appState.selectedThemeMode
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                rangeToolbar

                if selectedRange == .custom {
                    customRangeControls
                }

                if isLoadingReport && report.transactions.isEmpty {
                    loadingReportCard
                } else if let reportError {
                    reportErrorCard(reportError)
                } else {
                    executiveSummary
                    budgetHealthCard
                    calendarInsightCard
                    spendActivityCard
                    categoryBudgetCard
                    categoryCard
                    cashFlowTrendCard
                    recurringCard
                    goalsCard
                    topTransactionsCard
                }
            }
            .padding(20)
            .padding(.bottom, 40)
        }
        .navigationTitle("Reports")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: exportReport) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Export report")
            }
        }
        .fileExporter(
            isPresented: $exportingReport,
            document: reportDocument,
            contentType: .pdf,
            defaultFilename: report.defaultFilename
        ) { _ in }
        .sheet(item: $selectedCategory) { category in
            CategoryDrillDownSheet(
                category: category,
                currencyCode: appState.selectedCurrencyCode
            )
        }
        .task(id: reportLoadKey) {
            loadReportTransactions()
        }
        .onAppear {
            if hasLoadedReport {
                loadReportTransactions()
            }
        }
        .floatBackground()
    }

    private var rangeToolbar: some View {
        HStack {
            Menu {
                Picker("Range", selection: $selectedRange) {
                    ForEach(InsightRange.allCases) {
                        Text($0.title).tag($0)
                    }
                }
            } label: {
                Label(selectedRange.title, systemImage: "calendar")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.thinMaterial, in: Capsule())
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    )
            }
            .menuOrder(.fixed)

            Spacer()

            Text(report.dateRangeText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    private var customRangeControls: some View {
        GlassCard {
            VStack(spacing: 12) {
                DatePicker("From", selection: $customStart, displayedComponents: .date)
                DatePicker("To", selection: $customEnd, displayedComponents: .date)
            }
        }
    }

    private var loadingReportCard: some View {
        GlassCard {
            HStack(spacing: 12) {
                ProgressView()
                Text("Loading report")
                    .font(.subheadline.weight(.medium))
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func reportErrorCard(_ message: String) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("Report could not load", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(appState.themePalette.caution)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Retry", action: loadReportTransactions)
                    .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var executiveSummary: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Executive summary")
                            .font(.headline)
                        Text(report.narrative)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    NetFlowBadge(value: report.netCashFlowMinor)
                }

                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: 12
                ) {
                    reportMetric(
                        "Income",
                        amount: report.incomeTotalMinor,
                        icon: "arrow.down.circle.fill",
                        tint: Color(hex: "#1B8A5A")
                    )
                    reportMetric(
                        "Expenses",
                        amount: report.expenseTotalMinor,
                        icon: "arrow.up.circle.fill",
                        tint: Color(hex: "#B4613B")
                    )
                    reportMetric(
                        "Net",
                        amount: report.netCashFlowMinor,
                        icon: "equal.circle.fill",
                        tint: report.netCashFlowMinor >= 0
                            ? Color(hex: "#1B8A5A") : Color(hex: "#B4613B")
                    )
                    reportMetric(
                        "Daily average",
                        amount: report.dailyAverageExpenseMinor,
                        icon: "calendar.badge.clock",
                        tint: Color(hex: "#0E7C7B")
                    )
                }

                HStack(spacing: 12) {
                    insightFact("Top category", report.topCategory?.name ?? "None")
                    insightFact("Biggest", report.biggestTransactionLabel)
                }
            }
        }
    }

    private var budgetHealthCard: some View {
        insightCard(
            title: "Budget health",
            subtitle: "Safe-to-spend position against period timing"
        ) {
            VStack(spacing: 12) {
                progressRow(
                    title: "Period elapsed",
                    detail: report.percentText(report.safeToSpend.periodProgress),
                    progress: report.safeToSpend.periodProgress,
                    tint: Color(hex: "#0E7C7B")
                )
                progressRow(
                    title: "Spending used",
                    detail: report.percentText(report.safeToSpend.spendingProgress),
                    progress: report.safeToSpend.spendingProgress,
                    tint: report.safeToSpend.spendingProgress > report.safeToSpend.periodProgress
                        ? Color(hex: "#B4613B") : Color(hex: "#1B8A5A")
                )

                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: 12
                ) {
                    reportMetric(
                        "Safe to spend",
                        amount: report.safeToSpend.safeToSpendMinor,
                        icon: "checkmark.seal.fill",
                        tint: Color(hex: "#1B8A5A")
                    )
                    reportMetric(
                        "Daily limit",
                        amount: report.safeToSpend.dailyAllowanceMinor,
                        icon: "calendar",
                        tint: Color(hex: "#0E7C7B")
                    )
                    reportMetric(
                        "Recurring due",
                        amount: report.safeToSpend.recurringDueMinor,
                        icon: "repeat",
                        tint: Color(hex: "#B4613B")
                    )
                    reportMetric(
                        "Goals needed",
                        amount: report.safeToSpend.goalContributionMinor,
                        icon: "target",
                        tint: Color(hex: "#8B5CF6")
                    )
                }

                Text(report.budgetHealthMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var calendarInsightCard: some View {
        insightCard(
            title: "Calendar insights",
            subtitle: "Day and week patterns from this report range"
        ) {
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: 12
            ) {
                reportMetric(
                    "Highest day",
                    value: report.highestExpenseDay?.summaryText(currencyCode: appState.selectedCurrencyCode)
                        ?? "None",
                    icon: "calendar.badge.exclamationmark",
                    tint: appState.themePalette.caution
                )
                reportMetric(
                    "Lightest day",
                    value: report.lowestExpenseDay?.summaryText(currencyCode: appState.selectedCurrencyCode)
                        ?? "None",
                    icon: "calendar",
                    tint: appState.themePalette.positive
                )
                reportMetric(
                    "Busiest day",
                    value: report.busiestDay?.countText ?? "None",
                    icon: "list.bullet.rectangle",
                    tint: appState.themePalette.accent
                )
                reportMetric(
                    "Week trend",
                    value: report.weekTrendText,
                    icon: "chart.line.uptrend.xyaxis",
                    tint: report.weekExpenseDeltaMinor <= 0
                        ? appState.themePalette.positive
                        : appState.themePalette.caution
                )
            }
        }
    }

    private var spendActivityCard: some View {
        insightCard(
            title: "Spend activity",
            subtitle: spendActivityMode == .year
                ? "Expense intensity by day across \(report.spendActivityYearText)"
                : "Expense intensity by day across this report range"
        ) {
            SpendActivityHeatmap(
                days: spendActivityMode == .year
                    ? report.yearSpendActivityDays
                    : report.spendActivityDays,
                mode: $spendActivityMode,
                currencyCode: appState.selectedCurrencyCode
            )
        }
    }

    private var categoryCard: some View {
        insightCard(
            title: "Category breakdown",
            subtitle: "Expense concentration by category"
        ) {
            if report.categoryInsights.isEmpty {
                EmptyStateView(
                    icon: "chart.pie",
                    title: "No spending yet",
                    message: "Category reports update after transactions are added."
                )
            } else {
                VStack(spacing: 18) {
                    ZStack {
                        Chart(report.categoryInsights) { item in
                            SectorMark(
                                angle: .value("Amount", item.amountMinor),
                                innerRadius: .ratio(0.64),
                                angularInset: 2
                            )
                            .cornerRadius(8)
                            .foregroundStyle(item.color)
                        }
                        .chartLegend(.hidden)

                        VStack(spacing: 4) {
                            Text("Total")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(money(report.expenseTotalMinor))
                                .moneyStyle(size: 20, weight: .bold)
                                .minimumScaleFactor(0.75)
                        }
                    }
                    .frame(height: 250)

                    VStack(spacing: 10) {
                        ForEach(report.categoryInsights) { item in
                            Button {
                                selectedCategory = report.drillDown(for: item)
                            } label: {
                                categoryRow(item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var categoryBudgetCard: some View {
        insightCard(
            title: "Category budgets",
            subtitle: "Spending against category limits for this range"
        ) {
            if report.categoryBudgetInsights.isEmpty {
                EmptyStateView(
                    icon: "slider.horizontal.3",
                    title: "No category budgets",
                    message: "Set category limits in Budget settings to track them here."
                )
            } else {
                VStack(spacing: 14) {
                    HStack(spacing: 12) {
                        reportMetric(
                            "Allocated",
                            amount: report.totalCategoryBudgetMinor,
                            icon: "chart.pie.fill",
                            tint: appState.themePalette.accent
                        )
                        reportMetric(
                            "Spent",
                            amount: report.totalCategoryBudgetSpentMinor,
                            icon: "creditcard.fill",
                            tint: report.overCategoryBudgetCount > 0
                                ? appState.themePalette.caution : appState.themePalette.positive
                        )
                    }

                    ForEach(report.categoryBudgetInsights) { item in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 10) {
                                Image(systemName: item.icon)
                                    .foregroundStyle(Color(hex: item.colorHex))
                                    .frame(width: 28, height: 28)
                                    .background(
                                        Color(hex: item.colorHex).opacity(0.12),
                                        in: Circle()
                                    )
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name)
                                        .font(.subheadline.weight(.semibold))
                                    Text(item.statusText(currencyCode: appState.selectedCurrencyCode))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(money(item.spentMinor))
                                    .moneyStyle(size: 14, weight: .semibold)
                            }

                            ProgressView(value: min(item.progress, 1))
                                .tint(item.isOverBudget ? appState.themePalette.caution : Color(hex: item.colorHex))
                        }
                    }
                }
            }
        }
    }

    private var cashFlowTrendCard: some View {
        insightCard(
            title: "Cash flow trend",
            subtitle: "Income, expenses, and net movement over time"
        ) {
            if report.cashFlowTrend.isEmpty {
                EmptyStateView(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "No trend yet",
                    message: "Add dated income and expenses to build a trend."
                )
            } else {
                Chart {
                    ForEach(report.cashFlowTrend) { item in
                        LineMark(
                            x: .value("Period", item.date, unit: report.cashFlowTrendUnit),
                            y: .value("Amount", item.incomeMinor),
                            series: .value("Type", "Income")
                        )
                            .foregroundStyle(appState.themePalette.positive)
                        .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))

                        LineMark(
                            x: .value("Period", item.date, unit: report.cashFlowTrendUnit),
                            y: .value("Amount", item.expenseMinor),
                            series: .value("Type", "Expenses")
                        )
                            .foregroundStyle(appState.themePalette.caution)
                        .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))

                        BarMark(
                            x: .value("Period", item.date, unit: report.cashFlowTrendUnit),
                            y: .value("Net", item.netMinor)
                        )
                        .foregroundStyle(
                            item.netMinor >= 0
                                ? appState.themePalette.positive.opacity(0.22)
                                : appState.themePalette.caution.opacity(0.22)
                        )
                    }
                }
                .chartLegend(position: .bottom, alignment: .leading)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4))
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4))
                }
                .frame(height: 260)

                HStack(spacing: 12) {
                    reportMetric(
                        "Income",
                        amount: report.incomeTotalMinor,
                        icon: "arrow.down",
                        tint: appState.themePalette.positive
                    )
                    reportMetric(
                        "Expense",
                        amount: report.expenseTotalMinor,
                        icon: "arrow.up",
                        tint: appState.themePalette.caution
                    )
                }
            }
        }
    }

    private var recurringCard: some View {
        insightCard(
            title: "Recurring commitments",
            subtitle: "Predictable bills and subscriptions"
        ) {
            if report.recurringInsights.isEmpty {
                EmptyStateView(
                    icon: "repeat",
                    title: "No active recurring expenses",
                    message: "Recurring commitments appear here once added."
                )
            } else {
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        reportMetric(
                            "Active",
                            value: "\(report.activeRecurringCount)",
                            icon: "repeat",
                            tint: Color(hex: "#0E7C7B")
                        )
                        reportMetric(
                            "Monthly load",
                            amount: report.monthlyRecurringLoadMinor,
                            icon: "calendar",
                            tint: Color(hex: "#B4613B")
                        )
                    }

                    ForEach(report.recurringInsights.prefix(5)) { item in
                        compactMoneyRow(
                            title: item.name,
                            subtitle: item.detail,
                            amount: item.amountMinor,
                            icon: item.icon,
                            tint: Color(hex: "#B4613B")
                        )
                    }
                }
            }
        }
    }

    private var goalsCard: some View {
        insightCard(
            title: "Goals progress",
            subtitle: "Funding pressure from open targets"
        ) {
            if report.goalInsights.isEmpty {
                EmptyStateView(
                    icon: "target",
                    title: "No goals yet",
                    message: "Create a goal to include it in reports."
                )
            } else {
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        reportMetric(
                            "Saved",
                            amount: report.totalGoalSavedMinor,
                            icon: "checkmark.circle",
                            tint: Color(hex: "#1B8A5A")
                        )
                        reportMetric(
                            "Remaining",
                            amount: report.totalGoalRemainingMinor,
                            icon: "target",
                            tint: Color(hex: "#8B5CF6")
                        )
                    }

                    ForEach(report.goalInsights.prefix(4)) { item in
                        VStack(alignment: .leading, spacing: 7) {
                            HStack {
                                Text(item.name)
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(report.percentText(item.progress))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            ProgressView(value: item.progress)
                                .tint(Color(hex: item.colorHex))
                            HStack {
                                Text(item.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(money(item.remainingMinor))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private var topTransactionsCard: some View {
        insightCard(
            title: "Top transactions",
            subtitle: "Largest expenses in this report range"
        ) {
            if report.topTransactions.isEmpty {
                EmptyStateView(
                    icon: "list.bullet.rectangle",
                    title: "No expenses yet",
                    message: "Large expenses will appear here."
                )
            } else {
                VStack(spacing: 8) {
                    ForEach(report.topTransactions) { transaction in
                        TransactionRowView(
                            transaction: transaction,
                            currencyCode: appState.selectedCurrencyCode
                        )
                        if transaction.id != report.topTransactions.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private func insightCard<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                content()
            }
        }
    }

    private func reportMetric(
        _ title: String,
        amount: Int64,
        icon: String,
        tint: Color
    ) -> some View {
        reportMetric(title, value: money(amount), icon: icon, tint: tint)
    }

    private func reportMetric(
        _ title: String,
        value: String,
        icon: String,
        tint: Color
    ) -> some View {
        SummaryMetricTile(
            title: title,
            value: value,
            icon: icon,
            tint: tint
        )
    }

    private func progressRow(
        title: String,
        detail: String,
        progress: Double,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(detail)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: min(max(progress, 0), 1))
                .tint(tint)
        }
    }

    private func insightFact(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func categoryRow(_ item: CategoryInsight) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(item.color)
                .frame(width: 10, height: 10)
            Text(item.name)
                .font(.subheadline.weight(.medium))
            Spacer()
            Text(report.percentText(item.share))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(money(item.amountMinor))
                .moneyStyle(size: 14, weight: .semibold)
                .frame(minWidth: 88, alignment: .trailing)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func compactMoneyRow(
        title: String,
        subtitle: String,
        amount: Int64,
        icon: String,
        tint: Color
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(money(amount))
                .moneyStyle(size: 14, weight: .semibold)
        }
    }

    private func money(_ amount: Int64) -> String {
        MoneyFormatter.string(
            minorUnits: amount,
            currencyCode: appState.selectedCurrencyCode
        )
    }

    private func exportReport() {
        reportDocument = ReportPDFDocument(
            data: InsightsPDFRenderer.render(
                report: report,
                currencyCode: appState.selectedCurrencyCode
            )
        )
        exportingReport = true
    }

    private func loadReportTransactions() {
        isLoadingReport = true
        reportError = nil

        do {
            let active = activeRange
            let previous = previousRange
            let currentTransactions = try fetchTransactions(in: active)
            let previousRangeTransactions = try fetchTransactions(in: previous)
            let yearTransactions = try fetchTransactions(in: activityYearRange(for: active))
            report = InsightReport(
                title: selectedRange.title,
                range: active,
                transactions: currentTransactions,
                previousTransactions: previousRangeTransactions,
                allTransactions: yearTransactions,
                budgets: budgets,
                categoryBudgets: categoryBudgets,
                goals: goals,
                recurringRules: recurringRules,
                activeBudget: activeBudget,
                palette: palette
            )
        } catch {
            reportError = error.localizedDescription
        }

        hasLoadedReport = true
        isLoadingReport = false
    }

    private func fetchTransactions(in range: BudgetPeriod) throws -> [TransactionItem] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: range.start)
        let endExclusive = calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: range.end)
        ) ?? range.end
        let descriptor = FetchDescriptor<TransactionItem>(
            predicate: #Predicate<TransactionItem> { transaction in
                transaction.timestamp >= start && transaction.timestamp < endExclusive
            },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    private func activityYearRange(for range: BudgetPeriod) -> BudgetPeriod {
        let calendar = Calendar.current
        let yearComponents = calendar.dateComponents([.year], from: range.end)
        let yearStart = calendar.date(from: yearComponents) ?? range.start
        let nextYearStart = calendar.date(byAdding: .year, value: 1, to: yearStart)
            ?? range.end
        let yearEnd = calendar.date(byAdding: .day, value: -1, to: nextYearStart)
            ?? range.end
        return BudgetPeriod(start: yearStart, end: yearEnd)
    }

    private func rangeDayCount(_ range: BudgetPeriod) -> Int {
        max(
            1,
            (Calendar.current.dateComponents([.day], from: range.start, to: range.end).day ?? 0) + 1
        )
    }
}

private struct InsightReportLoadKey: Hashable {
    let range: InsightRange
    let customStart: Date
    let customEnd: Date
    let activeBudgetID: UUID?
    let activeBudgetUpdatedAt: Date?
    let categoryBudgetUpdatedAt: Date?
    let goalUpdatedAt: Date?
    let recurringUpdatedAt: Date?
    let themeMode: String
}

private struct NetFlowBadge: View {
    let value: Int64

    var body: some View {
        Text(value >= 0 ? "Positive" : "Negative")
            .font(.caption.weight(.semibold))
            .foregroundStyle(value >= 0 ? Color(hex: "#1B8A5A") : Color(hex: "#B4613B"))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                (value >= 0 ? Color(hex: "#1B8A5A") : Color(hex: "#B4613B"))
                    .opacity(0.12),
                in: Capsule()
            )
    }
}

private struct SpendActivityHeatmap: View {
    let days: [SpendActivityDay]
    @Binding var mode: SpendActivityMode
    let currencyCode: String

    @Environment(\.colorScheme) private var colorScheme

    private let cellSize: CGFloat = 14
    private let cellSpacing: CGFloat = 4

    private var weeks: [[SpendActivityDay]] {
        stride(from: 0, to: days.count, by: 7).map { index in
            Array(days[index..<min(index + 7, days.count)])
        }
    }

    private var maxActivityMinor: Int64 {
        max(days.map { activityValue(for: $0) }.max() ?? 0, 1)
    }

    private var heatmapWidth: CGFloat {
        guard !weeks.isEmpty else { return 0 }
        return 30
            + CGFloat(weeks.count) * cellSize
            + CGFloat(max(0, weeks.count - 1)) * cellSpacing
    }

    private var activeDayCount: Int {
        days.filter { $0.isInsideRange && $0.expenseMinor > 0 }.count
    }

    private var averageSpendMinor: Int64 {
        let rangeDays = days.filter(\.isInsideRange)
        guard !rangeDays.isEmpty else { return 0 }
        let total = rangeDays.reduce(Int64(0)) { $0 + $1.expenseMinor }
        return total / Int64(rangeDays.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            modePicker

            if days.isEmpty {
                EmptyStateView(
                    icon: "square.grid.3x3",
                    title: "No range selected",
                    message: "Choose a report range to build the spend activity map."
                )
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 6) {
                        monthHeader
                        heatmapGrid
                    }
                    .padding(.vertical, 2)
                }
                .accessibilityLabel("Spend activity heatmap")

                footer
            }
        }
    }

    private var modePicker: some View {
        HStack(spacing: 6) {
            ForEach(SpendActivityMode.allCases) { item in
                Button {
                    mode = item
                } label: {
                    Text(item.title)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.84)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(
                            mode == item
                                ? Color.primary.opacity(0.10)
                                : Color.primary.opacity(0.04),
                            in: Capsule()
                        )
                        .overlay(
                            Capsule()
                                .strokeBorder(Color.primary.opacity(mode == item ? 0.12 : 0.04), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .foregroundStyle(mode == item ? .primary : .secondary)
                .accessibilityLabel(item.accessibilityLabel)
            }
        }
    }

    private var monthHeader: some View {
        ZStack(alignment: .leading) {
            ForEach(weeks.indices.filter { !monthLabel(for: $0).isEmpty }, id: \.self) { index in
                Text(monthLabel(for: index))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .offset(x: 30 + CGFloat(index) * (cellSize + cellSpacing))
            }
        }
        .frame(width: heatmapWidth, height: 16, alignment: .leading)
    }

    private var heatmapGrid: some View {
        HStack(alignment: .top, spacing: 6) {
            weekdayLabels

            HStack(alignment: .top, spacing: cellSpacing) {
                ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                    VStack(spacing: cellSpacing) {
                        ForEach(week) { day in
                            SpendActivityCell(
                                day: day,
                                valueMinor: activityValue(for: day),
                                maxValueMinor: maxActivityMinor,
                                currencyCode: currencyCode,
                                colorScheme: colorScheme
                            )
                            .frame(width: cellSize, height: cellSize)
                        }
                    }
                }
            }
        }
    }

    private var weekdayLabels: some View {
        let labels = orderedWeekdayLabels()
        return VStack(alignment: .trailing, spacing: cellSpacing) {
            ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                Text(index.isMultiple(of: 2) ? label : "")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: cellSize, alignment: .trailing)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(activeDayCount) spending days")
                    .font(.caption.weight(.semibold))
                Text("Avg \(money(averageSpendMinor)) / day")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 5) {
                Text("Less")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                ForEach(0..<5, id: \.self) { level in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(legendColor(level: level))
                        .frame(width: 12, height: 12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
                        )
                }
                Text("More")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func activityValue(for day: SpendActivityDay) -> Int64 {
        switch mode {
        case .daily:
            return day.expenseMinor
        case .weekly:
            return day.weeklyExpenseMinor
        case .cumulative:
            return day.cumulativeExpenseMinor
        case .year:
            return day.expenseMinor
        }
    }

    private func monthLabel(for index: Int) -> String {
        guard let firstDay = weeks[index].first else { return "" }
        if index == 0 {
            return firstDay.date.formatted(.dateTime.month(.abbreviated))
        }
        guard let previous = weeks[index - 1].first else { return "" }
        let calendar = Calendar.current
        return calendar.isDate(firstDay.date, equalTo: previous.date, toGranularity: .month)
            ? ""
            : firstDay.date.formatted(.dateTime.month(.abbreviated))
    }

    private func orderedWeekdayLabels() -> [String] {
        let calendar = Calendar.current
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        return Array(symbols[(calendar.firstWeekday - 1)...])
            + Array(symbols[..<(calendar.firstWeekday - 1)])
    }

    private func legendColor(level: Int) -> Color {
        switch level {
        case 0:
            return emptyCellColor
        case 1:
            return Color(hex: "#A7F3D0")
        case 2:
            return Color(hex: "#34D399")
        case 3:
            return Color(hex: "#F59E0B")
        default:
            return Color(hex: "#DC2626")
        }
    }

    private var emptyCellColor: Color {
        Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.07)
    }

    private func money(_ amount: Int64) -> String {
        MoneyFormatter.string(minorUnits: amount, currencyCode: currencyCode)
    }
}

private struct SpendActivityCell: View {
    let day: SpendActivityDay
    let valueMinor: Int64
    let maxValueMinor: Int64
    let currencyCode: String
    let colorScheme: ColorScheme

    private var ratio: Double {
        guard valueMinor > 0 else { return 0 }
        return min(max(Double(valueMinor) / Double(maxValueMinor), 0), 1)
    }

    private var fill: Color {
        guard day.isInsideRange else {
            return Color.primary.opacity(colorScheme == .dark ? 0.055 : 0.035)
        }
        guard valueMinor > 0 else {
            return Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.07)
        }
        switch ratio {
        case 0..<0.18:
            return Color(hex: "#A7F3D0")
        case 0.18..<0.38:
            return Color(hex: "#34D399")
        case 0.38..<0.62:
            return Color(hex: "#F59E0B")
        case 0.62..<0.82:
            return Color(hex: "#F97316")
        default:
            return Color(hex: "#DC2626")
        }
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 3.5, style: .continuous)
            .fill(fill)
            .overlay(
                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: day.isToday ? 1.4 : 1)
            )
            .opacity(day.isInsideRange ? 1 : 0.46)
            .accessibilityLabel(accessibilityLabel)
    }

    private var borderColor: Color {
        if day.isToday {
            return Color.accentColor.opacity(0.75)
        }
        return Color.primary.opacity(day.isInsideRange ? 0.05 : 0.03)
    }

    private var accessibilityLabel: String {
        let date = day.date.formatted(date: .abbreviated, time: .omitted)
        let amount = MoneyFormatter.string(
            minorUnits: day.expenseMinor,
            currencyCode: currencyCode
        )
        if day.transactionCount == 1 {
            return "\(date), \(amount), 1 expense"
        }
        return "\(date), \(amount), \(day.transactionCount) expenses"
    }
}

private struct InsightReport {
    let title: String
    let range: BudgetPeriod
    let transactions: [TransactionItem]
    let previousTransactions: [TransactionItem]
    let allTransactions: [TransactionItem]
    let budgets: [BudgetPeriodItem]
    let categoryBudgets: [CategoryBudgetItem]
    let goals: [GoalItem]
    let recurringRules: [RecurringRuleItem]
    let activeBudget: BudgetPeriodItem?
    let palette: [Color]

    static var placeholder: InsightReport {
        let today = Calendar.current.startOfDay(for: Date())
        return InsightReport(
            title: InsightRange.currentPeriod.title,
            range: BudgetPeriod(start: today, end: today),
            transactions: [],
            previousTransactions: [],
            allTransactions: [],
            budgets: [],
            categoryBudgets: [],
            goals: [],
            recurringRules: [],
            activeBudget: nil,
            palette: FloatTheme.palette(for: "float").chartColors
        )
    }

    var dateRangeText: String {
        "\(range.start.formatted(date: .abbreviated, time: .omitted)) - \(range.end.formatted(date: .abbreviated, time: .omitted))"
    }

    var defaultFilename: String {
        "float-report-\(range.start.formatted(.iso8601.year().month().day()))"
    }

    var incomeTotalMinor: Int64 {
        transactions.filter { !$0.isExpense }.reduce(0) { $0 + $1.amountMinor }
    }

    var expenseTotalMinor: Int64 {
        transactions.filter(\.isExpense).reduce(0) { $0 + $1.amountMinor }
    }

    var netCashFlowMinor: Int64 {
        incomeTotalMinor - expenseTotalMinor
    }

    var previousExpenseTotalMinor: Int64 {
        previousTransactions.filter(\.isExpense).reduce(0) { $0 + $1.amountMinor }
    }

    var dailyAverageExpenseMinor: Int64 {
        expenseTotalMinor / Int64(rangeDayCount)
    }

    var rangeDayCount: Int {
        max(
            1,
            (Calendar.current.dateComponents([.day], from: range.start, to: range.end).day ?? 0) + 1
        )
    }

    var cashFlowTrendUnit: Calendar.Component {
        rangeDayCount > 95 ? .month : .day
    }

    var safeToSpend: SafeToSpendResult {
        SafeToSpendUseCase.calculate(
            budget: activeBudget,
            transactions: transactions,
            goals: goals,
            recurringRules: recurringRules
        )
    }

    var topCategory: CategoryInsight? {
        categoryInsights.first
    }

    var biggestTransactionLabel: String {
        topTransactions.first?.categoryName ?? "None"
    }

    var narrative: String {
        guard expenseTotalMinor > 0 || incomeTotalMinor > 0 else {
            return "No activity in this range yet."
        }

        let direction: String
        if previousExpenseTotalMinor == 0 {
            direction = "There is no comparable prior spending yet."
        } else if expenseTotalMinor < previousExpenseTotalMinor {
            direction = "Spending is below the previous comparable range."
        } else if expenseTotalMinor > previousExpenseTotalMinor {
            direction = "Spending is above the previous comparable range."
        } else {
            direction = "Spending matches the previous comparable range."
        }

        if let topCategory {
            return "\(topCategory.name) leads expenses. \(direction)"
        }
        return direction
    }

    var budgetHealthMessage: String {
        if safeToSpend.overAmountMinor > 0 {
            return "This period is over budget. Reduce flexible spending or adjust the budget assumptions."
        }
        if safeToSpend.spendingProgress > safeToSpend.periodProgress {
            return "Spending is ahead of time elapsed, so the daily allowance is tightening."
        }
        return "Spending is tracking within the current period pace."
    }

    var categoryBudgetInsights: [CategoryBudgetInsight] {
        categoryBudgets
            .filter {
                $0.isActive
                    && $0.amountMinor > 0
                    && $0.category?.isIncome == false
                    && $0.category?.archived == false
            }
            .map { budget in
                let category = budget.category
                let spent = transactions
                    .filter { transaction in
                        transaction.isExpense && transaction.category?.id == category?.id
                    }
                    .reduce(Int64(0)) { $0 + $1.amountMinor }
                let remaining = max(0, budget.amountMinor - spent)
                let over = max(0, spent - budget.amountMinor)
                return CategoryBudgetInsight(
                    name: category?.name ?? "Unknown Category",
                    icon: category?.iconKey ?? "questionmark.circle.fill",
                    colorHex: category?.colorHex ?? "#5A6B6B",
                    budgetMinor: budget.amountMinor,
                    spentMinor: spent,
                    remainingMinor: remaining,
                    overMinor: over,
                    progress: Double(spent) / Double(max(1, budget.amountMinor))
                )
            }
            .sorted {
                if $0.isOverBudget != $1.isOverBudget {
                    return $0.isOverBudget && !$1.isOverBudget
                }
                return $0.progress > $1.progress
            }
    }

    var totalCategoryBudgetMinor: Int64 {
        categoryBudgetInsights.reduce(0) { $0 + $1.budgetMinor }
    }

    var totalCategoryBudgetSpentMinor: Int64 {
        categoryBudgetInsights.reduce(0) { $0 + $1.spentMinor }
    }

    var overCategoryBudgetCount: Int {
        categoryBudgetInsights.filter(\.isOverBudget).count
    }

    var categoryInsights: [CategoryInsight] {
        let grouped = Dictionary(
            grouping: transactions.filter(\.isExpense),
            by: { $0.categoryName }
        )
        let rows = grouped.map { name, items in
            (name, items.reduce(Int64(0)) { $0 + $1.amountMinor })
        }
        .sorted { $0.1 > $1.1 }
        .prefix(7)

        return rows.enumerated().map { index, item in
            CategoryInsight(
                name: item.0,
                amountMinor: item.1,
                share: expenseTotalMinor == 0 ? 0 : Double(item.1) / Double(expenseTotalMinor),
                color: palette[index % palette.count]
            )
        }
    }

    var cashFlowTrend: [CashFlowTrendPoint] {
        let calendar = Calendar.current
        let components: Set<Calendar.Component> = rangeDayCount > 95
            ? [.year, .month] : [.year, .month, .day]
        let grouped = Dictionary(grouping: transactions) {
            calendar.date(from: calendar.dateComponents(components, from: $0.timestamp))
                ?? calendar.startOfDay(for: $0.timestamp)
        }

        return grouped.map { date, items in
            let income = items.filter { !$0.isExpense }.reduce(Int64(0)) {
                $0 + $1.amountMinor
            }
            let expense = items.filter(\.isExpense).reduce(Int64(0)) {
                $0 + $1.amountMinor
            }
            return CashFlowTrendPoint(
                date: date,
                incomeMinor: income,
                expenseMinor: expense,
                netMinor: income - expense
            )
        }
        .sorted { $0.date < $1.date }
    }

    var dailyExpenseInsights: [CalendarExpenseInsight] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: transactions.filter(\.isExpense)) {
            calendar.startOfDay(for: $0.timestamp)
        }
        return grouped.map { day, items in
            CalendarExpenseInsight(
                date: day,
                expenseMinor: items.reduce(Int64(0)) { $0 + $1.amountMinor },
                transactionCount: items.count
            )
        }
        .sorted { $0.date < $1.date }
    }

    var spendActivityDays: [SpendActivityDay] {
        spendActivityDays(
            from: range.start,
            through: range.end,
            transactions: transactions
        )
    }

    var yearSpendActivityDays: [SpendActivityDay] {
        let calendar = Calendar.current
        let yearComponents = calendar.dateComponents([.year], from: range.end)
        let yearStart = calendar.date(from: yearComponents) ?? range.start
        let nextYearStart = calendar.date(byAdding: .year, value: 1, to: yearStart)
            ?? range.end
        let yearEnd = calendar.date(byAdding: .day, value: -1, to: nextYearStart)
            ?? range.end

        return spendActivityDays(
            from: yearStart,
            through: yearEnd,
            transactions: allTransactions
        )
    }

    var spendActivityYearText: String {
        let year = Calendar.current.component(.year, from: range.end)
        return "\(year)"
    }

    private func spendActivityDays(
        from start: Date,
        through end: Date,
        transactions sourceTransactions: [TransactionItem]
    ) -> [SpendActivityDay] {
        let calendar = Calendar.current
        let rangeStart = calendar.startOfDay(for: start)
        let rangeEnd = calendar.startOfDay(for: end)
        let gridStart = startOfActivityWeek(containing: rangeStart, calendar: calendar)
        let gridEnd = calendar.date(
            byAdding: .day,
            value: 6,
            to: startOfActivityWeek(containing: rangeEnd, calendar: calendar)
        ) ?? rangeEnd

        let grouped = Dictionary(grouping: sourceTransactions.filter(\.isExpense)) {
            calendar.startOfDay(for: $0.timestamp)
        }
        let expenseByDay = grouped.mapValues { items in
            items.reduce(Int64(0)) { $0 + $1.amountMinor }
        }
        let countByDay = grouped.mapValues(\.count)

        let rangeDates = dates(from: rangeStart, through: rangeEnd, calendar: calendar)
        let weekTotals = Dictionary(grouping: rangeDates) {
            startOfActivityWeek(containing: $0, calendar: calendar)
        }
        .mapValues { dates in
            dates.reduce(Int64(0)) { $0 + (expenseByDay[$1] ?? 0) }
        }

        var runningTotal: Int64 = 0
        var cumulativeByDay: [Date: Int64] = [:]
        for day in rangeDates {
            runningTotal += expenseByDay[day] ?? 0
            cumulativeByDay[day] = runningTotal
        }

        return dates(from: gridStart, through: gridEnd, calendar: calendar).map { day in
            let isInsideRange = day >= rangeStart && day <= rangeEnd
            let weekStart = startOfActivityWeek(containing: day, calendar: calendar)
            return SpendActivityDay(
                date: day,
                isInsideRange: isInsideRange,
                expenseMinor: isInsideRange ? expenseByDay[day] ?? 0 : 0,
                transactionCount: isInsideRange ? countByDay[day] ?? 0 : 0,
                weeklyExpenseMinor: isInsideRange ? weekTotals[weekStart] ?? 0 : 0,
                cumulativeExpenseMinor: isInsideRange ? cumulativeByDay[day] ?? 0 : 0
            )
        }
    }

    var highestExpenseDay: CalendarExpenseInsight? {
        dailyExpenseInsights.max { $0.expenseMinor < $1.expenseMinor }
    }

    var lowestExpenseDay: CalendarExpenseInsight? {
        dailyExpenseInsights
            .filter { $0.expenseMinor > 0 }
            .min { $0.expenseMinor < $1.expenseMinor }
    }

    var busiestDay: CalendarExpenseInsight? {
        dailyExpenseInsights.max { $0.transactionCount < $1.transactionCount }
    }

    var weekExpenseDeltaMinor: Int64 {
        let calendar = Calendar.current
        let end = calendar.startOfDay(for: range.end)
        let currentWeekStart = calendar.date(byAdding: .day, value: -6, to: end) ?? end
        let previousWeekStart = calendar.date(byAdding: .day, value: -7, to: currentWeekStart)
            ?? currentWeekStart
        let previousWeekEnd = calendar.date(byAdding: .day, value: -1, to: currentWeekStart)
            ?? currentWeekStart
        let current = expenseTotal(
            from: currentWeekStart,
            through: end,
            calendar: calendar
        )
        let previous = expenseTotal(
            from: previousWeekStart,
            through: previousWeekEnd,
            calendar: calendar
        )
        return current - previous
    }

    var weekTrendText: String {
        guard weekExpenseDeltaMinor != 0 else { return "Flat" }
        return weekExpenseDeltaMinor < 0 ? "Down" : "Up"
    }

    var activeRecurringCount: Int {
        recurringRules.filter { $0.active }.count
    }

    var monthlyRecurringLoadMinor: Int64 {
        recurringRules.filter { $0.active && $0.isExpense }.reduce(0) {
            $0 + normalizedMonthlyAmount(for: $1)
        }
    }

    var recurringInsights: [RecurringInsight] {
        recurringRules
            .filter { $0.active && $0.isExpense }
            .sorted { normalizedMonthlyAmount(for: $0) > normalizedMonthlyAmount(for: $1) }
            .map {
                RecurringInsight(
                    name: $0.note?.nilIfBlank ?? $0.category?.name ?? "Recurring",
                    detail: "\($0.cadence.title) · next \($0.nextRunDate.formatted(date: .abbreviated, time: .omitted))",
                    amountMinor: $0.amountMinor,
                    monthlyAmountMinor: normalizedMonthlyAmount(for: $0),
                    icon: $0.category?.iconKey ?? "repeat"
                )
            }
    }

    var goalInsights: [GoalInsight] {
        goals.sorted {
            ($0.targetDate ?? .distantFuture) < ($1.targetDate ?? .distantFuture)
        }
        .map {
            let remaining = max(0, $0.targetMinor - $0.savedMinor)
            let progress = Double($0.savedMinor) / Double(max($0.targetMinor, 1))
            let date = $0.targetDate?.formatted(date: .abbreviated, time: .omitted)
                ?? "No target date"
            return GoalInsight(
                name: $0.name,
                savedMinor: $0.savedMinor,
                targetMinor: $0.targetMinor,
                remainingMinor: remaining,
                progress: min(max(progress, 0), 1),
                colorHex: $0.colorHex,
                detail: date
            )
        }
    }

    var totalGoalSavedMinor: Int64 {
        goals.reduce(0) { $0 + $1.savedMinor }
    }

    var totalGoalRemainingMinor: Int64 {
        goals.reduce(0) { $0 + max(0, $1.targetMinor - $1.savedMinor) }
    }

    var topTransactions: [TransactionItem] {
        Array(
            transactions
                .filter(\.isExpense)
                .sorted { $0.amountMinor > $1.amountMinor }
                .prefix(5)
        )
    }

    private func expenseTotal(from start: Date, through end: Date, calendar: Calendar) -> Int64 {
        let startOfRange = calendar.startOfDay(for: start)
        let endExclusive = calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: end)
        ) ?? end
        return transactions
            .filter {
                $0.isExpense
                    && startOfRange <= $0.timestamp
                    && $0.timestamp < endExclusive
            }
            .reduce(Int64(0)) { $0 + $1.amountMinor }
    }

    private func dates(from start: Date, through end: Date, calendar: Calendar) -> [Date] {
        var results: [Date] = []
        var cursor = calendar.startOfDay(for: start)
        let last = calendar.startOfDay(for: end)
        while cursor <= last {
            results.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else {
                break
            }
            cursor = next
        }
        return results
    }

    private func startOfActivityWeek(containing date: Date, calendar: Calendar) -> Date {
        let day = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: day)
        let offset = (weekday - calendar.firstWeekday + 7) % 7
        return calendar.date(byAdding: .day, value: -offset, to: day) ?? day
    }

    func drillDown(for category: CategoryInsight) -> CategoryDrillDown {
        let filtered = transactions
            .filter { $0.isExpense && $0.categoryName == category.name }
            .sorted { $0.timestamp > $1.timestamp }
        return CategoryDrillDown(
            name: category.name,
            amountMinor: category.amountMinor,
            share: category.share,
            color: category.color,
            transactions: filtered
        )
    }

    func percentText(_ value: Double) -> String {
        "\(Int((min(max(value, 0), 1) * 100).rounded()))%"
    }

    private func normalizedMonthlyAmount(for rule: RecurringRuleItem) -> Int64 {
        let interval = max(1, rule.intervalCount)
        switch rule.cadence {
        case .daily:
            return rule.amountMinor * Int64(30 / interval)
        case .weekly:
            return rule.amountMinor * Int64(max(1, 4 / interval))
        case .monthly:
            return rule.amountMinor / Int64(interval)
        }
    }
}

private struct CategoryInsight: Identifiable {
    let id = UUID()
    let name: String
    let amountMinor: Int64
    let share: Double
    let color: Color
}

private struct CategoryBudgetInsight: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let colorHex: String
    let budgetMinor: Int64
    let spentMinor: Int64
    let remainingMinor: Int64
    let overMinor: Int64
    let progress: Double

    var isOverBudget: Bool { overMinor > 0 }

    func statusText(currencyCode: String) -> String {
        if isOverBudget {
            return "Over by \(MoneyFormatter.string(minorUnits: overMinor, currencyCode: currencyCode))"
        }
        return "\(MoneyFormatter.string(minorUnits: remainingMinor, currencyCode: currencyCode)) left"
    }
}

private struct CategoryDrillDown: Identifiable {
    let id = UUID()
    let name: String
    let amountMinor: Int64
    let share: Double
    let color: Color
    let transactions: [TransactionItem]
}

private struct CategoryDrillDownSheet: View {
    let category: CategoryDrillDown
    let currencyCode: String

    private var groupedTransactions: [(Date, [TransactionItem])] {
        Dictionary(grouping: category.transactions) {
            Calendar.current.startOfDay(for: $0.timestamp)
        }
        .map { ($0.key, $0.value) }
        .sorted { $0.0 > $1.0 }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(category.color)
                                .frame(width: 12, height: 12)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(category.name)
                                    .font(.headline)
                                Text("\(percentText(category.share)) of report expenses")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(money(category.amountMinor))
                                .moneyStyle(size: 18, weight: .bold)
                        }
                    }
                    .padding(.vertical, 4)
                }

                ForEach(groupedTransactions, id: \.0) { day, items in
                    Section(day.formatted(date: .complete, time: .omitted)) {
                        ForEach(items) { transaction in
                            TransactionRowView(
                                transaction: transaction,
                                currencyCode: currencyCode
                            )
                        }
                    }
                }
            }
            .navigationTitle("Category report")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func money(_ amount: Int64) -> String {
        MoneyFormatter.string(minorUnits: amount, currencyCode: currencyCode)
    }

    private func percentText(_ value: Double) -> String {
        "\(Int((min(max(value, 0), 1) * 100).rounded()))%"
    }
}

private struct CashFlowTrendPoint: Identifiable {
    let id = UUID()
    let date: Date
    let incomeMinor: Int64
    let expenseMinor: Int64
    let netMinor: Int64
}

private struct CalendarExpenseInsight: Identifiable {
    let id = UUID()
    let date: Date
    let expenseMinor: Int64
    let transactionCount: Int

    var countText: String {
        "\(transactionCount) txns"
    }

    func summaryText(currencyCode: String) -> String {
        let amount = MoneyFormatter.string(
            minorUnits: expenseMinor,
            currencyCode: currencyCode
        )
        return "\(date.formatted(.dateTime.month(.abbreviated).day())) · \(amount)"
    }
}

private struct SpendActivityDay: Identifiable {
    let date: Date
    let isInsideRange: Bool
    let expenseMinor: Int64
    let transactionCount: Int
    let weeklyExpenseMinor: Int64
    let cumulativeExpenseMinor: Int64

    var id: Date { date }

    var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }
}

private enum SpendActivityMode: String, CaseIterable, Identifiable {
    case daily
    case weekly
    case cumulative
    case year

    var id: String { rawValue }

    var title: String {
        switch self {
        case .daily:
            return "Daily"
        case .weekly:
            return "Weekly"
        case .cumulative:
            return "Cumulative"
        case .year:
            return "Year"
        }
    }

    var accessibilityLabel: String {
        "\(title) spend activity"
    }
}

private struct RecurringInsight: Identifiable {
    let id = UUID()
    let name: String
    let detail: String
    let amountMinor: Int64
    let monthlyAmountMinor: Int64
    let icon: String
}

private struct GoalInsight: Identifiable {
    let id = UUID()
    let name: String
    let savedMinor: Int64
    let targetMinor: Int64
    let remainingMinor: Int64
    let progress: Double
    let colorHex: String
    let detail: String
}

private enum InsightRange: String, CaseIterable, Identifiable, Hashable {
    case currentPeriod
    case lastPeriod
    case lastThreePeriods
    case thisYear
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .currentPeriod: "Current period"
        case .lastPeriod: "Last period"
        case .lastThreePeriods: "Last 3 periods"
        case .thisYear: "This year"
        case .custom: "Custom range"
        }
    }
}

private struct ReportPDFDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.pdf] }
    static var writableContentTypes: [UTType] { [.pdf] }

    var data: Data

    init(data: Data = Data()) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

private enum InsightsPDFRenderer {
    static func render(report: InsightReport, currencyCode: String) -> Data {
        let pageBounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: pageBounds)
        return renderer.pdfData { context in
            context.beginPage()
            var y: CGFloat = 46

            draw("Float Report", at: &y, style: .title, bounds: pageBounds)
            draw(report.title, at: &y, style: .headline, bounds: pageBounds)
            draw(report.dateRangeText, at: &y, style: .body, bounds: pageBounds)
            y += 16

            draw("Summary", at: &y, style: .headline, bounds: pageBounds)
            draw("Income: \(money(report.incomeTotalMinor, currencyCode))", at: &y, style: .body, bounds: pageBounds)
            draw("Expenses: \(money(report.expenseTotalMinor, currencyCode))", at: &y, style: .body, bounds: pageBounds)
            draw("Net cash flow: \(money(report.netCashFlowMinor, currencyCode))", at: &y, style: .body, bounds: pageBounds)
            draw("Daily average expense: \(money(report.dailyAverageExpenseMinor, currencyCode))", at: &y, style: .body, bounds: pageBounds)
            draw(report.narrative, at: &y, style: .body, bounds: pageBounds)
            y += 16

            draw("Budget Health", at: &y, style: .headline, bounds: pageBounds)
            draw("Safe to spend: \(money(report.safeToSpend.safeToSpendMinor, currencyCode))", at: &y, style: .body, bounds: pageBounds)
            draw("Daily limit: \(money(report.safeToSpend.dailyAllowanceMinor, currencyCode))", at: &y, style: .body, bounds: pageBounds)
            draw("Recurring due: \(money(report.safeToSpend.recurringDueMinor, currencyCode))", at: &y, style: .body, bounds: pageBounds)
            draw("Goals needed: \(money(report.safeToSpend.goalContributionMinor, currencyCode))", at: &y, style: .body, bounds: pageBounds)
            draw(report.budgetHealthMessage, at: &y, style: .body, bounds: pageBounds)
            y += 16

            draw("Category Budgets", at: &y, style: .headline, bounds: pageBounds)
            draw("Allocated: \(money(report.totalCategoryBudgetMinor, currencyCode))", at: &y, style: .body, bounds: pageBounds)
            draw("Spent: \(money(report.totalCategoryBudgetSpentMinor, currencyCode))", at: &y, style: .body, bounds: pageBounds)
            for item in report.categoryBudgetInsights.prefix(6) {
                let status = item.isOverBudget
                    ? "over by \(money(item.overMinor, currencyCode))"
                    : "\(money(item.remainingMinor, currencyCode)) left"
                draw("\(item.name): \(money(item.spentMinor, currencyCode)) of \(money(item.budgetMinor, currencyCode)) (\(status))", at: &y, style: .body, bounds: pageBounds)
            }
            y += 16

            draw("Top Categories", at: &y, style: .headline, bounds: pageBounds)
            for item in report.categoryInsights.prefix(6) {
                draw("\(item.name): \(money(item.amountMinor, currencyCode)) (\(report.percentText(item.share)))", at: &y, style: .body, bounds: pageBounds)
            }
            y += 16

            draw("Recurring Commitments", at: &y, style: .headline, bounds: pageBounds)
            draw("Active rules: \(report.activeRecurringCount)", at: &y, style: .body, bounds: pageBounds)
            draw("Estimated monthly load: \(money(report.monthlyRecurringLoadMinor, currencyCode))", at: &y, style: .body, bounds: pageBounds)
            for item in report.recurringInsights.prefix(5) {
                draw("\(item.name): \(money(item.amountMinor, currencyCode)) · \(item.detail)", at: &y, style: .body, bounds: pageBounds)
            }

            if y > 650 {
                context.beginPage()
                y = 46
            } else {
                y += 16
            }

            draw("Goals", at: &y, style: .headline, bounds: pageBounds)
            draw("Saved: \(money(report.totalGoalSavedMinor, currencyCode))", at: &y, style: .body, bounds: pageBounds)
            draw("Remaining: \(money(report.totalGoalRemainingMinor, currencyCode))", at: &y, style: .body, bounds: pageBounds)
            for item in report.goalInsights.prefix(5) {
                draw("\(item.name): \(report.percentText(item.progress)) funded · \(money(item.remainingMinor, currencyCode)) remaining", at: &y, style: .body, bounds: pageBounds)
            }
        }
    }

    private static func money(_ amount: Int64, _ currencyCode: String) -> String {
        MoneyFormatter.string(minorUnits: amount, currencyCode: currencyCode)
    }

    private static func draw(
        _ text: String,
        at y: inout CGFloat,
        style: TextStyle,
        bounds: CGRect
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: style.font,
            .foregroundColor: style.color,
            .paragraphStyle: paragraph,
        ]
        let rect = CGRect(x: 46, y: y, width: bounds.width - 92, height: 80)
        let height = text.boundingRect(
            with: rect.size,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        ).height
        text.draw(in: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: height + 4), withAttributes: attributes)
        y += height + style.spacing
    }

    private enum TextStyle {
        case title
        case headline
        case body

        var font: UIFont {
            switch self {
            case .title:
                return .systemFont(ofSize: 28, weight: .bold)
            case .headline:
                return .systemFont(ofSize: 16, weight: .semibold)
            case .body:
                return .systemFont(ofSize: 11, weight: .regular)
            }
        }

        var color: UIColor {
            switch self {
            case .title, .headline:
                return .label
            case .body:
                return .secondaryLabel
            }
        }

        var spacing: CGFloat {
            switch self {
            case .title:
                return 12
            case .headline:
                return 8
            case .body:
                return 6
            }
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
