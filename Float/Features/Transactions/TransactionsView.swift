import Foundation
import SwiftData
import SwiftUI

struct TransactionsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @Query(sort: \CategoryItem.sortOrder) private var allCategories: [CategoryItem]
    @Query(sort: \AccountItem.createdAt) private var allAccounts: [AccountItem]
    @Query(sort: \PersonItem.createdAt) private var allPeople: [PersonItem]
    @Query(sort: \EventItem.startDate, order: .reverse) private var allEvents: [EventItem]
    @State private var ledgerItems: [LedgerListItem] = []
    @State private var nextPageEndDate: Date?
    @State private var isLoadingPage = false
    @State private var hasMorePages = true
    @State private var pageError: String?
    @State private var searchText = ""
    @State private var selectedCategoryID: UUID?
    @State private var selectedAccountID: UUID?
    @State private var selectedPersonID: UUID?
    @State private var selectedType = TransactionTypeFilter.all
    @State private var selectedSort = TransactionSortOption.newestFirst
    @State private var useDateRange = false
    @State private var startDate = Calendar.current.date(
        byAdding: .month,
        value: -1,
        to: Date()
    ) ?? Date()
    @State private var endDate = Date()
    @State private var minimumAmountText = ""
    @State private var maximumAmountText = ""
    @State private var deletedSnapshot: DeletedTransactionSnapshot?
    @State private var showingUndo = false
    @State private var showingFilters = false
    @State private var editingTransaction: TransactionItem?
    @State private var editingTransactionInitialIsExpense: Bool?
    @State private var splittingTransaction: TransactionItem?
    @State private var editingTransfer: TransferItem?
    @State private var isEntrySheetPresented = false
    @State private var isTransferSheetPresented = false
    @State private var isBulkEntrySheetPresented = false
    @State private var activeContextMenuItemID: String?

    private var categories: [CategoryItem] { filterActiveProfile(allCategories) }
    private var accounts: [AccountItem] { filterActiveProfile(allAccounts) }
    private var people: [PersonItem] { filterActiveProfile(allPeople) }
    private var events: [EventItem] { filterActiveProfile(allEvents) }

    private var filtered: [LedgerListItem] {
        switch selectedSort {
        case .newestFirst:
            return ledgerItems.sorted { $0.timestamp > $1.timestamp }
        case .oldestFirst:
            return ledgerItems.sorted { $0.timestamp < $1.timestamp }
        }
    }

    private var grouped: [(Date, [LedgerListItem])] {
        Dictionary(grouping: filtered) {
            Calendar.current.startOfDay(for: $0.timestamp)
        }
        .map { ($0.key, $0.value) }
        .sorted {
            selectedSort == .oldestFirst ? $0.0 < $1.0 : $0.0 > $1.0
        }
    }

    private var minimumAmountMinor: Int64? {
        amountMinor(from: minimumAmountText)
    }

    private var maximumAmountMinor: Int64? {
        amountMinor(from: maximumAmountText)
    }

    private var hasActiveFilters: Bool {
        selectedCategoryID != nil || selectedAccountID != nil || selectedPersonID != nil
            || selectedType != .all || useDateRange
            || minimumAmountMinor != nil || maximumAmountMinor != nil
    }

    var body: some View {
        transactionsScrollContent
        .navigationTitle("Transactions")
        .navigationBarItems(trailing: transactionNavigationBarItems)
        .searchable(text: $searchText, prompt: "Search notes, accounts, amounts")
        .keyboardDismissControls()
        .floatBackground()
        .overlay(alignment: .bottom) {
            if showingUndo, deletedSnapshot != nil {
                undoBar
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(transactionFilterSheetHost)
        .sheet(isPresented: $isEntrySheetPresented, content: entrySheet)
        .sheet(item: $splittingTransaction, content: splittingTransactionSheet)
        .sheet(isPresented: $isTransferSheetPresented, content: transferSheet)
        .sheet(isPresented: $isBulkEntrySheetPresented, content: bulkEntrySheet)
        .task {
            loadInitialState()
        }
        .onChange(of: appState.pendingSpotlightRequest?.id) { _, _ in
            handleSpotlightRequestChange()
        }
        .onChange(of: searchText) { _, _ in resetAndLoadFirstPage() }
        .onChange(of: selectedCategoryID) { _, _ in resetAndLoadFirstPage() }
        .onChange(of: selectedAccountID) { _, _ in resetAndLoadFirstPage() }
        .onChange(of: selectedPersonID) { _, _ in resetAndLoadFirstPage() }
        .onChange(of: selectedType) { _, _ in resetAndLoadFirstPage() }
        .onChange(of: selectedSort) { _, _ in resetAndLoadFirstPage() }
        .onChange(of: useDateRange) { _, _ in resetAndLoadFirstPage() }
        .onChange(of: startDate) { _, _ in
            if useDateRange { resetAndLoadFirstPage() }
        }
        .onChange(of: endDate) { _, _ in
            if useDateRange { resetAndLoadFirstPage() }
        }
        .onChange(of: minimumAmountText) { _, _ in resetAndLoadFirstPage() }
        .onChange(of: maximumAmountText) { _, _ in resetAndLoadFirstPage() }
        .onChange(of: isEntrySheetPresented) { _, isPresented in
            if !isPresented {
                editingTransaction = nil
                editingTransactionInitialIsExpense = nil
                resetAndLoadFirstPage()
            }
        }
        .onChange(of: isTransferSheetPresented) { _, isPresented in
            if !isPresented {
                editingTransfer = nil
                resetAndLoadFirstPage()
            }
        }
        .onChange(of: isBulkEntrySheetPresented) { _, isPresented in
            if !isPresented {
                resetAndLoadFirstPage()
            }
        }
    }

    private var transactionsScrollContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                compactFilterSection

                if filtered.isEmpty && !isLoadingPage {
                    EmptyStateView(
                        icon: "list.bullet.rectangle",
                        title: emptyStateTitle,
                        message: emptyStateMessage
                    )
                    .transactionPlainSurface(cornerRadius: FloatTheme.controlRadius)
                } else {
                    ForEach(grouped, id: \.0) { day, items in
                        transactionSection(day: day, items: items)
                    }
                    paginationFooter
                }
            }
            .padding(20)
            .padding(.bottom, 130)
        }
    }

    private func entrySheet() -> some View {
        QuickAddKeypadSheet(
            transactionToEdit: editingTransaction,
            initialIsExpense: editingTransactionInitialIsExpense
        )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
    }

    private func splittingTransactionSheet(_ transaction: TransactionItem) -> some View {
        BulkTransactionEntrySheet(
            transactionToReplace: transaction,
            onCreate: { resetAndLoadFirstPage() }
        )
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func transferSheet() -> some View {
        TransferEditorSheet(transferToEdit: editingTransfer)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
    }

    private func bulkEntrySheet() -> some View {
        BulkTransactionEntrySheet()
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
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

    private var emptyStateTitle: LocalizedStringResource {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !hasActiveFilters {
            return LocalizedStringResource("No transactions yet")
        }
        return LocalizedStringResource("No matching transactions")
    }

    private var emptyStateMessage: LocalizedStringResource {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !hasActiveFilters {
            return LocalizedStringResource("Your transactions will appear here as you add them.")
        }
        return LocalizedStringResource("Try changing your search or filters.")
    }

    private var transactionNavigationBarItems: some View {
        HStack(spacing: 14) {
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
        }
    }

    private func transactionSection(day: Date, items: [LedgerListItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(day.formatted(date: .complete, time: .omitted))
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(dayTotal(items))
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)

            VStack(spacing: 6) {
                ForEach(items) { item in
                    switch item {
                    case .transaction(let transaction):
                        Button {
                            presentEditTransaction(transaction)
                        } label: {
                            TransactionRowView(
                                transaction: transaction,
                                currencyCode: appState.selectedCurrencyCode
                            )
                            .contentShape(Rectangle())
                        }
                        .opacity(activeContextMenuItemID == item.id ? 0 : 1)
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                        .contextMenu {
                            if transaction.isPending {
                                Button {
                                    presentEditTransaction(transaction, initialIsExpense: true)
                                } label: {
                                    Label("Convert to expense", systemImage: "minus.circle")
                                }
                                Button {
                                    presentEditTransaction(transaction, initialIsExpense: false)
                                } label: {
                                    Label("Convert to income", systemImage: "plus.circle")
                                }
                            } else {
                                Button {
                                    splittingTransaction = transaction
                                } label: {
                                    Label("Split transaction", systemImage: "divide.circle")
                                }
                            }

                            Button(role: .destructive) {
                                delete(transaction)
                            } label: {
                                redDeleteLabel
                            }
                            .tint(.red)
                        }
                        
                        preview: {
                            TransactionRowView(
                                transaction: transaction,
                                currencyCode: appState.selectedCurrencyCode
                            )
                            .padding(16)
                            .frame(maxWidth: 720)
                            .onAppear {
                                activeContextMenuItemID = item.id
                            }
                            .onDisappear {
                                clearActiveContextMenuItem(item.id)
                            }
                        }
                        .onAppear {
                            loadOlderPageIfNeeded(afterDisplaying: item)
                        }
                    case .transfer(let transfer):
                        Button {
                            presentEditTransfer(transfer)
                        } label: {
                            TransferRowView(
                                transfer: transfer,
                                currencyCode: transfer.currencyCode
                            )
                            .contentShape(Rectangle())
                        }
                        .opacity(activeContextMenuItemID == item.id ? 0 : 1)
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                        .contextMenu {
                            Button(role: .destructive) {
                                delete(transfer)
                            } label: {
                                redDeleteLabel
                            }
                            .tint(.red)
                        } preview: {
                            TransferRowView(
                                transfer: transfer,
                                currencyCode: transfer.currencyCode
                            )
                            .padding(16)
                            .frame(maxWidth: 420)
                            .onAppear {
                                activeContextMenuItemID = item.id
                            }
                            .onDisappear {
                                clearActiveContextMenuItem(item.id)
                            }
                        }
                        .onAppear {
                            loadOlderPageIfNeeded(afterDisplaying: item)
                        }
                    }
                    if item.id != items.last?.id {
                        Divider()
                    }
                }
            }
            .padding(14)
            .transactionSectionGlassSurface(cornerRadius: FloatTheme.controlRadius)
        }
    }

    private var redDeleteLabel: some View {
        Label {
            Text("Delete")
                .foregroundStyle(.red)
        } icon: {
            Image(systemName: "trash")
                .foregroundStyle(.red)
        }
    }

    private func clearActiveContextMenuItem(_ itemID: String) {
        if activeContextMenuItemID == itemID {
            activeContextMenuItemID = nil
        }
    }

    private var compactFilterSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Menu {
                    Picker("Sort", selection: $selectedSort) {
                        ForEach(TransactionSortOption.allCases) {
                            Text($0.title).tag($0)
                        }
                    }
                } label: {
                    FilterControlLabel(
                        title: selectedSort.title,
                        icon: "arrow.up.arrow.down",
                        tint: appState.themePalette.accent
                    )
                }

                Menu {
                    Picker("Type", selection: $selectedType) {
                        ForEach(TransactionTypeFilter.allCases) {
                            Text($0.title).tag($0)
                        }
                    }
                } label: {
                    FilterControlLabel(
                        title: selectedType.title,
                        icon: "tray.full",
                        tint: appState.themePalette.accent
                    )
                }

                Spacer(minLength: 0)

                Button {
                    showingFilters = true
                } label: {
                    FilterControlLabel(
                        title: "Filters",
                        icon: hasActiveFilters
                            ? "line.3.horizontal.decrease.circle.fill"
                            : "line.3.horizontal.decrease.circle",
                        tint: appState.themePalette.accent
                    )
                }
                .buttonStyle(.plain)
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

    private func dayTotal(_ items: [LedgerListItem]) -> String {
        let transactions = items.compactMap(\.transaction)
        let income = transactions.filter(\.isPostedIncome).reduce(Int64(0)) { $0 + $1.amountMinor }
        let expenses = transactions.filter(\.isPostedExpense).reduce(Int64(0)) { $0 + $1.amountMinor }
        let net = income - expenses
        let amount = MoneyFormatter.string(
            minorUnits: abs(net),
            currencyCode: appState.selectedCurrencyCode
        )
        if net > 0 { return "+\(amount)" }
        if net < 0 { return "-\(amount)" }
        return amount
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
        if let selectedPersonID,
           let person = people.first(where: { $0.id == selectedPersonID }) {
            chips.append(TransactionFilterChip(title: person.name, kind: .person))
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
        .floatGlassSurface(
            cornerRadius: FloatTheme.controlRadius,
            material: .ultraThinMaterial,
            interactive: true,
            strokeOpacity: 0.08,
            shadowOpacity: 0.12,
            shadowRadius: 18,
            shadowY: 8
        )
    }

    private var transactionFiltersSheet: some View {
        TransactionFilterSheet(
            categories: categories,
            accounts: accounts,
            people: people,
            selectedCategoryID: $selectedCategoryID,
            selectedAccountID: $selectedAccountID,
            selectedPersonID: $selectedPersonID,
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
    }

    private var transactionFilterSheetHost: some View {
        TransactionFilterSheetHost(
            isPresented: $showingFilters,
            content: transactionFiltersSheet
        )
    }

    private func delete(_ transaction: TransactionItem) {
        deletedSnapshot = DeletedTransactionSnapshot(transaction: transaction)
        try? TransactionRepository(modelContext: modelContext)
            .delete(transaction)
        removeLoadedItem(id: "transaction-\(transaction.id.uuidString)")
        withAnimation { showingUndo = true }
    }

    private func delete(_ transfer: TransferItem) {
        try? TransferRepository(modelContext: modelContext).delete(transfer)
        removeLoadedItem(id: "transfer-\(transfer.id.uuidString)")
    }

    private func undoDelete() {
        guard let snapshot = deletedSnapshot else { return }
        modelContext.insert(snapshot.makeTransaction(
            categories: categories,
            accounts: accounts,
            events: events,
            people: people
        ))
        try? modelContext.save()
        resetAndLoadFirstPage()
        withAnimation { showingUndo = false }
        deletedSnapshot = nil
    }

    private func presentNewTransaction() {
        editingTransaction = nil
        editingTransactionInitialIsExpense = nil
        isEntrySheetPresented = true
    }

    private func presentEditTransaction(
        _ transaction: TransactionItem,
        initialIsExpense: Bool? = nil
    ) {
        editingTransaction = transaction
        editingTransactionInitialIsExpense = initialIsExpense
        isEntrySheetPresented = true
    }

    private func presentEditTransfer(_ transfer: TransferItem) {
        editingTransfer = transfer
        isTransferSheetPresented = true
    }

    private func resetAndLoadFirstPage() {
        ledgerItems = []
        nextPageEndDate = firstPageEndDate
        hasMorePages = true
        pageError = nil
        loadOlderPage()
    }

    private func loadOlderPage() {
        guard !isLoadingPage, hasMorePages else { return }
        isLoadingPage = true
        pageError = nil

        do {
            var accumulated: [LedgerListItem] = []
            var pageEnd = nextPageEndDate ?? firstPageEndDate
            var shouldContinue = true
            let lowerBound = try effectiveLowerPagingBound()

            while accumulated.isEmpty && shouldContinue {
                let window = pageWindow(endingAt: pageEnd)
                let fetched = try fetchLedgerItems(
                    from: window.start,
                    through: window.end
                )
                accumulated.append(contentsOf: fetched)

                guard let nextEnd = Calendar.current.date(
                    byAdding: .second,
                    value: -1,
                    to: window.start
                ) else {
                    shouldContinue = false
                    continue
                }

                pageEnd = nextEnd
                shouldContinue = window.start > lowerBound
            }

            mergeLoadedItems(accumulated)
            nextPageEndDate = pageEnd
            hasMorePages = shouldContinue
            isLoadingPage = false
        } catch {
            pageError = "Could not load older data"
            isLoadingPage = false
        }
    }

    private func loadOlderPageIfNeeded(afterDisplaying item: LedgerListItem) {
        guard shouldLoadOlderPage(afterDisplaying: item) else { return }
        loadOlderPage()
    }

    private func shouldLoadOlderPage(afterDisplaying item: LedgerListItem) -> Bool {
        guard hasMorePages, !isLoadingPage, pageError == nil else { return false }

        let triggerItems = selectedSort == .oldestFirst
            ? filtered.prefix(5)
            : filtered.suffix(5)
        return triggerItems.contains { $0.id == item.id }
    }

    private var firstPageEndDate: Date {
        if useDateRange {
            return Calendar.current.endOfDay(for: endDate)
        }
        return Date()
    }

    private var lowerPagingBound: Date {
        if useDateRange {
            return Calendar.current.startOfDay(for: startDate)
        }
        return .distantPast
    }

    private func pageWindow(endingAt end: Date) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let endOfPage = min(end, firstPageEndDate)
        let startCandidate = calendar.startOfDay(
            for: calendar.date(byAdding: .day, value: -14, to: endOfPage) ?? endOfPage
        )
        return (max(startCandidate, lowerPagingBound), endOfPage)
    }

    private func effectiveLowerPagingBound() throws -> Date {
        if useDateRange {
            return Calendar.current.startOfDay(for: startDate)
        }

        let dates = try [
            oldestTransactionDate(),
            oldestTransferDate(),
        ].compactMap { $0 }

        guard let oldest = dates.min() else {
            return Calendar.current.startOfDay(for: firstPageEndDate)
        }
        return Calendar.current.startOfDay(for: oldest)
    }

    private func fetchLedgerItems(from start: Date, through end: Date) throws
        -> [LedgerListItem]
    {
        let transactions = try fetchTransactions(from: start, through: end)
            .filter(matchesTransaction)
            .map(LedgerListItem.transaction)
        let transfers = try fetchTransfers(from: start, through: end)
            .filter(matchesTransfer)
            .map(LedgerListItem.transfer)
        return (transactions + transfers).sorted { $0.timestamp > $1.timestamp }
    }

    private func fetchTransactions(from start: Date, through end: Date) throws
        -> [TransactionItem]
    {
        let minAmount = minimumAmountMinor
        let maxAmount = maximumAmountMinor
        let includeExpenses = selectedType == .all || selectedType == .expenses
        let includeIncome = selectedType == .all || selectedType == .income
        let includePending = selectedType == .all || selectedType == .pending
        guard includeExpenses || includeIncome || includePending else { return [] }

        let descriptor = FetchDescriptor<TransactionItem>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        return filterActiveProfile(try modelContext.fetch(descriptor)).filter { transaction in
            let displayDate = transaction.displayDate
            let matchesDate = displayDate >= start && displayDate <= end
            let matchesAmount = (minAmount == nil || transaction.amountMinor >= minAmount!)
                && (maxAmount == nil || transaction.amountMinor <= maxAmount!)
            let matchesType =
                (includeExpenses && transaction.isPostedExpense)
                || (includeIncome && transaction.isPostedIncome)
                || (includePending && transaction.isPending)
            return matchesDate && matchesAmount && matchesType
        }
    }

    private func oldestTransactionDate() throws -> Date? {
        let includeExpenses = selectedType == .all || selectedType == .expenses
        let includeIncome = selectedType == .all || selectedType == .income
        let includePending = selectedType == .all || selectedType == .pending
        guard includeExpenses || includeIncome || includePending else { return nil }

        var descriptor = FetchDescriptor<TransactionItem>(
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )
        descriptor.fetchLimit = 500
        return filterActiveProfile(try modelContext.fetch(descriptor))
            .filter {
                (includeExpenses && $0.isPostedExpense)
                    || (includeIncome && $0.isPostedIncome)
                    || (includePending && $0.isPending)
            }
            .map(\.displayDate)
            .min()
    }

    private func fetchTransfers(from start: Date, through end: Date) throws
        -> [TransferItem]
    {
        let minAmount = minimumAmountMinor
        let maxAmount = maximumAmountMinor
        guard selectedType == .all || selectedType == .transfers else { return [] }

        let descriptor = FetchDescriptor<TransferItem>(
            predicate: #Predicate<TransferItem> { transfer in
                transfer.timestamp >= start
                    && transfer.timestamp <= end
                    && (minAmount == nil || transfer.amountMinor >= minAmount!)
                    && (maxAmount == nil || transfer.amountMinor <= maxAmount!)
            },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        return filterActiveProfile(try modelContext.fetch(descriptor))
    }

    private func oldestTransferDate() throws -> Date? {
        guard selectedType == .all || selectedType == .transfers else { return nil }

        var descriptor = FetchDescriptor<TransferItem>(
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )
        descriptor.fetchLimit = 500
        return filterActiveProfile(try modelContext.fetch(descriptor)).first?.timestamp
    }

    private func matchesTransaction(_ transaction: TransactionItem) -> Bool {
        let matchesCategory =
            selectedCategoryID == nil
            || transaction.category?.id == selectedCategoryID
        let matchesAccount =
            selectedAccountID == nil
            || transaction.account?.id == selectedAccountID
        let matchesPerson =
            selectedPersonID == nil
            || transaction.personTags.contains(where: { $0.person?.id == selectedPersonID })
        let matchesPendingFilters = !transaction.isPending
            || (selectedCategoryID == nil && selectedAccountID == nil)
        return matchesCategory && matchesAccount && matchesPerson && matchesPendingFilters && matchesSearch(transaction)
    }

    private func matchesTransfer(_ transfer: TransferItem) -> Bool {
        let matchesCategory = selectedCategoryID == nil
        let matchesAccount =
            selectedAccountID == nil
            || transfer.fromAccount?.id == selectedAccountID
            || transfer.toAccount?.id == selectedAccountID
        return matchesCategory && matchesAccount && matchesSearch(transfer)
    }

    private func matchesSearch(_ transaction: TransactionItem) -> Bool {
        let query = normalizedSearchText
        guard !query.isEmpty else { return true }
        return (transaction.note ?? "").localizedCaseInsensitiveContains(query)
            || transaction.categoryName.localizedCaseInsensitiveContains(query)
            || transaction.accountName.localizedCaseInsensitiveContains(query)
            || (transaction.personSummary ?? "").localizedCaseInsensitiveContains(query)
            || transaction.timestamp.formatted(date: .abbreviated, time: .shortened)
                .localizedCaseInsensitiveContains(query)
            || MoneyFormatter.string(
                minorUnits: transaction.amountMinor,
                currencyCode: appState.selectedCurrencyCode
            )
            .localizedCaseInsensitiveContains(query)
    }

    private func matchesSearch(_ transfer: TransferItem) -> Bool {
        let query = normalizedSearchText
        guard !query.isEmpty else { return true }
        return (transfer.note ?? "").localizedCaseInsensitiveContains(query)
            || transfer.fromAccountName.localizedCaseInsensitiveContains(query)
            || transfer.toAccountName.localizedCaseInsensitiveContains(query)
            || transfer.timestamp.formatted(date: .abbreviated, time: .shortened)
                .localizedCaseInsensitiveContains(query)
            || MoneyFormatter.string(
                minorUnits: transfer.amountMinor,
                currencyCode: transfer.currencyCode
            )
            .localizedCaseInsensitiveContains(query)
    }

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func mergeLoadedItems(_ items: [LedgerListItem]) {
        var existingIDs = Set(ledgerItems.map(\.id))
        for item in items where !existingIDs.contains(item.id) {
            ledgerItems.append(item)
            existingIDs.insert(item.id)
        }
    }

    private func removeLoadedItem(id: String) {
        ledgerItems.removeAll { $0.id == id }
    }

    private func clearFilters() {
        selectedCategoryID = nil
        selectedAccountID = nil
        selectedPersonID = nil
        selectedType = .all
        useDateRange = false
        minimumAmountText = ""
        maximumAmountText = ""
    }

    private func processSpotlightRequest(_ request: FloatSpotlightNavigationRequest?) {
        guard let request else { return }

        switch request.target.kind {
        case .transaction:
            if let transaction = fetchTransaction(id: request.target.id) {
                presentEditTransaction(transaction)
            }
            appState.consumeSpotlightRequest(request)
        case .transfer:
            if let transfer = fetchTransfer(id: request.target.id) {
                presentEditTransfer(transfer)
            }
            appState.consumeSpotlightRequest(request)
        case .account, .category, .people, .goal, .settlement, .template, .recurring:
            break
        }
    }

    private func fetchTransaction(id: UUID) -> TransactionItem? {
        let descriptor = FetchDescriptor<TransactionItem>(
            predicate: #Predicate<TransactionItem> { transaction in
                transaction.id == id
            }
        )
        return filterActiveProfile((try? modelContext.fetch(descriptor)) ?? []).first
    }

    private func fetchTransfer(id: UUID) -> TransferItem? {
        let descriptor = FetchDescriptor<TransferItem>(
            predicate: #Predicate<TransferItem> { transfer in
                transfer.id == id
            }
        )
        return filterActiveProfile((try? modelContext.fetch(descriptor)) ?? []).first
    }

    private func loadInitialState() {
        resetAndLoadFirstPage()
        handleSpotlightRequestChange()
    }

    private func handleSpotlightRequestChange() {
        let request = appState.pendingSpotlightRequest
        processSpotlightRequest(request)
    }

    private func removeFilter(_ kind: TransactionFilterChip.Kind) {
        switch kind {
        case .type:
            selectedType = .all
        case .category:
            selectedCategoryID = nil
        case .account:
            selectedAccountID = nil
        case .person:
            selectedPersonID = nil
        case .dateRange:
            useDateRange = false
        case .minimumAmount:
            minimumAmountText = ""
        case .maximumAmount:
            maximumAmountText = ""
        }
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
}

