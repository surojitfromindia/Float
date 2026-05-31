import Charts
import SwiftData
import SwiftUI

struct CalendarView: View {
    @EnvironmentObject private var appState: AppState
    @Query(sort: \TransactionItem.timestamp, order: .reverse) private
        var transactions: [TransactionItem]

    @State private var displayedMonth = Calendar.current.startOfMonth(for: Date())
    @State private var selectedDay: CalendarDaySelection?

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 7)

    private var monthTransactions: [TransactionItem] {
        guard let interval = calendar.dateInterval(of: .month, for: displayedMonth) else {
            return []
        }
        return transactions.filter {
            interval.start <= $0.timestamp && $0.timestamp < interval.end
        }
    }

    private var monthSummary: CalendarPeriodSummary {
        CalendarPeriodSummary(transactions: monthTransactions)
    }

    private var transactionGroups: [Date: [TransactionItem]] {
        Dictionary(grouping: transactions) {
            calendar.startOfDay(for: $0.timestamp)
        }
    }

    private var calendarDays: [CalendarDaySummary] {
        guard let interval = calendar.dateInterval(of: .month, for: displayedMonth) else {
            return []
        }
        let firstDay = interval.start
        let weekdayOffset = (
            calendar.component(.weekday, from: firstDay) - calendar.firstWeekday + 7
        ) % 7
        let gridStart = calendar.date(byAdding: .day, value: -weekdayOffset, to: firstDay)
            ?? firstDay

        return (0..<42).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: gridStart) else {
                return nil
            }
            let day = calendar.startOfDay(for: date)
            return CalendarDaySummary(
                date: day,
                isInDisplayedMonth: calendar.isDate(day, equalTo: displayedMonth, toGranularity: .month),
                transactions: transactionGroups[day] ?? []
            )
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                monthHeader
                monthMetrics
                weekdayHeader
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(calendarDays) { day in
                        Button {
                            selectedDay = CalendarDaySelection(date: day.date)
                            Haptics.tick()
                        } label: {
                            CalendarDayCell(
                                summary: day,
                                currencyCode: appState.selectedCurrencyCode,
                                palette: appState.themePalette
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(16)
        }
        .navigationTitle("Calendar")
        .floatBackground()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    selectedDay = CalendarDaySelection(date: calendar.startOfDay(for: Date()))
                } label: {
                    Image(systemName: "calendar.badge.plus")
                }
                .accessibilityLabel("Open today")
            }
        }
        .sheet(item: $selectedDay) { selection in
            NavigationStack {
                DailyDetailView(date: selection.date)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    private var monthHeader: some View {
        let isShowingCurrentMonth = calendar.isDate(
            displayedMonth,
            equalTo: Date(),
            toGranularity: .month
        )

        return HStack(spacing: 12) {
            Button {
                moveMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.headline.weight(.semibold))
                    .frame(width: 38, height: 38)
                    .background(.thinMaterial, in: Circle())
            }
            .accessibilityLabel("Previous month")

            VStack(alignment: .leading, spacing: 3) {
                Text(displayedMonth.formatted(.dateTime.month(.abbreviated).year()))
                    .font(.title2.weight(.bold))
                    .lineLimit(1)
                Text("\(monthTransactions.count) transactions")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .layoutPriority(1)

            Spacer()

            Button {
                displayedMonth = calendar.startOfMonth(for: Date())
            } label: {
                Text("Today")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 72, height: 38)
                    .foregroundStyle(
                        isShowingCurrentMonth
                            ? appState.themePalette.accent
                            : Color.primary
                    )
                    .background(
                        Color.primary.opacity(0.08),
                        in: Capsule()
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(
                                isShowingCurrentMonth
                                    ? appState.themePalette.accent.opacity(0.65)
                                    : Color.clear,
                                lineWidth: 1.5
                            )
                    )
            }
            .buttonStyle(.plain)

            Button {
                moveMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.headline.weight(.semibold))
                    .frame(width: 38, height: 38)
                    .background(.thinMaterial, in: Circle())
            }
            .accessibilityLabel("Next month")
        }
    }

    private var monthMetrics: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    MetricPill(
                        title: "Income",
                        amount: monthSummary.incomeMinor,
                        currencyCode: appState.selectedCurrencyCode,
                        tint: appState.themePalette.positive,
                        showsSign: true
                    )
                    MetricPill(
                        title: "Expenses",
                        amount: monthSummary.expenseMinor,
                        currencyCode: appState.selectedCurrencyCode,
                        tint: appState.themePalette.caution
                    )
                }
                HStack {
                    MetricPill(
                        title: "Net",
                        amount: monthSummary.netMinor,
                        currencyCode: appState.selectedCurrencyCode,
                        tint: monthSummary.netMinor >= 0
                            ? appState.themePalette.positive
                            : appState.themePalette.caution,
                        showsSign: true
                    )
                    MetricPill(
                        title: "Daily avg",
                        amount: monthSummary.averageDailyExpenseMinor,
                        currencyCode: appState.selectedCurrencyCode,
                        tint: appState.themePalette.accent
                    )
                }
            }
        }
    }

    private var weekdayHeader: some View {
        let symbols = calendar.shortStandaloneWeekdaySymbols
        let orderedSymbols = Array(symbols[(calendar.firstWeekday - 1)...])
            + Array(symbols[..<(calendar.firstWeekday - 1)])

        return HStack(spacing: 8) {
            ForEach(orderedSymbols, id: \.self) { symbol in
                Text(symbol.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func moveMonth(by value: Int) {
        displayedMonth = calendar.startOfMonth(
            for: calendar.date(byAdding: .month, value: value, to: displayedMonth)
                ?? displayedMonth
        )
    }
}

private struct DailyDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @Query(sort: \TransactionItem.timestamp, order: .forward) private
        var transactions: [TransactionItem]

    let date: Date

    @State private var editingTransaction: TransactionItem?
    @State private var initialTimestamp: Date?
    @State private var isEntrySheetPresented = false

    private let calendar = Calendar.current

    private var dayTransactions: [TransactionItem] {
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        return transactions
            .filter { start <= $0.timestamp && $0.timestamp < end }
            .sorted { $0.timestamp > $1.timestamp }
    }

    private var summary: CalendarPeriodSummary {
        CalendarPeriodSummary(transactions: dayTransactions)
    }

    private var categoryBreakdown: [CalendarAmountBreakdown] {
        let grouped = Dictionary(grouping: dayTransactions.filter(\.isExpense)) {
            $0.categoryName
        }
        return grouped.map { name, items in
            let first = items.first
            return CalendarAmountBreakdown(
                title: name,
                amountMinor: items.reduce(Int64(0)) { $0 + $1.amountMinor },
                color: Color(hex: first?.categoryColorHex ?? "#5A6B6B")
            )
        }
        .sorted { $0.amountMinor > $1.amountMinor }
    }

    private var accountBreakdown: [CalendarAmountBreakdown] {
        let grouped = Dictionary(grouping: dayTransactions) { $0.accountName }
        return grouped.map { name, items in
            CalendarAmountBreakdown(
                title: name,
                amountMinor: items.reduce(Int64(0)) { $0 + $1.amountMinor },
                color: appState.themePalette.accent
            )
        }
        .sorted { $0.amountMinor > $1.amountMinor }
    }

    private var hourlyBreakdown: [CalendarHourlyBreakdown] {
        let grouped = Dictionary(grouping: dayTransactions) {
            calendar.component(.hour, from: $0.timestamp)
        }
        return grouped.map { hour, items in
            CalendarHourlyBreakdown(
                hour: hour,
                incomeMinor: items.filter { !$0.isExpense }.reduce(Int64(0)) { $0 + $1.amountMinor },
                expenseMinor: items.filter(\.isExpense).reduce(Int64(0)) { $0 + $1.amountMinor }
            )
        }
        .sorted { $0.hour < $1.hour }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                headerCard
                metricGrid
                transactionSection
                graphSection
                breakdownSection(title: "Category breakdown", rows: categoryBreakdown)
                breakdownSection(title: "Account breakdown", rows: accountBreakdown)
            }
            .padding(16)
        }
        .navigationTitle(date.formatted(date: .abbreviated, time: .omitted))
        .navigationBarTitleDisplayMode(.inline)
        .floatBackground()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    presentNewTransaction()
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add transaction")
            }
        }
        .sheet(isPresented: $isEntrySheetPresented) {
            QuickAddKeypadSheet(
                transactionToEdit: editingTransaction,
                initialTimestamp: initialTimestamp
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    private var headerCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(date.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                            .font(.headline)
                        Text("\(dayTransactions.count) transactions")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(
                        MoneyFormatter.string(
                            minorUnits: summary.netMinor,
                            currencyCode: appState.selectedCurrencyCode,
                            showsSign: true
                        )
                    )
                    .moneyStyle(size: 24, weight: .bold)
                    .foregroundStyle(summary.netMinor >= 0 ? appState.themePalette.positive : appState.themePalette.caution)
                }

                HStack(spacing: 10) {
                    Label(summary.topCategoryTitle, systemImage: "tag.fill")
                    Spacer()
                    Label(summary.largestTransactionTitle, systemImage: "arrow.up.right.circle.fill")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
    }

    private var metricGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            MetricPill(
                title: "Income",
                amount: summary.incomeMinor,
                currencyCode: appState.selectedCurrencyCode,
                tint: appState.themePalette.positive,
                showsSign: true
            )
            MetricPill(
                title: "Expenses",
                amount: summary.expenseMinor,
                currencyCode: appState.selectedCurrencyCode,
                tint: appState.themePalette.caution
            )
            MetricPill(
                title: "Average",
                amount: summary.averageTransactionMinor,
                currencyCode: appState.selectedCurrencyCode,
                tint: appState.themePalette.accent
            )
            MetricPill(
                title: "Largest",
                amount: summary.largestTransactionMinor,
                currencyCode: appState.selectedCurrencyCode,
                tint: appState.themePalette.accent
            )
        }
    }

    private var transactionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(
                title: "Transactions",
                actionTitle: "Add",
                action: presentNewTransaction
            )

            if dayTransactions.isEmpty {
                GlassCard {
                    EmptyStateView(
                        icon: "calendar.badge.plus",
                        title: "No transactions",
                        message: "Add income or spending for this day."
                    )
                }
            } else {
                GlassCard {
                    VStack(spacing: 0) {
                        ForEach(dayTransactions) { transaction in
                            Button {
                                presentEditTransaction(transaction)
                            } label: {
                                TransactionRowView(
                                    transaction: transaction,
                                    currencyCode: appState.selectedCurrencyCode
                                )
                            }
                            .buttonStyle(.plain)
                            .swipeActions {
                                Button(role: .destructive) {
                                    delete(transaction)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }

                            if transaction.id != dayTransactions.last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
    }

    private var graphSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Graphs")
            flowChart
            categoryChart
            hourlyChart
        }
    }

    private var flowChart: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Income vs expenses")
                    .font(.subheadline.weight(.semibold))
                Chart {
                    BarMark(
                        x: .value("Type", "Income"),
                        y: .value("Amount", summary.incomeMinor)
                    )
                    .foregroundStyle(appState.themePalette.positive)

                    BarMark(
                        x: .value("Type", "Expenses"),
                        y: .value("Amount", summary.expenseMinor)
                    )
                    .foregroundStyle(appState.themePalette.caution)
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3))
                }
                .frame(height: 170)
            }
        }
    }

    @ViewBuilder
    private var categoryChart: some View {
        if !categoryBreakdown.isEmpty {
            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Expense mix")
                        .font(.subheadline.weight(.semibold))
                    Chart(categoryBreakdown) { item in
                        SectorMark(
                            angle: .value("Amount", item.amountMinor),
                            innerRadius: .ratio(0.62),
                            angularInset: 2
                        )
                        .foregroundStyle(by: .value("Category", item.title))
                        .cornerRadius(6)
                    }
                    .chartForegroundStyleScale(
                        domain: categoryBreakdown.map(\.title),
                        range: categoryBreakdown.map(\.color)
                    )
                    .chartLegend(position: .bottom, alignment: .leading)
                    .frame(height: 230)

                    VStack(spacing: 8) {
                        ForEach(categoryBreakdown.prefix(5)) { item in
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(item.color)
                                    .frame(width: 9, height: 9)
                                Text(item.title)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                                Spacer()
                                Text(
                                    MoneyFormatter.string(
                                        minorUnits: item.amountMinor,
                                        currencyCode: appState.selectedCurrencyCode
                                    )
                                )
                                .font(.caption.monospacedDigit().weight(.semibold))
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var hourlyChart: some View {
        if !hourlyBreakdown.isEmpty {
            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Time of day")
                        .font(.subheadline.weight(.semibold))
                    Chart {
                        ForEach(hourlyBreakdown) { item in
                            BarMark(
                                x: .value("Hour", item.date(on: date), unit: .hour),
                                y: .value("Expenses", item.expenseMinor)
                            )
                            .foregroundStyle(appState.themePalette.caution.opacity(0.78))

                            BarMark(
                                x: .value("Hour", item.date(on: date), unit: .hour),
                                y: .value("Income", item.incomeMinor)
                            )
                            .foregroundStyle(appState.themePalette.positive.opacity(0.78))
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 4))
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading, values: .automatic(desiredCount: 3))
                    }
                    .frame(height: 180)
                }
            }
        }
    }

    @ViewBuilder
    private func breakdownSection(title: String, rows: [CalendarAmountBreakdown]) -> some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: title)
                GlassCard {
                    VStack(spacing: 12) {
                        ForEach(rows) { row in
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(row.color)
                                    .frame(width: 9, height: 9)
                                Text(row.title)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                Spacer()
                                Text(
                                    MoneyFormatter.string(
                                        minorUnits: row.amountMinor,
                                        currencyCode: appState.selectedCurrencyCode
                                    )
                                )
                                .moneyStyle(size: 14, weight: .semibold)
                            }
                        }
                    }
                }
            }
        }
    }

    private func presentNewTransaction() {
        editingTransaction = nil
        initialTimestamp = calendar.timestamp(on: date, matchingTimeFrom: Date())
        isEntrySheetPresented = true
    }

    private func presentEditTransaction(_ transaction: TransactionItem) {
        editingTransaction = transaction
        initialTimestamp = nil
        isEntrySheetPresented = true
    }

    private func delete(_ transaction: TransactionItem) {
        try? TransactionRepository(modelContext: modelContext).delete(transaction)
        Haptics.tick()
    }
}

