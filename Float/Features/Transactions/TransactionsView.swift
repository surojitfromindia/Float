import SwiftData
import SwiftUI

struct TransactionsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @Query(sort: \CategoryItem.sortOrder) private var categories: [CategoryItem]
    @Query(sort: \AccountItem.createdAt) private var accounts: [AccountItem]
    @State private var ledgerItems: [LedgerListItem] = []
    @State private var nextPageEndDate: Date?
    @State private var isLoadingPage = false
    @State private var hasMorePages = true
    @State private var pageError: String?
    @State private var searchText = ""
    @State private var selectedCategoryID: UUID?
    @State private var selectedAccountID: UUID?
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
        selectedCategoryID != nil || selectedAccountID != nil
            || selectedType != .all || useDateRange
            || minimumAmountMinor != nil || maximumAmountMinor != nil
    }

    var body: some View {
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
        .navigationTitle("Transactions")
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
            }
        }
        .sheet(isPresented: $isEntrySheetPresented) {
            QuickAddKeypadSheet(
                transactionToEdit: editingTransaction,
                initialIsExpense: editingTransactionInitialIsExpense
            )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $splittingTransaction) { transaction in
            BulkTransactionEntrySheet(
                transactionToReplace: transaction,
                onCreate: { resetAndLoadFirstPage() }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isTransferSheetPresented) {
            TransferEditorSheet(transferToEdit: editingTransfer)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isBulkEntrySheetPresented) {
            BulkTransactionEntrySheet()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingFilters) {
            TransactionFilterSheet(
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
        .task {
            resetAndLoadFirstPage()
        }
        .onChange(of: searchText) { _, _ in resetAndLoadFirstPage() }
        .onChange(of: selectedCategoryID) { _, _ in resetAndLoadFirstPage() }
        .onChange(of: selectedAccountID) { _, _ in resetAndLoadFirstPage() }
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
            return "Your transactions will appear here as you add them."
        }
        return "Try changing your search or filters."
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
                        }
                        .buttonStyle(.plain)
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
                                Label("Delete", systemImage: "trash")
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
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                delete(transfer)
                            } label: {
                                Label("Delete", systemImage: "trash")
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
            .transactionPlainSurface(cornerRadius: FloatTheme.controlRadius)
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
                        icon: "arrow.up.arrow.down"
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
                        icon: "tray.full"
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
                            : "line.3.horizontal.decrease.circle"
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
            accounts: accounts
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
        return try modelContext.fetch(descriptor).filter { transaction in
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
        return try modelContext.fetch(descriptor)
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
        return try modelContext.fetch(descriptor)
    }

    private func oldestTransferDate() throws -> Date? {
        guard selectedType == .all || selectedType == .transfers else { return nil }

        var descriptor = FetchDescriptor<TransferItem>(
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first?.timestamp
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
        return matchesCategory && matchesAccount && matchesPendingFilters && matchesSearch(transaction)
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
        case dateRange
        case minimumAmount
        case maximumAmount
    }
}

private struct TransactionFilterSheet: View {
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

                    filterSection(title: "Type", icon: "tray.full") {
                    Picker("Type", selection: $selectedType) {
                        ForEach(TransactionTypeFilter.allCases) {
                            Text($0.title).tag($0)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                    filterSection(title: "Category", icon: "square.grid.2x2.fill") {
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
                }

                    filterSection(title: "Account", icon: "wallet.pass.fill") {
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
                }

                    filterSection(title: "Date", icon: "calendar") {
                        Toggle("Date range", isOn: $useDateRange)
                            .font(.subheadline.weight(.semibold))
                        if useDateRange {
                            Divider()
                            DatePicker(
                                "From",
                                selection: $startDate,
                                displayedComponents: .date
                            )
                            DatePicker(
                                "To",
                                selection: $endDate,
                                displayedComponents: .date
                            )
                        }
                    }

                    filterSection(title: "Amount", icon: "dollarsign.circle.fill") {
                        VStack(spacing: 0) {
                            amountField("Min amount", text: $minimumAmountText)
                            Divider()
                            amountField("Max amount", text: $maximumAmountText)
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
            GlassCard {
                content()
            }
        }
    }

    private func menuRow<MenuContent: View>(
        title: String,
        value: String,
        icon: String,
        @ViewBuilder menuContent: () -> MenuContent
    ) -> some View {
        Menu {
            menuContent()
        } label: {
            HStack(spacing: 12) {
                FloatIconBadge(icon: icon, tint: Color(hex: "#0A6FAE"), size: 34)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(hex: "#0A6FAE"))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color(hex: "#0A6FAE"))
            }
        }
        .buttonStyle(.plain)
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
        .padding(.vertical, 8)
    }

    private func parsedAmount(_ text: String) -> Int64? {
        let parsed = BudgetAmountField.minorUnits(
            fromMajorAmount: text,
            currencyCode: currencyCode
        )
        return parsed > 0 ? parsed : nil
    }
}

private struct DeletedTransactionSnapshot {
    let id: UUID
    let amountMinor: Int64
    let isExpense: Bool
    let statusRaw: String
    let timestamp: Date
    let expectedDueDate: Date?
    let categoryID: UUID?
    let accountID: UUID?
    let note: String?
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
        note = transaction.note
        createdAt = transaction.createdAt
        updatedAt = transaction.updatedAt
    }

    func makeTransaction(
        categories: [CategoryItem],
        accounts: [AccountItem]
    ) -> TransactionItem {
        TransactionItem(
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
            note: note,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
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
