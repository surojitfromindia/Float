import Charts
import SwiftData
import SwiftUI

struct EventDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @Query(sort: \CategoryItem.sortOrder) private var categories: [CategoryItem]
    @Query(sort: \AccountItem.createdAt) private var accounts: [AccountItem]
    @Query(sort: \EventCategoryItem.sortOrder) private var eventCategories: [EventCategoryItem]

    let event: EventItem

    @State private var allTransactions: [TransactionItem] = []
    @State private var loadedTransactions: [TransactionItem] = []
    @State private var nextPageOffset = 0
    @State private var isLoadingPage = false
    @State private var hasMorePages = true
    @State private var pageError: String?
    @State private var searchText = ""
    @State private var selectedCategoryID: UUID?
    @State private var selectedAccountID: UUID?
    @State private var selectedType = TransactionTypeFilter.all
    @State private var useDateRange = false
    @State private var startDate = Calendar.current.date(
        byAdding: .month,
        value: -1,
        to: Date()
    ) ?? Date()
    @State private var endDate = Date()
    @State private var minimumAmountText = ""
    @State private var maximumAmountText = ""
    @State private var showingFilters = false
    @State private var editingTransaction: TransactionItem?
    @State private var showingTransactionEditor = false
    @State private var editorPresentation: EventEditorPresentation?
    @State private var pendingDeleteTransaction: TransactionItem?
    @State private var showingDeleteAlert = false

    private var filteredTransactions: [TransactionItem] {
        loadedTransactions.filter(matchesTransaction).sorted {
            $0.timestamp > $1.timestamp
        }
    }

    private var hasActiveFilters: Bool {
        selectedCategoryID != nil || selectedAccountID != nil
            || selectedType != .all || useDateRange
            || minimumAmountMinor != nil || maximumAmountMinor != nil
    }

    private var minimumAmountMinor: Int64? {
        amountMinor(from: minimumAmountText)
    }

    private var maximumAmountMinor: Int64? {
        amountMinor(from: maximumAmountText)
    }

    private var postedExpenses: [TransactionItem] {
        allTransactions.filter(\.isPostedExpense)
    }

    private var postedIncome: [TransactionItem] {
        allTransactions.filter(\.isPostedIncome)
    }

    private var totalExpenseMinor: Int64 {
        postedExpenses.reduce(Int64(0)) { $0 + $1.amountMinor }
    }

    private var totalIncomeMinor: Int64 {
        postedIncome.reduce(Int64(0)) { $0 + $1.amountMinor }
    }

    private var netMinor: Int64 {
        totalIncomeMinor - totalExpenseMinor
    }

    private var averageExpenseMinor: Int64 {
        guard !postedExpenses.isEmpty else { return 0 }
        return totalExpenseMinor / Int64(postedExpenses.count)
    }

    private var expenseCount: Int {
        postedExpenses.count
    }

    private var totalTransactionCount: Int {
        allTransactions.count
    }

    private var durationDays: Int {
        let days = Calendar.current.dateComponents(
            [.day],
            from: event.startDate.startOfDay,
            to: event.endDate.endOfDay
        ).day ?? 0
        return max(1, days + 1)
    }

    private var dailySpendSeries: [EventDailySpend] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: postedExpenses) {
            calendar.startOfDay(for: $0.displayDate)
        }
        return grouped
            .map {
                EventDailySpend(date: $0.key, amountMinor: $0.value.reduce(Int64(0)) { $0 + $1.amountMinor })
            }
            .sorted { $0.date < $1.date }
    }

    private var categoryBreakdown: [EventCategorySpend] {
        let grouped = Dictionary(grouping: postedExpenses) { transaction in
            transaction.category?.name ?? "Uncategorized"
        }
        return grouped.map { key, value in
            EventCategorySpend(
                name: key,
                amountMinor: value.reduce(Int64(0)) { $0 + $1.amountMinor },
                colorHex: value.first?.category?.colorHex ?? "#0E7C7B"
            )
        }
        .sorted { $0.amountMinor > $1.amountMinor }
        .prefix(6)
        .map { $0 }
    }

    private var summaryCards: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            SummaryMetricTile(
                title: "Expenses",
                value: money(totalExpenseMinor),
                caption: expenseCount == 0 ? "No expense transactions" : "\(expenseCount) expense tx",
                icon: "arrow.up.circle.fill",
                tint: appState.themePalette.caution
            )
            SummaryMetricTile(
                title: "Income",
                value: money(totalIncomeMinor),
                caption: "\(postedIncome.count) income tx",
                icon: "arrow.down.circle.fill",
                tint: appState.themePalette.positive
            )
            SummaryMetricTile(
                title: "Net",
                value: money(abs(netMinor)),
                caption: netMinor >= 0 ? "Positive flow" : "Negative flow",
                icon: "chart.line.uptrend.xyaxis",
                tint: netMinor >= 0 ? appState.themePalette.positive : appState.themePalette.caution
            )
            SummaryMetricTile(
                title: "Average",
                value: money(averageExpenseMinor),
                caption: "\(durationDays) days",
                icon: "function",
                tint: appState.themePalette.accent
            )
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                eventHeaderCard
                summaryCards
                chartCard
                categoryChartCard
                compactFilterSection

                if filteredTransactions.isEmpty && !isLoadingPage {
                    EmptyStateView(
                        icon: "list.bullet.rectangle",
                        title: emptyStateTitle,
                        message: emptyStateMessage
                    )
                    .transactionPlainSurface(cornerRadius: FloatTheme.controlRadius)
                } else {
                    ForEach(filteredTransactions) { transaction in
                        Button {
                            editingTransaction = transaction
                            showingTransactionEditor = true
                        } label: {
                            TransactionRowView(
                                transaction: transaction,
                                currencyCode: appState.selectedCurrencyCode
                            )
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                editingTransaction = transaction
                                showingTransactionEditor = true
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                pendingDeleteTransaction = transaction
                                showingDeleteAlert = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .onAppear {
                            loadOlderPageIfNeeded(afterDisplaying: transaction)
                        }
                    }
                    paginationFooter
                }
            }
            .padding(20)
            .padding(.bottom, 42)
        }
        .navigationTitle("Event")
        .searchable(text: $searchText, prompt: "Search event transactions")
        .keyboardDismissControls()
        .floatBackground()
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    togglePinned()
                } label: {
                    Image(systemName: event.pinned ? "pin.fill" : "pin")
                }
                .accessibilityLabel(event.pinned ? "Unpin event" : "Pin event")

                Button {
                    editorPresentation = EventEditorPresentation(event: event)
                } label: {
                    Image(systemName: "pencil")
                }
                .accessibilityLabel("Edit event")

                Button {
                    editingTransaction = nil
                    showingTransactionEditor = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add transaction")
                .disabled(event.isEnded)
            }
        }
        .sheet(item: $editorPresentation, onDismiss: resetAndLoadFirstPage) { presentation in
            EventEditorSheet(
                eventToEdit: presentation.event,
                categories: eventCategories,
                onSave: resetAndLoadFirstPage
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingTransactionEditor) {
            QuickAddKeypadSheet(
                transactionToEdit: editingTransaction,
                event: event,
                initialTimestamp: editingTransaction?.timestamp ?? Date(),
                initialIsExpense: nil
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingFilters) {
            EventTransactionFilterSheet(
                categories: categories,
                accounts: accounts,
                selectedCategoryID: $selectedCategoryID,
                selectedAccountID: $selectedAccountID,
                selectedType: $selectedType,
                useDateRange: $useDateRange,
                startDate: $startDate,
                endDate: $endDate,
                minimumAmountText: $minimumAmountText,
                maximumAmountText: $maximumAmountText,
                hasActiveFilters: hasActiveFilters,
                clearFilters: clearFilters,
                currencyCode: appState.selectedCurrencyCode
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .alert("Delete transaction?", isPresented: $showingDeleteAlert, presenting: pendingDeleteTransaction) { transaction in
            Button("Cancel", role: .cancel) {}
            Button("Delete transaction", role: .destructive) {
                delete(transaction)
            }
        } message: { transaction in
            Text("Delete \(MoneyFormatter.string(minorUnits: transaction.amountMinor, currencyCode: appState.selectedCurrencyCode)) from this event?")
        }
        .task {
            resetAndLoadFirstPage()
        }
        .onChange(of: searchText) { _, _ in resetAndLoadFirstPage() }
        .onChange(of: selectedCategoryID) { _, _ in resetAndLoadFirstPage() }
        .onChange(of: selectedAccountID) { _, _ in resetAndLoadFirstPage() }
        .onChange(of: selectedType) { _, _ in resetAndLoadFirstPage() }
        .onChange(of: useDateRange) { _, _ in resetAndLoadFirstPage() }
        .onChange(of: startDate) { _, newValue in
            if newValue > endDate { endDate = newValue }
            if useDateRange { resetAndLoadFirstPage() }
        }
        .onChange(of: endDate) { _, newValue in
            if newValue < startDate { startDate = newValue }
            if useDateRange { resetAndLoadFirstPage() }
        }
        .onChange(of: showingTransactionEditor) { _, isPresented in
            if !isPresented {
                editingTransaction = nil
                resetAndLoadFirstPage()
            }
        }
    }

    private var eventHeaderCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    FloatIconBadge(
                        icon: event.category?.iconKey ?? "calendar",
                        tint: Color(hex: event.category?.colorHex ?? "#0E7C7B"),
                        size: 42
                    )
                    VStack(alignment: .leading, spacing: 4) {
                        Text(event.name)
                            .font(.title2.weight(.bold))
                        Text(event.status.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(event.isActive ? appState.themePalette.positive : appState.themePalette.caution)
                    }
                    Spacer()
                    if event.pinned {
                        Image(systemName: "pin.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(appState.themePalette.accent)
                    }
                }

                HStack(spacing: 8) {
                    Label(eventDateRangeText, systemImage: "calendar")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    if let category = event.category {
                        Label(category.name, systemImage: category.iconKey)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color(hex: category.colorHex))
                    }
                }

                if let description = event.eventDescription?.trimmingCharacters(in: .whitespacesAndNewlines), !description.isEmpty {
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var chartCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Spend by day")
                if dailySpendSeries.isEmpty {
                    EmptyStateView(
                        icon: "chart.bar.xaxis",
                        title: "No spending yet",
                        message: "Add transactions to see the event trend."
                    )
                } else {
                    Chart(dailySpendSeries) { item in
                        BarMark(
                            x: .value("Day", item.date, unit: .day),
                            y: .value("Amount", item.amountMinor)
                        )
                        .foregroundStyle(appState.themePalette.accent)
                    }
                    .frame(height: 220)
                    .chartYAxis {
                        AxisMarks(position: .leading)
                    }
                }
            }
        }
    }

    private var categoryChartCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Category breakdown")
                if categoryBreakdown.isEmpty {
                    EmptyStateView(
                        icon: "chart.pie",
                        title: "No expense categories yet",
                        message: "Expense transactions will appear here when added."
                    )
                } else {
                    Chart(categoryBreakdown) { item in
                        SectorMark(
                            angle: .value("Amount", item.amountMinor),
                            innerRadius: .ratio(0.55),
                            angularInset: 1
                        )
                        .foregroundStyle(Color(hex: item.colorHex))
                    }
                    .frame(height: 240)
                    .chartLegend(position: .bottom, alignment: .leading)
                    .chartForegroundStyleScale(
                        domain: categoryBreakdown.map(\.name),
                        range: categoryBreakdown.map { Color(hex: $0.colorHex) }
                    )
                }
            }
        }
    }

    private var compactFilterSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button {
                    showingFilters = true
                } label: {
                    FilterControlLabel(
                        title: hasActiveFilters ? "Filters active" : "Filters",
                        icon: hasActiveFilters
                            ? "line.3.horizontal.decrease.circle.fill"
                            : "line.3.horizontal.decrease.circle"
                    )
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .padding(.horizontal, 2)

            if hasActiveFilters {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(activeFilterChips) { chip in
                            Button {
                                removeFilter(chip.kind)
                            } label: {
                                HStack(spacing: 5) {
                                    Text(chip.title)
                                    Image(systemName: "xmark")
                                        .font(.caption2.weight(.bold))
                                }
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 2)
                                .padding(.vertical, 6)
                            }
                            .buttonStyle(.plain)
                        }

                        Button("Clear", action: clearFilters)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 2)
                            .padding(.vertical, 6)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var paginationFooter: some View {
        if let pageError {
            Button {
                loadOlderPage()
            } label: {
                Label(pageError, systemImage: "arrow.clockwise")
                    .font(.footnote.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        } else if hasMorePages {
            HStack(spacing: 10) {
                if isLoadingPage {
                    ProgressView()
                }
                Text(isLoadingPage ? "Loading older data" : "Load older data")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .onAppear {
                loadOlderPage()
            }
        }
    }

    private var emptyStateTitle: String {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !hasActiveFilters {
            return "No transactions yet"
        }
        return "No matching transactions"
    }

    private var emptyStateMessage: String {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !hasActiveFilters {
            return "Add transactions to build event-level charts and metrics."
        }
        return "Try a different search or filter."
    }

    private var activeFilterChips: [TransactionFilterChip] {
        var chips: [TransactionFilterChip] = []
        if selectedType != .all {
            chips.append(TransactionFilterChip(title: selectedType.title, kind: .type))
        }
        if let selectedCategoryID,
           let category = categories.first(where: { $0.id == selectedCategoryID }) {
            chips.append(TransactionFilterChip(title: category.name, kind: .category))
        }
        if let selectedAccountID,
           let account = accounts.first(where: { $0.id == selectedAccountID }) {
            chips.append(TransactionFilterChip(title: account.name, kind: .account))
        }
        if useDateRange {
            chips.append(
                TransactionFilterChip(
                    title: "\(startDate.formatted(date: .abbreviated, time: .omitted)) - \(endDate.formatted(date: .abbreviated, time: .omitted))",
                    kind: .dateRange
                )
            )
        }
        if minimumAmountMinor != nil {
            chips.append(TransactionFilterChip(title: "Min \(minimumAmountText)", kind: .minimumAmount))
        }
        if maximumAmountMinor != nil {
            chips.append(TransactionFilterChip(title: "Max \(maximumAmountText)", kind: .maximumAmount))
        }
        return chips
    }

    private func delete(_ transaction: TransactionItem) {
        do {
            try TransactionRepository(modelContext: modelContext).delete(transaction)
            pendingDeleteTransaction = nil
            resetAndLoadFirstPage()
        } catch {
            pageError = error.localizedDescription
        }
    }

    private func togglePinned() {
        do {
            try EventRepository(modelContext: modelContext).update(
                event,
                name: event.name,
                startDate: event.startDate,
                endDate: event.endDate,
                status: event.status,
                category: event.category,
                eventDescription: event.eventDescription,
                pinned: !event.pinned
            )
        } catch {
            pageError = error.localizedDescription
        }
    }

    private func clearFilters() {
        selectedCategoryID = nil
        selectedAccountID = nil
        selectedType = .all
        useDateRange = false
        minimumAmountText = ""
        maximumAmountText = ""
    }

    private func removeFilter(_ kind: TransactionFilterChip.Kind) {
        switch kind {
        case .type:
            selectedType = .all
        case .category:
            selectedCategoryID = nil
        case .account:
            selectedAccountID = nil
        case .dateRange:
            useDateRange = false
        case .minimumAmount:
            minimumAmountText = ""
        case .maximumAmount:
            maximumAmountText = ""
        }
    }

    private func resetAndLoadFirstPage() {
        allTransactions = []
        loadedTransactions = []
        nextPageOffset = 0
        hasMorePages = true
        pageError = nil
        loadAnalytics()
        loadOlderPage()
    }

    private func loadAnalytics() {
        do {
            let descriptor = allTransactionsDescriptor
            allTransactions = try modelContext.fetch(descriptor)
        } catch {
            allTransactions = []
        }
    }

    private func loadOlderPage() {
        guard !isLoadingPage, hasMorePages else { return }
        isLoadingPage = true
        pageError = nil

        do {
            let descriptor = pageDescriptor(offset: nextPageOffset)
            let fetched = try modelContext.fetch(descriptor)
            mergeLoadedTransactions(fetched)
            nextPageOffset += fetched.count
            hasMorePages = fetched.count == 100
            isLoadingPage = false
        } catch {
            pageError = "Could not load older data"
            isLoadingPage = false
        }
    }

    private func loadOlderPageIfNeeded(afterDisplaying transaction: TransactionItem) {
        guard shouldLoadOlderPage(afterDisplaying: transaction) else { return }
        loadOlderPage()
    }

    private func shouldLoadOlderPage(afterDisplaying transaction: TransactionItem) -> Bool {
        guard hasMorePages, !isLoadingPage, pageError == nil else { return false }
        let triggerItems = filteredTransactions.suffix(5)
        return triggerItems.contains { $0.id == transaction.id }
    }

    private var allTransactionsDescriptor: FetchDescriptor<TransactionItem> {
        let eventID = event.id
        let descriptor = FetchDescriptor<TransactionItem>(
            predicate: #Predicate<TransactionItem> { transaction in
                transaction.event?.id == eventID
            },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        return descriptor
    }

    private func pageDescriptor(offset: Int) -> FetchDescriptor<TransactionItem> {
        let eventID = event.id
        var descriptor = FetchDescriptor<TransactionItem>(
            predicate: #Predicate<TransactionItem> { transaction in
                transaction.event?.id == eventID
            },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 100
        descriptor.fetchOffset = offset
        return descriptor
    }

    private func mergeLoadedTransactions(_ items: [TransactionItem]) {
        var existingIDs = Set(loadedTransactions.map(\.id))
        for item in items where !existingIDs.contains(item.id) {
            loadedTransactions.append(item)
            existingIDs.insert(item.id)
        }
    }

    private func matchesTransaction(_ transaction: TransactionItem) -> Bool {
        let matchesCategory =
            selectedCategoryID == nil
            || transaction.category?.id == selectedCategoryID
        let matchesAccount =
            selectedAccountID == nil
            || transaction.account?.id == selectedAccountID
        let matchesPendingFilters = !transaction.isPending
            || (selectedCategoryID == nil && selectedAccountID == nil)
        let matchesAmount = (minimumAmountMinor == nil || transaction.amountMinor >= minimumAmountMinor!)
            && (maximumAmountMinor == nil || transaction.amountMinor <= maximumAmountMinor!)
        let matchesType =
            selectedType == .all
            || (selectedType == .expenses && transaction.isPostedExpense)
            || (selectedType == .income && transaction.isPostedIncome)
            || (selectedType == .pending && transaction.isPending)
        let matchesDate = !useDateRange
            || transaction.displayDate >= startDate.startOfDay
                && transaction.displayDate <= endDate.endOfDay
        return matchesCategory
            && matchesAccount
            && matchesPendingFilters
            && matchesAmount
            && matchesType
            && matchesDate
            && matchesSearch(transaction)
    }

    private func matchesSearch(_ transaction: TransactionItem) -> Bool {
        let query = normalizedSearchText
        guard !query.isEmpty else { return true }
        return (transaction.note ?? "").localizedCaseInsensitiveContains(query)
            || transaction.categoryName.localizedCaseInsensitiveContains(query)
            || transaction.accountName.localizedCaseInsensitiveContains(query)
            || transaction.timestamp.formatted(date: .abbreviated, time: .shortened)
                .localizedCaseInsensitiveContains(query)
            || MoneyFormatter.string(
                minorUnits: transaction.amountMinor,
                currencyCode: appState.selectedCurrencyCode
            )
            .localizedCaseInsensitiveContains(query)
    }

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func amountMinor(from text: String) -> Int64? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let parsed = BudgetAmountField.minorUnits(
            fromMajorAmount: trimmed,
            currencyCode: appState.selectedCurrencyCode
        )
        return parsed > 0 ? parsed : nil
    }

    private func money(_ amount: Int64) -> String {
        MoneyFormatter.string(
            minorUnits: amount,
            currencyCode: appState.selectedCurrencyCode
        )
    }

    private var eventDateRangeText: String {
        "\(event.startDate.formatted(date: .abbreviated, time: .omitted)) - \(event.endDate.formatted(date: .abbreviated, time: .omitted))"
    }
}

private struct EventDailySpend: Identifiable {
    let date: Date
    let amountMinor: Int64
    var id: Date { date }
}

private struct EventCategorySpend: Identifiable {
    let name: String
    let amountMinor: Int64
    let colorHex: String

    var id: String { name }
}

private struct EventEditorPresentation: Identifiable {
    let id = UUID()
    let event: EventItem?
}

private struct TransactionFilterChip: Identifiable {
    let id = UUID()
    let title: String
    let kind: Kind

    enum Kind {
        case type
        case category
        case account
        case dateRange
        case minimumAmount
        case maximumAmount
    }
}

private enum TransactionTypeFilter: String, CaseIterable, Identifiable {
    case all
    case expenses
    case income
    case pending

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .expenses: "Expenses"
        case .income: "Income"
        case .pending: "Pending"
        }
    }
}