private struct TransactionFilterSheetHost<Content: View>: View {
    @Binding var isPresented: Bool
    let content: Content

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .sheet(isPresented: $isPresented) {
                AnyView(
                    content
                        .presentationDetents([.large])
                        .presentationDragIndicator(.visible)
                )
            }
    }
}

private struct FilterControlLabel: View {
    let title: String
    let icon: String
    let tint: Color

    var body: some View {
        Label(title, systemImage: icon)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 2)
            .padding(.vertical, 8)
    }
}

extension View {
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

private enum TransactionTypeFilter: String, CaseIterable, Identifiable {
    case all
    case expenses
    case income
    case pending
    case transfers

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .expenses: "Expenses"
        case .income: "Income"
        case .pending: "Pending"
        case .transfers: "Transfers"
        }
    }
}

private enum LedgerListItem: Identifiable {
    case transaction(TransactionItem)
    case transfer(TransferItem)

    var id: String {
        switch self {
        case .transaction(let transaction): "transaction-\(transaction.id.uuidString)"
        case .transfer(let transfer): "transfer-\(transfer.id.uuidString)"
        }
    }

    var timestamp: Date {
        switch self {
        case .transaction(let transaction): transaction.displayDate
        case .transfer(let transfer): transfer.timestamp
        }
    }

