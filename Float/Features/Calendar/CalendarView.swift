import Charts
import SwiftData
import SwiftUI

struct CalendarView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @Query private var goals: [GoalItem]
    @Query private var recurringRules: [RecurringRuleItem]
    @Query private var budgetPeriods: [BudgetPeriodItem]

    @State private var displayedMonth = Calendar.current.startOfMonth(for: Date())
    @State private var monthSnapshot = CalendarMonthSnapshot.empty
    @State private var selectedDay: CalendarDaySelection?
    @State private var highlightedDay: Date?
    @State private var jumpMonth = Date()
    @State private var showingMonthPicker = false

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 7)

    private var activeBudget: BudgetPeriodItem? {
        budgetPeriods.first { $0.isActive }
    }

    private var safeToSpend: SafeToSpendResult {
        monthSnapshot.safeToSpend
    }

    private var monthTransactions: [TransactionItem] {
        monthSnapshot.monthTransactions
    }

    private var monthTransfers: [TransferItem] {
        monthSnapshot.monthTransfers
    }

    private var monthSummary: CalendarPeriodSummary {
        CalendarPeriodSummary(transactions: monthTransactions)
    }

    private var monthRecurringProjections: [CalendarRecurringProjection] {
        guard let interval = calendar.dateInterval(of: .month, for: displayedMonth) else {
            return []
        }
        return recurringProjections(in: interval)
    }

    private var transactionGroups: [Date: [TransactionItem]] {
        Dictionary(grouping: monthSnapshot.gridTransactions) {
            calendar.startOfDay(for: $0.timestamp)
        }
    }

    private var transferGroups: [Date: [TransferItem]] {
        Dictionary(grouping: monthSnapshot.gridTransfers) {
            calendar.startOfDay(for: $0.timestamp)
        }
    }

    private var recurringProjectionGroups: [Date: [CalendarRecurringProjection]] {
        Dictionary(grouping: monthRecurringProjections) {
            calendar.startOfDay(for: $0.date)
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
                transactions: transactionGroups[day] ?? [],
                transfers: transferGroups[day] ?? [],
                projectedRecurring: recurringProjectionGroups[day] ?? [],
                dailyAllowanceMinor: safeToSpend.dailyAllowanceMinor,
                selected: highlightedDay.map { calendar.isDate($0, inSameDayAs: day) } ?? false
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
                            highlightedDay = day.date
                            selectedDay = CalendarDaySelection(date: day.date)
                            Haptics.tick()
                        } label: {
                            CalendarDayCell(
                                summary: day,
                                palette: appState.themePalette
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(16)
        }
        .gesture(
            DragGesture(minimumDistance: 36)
                .onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height) else {
                        return
                    }
                    moveMonth(by: value.translation.width < 0 ? 1 : -1)
                }
        )
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
                DailyDetailView(initialDate: selection.date)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingMonthPicker) {
            NavigationStack {
                DatePicker(
                    "Month",
                    selection: $jumpMonth,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .padding()
                .navigationTitle("Jump to month")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showingMonthPicker = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            displayedMonth = calendar.startOfMonth(for: jumpMonth)
                            showingMonthPicker = false
                        }
                    }
                }
            }
        }
        .task(id: monthLoadKey) {
            loadMonthSnapshot()
        }
        .onChange(of: selectedDay?.date) { _, date in
            if date == nil {
                loadMonthSnapshot()
            }
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
                    .floatGlassCircle(
                        tint: appState.themePalette.accent,
                        interactive: true,
                        strokeOpacity: 0.08
                    )
            }
            .accessibilityLabel("Previous month")

            VStack(alignment: .leading, spacing: 3) {
                Button {
                    jumpMonth = displayedMonth
                    showingMonthPicker = true
                } label: {
                    HStack(spacing: 6) {
                        Text(displayedMonth.formatted(.dateTime.month(.abbreviated).year()))
                            .font(.title2.weight(.bold))
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                Text("\(monthTransactions.count) transactions, \(monthTransfers.count) transfers")
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
                    .floatGlassSurface(
                        cornerRadius: FloatTheme.controlRadius,
                        tint: appState.themePalette.accent,
                        interactive: true,
                        strokeOpacity: isShowingCurrentMonth ? 0.14 : 0.06
                    )
            }
            .buttonStyle(.plain)

            Button {
                moveMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.headline.weight(.semibold))
                    .frame(width: 38, height: 38)
                    .floatGlassCircle(
                        tint: appState.themePalette.accent,
                        interactive: true,
                        strokeOpacity: 0.08
                    )
            }
            .accessibilityLabel("Next month")
        }
    }

    private var monthMetrics: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                MetricPill(
                    title: "Income",
                    amount: monthSummary.incomeMinor,
                    currencyCode: appState.selectedCurrencyCode,
                    tint: appState.themePalette.positive,
                    showsSign: true,
                    isCompact: true
                )
                MetricPill(
                    title: "Expenses",
                    amount: monthSummary.expenseMinor,
                    currencyCode: appState.selectedCurrencyCode,
                    tint: appState.themePalette.caution,
                    isCompact: true
                )
                MetricPill(
                    title: "Net",
                    amount: monthSummary.netMinor,
                    currencyCode: appState.selectedCurrencyCode,
                    tint: monthSummary.netMinor >= 0
                        ? appState.themePalette.positive
                        : appState.themePalette.caution,
                    showsSign: true,
                    isCompact: true
                )
                MetricPill(
                    title: "Daily avg",
                    amount: monthSummary.averageDailyExpenseMinor,
                    currencyCode: appState.selectedCurrencyCode,
                    tint: appState.themePalette.accent,
                    isCompact: true
                )
                MetricPill(
                    title: "Safe left",
                    amount: safeToSpend.safeToSpendMinor,
                    currencyCode: appState.selectedCurrencyCode,
                    tint: appState.themePalette.positive,
                    isCompact: true
                )
                MetricPill(
                    title: "Projected",
                    amount: monthRecurringProjections
                        .filter(\.isExpense)
                        .reduce(Int64(0)) { $0 + $1.amountMinor },
                    currencyCode: appState.selectedCurrencyCode,
                    tint: appState.themePalette.caution,
                    isCompact: true
                )
            }
            .padding(.horizontal, 1)
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

    private func recurringProjections(in interval: DateInterval) -> [CalendarRecurringProjection] {
        recurringRules.flatMap { rule in
            CalendarRecurringProjection.dueDates(
                for: rule,
                from: interval.start,
                through: calendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end,
                transactions: monthSnapshot.gridTransactions,
                calendar: calendar
            )
        }
    }

    private var monthLoadKey: CalendarMonthLoadKey {
        CalendarMonthLoadKey(
            displayedMonth: displayedMonth,
            budgetID: activeBudget?.id,
            budgetUpdatedAt: activeBudget?.updatedAt,
            goalUpdatedAt: goals.map(\.updatedAt).max(),
            recurringUpdatedAt: recurringRules.map(\.updatedAt).max()
        )
    }

    private func loadMonthSnapshot() {
        monthSnapshot = fetchMonthSnapshot()
    }

    private func fetchMonthSnapshot() -> CalendarMonthSnapshot {
        guard
            let monthInterval = calendar.dateInterval(of: .month, for: displayedMonth),
            let gridInterval = visibleGridInterval(for: monthInterval)
        else {
            return .empty
        }

        do {
            let gridEnd = calendar.date(
                byAdding: .second,
                value: -1,
                to: gridInterval.end
            ) ?? gridInterval.end
            let monthEnd = calendar.date(
                byAdding: .second,
                value: -1,
                to: monthInterval.end
            ) ?? monthInterval.end
            let gridTransactions = try fetchTransactions(from: gridInterval.start, through: gridEnd)
            let gridTransfers = try fetchTransfers(from: gridInterval.start, through: gridEnd)
            let monthTransactions = gridTransactions.filter {
                monthInterval.start <= $0.timestamp && $0.timestamp < monthInterval.end
            }
            let monthTransfers = gridTransfers.filter {
                monthInterval.start <= $0.timestamp && $0.timestamp < monthInterval.end
            }
            let safeTransactions = try fetchSafeToSpendTransactions(through: monthEnd)
            let safeToSpend = SafeToSpendUseCase.calculate(
                budget: activeBudget,
                transactions: safeTransactions,
                goals: goals,
                recurringRules: recurringRules,
                calendar: calendar
            )
            return CalendarMonthSnapshot(
                gridTransactions: gridTransactions,
                gridTransfers: gridTransfers,
                monthTransactions: monthTransactions,
                monthTransfers: monthTransfers,
                safeToSpend: safeToSpend
            )
        } catch {
            return .empty
        }
    }

    private func visibleGridInterval(for monthInterval: DateInterval) -> DateInterval? {
        let weekdayOffset = (
            calendar.component(.weekday, from: monthInterval.start) - calendar.firstWeekday + 7
        ) % 7
        let gridStart = calendar.date(
            byAdding: .day,
            value: -weekdayOffset,
            to: monthInterval.start
        ) ?? monthInterval.start
        guard let gridEnd = calendar.date(byAdding: .day, value: 42, to: gridStart) else {
            return nil
        }
        return DateInterval(start: gridStart, end: gridEnd)
    }

    private func fetchTransactions(from start: Date, through end: Date) throws
        -> [TransactionItem]
    {
        let descriptor = FetchDescriptor<TransactionItem>(
            predicate: #Predicate<TransactionItem> { transaction in
                transaction.timestamp >= start && transaction.timestamp <= end
            },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    private func fetchTransfers(from start: Date, through end: Date) throws
        -> [TransferItem]
    {
        let descriptor = FetchDescriptor<TransferItem>(
            predicate: #Predicate<TransferItem> { transfer in
                transfer.timestamp >= start && transfer.timestamp <= end
            },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    private func fetchSafeToSpendTransactions(through end: Date) throws -> [TransactionItem] {
        let period = BudgetPeriodCalculator.currentPeriod(
            for: activeBudget,
            now: Date(),
            calendar: calendar
        )
        let start = period.start
        let effectiveEnd = min(end, calendar.endOfDay(for: period.end))
        let descriptor = FetchDescriptor<TransactionItem>(
            predicate: #Predicate<TransactionItem> { transaction in
                transaction.timestamp >= start && transaction.timestamp <= effectiveEnd
            }
        )
        return try modelContext.fetch(descriptor)
    }
}