private struct EventTransactionFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    let categories: [CategoryItem]
    let accounts: [AccountItem]
    @Binding var selectedCategoryID: UUID?
    @Binding var selectedAccountID: UUID?
    @Binding var selectedType: TransactionTypeFilter
    @Binding var useDateRange: Bool
    @Binding var startDate: Date
    @Binding var endDate: Date
    @Binding var minimumAmountText: String
    @Binding var maximumAmountText: String
    let hasActiveFilters: Bool
    let clearFilters: () -> Void
    let currencyCode: String

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    filterHeader

                    filterSection(title: "Filters", icon: "line.3.horizontal.decrease.circle") {
                        VStack(spacing: 10) {
                            menuRow(
                                title: "Type",
                                value: selectedType.title,
                                icon: "tray.full"
                            ) {
                                Picker("Type", selection: $selectedType) {
                                    ForEach(TransactionTypeFilter.allCases) {
                                        Text($0.title).tag($0)
                                    }
                                }
                            }

                            Divider()

                            menuRow(
                                title: "Category",
                                value: selectedCategoryName,
                                icon: "folder"
                            ) {
                                Picker("Category", selection: $selectedCategoryID) {
                                    Text("All categories").tag(UUID?.none)
                                    ForEach(categories.filter { !$0.archived }) {
                                        Text($0.name).tag(Optional($0.id))
                                    }
                                }
                            }

                            Divider()

                            menuRow(
                                title: "Account",
                                value: selectedAccountName,
                                icon: "creditcard"
                            ) {
                                Picker("Account", selection: $selectedAccountID) {
                                    Text("All accounts").tag(UUID?.none)
                                    ForEach(accounts.filter { !$0.archived }) {
                                        Text($0.name).tag(Optional($0.id))
                                    }
                                }
                            }

                            Divider()

                            Toggle(isOn: $useDateRange) {
                                filterRowLabel(title: "Date range", icon: "calendar")
                            }
                            .tint(Color(hex: "#0A6FAE"))
                            .padding(.vertical, 8)

                            if useDateRange {
                                Divider()
                                dateRow(
                                    title: "From",
                                    selection: $startDate
                                )
                                Divider()
                                dateRow(
                                    title: "To",
                                    selection: $endDate
                                )
                            }

                            Divider()

                            amountField("Min amount", text: $minimumAmountText)
                            Divider()
                            amountField("Max amount", text: $maximumAmountText)
                        }
                    }
                    .onChange(of: startDate) { _, newValue in
                        if newValue > endDate {
                            endDate = newValue
                        }
                    }
                    .onChange(of: endDate) { _, newValue in
                        if newValue < startDate {
                            startDate = newValue
                        }
                    }

                    HStack(spacing: 12) {
                        Button(action: clearFilters) {
                            Label("Clear", systemImage: "xmark.circle")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(!hasActiveFilters)

                        Button {
                            dismiss()
                        } label: {
                            Label("Done", systemImage: "checkmark.circle.fill")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(20)
                .padding(.bottom, 24)
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDismissControls()
            .scrollContentBackground(.hidden)
            .floatBackground()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var filterHeader: some View {
        GlassCard {
            HStack(spacing: 12) {
                FloatIconBadge(
                    icon: hasActiveFilters
                        ? "line.3.horizontal.decrease.circle.fill"
                        : "line.3.horizontal.decrease.circle",
                    tint: Color(hex: "#0A6FAE"),
                    size: 40
                )
                VStack(alignment: .leading, spacing: 4) {
                    Text(hasActiveFilters ? "Filters active" : "All transactions")
                        .font(.headline)
                    Text(filterSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
            }
        }
    }

    private var filterSummary: String {
        var parts: [String] = []
        if selectedType != .all { parts.append(selectedType.title) }
        if selectedCategoryID != nil { parts.append(selectedCategoryName) }
        if selectedAccountID != nil { parts.append(selectedAccountName) }
        if useDateRange { parts.append("Date range") }
        if !minimumAmountText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("Min \(minimumAmountText)")
        }
        if !maximumAmountText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("Max \(maximumAmountText)")
        }
        return parts.isEmpty ? "No filters are applied." : parts.joined(separator: " • ")
    }

    private var selectedCategoryName: String {
        guard let selectedCategoryID,
              let category = categories.first(where: { $0.id == selectedCategoryID })
        else {
            return "All categories"
        }
        return category.name
    }

    private var selectedAccountName: String {
        guard let selectedAccountID,
              let account = accounts.first(where: { $0.id == selectedAccountID })
        else {
            return "All accounts"
        }
        return account.name
    }

    private func filterSection<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(.secondary)
            content()
                .padding(.vertical, 2)
        }
    }

    private func filterRowLabel(title: String, icon: String) -> some View {
        HStack(spacing: 12) {
            FloatIconBadge(icon: icon, tint: Color(hex: "#0A6FAE"), size: 34)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
        }
    }

    private func dateRow(
        title: String,
        selection: Binding<Date>
    ) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Spacer()
            DatePicker(
                title,
                selection: selection,
                displayedComponents: .date
            )
            .labelsHidden()
            .datePickerStyle(.compact)
            .fixedSize()
        }
        .padding(.vertical, 8)
    }

    private func menuRow<MenuContent: View>(
        title: String,
        value: String,
        icon: String,
        @ViewBuilder menuContent: () -> MenuContent
    ) -> some View {
        HStack(spacing: 12) {
            FloatIconBadge(icon: icon, tint: Color(hex: "#0A6FAE"), size: 34)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Spacer()
            Menu {
                menuContent()
            } label: {
                HStack(spacing: 8) {
                    Text(value)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(hex: "#0A6FAE"))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color(hex: "#0A6FAE"))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
    }

    private func amountField(
        _ title: String,
        text: Binding<String>
    ) -> some View {
        HStack(spacing: 12) {
            TextField(title, text: text)
                .keyboardType(.decimalPad)
                .textFieldStyle(.plain)
            if let amount = parsedAmount(text.wrappedValue) {
                Text(
                    MoneyFormatter.string(
                        minorUnits: amount,
                        currencyCode: currencyCode
                    )
                )
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 10)
    }

    private func parsedAmount(_ text: String) -> Int64? {
        let parsed = BudgetAmountField.minorUnits(
            fromMajorAmount: text,
            currencyCode: currencyCode
        )
        return parsed > 0 ? parsed : nil
    }
}

private extension View {
    func transactionPlainSurface(
        cornerRadius: CGFloat,
        tint: Color? = nil
    ) -> some View {
        let shape = RoundedRectangle(
            cornerRadius: cornerRadius,
            style: .continuous
        )

        return self
            .background(
                Color(.secondarySystemGroupedBackground),
                in: shape
            )
            .background(
                (tint ?? Color.clear).opacity(tint == nil ? 0 : 0.08),
                in: shape
            )
            .overlay(
                shape.strokeBorder(
                    (tint ?? Color.primary).opacity(tint == nil ? 0.06 : 0.14),
                    lineWidth: 1
                )
            )
    }
}

private struct FilterControlLabel: View {
    let title: String
    let icon: String

    var body: some View {
        Label(title, systemImage: icon)
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 2)
            .padding(.vertical, 8)
    }
}

private extension Date {
    var startOfDay: Date {
        Calendar.current.startOfDay(for: self)
    }

    var endOfDay: Date {
        Calendar.current.date(
            byAdding: DateComponents(day: 1, second: -1),
            to: Calendar.current.startOfDay(for: self)
        ) ?? self
    }
}
