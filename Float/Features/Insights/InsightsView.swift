import Charts
import SwiftData
import SwiftUI

struct InsightsView: View {
    @EnvironmentObject private var appState: AppState
    @Query(sort: \TransactionItem.timestamp, order: .reverse) private
        var transactions: [TransactionItem]
    @Query private var budgets: [BudgetPeriodItem]
    @Query private var recurringRules: [RecurringRuleItem]

    private let palette = [
        Color(hex: "#0E7C7B"),
        Color(hex: "#1B8A5A"),
        Color(hex: "#3B82F6"),
        Color(hex: "#8B5CF6"),
        Color(hex: "#B4613B"),
        Color(hex: "#EC4899"),
    ]

    private var period: BudgetPeriod {
        BudgetPeriodCalculator.currentPeriod(
            for: budgets.first { $0.isActive } ?? budgets.first
        )
    }

    private var currentTransactions: [TransactionItem] {
        transactions.filter {
            period.start <= $0.timestamp
                && $0.timestamp <= Calendar.current.endOfDay(for: period.end)
        }
    }

    private var categoryInsights: [CategoryInsight] {
        Dictionary(
            grouping: currentTransactions.filter(\.isExpense),
            by: { $0.category?.name ?? "Other" }
        )
        .map { name, items in
            (name, items.reduce(Int64(0)) { $0 + $1.amountMinor })
        }
        .sorted { $0.1 > $1.1 }
        .prefix(6)
        .enumerated()
        .map { index, item in
            CategoryInsight(
                name: item.0,
                amountMinor: item.1,
                color: palette[index % palette.count]
            )
        }
    }

    private var dailyInsights: [DailyInsight] {
        let grouped = Dictionary(
            grouping: currentTransactions.filter(\.isExpense),
            by: { Calendar.current.startOfDay(for: $0.timestamp) }
        )
        return
            grouped
            .map { day, items in
                DailyInsight(
                    day: day,
                    amountMinor: items.reduce(Int64(0)) { $0 + $1.amountMinor }
                )
            }
            .sorted { $0.day < $1.day }
    }

    private var cashFlowInsights: [CashFlowInsight] {
        [
            CashFlowInsight(
                name: "Income",
                amountMinor: incomeTotal,
                color: Color(hex: "#1B8A5A")
            ),
            CashFlowInsight(
                name: "Expense",
                amountMinor: expenseTotal,
                color: Color(hex: "#0E7C7B")
            ),
        ]
    }

    private var incomeTotal: Int64 {
        currentTransactions.filter { !$0.isExpense }.reduce(0) {
            $0 + $1.amountMinor
        }
    }

    private var expenseTotal: Int64 {
        currentTransactions.filter(\.isExpense).reduce(0) {
            $0 + $1.amountMinor
        }
    }