private struct CalendarMonthLoadKey: Equatable {
    let displayedMonth: Date
    let budgetID: UUID?
    let budgetUpdatedAt: Date?
    let goalUpdatedAt: Date?
    let recurringUpdatedAt: Date?
}

private struct CalendarDayLoadKey: Equatable {
    let selectedDate: Date
    let budgetID: UUID?
    let budgetUpdatedAt: Date?
    let goalUpdatedAt: Date?
    let recurringUpdatedAt: Date?
}

private struct CalendarMonthSnapshot {
    let gridTransactions: [TransactionItem]
    let gridTransfers: [TransferItem]
    let monthTransactions: [TransactionItem]
    let monthTransfers: [TransferItem]
    let safeToSpend: SafeToSpendResult

    static var empty: CalendarMonthSnapshot {
        CalendarMonthSnapshot(
            gridTransactions: [],
            gridTransfers: [],
            monthTransactions: [],
            monthTransfers: [],
            safeToSpend: .empty
        )
    }
}

private struct CalendarDaySnapshot {
    let transactions: [TransactionItem]
    let transfers: [TransferItem]
    let safeToSpend: SafeToSpendResult

    static var empty: CalendarDaySnapshot {
        CalendarDaySnapshot(
            transactions: [],
            transfers: [],
            safeToSpend: .empty
        )
    }
}

