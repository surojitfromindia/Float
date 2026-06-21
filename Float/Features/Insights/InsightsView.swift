import Foundation
import Charts
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct InsightsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @Query private var allBudgets: [BudgetPeriodItem]
    @Query private var allCategoryBudgets: [CategoryBudgetItem]
    @Query private var allGoals: [GoalItem]
    @Query private var allRecurringRules: [RecurringRuleItem]

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

    private var budgets: [BudgetPeriodItem] { filterActiveProfile(allBudgets) }
    private var categoryBudgets: [CategoryBudgetItem] { filterActiveProfile(allCategoryBudgets) }
    private var goals: [GoalItem] { filterActiveProfile(allGoals) }
    private var recurringRules: [RecurringRuleItem] { filterActiveProfile(allRecurringRules) }

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
            VStack(alignment: .leading, spacing: 16) {
                InsightsHeaderBar(
                    selectedRange: $selectedRange,
                    dateRangeText: report.dateRangeText
                )

                if selectedRange == .custom {
                    InsightsCustomRangeCard(
                        customStart: $customStart,
                        customEnd: $customEnd
                    )
                }

                if isLoadingReport && report.transactions.isEmpty {
                    InsightsLoadingCard()
                } else if let reportError {
                    InsightsErrorCard(
                        message: reportError,
                        tint: appState.themePalette.caution,
                        retry: loadReportTransactions
                    )
                } else {
                    dashboardContent
                }
            }
            .padding(20)
            .padding(.bottom, 40)
        }
        .navigationTitle(String(localized: "Insights"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: exportReport) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel(String(localized: "Export report"))
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

    private var dashboardContent: some View {
        InsightsDashboardContent(
            report: report,
            spendActivityMode: $spendActivityMode,
            selectedCategory: $selectedCategory,
            currencyCode: appState.selectedCurrencyCode,
            palette: appState.themePalette
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
        return filterActiveProfile(try modelContext.fetch(descriptor))
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

private struct InsightsHeaderBar: View {
    @Binding var selectedRange: InsightRange
    let dateRangeText: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Report range")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)

                Menu {
                    Picker("Range", selection: $selectedRange) {
                        ForEach(InsightRange.allCases) {
                            Text($0.title).tag($0)
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "calendar")
                            .font(.caption.weight(.semibold))
                        Text(selectedRange.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .floatGlassSurface(
                        cornerRadius: FloatTheme.controlRadius,
                        material: .thinMaterial,
                        strokeOpacity: 0.06
                    )
                }
                .menuOrder(.fixed)
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 4) {
                Text("Live window")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(dateRangeText)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
            }
        }
    }
}

private struct InsightsCustomRangeCard: View {
    @Binding var customStart: Date
    @Binding var customEnd: Date

    var body: some View {
        GlassCard(padding: 16) {
            VStack(spacing: 12) {
                InsightsDateField(
                    title: "From",
                    selection: $customStart
                )
                InsightsDateField(
                    title: "To",
                    selection: $customEnd
                )
            }
        }
    }
}

private struct InsightsDateField: View {
    let title: LocalizedStringResource
    @Binding var selection: Date

    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Spacer()
            DatePicker(
                title,
                selection: $selection,
                displayedComponents: .date
            )
            .labelsHidden()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .floatGlassSurface(
            cornerRadius: FloatTheme.tileRadius,
            material: .thinMaterial,
            strokeOpacity: 0.05
        )
    }
}

private struct InsightsLoadingCard: View {
    var body: some View {
        GlassCard {
            HStack(spacing: 12) {
                ProgressView()
                VStack(alignment: .leading, spacing: 3) {
                    Text("Loading insights")
                        .font(.headline)
                    Text("Rebuilding your report for the selected range.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
    }
}

private struct InsightsErrorCard: View {
    let message: String
    let tint: Color
    let retry: () -> Void

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("Insights could not load", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(tint)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Retry", action: retry)
                    .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct InsightsDashboardContent: View {
    let report: InsightReport
    @Binding var spendActivityMode: SpendActivityMode
    @Binding var selectedCategory: CategoryDrillDown?
    let currencyCode: String
    let palette: FloatThemePalette

    var body: some View {
        VStack(spacing: 16) {
            InsightsHeroPanel(
                report: report,
                currencyCode: currencyCode,
                palette: palette
            )
            InsightsBudgetControlPanel(
                report: report,
                currencyCode: currencyCode,
                palette: palette
            )

            ViewThatFits {
                HStack(alignment: .top, spacing: 16) {
                    VStack(spacing: 16) {
                        InsightsCategoryPanel(
                            report: report,
                            currencyCode: currencyCode,
                            onSelectCategory: { selectedCategory = report.drillDown(for: $0) }
                        )
                        InsightsCommitmentsPanel(
                            report: report,
                            currencyCode: currencyCode,
                            palette: palette
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .top)

                    VStack(spacing: 16) {
                        InsightsActivityPanel(
                            report: report,
                            mode: $spendActivityMode,
                            currencyCode: currencyCode
                        )
                        InsightsTopTransactionsPanel(
                            transactions: report.topTransactions,
                            currencyCode: currencyCode
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                }

                VStack(spacing: 16) {
                    InsightsCategoryPanel(
                        report: report,
                        currencyCode: currencyCode,
                        onSelectCategory: { selectedCategory = report.drillDown(for: $0) }
                    )
                    InsightsActivityPanel(
                        report: report,
                        mode: $spendActivityMode,
                        currencyCode: currencyCode
                    )
                    InsightsCommitmentsPanel(
                        report: report,
                        currencyCode: currencyCode,
                        palette: palette
                    )
                    InsightsTopTransactionsPanel(
                        transactions: report.topTransactions,
                        currencyCode: currencyCode
                    )
                }
            }
        }
    }
}

private struct InsightsPanel<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: LocalizedStringResource
    let subtitle: LocalizedStringResource
    let content: Content

    init(
        title: LocalizedStringResource,
        subtitle: LocalizedStringResource,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline.weight(.semibold))
                    Text(subtitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            content
        }
        .padding(18)
        .floatGlassSurface(
            cornerRadius: 24,
            material: .ultraThinMaterial,
            strokeOpacity: colorScheme == .dark ? 0.08 : 0.055,
            shadowOpacity: colorScheme == .dark ? 0.05 : 0.035,
            shadowRadius: 18,
            shadowY: 10
        )
    }
}

private struct InsightsHeroPanel: View {
    let report: InsightReport
    let currencyCode: String
    let palette: FloatThemePalette

    private var weekPulseDetail: String {
        if report.weekExpenseDeltaMinor == 0 {
            return String(localized: "Flat")
        }
        return signedMoney(report.weekExpenseDeltaMinor)
    }

    var body: some View {
        InsightsPanel(
            title: "Spending behavior",
            subtitle: "How money moved across this range"
        ) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    Text(report.narrative)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    NetFlowBadge(value: report.netCashFlowMinor)
                }

                InsightsMetricCard(
                    title: "Net position",
                    value: signedMoney(report.netCashFlowMinor),
                    detail: report.dateRangeText,
                    icon: "equal.circle.fill",
                    tint: report.netCashFlowMinor >= 0 ? palette.positive : palette.caution,
                    emphasis: .featured
                )

                if report.incomeTotalMinor == 0 && report.expenseTotalMinor == 0 {
                    EmptyStateView(
                        icon: "chart.line.uptrend.xyaxis",
                        title: "No trend yet",
                        message: "Add dated income and expenses to build a trend."
                    )
                } else {
                    InsightsSpendPulseChart(
                        report: report,
                        currencyCode: currencyCode,
                        palette: palette
                    )
                }

                InsightsMetricStrip {
                    ViewThatFits {
                        HStack(spacing: 0) {
                            InsightsCompactMetricCell(
                                title: "Run rate",
                                value: money(report.dailyAverageExpenseMinor),
                                detail: String(localized: "Average per day"),
                                icon: "calendar.badge.clock",
                                tint: palette.accent
                            )
                            Divider()
                            InsightsCompactMetricCell(
                                title: "Top spend day",
                                value: money(report.highestExpenseDay?.expenseMinor ?? 0),
                                detail: report.highestExpenseDay?.date.formatted(date: .abbreviated, time: .omitted)
                                    ?? String(localized: "None"),
                                icon: "calendar.badge.exclamationmark",
                                tint: palette.caution
                            )
                            Divider()
                            InsightsCompactMetricCell(
                                title: "Week pulse",
                                value: report.weekTrendText,
                                detail: weekPulseDetail,
                                icon: "waveform.path.ecg",
                                tint: report.weekExpenseDeltaMinor <= 0 ? palette.positive : palette.caution
                            )
                        }

                        VStack(spacing: 0) {
                            InsightsCompactMetricCell(
                                title: "Run rate",
                                value: money(report.dailyAverageExpenseMinor),
                                detail: String(localized: "Average per day"),
                                icon: "calendar.badge.clock",
                                tint: palette.accent
                            )
                            Divider()
                            InsightsCompactMetricCell(
                                title: "Top spend day",
                                value: money(report.highestExpenseDay?.expenseMinor ?? 0),
                                detail: report.highestExpenseDay?.date.formatted(date: .abbreviated, time: .omitted)
                                    ?? String(localized: "None"),
                                icon: "calendar.badge.exclamationmark",
                                tint: palette.caution
                            )
                            Divider()
                            InsightsCompactMetricCell(
                                title: "Week pulse",
                                value: report.weekTrendText,
                                detail: weekPulseDetail,
                                icon: "waveform.path.ecg",
                                tint: report.weekExpenseDeltaMinor <= 0 ? palette.positive : palette.caution
                            )
                        }
                    }
                }
            }
        }
    }

    private func money(_ amount: Int64) -> String {
        MoneyFormatter.string(minorUnits: amount, currencyCode: currencyCode)
    }

    private func signedMoney(_ amount: Int64) -> String {
        let absolute = MoneyFormatter.string(
            minorUnits: abs(amount),
            currencyCode: currencyCode
        )
        if amount == 0 {
            return absolute
        }
        return amount > 0 ? "+\(absolute)" : "-\(absolute)"
    }
}

private struct InsightsSpendPulseChart: View {
    @Environment(\.colorScheme) private var colorScheme

    let report: InsightReport
    let currencyCode: String
    let palette: FloatThemePalette

    private var maxExpenseMinor: Int64 {
        max(report.spendPulsePoints.map(\.expenseMinor).max() ?? 0, 1)
    }

    private var barWidth: MarkDimension {
        report.spendPulseUnit == .month ? .fixed(18) : .fixed(5)
    }

    private var xAxisLabelFormat: Date.FormatStyle {
        report.spendPulseUnit == .month
            ? .dateTime.month(.abbreviated)
            : .dateTime.month(.abbreviated).day()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits {
                HStack(spacing: 8) {
                    InsightsChartSummaryPill(
                        title: "Spent",
                        value: money(report.expenseTotalMinor),
                        tint: palette.caution
                    )
                    InsightsChartSummaryPill(
                        title: "Income",
                        value: money(report.incomeTotalMinor),
                        tint: palette.positive
                    )
                    InsightsChartSummaryPill(
                        title: "Daily average",
                        value: money(report.dailyAverageExpenseMinor),
                        tint: palette.accent
                    )
                }

                VStack(spacing: 8) {
                    InsightsChartSummaryPill(
                        title: "Spent",
                        value: money(report.expenseTotalMinor),
                        tint: palette.caution
                    )
                    HStack(spacing: 8) {
                        InsightsChartSummaryPill(
                            title: "Income",
                            value: money(report.incomeTotalMinor),
                            tint: palette.positive
                        )
                        InsightsChartSummaryPill(
                            title: "Daily average",
                            value: money(report.dailyAverageExpenseMinor),
                            tint: palette.accent
                        )
                    }
                }
            }

            Chart {
                ForEach(report.spendPulsePoints) { item in
                    BarMark(
                        x: .value("Period", item.date, unit: report.spendPulseUnit),
                        y: .value("Expenses", item.expenseMinor),
                        width: barWidth
                    )
                    .foregroundStyle(barColor(for: item))
                    .cornerRadius(4)
                }

                if report.dailyAverageExpenseMinor > 0 {
                    RuleMark(y: .value("Daily average", report.dailyAverageExpenseMinor))
                        .foregroundStyle(palette.accent.opacity(0.54))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 5]))
                }
            }
            .chartLegend(.hidden)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) {
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 4]))
                        .foregroundStyle(Color.primary.opacity(0.08))
                    AxisValueLabel(format: xAxisLabelFormat)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            .chartYAxis(.hidden)
            .chartPlotStyle { plotArea in
                plotArea
                    .padding(.top, 4)
                    .padding(.horizontal, 4)
                    .background(
                        Color.primary.opacity(colorScheme == .dark ? 0.045 : 0.024),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
            }
            .frame(height: 128)
            .accessibilityLabel(Text("Spending behavior"))
        }
    }

    private func barColor(for item: SpendingPulsePoint) -> Color {
        guard item.expenseMinor > 0 else {
            return Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08)
        }
        if item.expenseMinor == maxExpenseMinor {
            return palette.caution
        }
        return palette.accent.opacity(colorScheme == .dark ? 0.74 : 0.62)
    }

    private func money(_ amount: Int64) -> String {
        MoneyFormatter.string(minorUnits: amount, currencyCode: currencyCode)
    }
}