private struct CalendarDayCell: View {
    let summary: CalendarDaySummary
    let currencyCode: String
    let palette: FloatThemePalette

    private var netColor: Color {
        if summary.transactions.isEmpty { return .secondary }
        return summary.netMinor >= 0 ? palette.positive : palette.caution
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(summary.date.formatted(.dateTime.day()))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(summary.isInDisplayedMonth ? .primary : .tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            if summary.transactions.isEmpty {
                Capsule()
                    .fill(Color.primary.opacity(0.08))
                    .frame(height: 4)
            } else {
                VStack(spacing: 5) {
                    Text("\(summary.transactions.count)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(netColor, in: Circle())

                    Text(
                        MoneyFormatter.string(
                            minorUnits: abs(summary.netMinor),
                            currencyCode: currencyCode
                        )
                    )
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(netColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    HStack(spacing: 3) {
                        if summary.incomeMinor > 0 {
                            Capsule()
                                .fill(palette.positive)
                                .frame(height: 4)
                        }
                        if summary.expenseMinor > 0 {
                            Capsule()
                                .fill(palette.caution)
                                .frame(height: 4)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(8)
        .frame(height: 78)
        .frame(maxWidth: .infinity)
        .background(
            summary.isToday
                ? palette.accent.opacity(0.16)
                : Color.primary.opacity(summary.isInDisplayedMonth ? 0.055 : 0.025),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    summary.isToday ? palette.accent.opacity(0.45) : Color.primary.opacity(0.06),
                    lineWidth: 1
                )
        )
    }
}

private struct MetricPill: View {
    let title: String
    let amount: Int64
    let currencyCode: String
    let tint: Color
    var showsSign = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(
                MoneyFormatter.string(
                    minorUnits: amount,
                    currencyCode: currencyCode,
                    showsSign: showsSign
                )
            )
            .moneyStyle(size: 17, weight: .bold)
            .foregroundStyle(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct CalendarDaySelection: Identifiable {
    let date: Date
    var id: Date { date }
}

private struct CalendarDaySummary: Identifiable {
    let date: Date
    let isInDisplayedMonth: Bool
    let transactions: [TransactionItem]

    var id: Date { date }
    var incomeMinor: Int64 {
        transactions.filter { !$0.isExpense }.reduce(0) { $0 + $1.amountMinor }
    }
    var expenseMinor: Int64 {
        transactions.filter(\.isExpense).reduce(0) { $0 + $1.amountMinor }
    }
    var netMinor: Int64 { incomeMinor - expenseMinor }
    var isToday: Bool { Calendar.current.isDateInToday(date) }
}

private struct CalendarPeriodSummary {
    let transactions: [TransactionItem]

    var incomeMinor: Int64 {
        transactions.filter { !$0.isExpense }.reduce(0) { $0 + $1.amountMinor }
    }

    var expenseMinor: Int64 {
        transactions.filter(\.isExpense).reduce(0) { $0 + $1.amountMinor }
    }

    var netMinor: Int64 { incomeMinor - expenseMinor }

    var averageTransactionMinor: Int64 {
        guard !transactions.isEmpty else { return 0 }
        let total = transactions.reduce(Int64(0)) { $0 + $1.amountMinor }
        return total / Int64(transactions.count)
    }

    var averageDailyExpenseMinor: Int64 {
        let activeDays = Set(transactions.map { Calendar.current.startOfDay(for: $0.timestamp) }).count
        guard activeDays > 0 else { return 0 }
        return expenseMinor / Int64(activeDays)
    }

    var largestTransactionMinor: Int64 {
        transactions.map(\.amountMinor).max() ?? 0
    }

    var largestTransactionTitle: String {
        transactions.max { $0.amountMinor < $1.amountMinor }?.categoryName ?? "No largest yet"
    }

    var topCategoryTitle: String {
        let grouped = Dictionary(grouping: transactions.filter(\.isExpense)) {
            $0.categoryName
        }
        return grouped
            .map { ($0.key, $0.value.reduce(Int64(0)) { $0 + $1.amountMinor }) }
            .max { $0.1 < $1.1 }?
            .0 ?? "No category yet"
    }
}

private struct CalendarAmountBreakdown: Identifiable {
    let id = UUID()
    let title: String
    let amountMinor: Int64
    let color: Color
}

private struct CalendarHourlyBreakdown: Identifiable {
    let hour: Int
    let incomeMinor: Int64
    let expenseMinor: Int64

    var id: Int { hour }

    func date(on day: Date) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: day)
            ?? day
    }
}

private extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        self.date(from: dateComponents([.year, .month], from: date))
            ?? startOfDay(for: date)
    }

    func timestamp(on day: Date, matchingTimeFrom timeSource: Date) -> Date {
        let time = dateComponents([.hour, .minute, .second], from: timeSource)
        return date(
            bySettingHour: time.hour ?? 12,
            minute: time.minute ?? 0,
            second: time.second ?? 0,
            of: startOfDay(for: day)
        ) ?? startOfDay(for: day)
    }
}