private struct DailyDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @Query(sort: \CategoryItem.sortOrder) private var categories: [CategoryItem]
    @Query(sort: \AccountItem.createdAt) private var accounts: [AccountItem]
    @Query private var goals: [GoalItem]
    @Query private var recurringRules: [RecurringRuleItem]
    @Query private var budgetPeriods: [BudgetPeriodItem]

    let initialDate: Date

    @State private var editingTransaction: TransactionItem?
    @State private var editingTransfer: TransferItem?
    @State private var initialTimestamp: Date?
    @State private var initialTransferTimestamp: Date?
    @State private var isEntrySheetPresented = false
    @State private var isTransferSheetPresented = false
    @State private var selectedDate: Date
    @State private var deletedSnapshot: CalendarDeletedTransactionSnapshot?
    @State private var showingUndo = false
    @State private var daySnapshot = CalendarDaySnapshot.empty

    private let calendar = Calendar.current

    init(initialDate: Date) {
        self.initialDate = initialDate
        _selectedDate = State(initialValue: Calendar.current.startOfDay(for: initialDate))
    }

    private var activeBudget: BudgetPeriodItem? {
        budgetPeriods.first { $0.isActive }
    }

    private var safeToSpend: SafeToSpendResult {
        daySnapshot.safeToSpend
    }

    private var dayTransactions: [TransactionItem] {
        daySnapshot.transactions
    }

    private var dayTransfers: [TransferItem] {
        daySnapshot.transfers
    }

    private var summary: CalendarPeriodSummary {
        CalendarPeriodSummary(transactions: dayTransactions)
    }

    private var projectedRecurring: [CalendarRecurringProjection] {
        CalendarRecurringProjection.dueDates(
            for: recurringRules,
            on: selectedDate,
            transactions: dayTransactions,
            calendar: calendar
        )
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
                budgetPaceCard
                transactionSection
                transferSection
                projectedRecurringSection
                graphSection
                breakdownSection(title: "Category breakdown", rows: categoryBreakdown)
                breakdownSection(title: "Account breakdown", rows: accountBreakdown)
            }
            .padding(16)
        }
        .navigationTitle(selectedDate.formatted(date: .abbreviated, time: .omitted))
        .navigationBarTitleDisplayMode(.inline)
        .floatBackground()
        .overlay(alignment: .bottom) {
            if showingUndo, deletedSnapshot != nil {
                undoBar
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    moveDay(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .accessibilityLabel("Previous day")

                Button {
                    moveDay(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .accessibilityLabel("Next day")
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
        .sheet(isPresented: $isTransferSheetPresented) {
            TransferEditorSheet(
                transferToEdit: editingTransfer,
                initialTimestamp: initialTransferTimestamp
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .task(id: dayLoadKey) {
            loadDaySnapshot()
        }
        .onChange(of: isEntrySheetPresented) { _, isPresented in
            if !isPresented {
                editingTransaction = nil
                initialTimestamp = nil
                loadDaySnapshot()
            }
        }
        .onChange(of: isTransferSheetPresented) { _, isPresented in
            if !isPresented {
                editingTransfer = nil
                initialTransferTimestamp = nil
                loadDaySnapshot()
            }
        }
    }

    private var headerCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(selectedDate.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                            .font(.headline)
                        Text("\(dayTransactions.count) transactions, \(dayTransfers.count) transfers, \(projectedRecurring.count) projected")
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

    private var budgetPaceCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Budget pace", systemImage: summary.expenseMinor > safeToSpend.dailyAllowanceMinor ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(summary.expenseMinor > safeToSpend.dailyAllowanceMinor ? appState.themePalette.caution : appState.themePalette.positive)
                    Spacer()
                    Text(
                        MoneyFormatter.string(
                            minorUnits: safeToSpend.dailyAllowanceMinor,
                            currencyCode: appState.selectedCurrencyCode
                        )
                    )
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
                }
                ProgressView(
                    value: Double(summary.expenseMinor),
                    total: Double(max(safeToSpend.dailyAllowanceMinor, summary.expenseMinor, 1))
                )
                .tint(summary.expenseMinor > safeToSpend.dailyAllowanceMinor ? appState.themePalette.caution : appState.themePalette.positive)
                Text(summary.expenseMinor > safeToSpend.dailyAllowanceMinor ? "This day is above the current daily allowance." : "This day is inside the current daily allowance.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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
                                Button {
                                    copy(transaction)
                                } label: {
                                    Label("Copy", systemImage: "doc.on.doc")
                                }
                                .tint(appState.themePalette.accent)
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

    private var transferSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(
                title: "Transfers",
                actionTitle: "Add",
                action: presentNewTransfer
            )

            if dayTransfers.isEmpty {
                GlassCard {
                    EmptyStateView(
                        icon: "arrow.left.arrow.right.circle",
                        title: "No transfers",
                        message: "Move money between accounts for this day."
                    )
                }
            } else {
                GlassCard {
                    VStack(spacing: 0) {
                        ForEach(dayTransfers) { transfer in
                            Button {
                                presentEditTransfer(transfer)
                            } label: {
                                TransferRowView(
                                    transfer: transfer,
                                    currencyCode: transfer.currencyCode
                                )
                            }
                            .buttonStyle(.plain)
                            .swipeActions {
                                Button(role: .destructive) {
                                    delete(transfer)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }

                            if transfer.id != dayTransfers.last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var projectedRecurringSection: some View {
        if !projectedRecurring.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Projected recurring")
                GlassCard {
                    VStack(spacing: 0) {
                        ForEach(projectedRecurring) { projection in
                            HStack(spacing: 12) {
                                Image(systemName: projection.icon)
                                    .foregroundStyle(projection.color)
                                    .frame(width: 34, height: 34)
                                    .background(projection.color.opacity(0.14), in: Circle())
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(projection.title)
                                        .font(.subheadline.weight(.semibold))
                                    Text(projection.rule.cadence.title)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(
                                    MoneyFormatter.string(
                                        minorUnits: projection.amountMinor,
                                        currencyCode: appState.selectedCurrencyCode,
                                        showsSign: !projection.isExpense
                                    )
                                )
                                .moneyStyle(size: 14, weight: .semibold)
                                Button {
                                    materialize(projection)
                                } label: {
                                    Image(systemName: "plus.circle.fill")
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(appState.themePalette.accent)
                            }
                            .padding(.vertical, 8)

                            if projection.id != projectedRecurring.last?.id {
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
                                x: .value("Hour", item.date(on: selectedDate), unit: .hour),
                                y: .value("Expenses", item.expenseMinor)
                            )
                            .foregroundStyle(appState.themePalette.caution.opacity(0.78))

                            BarMark(
                                x: .value("Hour", item.date(on: selectedDate), unit: .hour),
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
        initialTimestamp = calendar.timestamp(on: selectedDate, matchingTimeFrom: Date())
        isEntrySheetPresented = true
    }

    private func presentNewTransfer() {
        editingTransfer = nil
        initialTransferTimestamp = calendar.timestamp(on: selectedDate, matchingTimeFrom: Date())
        isTransferSheetPresented = true
    }

    private func presentEditTransaction(_ transaction: TransactionItem) {
        editingTransaction = transaction
        initialTimestamp = nil
        isEntrySheetPresented = true
    }

    private func presentEditTransfer(_ transfer: TransferItem) {
        editingTransfer = transfer
        initialTransferTimestamp = nil
        isTransferSheetPresented = true
    }

    private func delete(_ transaction: TransactionItem) {
        deletedSnapshot = CalendarDeletedTransactionSnapshot(transaction: transaction)
        try? TransactionRepository(modelContext: modelContext).delete(transaction)
        loadDaySnapshot()
        withAnimation { showingUndo = true }
        Haptics.tick()
    }

    private func delete(_ transfer: TransferItem) {
        try? TransferRepository(modelContext: modelContext).delete(transfer)
        loadDaySnapshot()
        Haptics.tick()
    }

    private func undoDelete() {
        guard let deletedSnapshot else { return }
        modelContext.insert(
            deletedSnapshot.makeTransaction(
                categories: categories,
                accounts: accounts,
                recurringRules: recurringRules
            )
        )
        try? modelContext.save()
        loadDaySnapshot()
        withAnimation { showingUndo = false }
        self.deletedSnapshot = nil
        Haptics.confirm()
    }

    private var undoBar: some View {
        HStack(spacing: 12) {
            Text("Transaction deleted")
                .font(.subheadline.weight(.medium))
            Spacer()
            Button("Undo", action: undoDelete)
                .font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
        .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
    }

    private func copy(_ transaction: TransactionItem) {
        let copied = TransactionItem(
            amountMinor: transaction.amountMinor,
            isExpense: transaction.isExpense,
            timestamp: calendar.timestamp(on: selectedDate, matchingTimeFrom: transaction.timestamp),
            category: transaction.category,
            account: transaction.account,
            note: transaction.note
        )
        modelContext.insert(copied)
        try? modelContext.save()
        loadDaySnapshot()
        Haptics.confirm()
    }

    private func materialize(_ projection: CalendarRecurringProjection) {
        let category = projection.rule.category ?? DefaultCategoryResolver.resolve(
            isExpense: projection.rule.isExpense,
            preferredID: appState.lastUsedCategoryID,
            categories: categories,
            modelContext: modelContext
        )
        let account = projection.rule.account ?? DefaultAccountResolver.resolve(
            preferredID: appState.lastUsedAccountID,
            accounts: accounts,
            modelContext: modelContext,
            currencyCode: appState.selectedCurrencyCode
        )
        let transaction = TransactionItem(
            amountMinor: projection.rule.amountMinor,
            isExpense: projection.rule.isExpense,
            timestamp: projection.date,
            category: category,
            account: account,
            note: projection.rule.note,
            recurringRule: projection.rule
        )
        modelContext.insert(transaction)
        try? modelContext.save()
        loadDaySnapshot()
        Haptics.confirm()
    }

    private func moveDay(by value: Int) {
        selectedDate = calendar.startOfDay(
            for: calendar.date(byAdding: .day, value: value, to: selectedDate)
                ?? selectedDate
        )
        Haptics.tick()
    }

    private var dayLoadKey: CalendarDayLoadKey {
        CalendarDayLoadKey(
            selectedDate: selectedDate,
            budgetID: activeBudget?.id,
            budgetUpdatedAt: activeBudget?.updatedAt,
            goalUpdatedAt: goals.map(\.updatedAt).max(),
            recurringUpdatedAt: recurringRules.map(\.updatedAt).max()
        )
    }

    private func loadDaySnapshot() {
        daySnapshot = fetchDaySnapshot()
    }

    private func fetchDaySnapshot() -> CalendarDaySnapshot {
        let start = calendar.startOfDay(for: selectedDate)
        let end = calendar.endOfDay(for: selectedDate)

        do {
            let transactions = try fetchTransactions(from: start, through: end)
            let transfers = try fetchTransfers(from: start, through: end)
            let safeTransactions = try fetchSafeToSpendTransactions(through: end)
            let safeToSpend = SafeToSpendUseCase.calculate(
                budget: activeBudget,
                transactions: safeTransactions,
                goals: goals,
                recurringRules: recurringRules,
                now: selectedDate,
                calendar: calendar
            )
            return CalendarDaySnapshot(
                transactions: transactions,
                transfers: transfers,
                safeToSpend: safeToSpend
            )
        } catch {
            return .empty
        }
    }

    private func fetchTransactions(from start: Date, through end: Date) throws
        -> [TransactionItem]
    {
        let descriptor = FetchDescriptor<TransactionItem>(
            predicate: #Predicate<TransactionItem> { transaction in
                transaction.timestamp >= start && transaction.timestamp <= end
            },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    private func fetchTransfers(from start: Date, through end: Date) throws
        -> [TransferItem]
    {
        let descriptor = FetchDescriptor<TransferItem>(
            predicate: #Predicate<TransferItem> { transfer in
                transfer.timestamp >= start && transfer.timestamp <= end
            },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    private func fetchSafeToSpendTransactions(through end: Date) throws -> [TransactionItem] {
        let period = BudgetPeriodCalculator.currentPeriod(
            for: activeBudget,
            now: selectedDate,
            calendar: calendar
        )
        let start = period.start
        let effectiveEnd = min(end, calendar.endOfDay(for: period.end))
        let descriptor = FetchDescriptor<TransactionItem>(
            predicate: #Predicate<TransactionItem> { transaction in
                transaction.timestamp >= start && transaction.timestamp <= effectiveEnd
            }
        )
        return try modelContext.fetch(descriptor)
    }
}

private struct CalendarDayCell: View {
    let summary: CalendarDaySummary
    let palette: FloatThemePalette

    private let elementRadius = FloatTheme.tileRadius

    private var activityColor: Color {
        if !summary.hasActivity {
            return .secondary
        }
        return summary.netMinor >= 0 ? palette.positive : palette.caution
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Text(summary.date.formatted(.dateTime.day()))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(summary.isInDisplayedMonth ? .primary : .tertiary)
                Spacer(minLength: 0)
                if summary.isOverDailyAllowance {
                    Circle()
                        .fill(palette.caution)
                        .frame(width: 6, height: 6)
                        .accessibilityLabel("Over daily allowance")
                }
            }

            Spacer(minLength: 0)

            if summary.hasActivity {
                HStack(spacing: 3) {
                    Spacer(minLength: 0)
                    Text(summary.cappedActivityLabel)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: 18, height: 18)
                        .background(activityColor, in: Circle())
                    if summary.hasRecurringProjection {
                        Image(systemName: "repeat")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 10, height: 18)
                    }
                    Spacer(minLength: 0)
                }
            }

            Spacer(minLength: 0)
            activityBars
        }
        .padding(7)
        .frame(height: 66)
        .frame(maxWidth: .infinity)
        .background(
            cellBackground,
            in: RoundedRectangle(cornerRadius: elementRadius, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: elementRadius, style: .continuous)
                .strokeBorder(
                    cellBorder,
                    lineWidth: summary.selected ? 1.8 : 1
                )
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var activityBars: some View {
        GeometryReader { proxy in
            let availableWidth = proxy.size.width
            let hasIncomeAndExpense = summary.incomeMinor > 0 && summary.expenseMinor > 0
            let barWidth = max(0, availableWidth - (hasIncomeAndExpense ? 2 : 0))
            let totalMinor = max(summary.incomeMinor + summary.expenseMinor, 1)
            let incomeWidth = summary.incomeMinor > 0
                ? max(5, barWidth * CGFloat(summary.incomeMinor) / CGFloat(totalMinor))
                : 0
            let expenseWidth = summary.expenseMinor > 0
                ? max(5, barWidth * CGFloat(summary.expenseMinor) / CGFloat(totalMinor))
                : 0

            HStack(spacing: 2) {
                if summary.incomeMinor > 0 {
                    Capsule()
                        .fill(palette.positive.opacity(summary.isInDisplayedMonth ? 0.9 : 0.35))
                        .frame(width: incomeWidth, height: 3)
                }
                if summary.expenseMinor > 0 {
                    Capsule()
                        .fill(palette.caution.opacity(summary.isInDisplayedMonth ? 0.9 : 0.35))
                        .frame(width: expenseWidth, height: 3)
                }
                if !summary.hasActivity {
                    Capsule()
                        .fill(Color.primary.opacity(summary.isInDisplayedMonth ? 0.08 : 0.035))
                        .frame(height: 3)
                }
            }
            .frame(width: availableWidth, alignment: .leading)
        }
        .frame(height: 3)
    }

    private var cellBackground: Color {
        if summary.selected {
            return palette.accent.opacity(0.18)
        }
        if summary.isToday {
            return palette.accent.opacity(0.12)
        }
        return Color.primary.opacity(summary.isInDisplayedMonth ? 0.04 : 0.018)
    }

    private var cellBorder: Color {
        if summary.selected {
            return palette.accent.opacity(0.78)
        }
        if summary.isToday {
            return palette.accent.opacity(0.45)
        }
        if summary.isOverDailyAllowance {
            return palette.caution.opacity(0.5)
        }
        return Color.primary.opacity(0.055)
    }

    private var accessibilityLabel: String {
        var parts = [summary.date.formatted(date: .abbreviated, time: .omitted)]
        if summary.hasActivity {
            parts.append("\(summary.activityCount) activities")
        }
        if summary.hasRecurringProjection {
            parts.append("includes recurring projection")
        }
        if summary.isOverDailyAllowance {
            parts.append("over daily allowance")
        }
        return parts.joined(separator: ", ")
    }
}

private struct MetricPill: View {
    let title: String
    let amount: Int64
    let currencyCode: String
    let tint: Color
    var showsSign = false
    var isCompact = false

    private let elementRadius = FloatTheme.tileRadius

    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? 3 : 6) {
            Text(title)
                .font((isCompact ? Font.caption2 : Font.caption).weight(.semibold))
                .foregroundStyle(.secondary)
            Text(
                MoneyFormatter.string(
                    minorUnits: amount,
                    currencyCode: currencyCode,
                    showsSign: showsSign
                )
            )
            .moneyStyle(size: isCompact ? 15 : 17, weight: .bold)
            .foregroundStyle(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
        }
        .padding(isCompact ? 10 : 12)
        .frame(width: isCompact ? 132 : nil, alignment: .leading)
        .frame(maxWidth: isCompact ? nil : .infinity, alignment: .leading)
        .background(
            tint.opacity(0.1),
            in: RoundedRectangle(cornerRadius: elementRadius, style: .continuous)
        )
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
    let transfers: [TransferItem]
    let projectedRecurring: [CalendarRecurringProjection]
    let dailyAllowanceMinor: Int64
    let selected: Bool

    var id: Date { date }
    var incomeMinor: Int64 {
        transactions.filter { !$0.isExpense }.reduce(0) { $0 + $1.amountMinor }
            + projectedRecurring.filter { !$0.isExpense }.reduce(0) { $0 + $1.amountMinor }
    }
    var expenseMinor: Int64 {
        transactions.filter(\.isExpense).reduce(0) { $0 + $1.amountMinor }
            + projectedRecurring.filter(\.isExpense).reduce(0) { $0 + $1.amountMinor }
    }
    var netMinor: Int64 { incomeMinor - expenseMinor }
    var activityCount: Int { transactions.count + transfers.count + projectedRecurring.count }
    var hasActivity: Bool { activityCount > 0 }
    var hasRecurringProjection: Bool { !projectedRecurring.isEmpty }
    var cappedActivityLabel: String {
        activityCount > 9 ? "9+" : "\(activityCount)"
    }
    var isOverDailyAllowance: Bool {
        dailyAllowanceMinor > 0 && expenseMinor > dailyAllowanceMinor
    }
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

private struct CalendarRecurringProjection: Identifiable {
    let rule: RecurringRuleItem
    let date: Date

    var id: String { "\(rule.id.uuidString)-\(date.timeIntervalSince1970)" }
    var amountMinor: Int64 { rule.amountMinor }
    var isExpense: Bool { rule.isExpense }
    var title: String { rule.note?.nilIfBlank ?? rule.category?.name ?? "Recurring" }
    var icon: String { rule.category?.iconKey ?? "repeat" }
    var color: Color { Color(hex: rule.category?.colorHex ?? "#5A6B6B") }

    static func dueDates(
        for rules: [RecurringRuleItem],
        on day: Date,
        transactions: [TransactionItem],
        calendar: Calendar
    ) -> [CalendarRecurringProjection] {
        let start = calendar.startOfDay(for: day)
        return rules.flatMap {
            dueDates(
                for: $0,
                from: start,
                through: start,
                transactions: transactions,
                calendar: calendar
            )
        }
        .sorted { $0.date < $1.date }
    }

    static func dueDates(
        for rule: RecurringRuleItem,
        from start: Date,
        through end: Date,
        transactions: [TransactionItem],
        calendar: Calendar
    ) -> [CalendarRecurringProjection] {
        guard rule.active, rule.amountMinor > 0 else { return [] }
        let rangeStart = calendar.startOfDay(for: start)
        let rangeEnd = calendar.startOfDay(for: end)
        var date = calendar.startOfDay(for: rule.nextRunDate)
        var results: [CalendarRecurringProjection] = []

        while date <= rangeEnd {
            if let endDate = rule.endDate, date > calendar.startOfDay(for: endDate) {
                break
            }
            if date >= rangeStart
                && !hasMaterializedTransaction(
                    for: rule,
                    on: date,
                    transactions: transactions,
                    calendar: calendar
                )
            {
                results.append(CalendarRecurringProjection(rule: rule, date: date))
            }

            guard
                let next = SafeToSpendUseCase.advance(
                    date,
                    cadence: rule.cadence,
                    intervalCount: rule.intervalCount,
                    calendar: calendar
                ),
                next > date
            else { break }
            date = calendar.startOfDay(for: next)
        }

        return results
    }

    private static func hasMaterializedTransaction(
        for rule: RecurringRuleItem,
        on date: Date,
        transactions: [TransactionItem],
        calendar: Calendar
    ) -> Bool {
        transactions.contains {
            $0.recurringRule?.id == rule.id
                && calendar.isDate($0.timestamp, inSameDayAs: date)
                && $0.amountMinor == rule.amountMinor
                && $0.isExpense == rule.isExpense
        }
    }
}

private struct CalendarDeletedTransactionSnapshot {
    let id: UUID
    let amountMinor: Int64
    let isExpense: Bool
    let timestamp: Date
    let categoryID: UUID?
    let accountID: UUID?
    let recurringRuleID: UUID?
    let note: String?
    let createdAt: Date
    let updatedAt: Date

    init(transaction: TransactionItem) {
        id = transaction.id
        amountMinor = transaction.amountMinor
        isExpense = transaction.isExpense
        timestamp = transaction.timestamp
        categoryID = transaction.category?.id
        accountID = transaction.account?.id
        recurringRuleID = transaction.recurringRule?.id
        note = transaction.note
        createdAt = transaction.createdAt
        updatedAt = transaction.updatedAt
    }

    func makeTransaction(
        categories: [CategoryItem],
        accounts: [AccountItem],
        recurringRules: [RecurringRuleItem]
    ) -> TransactionItem {
        TransactionItem(
            id: id,
            amountMinor: amountMinor,
            isExpense: isExpense,
            timestamp: timestamp,
            category: categoryID.flatMap { id in categories.first { $0.id == id } },
            account: accountID.flatMap { id in accounts.first { $0.id == id } },
            note: note,
            recurringRule: recurringRuleID.flatMap { id in recurringRules.first { $0.id == id } },
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension SafeToSpendResult {
    static var empty: SafeToSpendResult {
        SafeToSpendResult(
            periodStart: Date(),
            periodEnd: Date(),
            expectedIncomeMinor: 0,
            recurringDueMinor: 0,
            goalContributionMinor: 0,
            variableSpentMinor: 0,
            safeToSpendMinor: 0,
            dailyAllowanceMinor: 0,
            overAmountMinor: 0,
            daysRemaining: 1,
            periodProgress: 0,
            spendingProgress: 0
        )
    }
}

private extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        self.date(from: dateComponents([.year, .month], from: date))
            ?? startOfDay(for: date)
    }

    func endOfDay(for date: Date) -> Date {
        let start = startOfDay(for: date)
        return self.date(byAdding: DateComponents(day: 1, second: -1), to: start)
            ?? start
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