    var amountMinor: Int64 {
        switch self {
        case .transaction(let transaction): transaction.amountMinor
        case .transfer(let transfer): transfer.amountMinor
        }
    }

    var transaction: TransactionItem? {
        if case .transaction(let transaction) = self { return transaction }
        return nil
    }
}

private enum TransactionSortOption: String, CaseIterable, Identifiable {
    case newestFirst
    case oldestFirst

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newestFirst: "Newest first"
        case .oldestFirst: "Oldest first"
        }
    }
}

private struct TransactionFilterChip: Identifiable {
    let id = UUID()
    let title: String
    let kind: Kind

    enum Kind {
        case type
        case category
        case account
        case person
        case dateRange
        case minimumAmount
        case maximumAmount
    }
}

private struct TransactionFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    let categories: [CategoryItem]
    let accounts: [AccountItem]
    let people: [PersonItem]
    @Binding var selectedCategoryID: UUID?
    @Binding var selectedAccountID: UUID?
    @Binding var selectedPersonID: UUID?
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

                            menuRow(
                                title: "People",
                                value: selectedPersonName,
                                icon: "person.2.fill"
                            ) {
                                Picker("People", selection: $selectedPersonID) {
                                    Text("All people").tag(UUID?.none)
                                    ForEach(people) {
                                        Text($0.name).tag(Optional($0.id))
                                    }
                                }
                            }

                            Divider()

                            Toggle(isOn: $useDateRange) {
                                filterRowLabel(title: "Date range", icon: "calendar")
                            }
                            .tint(appState.themePalette.accent)
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

                }
                .padding(20)
                .padding(.bottom, 156)
            }
            .safeAreaInset(edge: .bottom) {
                FilterActionBar(
                    accent: appState.themePalette.accent,
                    hasActiveFilters: hasActiveFilters,
                    clearFilters: clearFilters,
                    done: { dismiss() }
                )
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDismissControls()
            .scrollContentBackground(.hidden)
            .floatBackground()
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

    private var selectedPersonName: String {
        guard let selectedPersonID,
              let person = people.first(where: { $0.id == selectedPersonID })
        else {
            return "All people"
        }
        return person.name
    }

    private func filterSection<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                FloatIconBadge(icon: icon, tint: appState.themePalette.accent, size: 30)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(appState.themePalette.accent)
            }
            content()
                .padding(.vertical, 2)
        }
    }

    private func filterRowLabel(title: String, icon: String) -> some View {
        HStack(spacing: 12) {
            FloatIconBadge(icon: icon, tint: appState.themePalette.accent, size: 34)
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
            FloatIconBadge(icon: icon, tint: appState.themePalette.accent, size: 34)
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
                        .foregroundStyle(appState.themePalette.accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(appState.themePalette.accent)
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

private struct FilterActionBar: View {
    let accent: Color
    let hasActiveFilters: Bool
    let clearFilters: () -> Void
    let done: () -> Void
    private let actionShape = RoundedRectangle(cornerRadius: 25, style: .continuous)

    var body: some View {
        HStack(spacing: 10) {
            Button(action: clearFilters) {
                Label("Clear", systemImage: "xmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .contentShape(actionShape)
            }
            .buttonStyle(.plain)
            .disabled(!hasActiveFilters)

            Button(action: done) {
                Label("Done", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(accent, in: actionShape)
                    .overlay(
                        actionShape
                            .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                    )
                    .shadow(color: accent.opacity(0.24), radius: 16, y: 8)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 10)
    }

}

    private struct DeletedTransactionSnapshot {
        struct PersonTagSnapshot {
            let personID: UUID
            let sortOrder: Int
            let allocatedMinor: Int64?
            let settledMinor: Int64
        }

        let id: UUID
        let amountMinor: Int64
        let isExpense: Bool
        let statusRaw: String
        let timestamp: Date
        let expectedDueDate: Date?
        let categoryID: UUID?
        let accountID: UUID?
        let eventID: UUID?
        let note: String?
        let personTags: [PersonTagSnapshot]
        let createdAt: Date
        let updatedAt: Date

        init(transaction: TransactionItem) {
            id = transaction.id
            amountMinor = transaction.amountMinor
            isExpense = transaction.isExpense
            statusRaw = transaction.statusRaw
            timestamp = transaction.timestamp
            expectedDueDate = transaction.expectedDueDate
            categoryID = transaction.category?.id
            accountID = transaction.account?.id
            eventID = transaction.event?.id
            note = transaction.note
            personTags = transaction.personTags.compactMap { tag in
                guard let personID = tag.person?.id else { return nil }
                return PersonTagSnapshot(
                    personID: personID,
                    sortOrder: tag.sortOrder,
                    allocatedMinor: tag.allocatedMinor,
                    settledMinor: tag.settledMinor
                )
            }
            createdAt = transaction.createdAt
            updatedAt = transaction.updatedAt
        }

        func makeTransaction(
            categories: [CategoryItem],
            accounts: [AccountItem],
            events: [EventItem],
            people: [PersonItem]
        ) -> TransactionItem {
            let transaction = TransactionItem(
                id: id,
                amountMinor: amountMinor,
                isExpense: isExpense,
                status: TransactionStatus(rawValue: statusRaw) ?? .posted,
                timestamp: timestamp,
                expectedDueDate: expectedDueDate,
                category: categoryID.flatMap { id in
                    categories.first { $0.id == id }
                },
                account: accountID.flatMap { id in
                    accounts.first { $0.id == id }
                },
                event: eventID.flatMap { id in
                    events.first { $0.id == id }
                },
                note: note,
                createdAt: createdAt,
                updatedAt: updatedAt
            )
            let resolvedPeople = personTags.compactMap { snapshot in
                people.first { $0.id == snapshot.personID }
            }
            transaction.replacePeople(resolvedPeople)
            return transaction
        }
    }

private extension Calendar {
    func endOfDay(for date: Date) -> Date {
        let start = startOfDay(for: date)
        return self.date(
            byAdding: DateComponents(day: 1, second: -1),
            to: start
        ) ?? date
    }
}