    private var dailyAverage: Int64 {
        guard !dailyInsights.isEmpty else { return 0 }
        return expenseTotal / Int64(max(1, dailyInsights.count))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                summaryCard
                categoryCard
                dailyCard
                cashFlowCard
            }
            .padding(20)
            .padding(.bottom, 40)
        }
        .navigationTitle("Insights")
        .floatBackground()
    }

    private var summaryCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Current period")
                            .font(.headline)
                        Text(
                            period.start.formatted(
                                date: .abbreviated,
                                time: .omitted
                            ) + " - "
                                + period.end.formatted(
                                    date: .abbreviated,
                                    time: .omitted
                                )
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(
                            MoneyFormatter.string(
                                minorUnits: expenseTotal,
                                currencyCode: appState.selectedCurrencyCode
                            )
                        )
                        .moneyStyle(size: 22, weight: .bold)
                        Text("spent")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(
                    categoryInsights.first.map {
                        "\($0.name) is your top category this period."
                    } ?? "Your period is ready for its first transaction."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    metricPill(
                        title: "Income",
                        amount: incomeTotal,
                        tint: Color(hex: "#1B8A5A")
                    )
                    metricPill(
                        title: "Recurring",
                        amount: recurringExpenseTotal,
                        tint: Color(hex: "#B4613B")
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var categoryCard: some View {
        insightCard(
            title: "Top categories",
            subtitle: "Share of spending this period"
        ) {
            if categoryInsights.isEmpty {
                EmptyStateView(
                    icon: "chart.pie",
                    title: "No spending yet",
                    message: "Charts update as your period fills in."
                )
            } else {
                VStack(spacing: 18) {
                    ZStack {
                        Chart(categoryInsights) { item in
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
                            Text(
                                MoneyFormatter.string(
                                    minorUnits: expenseTotal,
                                    currencyCode: appState.selectedCurrencyCode
                                )
                            )
                            .moneyStyle(size: 20, weight: .bold)
                            .minimumScaleFactor(0.75)
                        }
                    }
                    .frame(height: 250)

                    VStack(spacing: 10) {
                        ForEach(categoryInsights) { item in
                            categoryLegendRow(item)
                        }
                    }
                }
            }
        }
    }

    private var dailyCard: some View {
        insightCard(
            title: "Daily spending",
            subtitle: "A calmer view of your period rhythm"
        ) {
            if dailyInsights.isEmpty {
                EmptyStateView(
                    icon: "chart.xyaxis.line",
                    title: "No daily trend yet",
                    message:
                        "Add a few transactions to see the line take shape."
                )
            } else {
                Chart {
                    ForEach(dailyInsights) { item in
                        AreaMark(
                            x: .value("Day", item.day),
                            y: .value("Amount", item.amountMinor)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    Color(hex: "#0E7C7B").opacity(0.28),
                                    Color(hex: "#0E7C7B").opacity(0.02),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                        LineMark(
                            x: .value("Day", item.day),
                            y: .value("Amount", item.amountMinor)
                        )
                        .foregroundStyle(Color(hex: "#0E7C7B"))
                        .lineStyle(
                            StrokeStyle(
                                lineWidth: 3,
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )

                        PointMark(
                            x: .value("Day", item.day),
                            y: .value("Amount", item.amountMinor)
                        )
                        .foregroundStyle(Color(hex: "#0E7C7B"))
                    }

                    if dailyAverage > 0 {
                        RuleMark(y: .value("Average", dailyAverage))
                            .foregroundStyle(Color.secondary.opacity(0.45))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4))
                }
                .chartYAxis {
                    AxisMarks(
                        position: .leading,
                        values: .automatic(desiredCount: 4)
                    )
                }
                .frame(height: 240)
            }
        }
    }

    private var cashFlowCard: some View {
        insightCard(
            title: "Income vs expense",
            subtitle: "Money in and out for this period"
        ) {
            Chart(cashFlowInsights) { item in
                BarMark(
                    x: .value("Type", item.name),
                    y: .value("Amount", item.amountMinor),
                    width: .ratio(0.52)
                )
                .cornerRadius(12)
                .foregroundStyle(item.color.gradient)
            }
            .chartLegend(.hidden)
            .chartYAxis {
                AxisMarks(
                    position: .leading,
                    values: .automatic(desiredCount: 4)
                )
            }
            .frame(height: 220)

            HStack(spacing: 12) {
                metricPill(
                    title: "Income",
                    amount: incomeTotal,
                    tint: Color(hex: "#1B8A5A")
                )
                metricPill(
                    title: "Expense",
                    amount: expenseTotal,
                    tint: Color(hex: "#0E7C7B")
                )
            }
        }
    }

    private var recurringExpenseTotal: Int64 {
        recurringRules.filter { $0.active && $0.isExpense }.reduce(0) {
            $0 + $1.amountMinor
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

    private func categoryLegendRow(_ item: CategoryInsight) -> some View {
        let percent =
            expenseTotal == 0
            ? 0
            : Int(
                (Double(item.amountMinor) / Double(expenseTotal) * 100)
                    .rounded()
            )
        return HStack(spacing: 10) {
            Circle()
                .fill(item.color)
                .frame(width: 10, height: 10)
            Text(item.name)
                .font(.subheadline.weight(.medium))
            Spacer()
            Text("\(percent)%")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(
                MoneyFormatter.string(
                    minorUnits: item.amountMinor,
                    currencyCode: appState.selectedCurrencyCode
                )
            )
            .moneyStyle(size: 14, weight: .semibold)
            .frame(minWidth: 88, alignment: .trailing)
        }
    }

    private func metricPill(title: String, amount: Int64, tint: Color)
        -> some View
    {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(
                MoneyFormatter.string(
                    minorUnits: amount,
                    currencyCode: appState.selectedCurrencyCode
                )
            )
            .moneyStyle(size: 15, weight: .semibold)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            tint.opacity(0.12),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(tint.opacity(0.18), lineWidth: 1)
        )
    }
}

private struct CategoryInsight: Identifiable {
    let id = UUID()
    let name: String
    let amountMinor: Int64
    let color: Color
}

private struct DailyInsight: Identifiable {
    let id = UUID()
    let day: Date
    let amountMinor: Int64
}

private struct CashFlowInsight: Identifiable {
    let id = UUID()
    let name: String
    let amountMinor: Int64
    let color: Color
}

extension Calendar {
    fileprivate func endOfDay(for date: Date) -> Date {
        let start = startOfDay(for: date)
        return self.date(
            byAdding: DateComponents(day: 1, second: -1),
            to: start
        ) ?? date
    }
}