private struct InsightsChartSummaryPill: View {
    let title: LocalizedStringResource
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(value)
                    .font(.caption.weight(.bold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.74)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(minWidth: 112, maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.035), in: Capsule())
    }
}

private struct InsightsBudgetControlPanel: View {
    let report: InsightReport
    let currencyCode: String
    let palette: FloatThemePalette

    var body: some View {
        InsightsPanel(
            title: "Budget control",
            subtitle: "Safe-to-spend position and category pressure"
        ) {
            VStack(spacing: 14) {
                InsightsMetricCard(
                    title: "Safe to spend",
                    value: money(report.safeToSpend.safeToSpendMinor),
                    detail: report.safeToSpend.safeToSpendMinor >= 0
                        ? String(localized: "Available now")
                        : String(localized: "Overspent"),
                    icon: "checkmark.seal.fill",
                    tint: report.safeToSpend.safeToSpendMinor >= 0 ? palette.positive : palette.caution,
                    emphasis: .featured
                )

                InsightsMetricStrip {
                    ViewThatFits {
                        HStack(spacing: 0) {
                            InsightsCompactMetricCell(
                                title: "Daily room",
                                value: money(report.safeToSpend.dailyAllowanceMinor),
                                detail: String(localized: "Remaining pace"),
                                icon: "calendar",
                                tint: palette.accent
                            )
                            Divider()
                            InsightsCompactMetricCell(
                                title: "Recurring due",
                                value: money(report.safeToSpend.recurringDueMinor),
                                detail: String(localized: "Known commitments"),
                                icon: "repeat",
                                tint: palette.caution
                            )
                            Divider()
                            InsightsCompactMetricCell(
                                title: "Goals needed",
                                value: money(report.safeToSpend.goalContributionMinor),
                                detail: String(localized: "Target funding"),
                                icon: "target",
                                tint: palette.positive
                            )
                        }

                        VStack(spacing: 0) {
                            InsightsCompactMetricCell(
                                title: "Daily room",
                                value: money(report.safeToSpend.dailyAllowanceMinor),
                                detail: String(localized: "Remaining pace"),
                                icon: "calendar",
                                tint: palette.accent
                            )
                            Divider()
                            InsightsCompactMetricCell(
                                title: "Recurring due",
                                value: money(report.safeToSpend.recurringDueMinor),
                                detail: String(localized: "Known commitments"),
                                icon: "repeat",
                                tint: palette.caution
                            )
                            Divider()
                            InsightsCompactMetricCell(
                                title: "Goals needed",
                                value: money(report.safeToSpend.goalContributionMinor),
                                detail: String(localized: "Target funding"),
                                icon: "target",
                                tint: palette.positive
                            )
                        }
                    }
                }

                InsightsProgressRow(
                    title: "Period elapsed",
                    detail: report.percentText(report.safeToSpend.periodProgress),
                    progress: report.safeToSpend.periodProgress,
                    tint: palette.accent
                )
                InsightsProgressRow(
                    title: "Spending used",
                    detail: report.percentText(report.safeToSpend.spendingProgress),
                    progress: report.safeToSpend.spendingProgress,
                    tint: report.safeToSpend.spendingProgress > report.safeToSpend.periodProgress
                        ? palette.caution
                        : palette.positive
                )

                VStack(alignment: .leading, spacing: 10) {
                    InsightsMetricStrip {
                        HStack(spacing: 0) {
                            InsightsCompactMetricCell(
                                title: "Allocated",
                                value: money(report.totalCategoryBudgetMinor),
                                detail: String(localized: "Category budgets"),
                                icon: "chart.pie.fill",
                                tint: palette.accent
                            )
                            Divider()
                            InsightsCompactMetricCell(
                                title: "Spent",
                                value: money(report.totalCategoryBudgetSpentMinor),
                                detail: report.overCategoryBudgetCount == 0
                                    ? String(localized: "Within plan")
                                    : AppLocalization.format(
                                        "%lld over limit",
                                        Int64(report.overCategoryBudgetCount)
                                    ),
                                icon: "creditcard.fill",
                                tint: report.overCategoryBudgetCount == 0 ? palette.positive : palette.caution
                            )
                        }
                    }

                    Text(report.budgetHealthMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func money(_ amount: Int64) -> String {
        MoneyFormatter.string(minorUnits: amount, currencyCode: currencyCode)
    }
}

private struct InsightsCategoryPanel: View {
    let report: InsightReport
    let currencyCode: String
    let onSelectCategory: (CategoryInsight) -> Void

    var body: some View {
        InsightsPanel(
            title: "Category mix",
            subtitle: "Where expenses concentrate"
        ) {
            if report.categoryInsights.isEmpty {
                EmptyStateView(
                    icon: "chart.pie",
                    title: "No spending yet",
                    message: "Category reports update after transactions are added."
                )
            } else {
                ViewThatFits {
                    HStack(alignment: .top, spacing: 16) {
                        donutSummary
                            .frame(width: 154)
                        categoryList
                    }

                    VStack(spacing: 16) {
                        donutSummary
                        categoryList
                    }
                }
            }
        }
    }

    private var donutSummary: some View {
        ZStack {
            Chart(report.categoryInsights.prefix(5)) { item in
                SectorMark(
                    angle: .value("Amount", item.amountMinor),
                    innerRadius: .ratio(0.66),
                    angularInset: 2
                )
                .cornerRadius(7)
                .foregroundStyle(item.color)
            }
            .chartLegend(.hidden)

            VStack(spacing: 3) {
                Text("Total")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(money(report.expenseTotalMinor))
                    .moneyStyle(size: 17, weight: .bold)
                    .minimumScaleFactor(0.72)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(height: 154)
    }

    private var categoryList: some View {
        VStack(spacing: 10) {
            ForEach(report.categoryInsights.prefix(5)) { item in
                let budget = report.categoryBudgetInsights.first { $0.name == item.name }
                Button {
                    onSelectCategory(item)
                } label: {
                    InsightsCategoryRow(
                        item: item,
                        budgetInsight: budget,
                        currencyCode: currencyCode
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func money(_ amount: Int64) -> String {
        MoneyFormatter.string(minorUnits: amount, currencyCode: currencyCode)
    }
}

private struct InsightsActivityPanel: View {
    let report: InsightReport
    @Binding var mode: SpendActivityMode
    let currencyCode: String

    private var subtitle: LocalizedStringResource {
        mode == .year ? "Intensity across this year" : "Intensity across the selected days"
    }

    private var heatmapDays: [SpendActivityDay] {
        mode == .year ? report.yearSpendActivityDays : report.spendActivityDays
    }

    var body: some View {
        InsightsPanel(
            title: "Spend activity",
            subtitle: subtitle
        ) {
            SpendActivityHeatmap(
                days: heatmapDays,
                mode: $mode,
                currencyCode: currencyCode
            )
        }
    }
}

private struct InsightsCommitmentsPanel: View {
    let report: InsightReport
    let currencyCode: String
    let palette: FloatThemePalette

    private var isEmpty: Bool {
        report.recurringInsights.isEmpty && report.goalInsights.isEmpty
    }

    var body: some View {
        InsightsPanel(
            title: "Commitments and goals",
            subtitle: "Fixed outflow and target funding"
        ) {
            if isEmpty {
                EmptyStateView(
                    icon: "calendar.badge.clock",
                    title: "No commitments yet",
                    message: "Recurring bills and goals will appear here."
                )
            } else {
                VStack(spacing: 14) {
                    InsightsMetricStrip {
                        HStack(spacing: 0) {
                            InsightsCompactMetricCell(
                                title: "Active recurring",
                                value: "\(report.activeRecurringCount)",
                                detail: String(localized: "Rules running"),
                                icon: "repeat",
                                tint: palette.accent
                            )
                            Divider()
                            InsightsCompactMetricCell(
                                title: "Monthly load",
                                value: money(report.monthlyRecurringLoadMinor),
                                detail: String(localized: "Expected outflow"),
                                icon: "calendar",
                                tint: palette.caution
                            )
                        }
                    }

                    InsightsMetricStrip {
                        HStack(spacing: 0) {
                            InsightsCompactMetricCell(
                                title: "Saved",
                                value: money(report.totalGoalSavedMinor),
                                detail: String(localized: "Across goals"),
                                icon: "checkmark.circle",
                                tint: palette.positive
                            )
                            Divider()
                            InsightsCompactMetricCell(
                                title: "Remaining",
                                value: money(report.totalGoalRemainingMinor),
                                detail: String(localized: "Still to fund"),
                                icon: "target",
                                tint: palette.positive
                            )
                        }
                    }

                    if !report.recurringInsights.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Recurring")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            ForEach(report.recurringInsights.prefix(3)) { item in
                                InsightsCommitmentRow(
                                    title: item.name,
                                    subtitle: item.detail,
                                    amountText: money(item.amountMinor),
                                    icon: item.icon,
                                    tint: palette.caution
                                )
                            }
                        }
                    }

                    if !report.recurringInsights.isEmpty && !report.goalInsights.isEmpty {
                        Divider()
                    }

                    if !report.goalInsights.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Goals")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            ForEach(report.goalInsights.prefix(3)) { item in
                                InsightsGoalProgressRow(
                                    item: item,
                                    currencyCode: currencyCode,
                                    percentText: report.percentText(item.progress)
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    private func money(_ amount: Int64) -> String {
        MoneyFormatter.string(minorUnits: amount, currencyCode: currencyCode)
    }
}

private struct InsightsTopTransactionsPanel: View {
    let transactions: [TransactionItem]
    let currencyCode: String

    var body: some View {
        InsightsPanel(
            title: "Top transactions",
            subtitle: "Largest expenses in this range"
        ) {
            if transactions.isEmpty {
                EmptyStateView(
                    icon: "list.bullet.rectangle",
                    title: "No expenses yet",
                    message: "Large expenses will appear here."
                )
            } else {
                VStack(spacing: 8) {
                    ForEach(transactions) { transaction in
                        TransactionRowView(
                            transaction: transaction,
                            currencyCode: currencyCode
                        )
                        if transaction.id != transactions.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }
}

private struct InsightsMetricCard: View {
    enum Emphasis {
        case regular
        case featured
    }

    @Environment(\.colorScheme) private var colorScheme

    let title: LocalizedStringResource
    let value: String
    let detail: String?
    let icon: String
    let tint: Color
    var emphasis: Emphasis = .regular

    private var shape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: emphasis == .featured ? 24 : 14,
            style: .continuous
        )
    }

    private var backgroundColor: Color {
        Color.primary.opacity(colorScheme == .dark ? 0.045 : 0.025)
    }

    private var strokeColor: Color {
        Color.primary.opacity(colorScheme == .dark ? 0.09 : 0.06)
    }

    private var featuredGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.primary.opacity(colorScheme == .dark ? 0.055 : 0.026),
                tint.opacity(colorScheme == .dark ? 0.07 : 0.035)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        HStack(alignment: .top, spacing: emphasis == .featured ? 14 : 10) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(tint)
                .frame(width: emphasis == .featured ? 4 : 3)
                .opacity(emphasis == .featured ? 0.82 : 0.64)

            VStack(alignment: .leading, spacing: emphasis == .featured ? 14 : 9) {
                HStack(spacing: 7) {
                    Image(systemName: icon)
                        .font(.system(size: emphasis == .featured ? 14 : 12, weight: .semibold))
                        .foregroundStyle(tint)
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(value)
                        .font(
                            .system(
                                size: emphasis == .featured ? 31 : 20,
                                weight: .bold,
                                design: .rounded
                            )
                            .monospacedDigit()
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)

                    if let detail {
                        Text(detail)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
        }
        .padding(emphasis == .featured ? 18 : 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if emphasis == .featured {
                featuredGradient
                    .clipShape(shape)
            } else {
                backgroundColor
                    .clipShape(shape)
            }
        }
        .overlay(shape.strokeBorder(strokeColor, lineWidth: 1))
    }
}

private struct InsightsMetricStrip<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
    }

    var body: some View {
        content
            .background(
                Color.primary.opacity(colorScheme == .dark ? 0.045 : 0.025),
                in: shape
            )
            .overlay(
                shape.strokeBorder(
                    Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.05),
                    lineWidth: 1
                )
            )
    }
}

private struct InsightsCompactMetricCell: View {
    let title: LocalizedStringResource
    let value: String
    let detail: String?
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }

            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.74)

            if let detail {
                Text(detail)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.74)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct InsightsLegendLabel: View {
    let title: LocalizedStringResource
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}

private struct InsightsProgressRow: View {
    let title: LocalizedStringResource
    let detail: String
    let progress: Double
    let tint: Color

    var body: some View {
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
}

private struct InsightsCategoryRow: View {
    let item: CategoryInsight
    let budgetInsight: CategoryBudgetInsight?
    let currencyCode: String

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(item.color)
                .frame(width: 9, height: 9)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if let budgetInsight {
                    Text(budgetInsight.statusText(currencyCode: currencyCode))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("No category budget")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(money(item.amountMinor))
                    .moneyStyle(size: 14, weight: .semibold)
                Text(percentText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var percentText: String {
        "\(Int((item.share * 100).rounded()))%"
    }

    private func money(_ amount: Int64) -> String {
        MoneyFormatter.string(minorUnits: amount, currencyCode: currencyCode)
    }
}

private struct InsightsCommitmentRow: View {
    let title: String
    let subtitle: String
    let amountText: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            FloatIconBadge(icon: icon, tint: tint, size: 32)
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
            Text(amountText)
                .moneyStyle(size: 14, weight: .semibold)
        }
    }
}

private struct InsightsGoalProgressRow: View {
    let item: GoalInsight
    let currencyCode: String
    let percentText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(item.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Text(percentText)
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
                Text(
                    MoneyFormatter.string(
                        minorUnits: item.remainingMinor,
                        currencyCode: currencyCode
                    )
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            }
        }
    }
}

private struct NetFlowBadge: View {
    let value: Int64

    private var tint: Color {
        if value == 0 {
            return .secondary
        }
        return value > 0 ? Color(hex: "#1B8A5A") : Color(hex: "#B4613B")
    }

    private var icon: String {
        if value == 0 {
            return "equal.circle.fill"
        }
        return value > 0 ? "arrow.up.right.circle.fill" : "arrow.down.right.circle.fill"
    }

    private var title: LocalizedStringResource {
        if value == 0 {
            return "Flat"
        }
        return value > 0 ? "Positive" : "Negative"
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption.weight(.bold))
            Text(title)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(tint.opacity(0.12), in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(tint.opacity(0.12), lineWidth: 1)
        )
    }
}

private struct SpendActivityHeatmap: View {
    let days: [SpendActivityDay]
    @Binding var mode: SpendActivityMode
    let currencyCode: String

    @Environment(\.colorScheme) private var colorScheme

    private let cellSize: CGFloat = 11
    private let cellSpacing: CGFloat = 3

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
        return 28
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
                VStack(alignment: .leading, spacing: 10) {
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
                .padding(12)
                .background(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.035), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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
                        .minimumScaleFactor(0.82)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(
                            mode == item ? Color.primary.opacity(0.10) : Color.clear,
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
                .foregroundStyle(mode == item ? .primary : .secondary)
                .accessibilityLabel(item.accessibilityLabel)
            }
        }
        .padding(4)
        .background(Color.primary.opacity(0.05), in: Capsule())
    }

    private var monthHeader: some View {
        ZStack(alignment: .leading) {
            ForEach(weeks.indices.filter { !monthLabel(for: $0).isEmpty }, id: \.self) { index in
                Text(monthLabel(for: index))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .offset(x: 28 + CGFloat(index) * (cellSize + cellSpacing))
            }
        }
        .frame(width: heatmapWidth, height: 14, alignment: .leading)
    }

    private var heatmapGrid: some View {
        HStack(alignment: .top, spacing: 5) {
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
                    .frame(width: 22, height: cellSize, alignment: .trailing)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(
                    AppLocalization.format(
                        "%lld spending days",
                        Int64(activeDayCount)
                    )
                )
                .font(.caption.weight(.semibold))
                Text(
                    AppLocalization.format(
                        "Avg %@ / day",
                        money(averageSpendMinor)
                    )
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 4) {
                Text("Low")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                ForEach(0..<5, id: \.self) { level in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(legendColor(level: level))
                        .frame(width: 10, height: 10)
                }
                Text("High")
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
            return Color(hex: "#D7F0EE")
        case 2:
            return Color(hex: "#83D8CE")
        case 3:
            return Color(hex: "#0E7C7B")
        default:
            return Color(hex: "#B4613B")
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
            return Color.primary.opacity(colorScheme == .dark ? 0.05 : 0.03)
        }
        guard valueMinor > 0 else {
            return Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.07)
        }
        switch ratio {
        case 0..<0.2:
            return Color(hex: "#D7F0EE")
        case 0.2..<0.42:
            return Color(hex: "#83D8CE")
        case 0.42..<0.68:
            return Color(hex: "#0E7C7B")
        default:
            return Color(hex: "#B4613B")
        }
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(fill)
            .overlay(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: day.isToday ? 1.2 : 0.8)
            )
            .opacity(day.isInsideRange ? 1 : 0.46)
            .accessibilityLabel(accessibilityLabel)
    }

    private var borderColor: Color {
        if day.isToday {
            return Color.accentColor.opacity(0.8)
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
            return AppLocalization.format("%@, %@, 1 expense", date, amount)
        }
        return AppLocalization.format(
            "%@, %@, %lld expenses",
            date,
            amount,
            Int64(day.transactionCount)
        )
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
        transactions.filter(\.isPostedIncome).reduce(0) { $0 + $1.amountMinor }
    }

    var expenseTotalMinor: Int64 {
        transactions.filter(\.isPostedExpense).reduce(0) { $0 + $1.amountMinor }
    }

    var netCashFlowMinor: Int64 {
        incomeTotalMinor - expenseTotalMinor
    }

    var previousExpenseTotalMinor: Int64 {
        previousTransactions.filter(\.isPostedExpense).reduce(0) { $0 + $1.amountMinor }
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

    var spendPulseUnit: Calendar.Component {
        cashFlowTrendUnit
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
        topTransactions.first?.categoryName ?? String(localized: "None")
    }

    var narrative: String {
        guard expenseTotalMinor > 0 || incomeTotalMinor > 0 else {
            return String(localized: "No activity in this range yet.")
        }

        let direction: String
        if previousExpenseTotalMinor == 0 {
            direction = String(localized: "There is no comparable prior spending yet.")
        } else if expenseTotalMinor < previousExpenseTotalMinor {
            direction = String(localized: "Spending is below the previous comparable range.")
        } else if expenseTotalMinor > previousExpenseTotalMinor {
            direction = String(localized: "Spending is above the previous comparable range.")
        } else {
            direction = String(localized: "Spending matches the previous comparable range.")
        }

        if let topCategory {
            return AppLocalization.format(
                "%@ leads expenses. %@",
                topCategory.name,
                direction
            )
        }
        return direction
    }

    var budgetHealthMessage: String {
        if safeToSpend.overAmountMinor > 0 {
            return String(
                localized: "This period is over budget. Reduce flexible spending or adjust the budget assumptions."
            )
        }
        if safeToSpend.spendingProgress > safeToSpend.periodProgress {
            return String(
                localized: "Spending is ahead of time elapsed, so the daily allowance is tightening."
            )
        }
        return String(localized: "Spending is tracking within the current period pace.")
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
                        transaction.isPostedExpense && transaction.category?.id == category?.id
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
            grouping: transactions.filter(\.isPostedExpense),
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
            let income = items.filter(\.isPostedIncome).reduce(Int64(0)) {
                $0 + $1.amountMinor
            }
            let expense = items.filter(\.isPostedExpense).reduce(Int64(0)) {
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

    var spendPulsePoints: [SpendingPulsePoint] {
        let calendar = Calendar.current
        let unit = spendPulseUnit
        let components: Set<Calendar.Component> = unit == .month
            ? [.year, .month] : [.year, .month, .day]
        let grouped = Dictionary(grouping: transactions) {
            calendar.date(from: calendar.dateComponents(components, from: $0.timestamp))
                ?? calendar.startOfDay(for: $0.timestamp)
        }

        return pulseDates(calendar: calendar, unit: unit).map { date in
            let items = grouped[date] ?? []
            return SpendingPulsePoint(
                date: date,
                incomeMinor: items.filter(\.isPostedIncome).reduce(Int64(0)) {
                    $0 + $1.amountMinor
                },
                expenseMinor: items.filter(\.isPostedExpense).reduce(Int64(0)) {
                    $0 + $1.amountMinor
                }
            )
        }
    }

    var dailyExpenseInsights: [CalendarExpenseInsight] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: transactions.filter(\.isPostedExpense)) {
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

        let grouped = Dictionary(grouping: sourceTransactions.filter(\.isPostedExpense)) {
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
        guard weekExpenseDeltaMinor != 0 else { return String(localized: "Flat") }
        return weekExpenseDeltaMinor < 0 ? String(localized: "Down") : String(localized: "Up")
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
                    name: $0.note?.nilIfBlank ?? $0.category?.name ?? String(localized: "Recurring"),
                    detail: AppLocalization.format(
                        "%@ · next %@",
                        $0.cadence.title,
                        $0.nextRunDate.formatted(
                            Date.FormatStyle(date: .abbreviated, time: .omitted)
                                .locale(AppLocalization.locale)
                        )
                    ),
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
                ?? String(localized: "No target date")
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
                .filter(\.isPostedExpense)
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
                $0.isPostedExpense
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

    private func pulseDates(calendar: Calendar, unit: Calendar.Component) -> [Date] {
        if unit == .month {
            let start = calendar.date(
                from: calendar.dateComponents([.year, .month], from: range.start)
            ) ?? calendar.startOfDay(for: range.start)
            let end = calendar.date(
                from: calendar.dateComponents([.year, .month], from: range.end)
            ) ?? calendar.startOfDay(for: range.end)
            return datesByAdding(.month, from: start, through: end, calendar: calendar)
        }
        return dates(from: range.start, through: range.end, calendar: calendar)
    }

    private func datesByAdding(
        _ component: Calendar.Component,
        from start: Date,
        through end: Date,
        calendar: Calendar
    ) -> [Date] {
        var results: [Date] = []
        var cursor = start
        while cursor <= end {
            results.append(cursor)
            guard let next = calendar.date(byAdding: component, value: 1, to: cursor) else {
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
            .filter { $0.isPostedExpense && $0.categoryName == category.name }
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

private extension InsightReport {
    static var previewPopulated: InsightReport {
        let calendar = Calendar.current
        let end = calendar.startOfDay(for: Date())
        let start = calendar.date(byAdding: .day, value: -29, to: end) ?? end
        let previousStart = calendar.date(byAdding: .day, value: -29, to: start) ?? start

        let checking = AccountItem(name: "Checking", currencyCode: "USD")
        let salary = CategoryItem(
            name: "Salary",
            iconKey: "banknote.fill",
            colorHex: "#1B8A5A",
            isIncome: true
        )
        let groceries = CategoryItem(
            name: "Groceries",
            iconKey: "cart.fill",
            colorHex: "#0E7C7B"
        )
        let dining = CategoryItem(
            name: "Dining",
            iconKey: "fork.knife",
            colorHex: "#B4613B"
        )
        let travel = CategoryItem(
            name: "Travel",
            iconKey: "airplane",
            colorHex: "#0A6FAE"
        )
        let utilities = CategoryItem(
            name: "Utilities",
            iconKey: "bolt.fill",
            colorHex: "#8B5CF6"
        )
        let transport = CategoryItem(
            name: "Transport",
            iconKey: "car.fill",
            colorHex: "#F59E0B"
        )

        let transactions: [TransactionItem] = [
            TransactionItem(
                amountMinor: 650_000,
                isExpense: false,
                timestamp: calendar.date(byAdding: .day, value: 1, to: start) ?? start,
                category: salary,
                account: checking,
                note: "Monthly pay"
            ),
            TransactionItem(
                amountMinor: 12_400,
                timestamp: calendar.date(byAdding: .day, value: 2, to: start) ?? start,
                category: groceries,
                account: checking,
                note: "Weekly market"
            ),
            TransactionItem(
                amountMinor: 5_600,
                timestamp: calendar.date(byAdding: .day, value: 4, to: start) ?? start,
                category: dining,
                account: checking,
                note: "Dinner with friends"
            ),
            TransactionItem(
                amountMinor: 2_100,
                timestamp: calendar.date(byAdding: .day, value: 6, to: start) ?? start,
                category: transport,
                account: checking,
                note: "Metro card"
            ),
            TransactionItem(
                amountMinor: 18_900,
                timestamp: calendar.date(byAdding: .day, value: 8, to: start) ?? start,
                category: travel,
                account: checking,
                note: "Flight booking"
            ),
            TransactionItem(
                amountMinor: 7_800,
                timestamp: calendar.date(byAdding: .day, value: 13, to: start) ?? start,
                category: utilities,
                account: checking,
                note: "Power bill"
            ),
            TransactionItem(
                amountMinor: 4_900,
                timestamp: calendar.date(byAdding: .day, value: 17, to: start) ?? start,
                category: dining,
                account: checking,
                note: "Coffee and lunch"
            ),
            TransactionItem(
                amountMinor: 8_400,
                timestamp: calendar.date(byAdding: .day, value: 20, to: start) ?? start,
                category: groceries,
                account: checking,
                note: "Restock"
            ),
            TransactionItem(
                amountMinor: 3_600,
                timestamp: calendar.date(byAdding: .day, value: 24, to: start) ?? start,
                category: transport,
                account: checking,
                note: "Ride share"
            ),
            TransactionItem(
                amountMinor: 6_200,
                timestamp: calendar.date(byAdding: .day, value: 27, to: start) ?? start,
                category: groceries,
                account: checking,
                note: "Farmer's market"
            ),
        ]

        let previousTransactions: [TransactionItem] = [
            TransactionItem(
                amountMinor: 10_200,
                timestamp: calendar.date(byAdding: .day, value: 3, to: previousStart) ?? previousStart,
                category: groceries,
                account: checking
            ),
            TransactionItem(
                amountMinor: 3_900,
                timestamp: calendar.date(byAdding: .day, value: 7, to: previousStart) ?? previousStart,
                category: dining,
                account: checking
            ),
            TransactionItem(
                amountMinor: 5_000,
                timestamp: calendar.date(byAdding: .day, value: 12, to: previousStart) ?? previousStart,
                category: utilities,
                account: checking
            ),
        ]

        let recurringRules = [
            RecurringRuleItem(
                amountMinor: 7_800,
                category: utilities,
                account: checking,
                note: "Power",
                cadence: .monthly,
                nextRunDate: calendar.date(byAdding: .day, value: 3, to: end) ?? end
            ),
            RecurringRuleItem(
                amountMinor: 1_299,
                category: dining,
                account: checking,
                note: "Music",
                cadence: .monthly,
                nextRunDate: calendar.date(byAdding: .day, value: 8, to: end) ?? end
            ),
        ]

        let goals = [
            GoalItem(
                name: "Vacation",
                targetMinor: 250_000,
                savedMinor: 98_000,
                targetDate: calendar.date(byAdding: .month, value: 3, to: end),
                colorHex: "#0A6FAE"
            ),
            GoalItem(
                name: "Emergency fund",
                targetMinor: 500_000,
                savedMinor: 275_000,
                targetDate: calendar.date(byAdding: .month, value: 6, to: end),
                colorHex: "#8B5CF6"
            ),
        ]

        let budget = BudgetPeriodItem(
            cadence: .monthly,
            startDayOfMonth: 1,
            expectedIncomeMinor: 650_000,
            currencyCode: "USD",
            isActive: true
        )

        let categoryBudgets = [
            CategoryBudgetItem(
                category: groceries,
                amountMinor: 35_000,
                currencyCode: "USD"
            ),
            CategoryBudgetItem(
                category: dining,
                amountMinor: 12_000,
                currencyCode: "USD"
            ),
            CategoryBudgetItem(
                category: travel,
                amountMinor: 15_000,
                currencyCode: "USD"
            ),
            CategoryBudgetItem(
                category: utilities,
                amountMinor: 9_000,
                currencyCode: "USD"
            ),
        ]

        return InsightReport(
            title: String(localized: "Current period"),
            range: BudgetPeriod(start: start, end: end),
            transactions: transactions,
            previousTransactions: previousTransactions,
            allTransactions: transactions,
            budgets: [budget],
            categoryBudgets: categoryBudgets,
            goals: goals,
            recurringRules: recurringRules,
            activeBudget: budget,
            palette: FloatTheme.palette(for: "float").chartColors
        )
    }

    static var previewEmpty: InsightReport {
        let end = Calendar.current.startOfDay(for: Date())
        let start = Calendar.current.date(byAdding: .day, value: -29, to: end) ?? end
        return InsightReport(
            title: String(localized: "Current period"),
            range: BudgetPeriod(start: start, end: end),
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
            return String(
                localized: "Over by \(MoneyFormatter.string(minorUnits: overMinor, currencyCode: currencyCode))"
            )
        }
        return String(
            localized: "\(MoneyFormatter.string(minorUnits: remainingMinor, currencyCode: currencyCode)) left"
        )
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
                                Text("Share of report expenses")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(money(category.amountMinor))
                                .moneyStyle(size: 18, weight: .bold)
                        }

                        InsightsMetricStrip {
                            HStack(spacing: 0) {
                                InsightsCompactMetricCell(
                                    title: "Share",
                                    value: percentText(category.share),
                                    detail: String(localized: "Of this report"),
                                    icon: "chart.pie.fill",
                                    tint: category.color
                                )
                                Divider()
                                InsightsCompactMetricCell(
                                    title: "Transactions",
                                    value: "\(category.transactions.count)",
                                    detail: groupedTransactions.first?.0.formatted(date: .abbreviated, time: .omitted)
                                        ?? String(localized: "None"),
                                    icon: "list.bullet.rectangle",
                                    tint: category.color
                                )
                            }
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

private struct SpendingPulsePoint: Identifiable {
    var id: Date { date }

    let date: Date
    let incomeMinor: Int64
    let expenseMinor: Int64
}

private struct CalendarExpenseInsight: Identifiable {
    let id = UUID()
    let date: Date
    let expenseMinor: Int64
    let transactionCount: Int

    var countText: String {
        AppLocalization.format("%lld txns", Int64(transactionCount))
    }

    func summaryText(currencyCode: String) -> String {
        let amount = MoneyFormatter.string(
            minorUnits: expenseMinor,
            currencyCode: currencyCode
        )
        return AppLocalization.format(
            "%@ • %@",
            date.formatted(
                Date.FormatStyle()
                    .month(.abbreviated)
                    .day()
                    .locale(AppLocalization.locale)
            ),
            amount
        )
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
            return String(localized: "Daily")
        case .weekly:
            return String(localized: "Weekly")
        case .cumulative:
            return String(localized: "Cumulative")
        case .year:
            return String(localized: "Year")
        }
    }

    var accessibilityLabel: String {
        AppLocalization.format("%@ spend activity", title)
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
        case .currentPeriod: String(localized: "Current period")
        case .lastPeriod: String(localized: "Last period")
        case .lastThreePeriods: String(localized: "Last 3 periods")
        case .thisYear: String(localized: "This year")
        case .custom: String(localized: "Custom range")
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

#Preview("Insights Populated") {
    InsightsPreviewScaffold {
        InsightsDashboardContent(
            report: .previewPopulated,
            spendActivityMode: .constant(.daily),
            selectedCategory: .constant(nil),
            currencyCode: "USD",
            palette: FloatTheme.palette(for: "float")
        )
    }
}

#Preview("Insights Empty") {
    InsightsPreviewScaffold {
        InsightsDashboardContent(
            report: .previewEmpty,
            spendActivityMode: .constant(.daily),
            selectedCategory: .constant(nil),
            currencyCode: "USD",
            palette: FloatTheme.palette(for: "float")
        )
    }
}

#Preview("Insights Loading") {
    InsightsPreviewScaffold {
        InsightsLoadingCard()
    }
}

#Preview("Insights Error") {
    InsightsPreviewScaffold {
        InsightsErrorCard(
            message: "Preview error state",
            tint: FloatTheme.palette(for: "float").caution,
            retry: {}
        )
    }
}

private struct InsightsPreviewScaffold<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView {
            content
                .padding(20)
        }
        .floatBackground()
    }
}
