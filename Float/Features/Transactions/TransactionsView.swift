import SwiftData
import SwiftUI

struct TransactionsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @Query(sort: \TransactionItem.timestamp, order: .reverse) private
        var transactions: [TransactionItem]
    @Query(sort: \TransferItem.timestamp, order: .reverse) private
        var transfers: [TransferItem]
    @Query(sort: \CategoryItem.sortOrder) private var categories: [CategoryItem]
    @Query(sort: \AccountItem.createdAt) private var accounts: [AccountItem]
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

    private var filteredTransactions: [TransactionItem] {
        transactions.filter { transaction in
            let matchesSearch =
                searchText.isEmpty
                || (transaction.note ?? "").localizedCaseInsensitiveContains(
                    searchText
                )
                || transaction.categoryName
                    .localizedCaseInsensitiveContains(searchText)
                || transaction.accountName
                    .localizedCaseInsensitiveContains(searchText)
                || transaction.timestamp.formatted(date: .abbreviated, time: .shortened)
                    .localizedCaseInsensitiveContains(searchText)
                || MoneyFormatter.string(
                    minorUnits: transaction.amountMinor,
                    currencyCode: appState.selectedCurrencyCode
                )
                .localizedCaseInsensitiveContains(searchText)
            let matchesCategory =
                selectedCategoryID == nil
                || transaction.category?.id == selectedCategoryID
            let matchesAccount =
                selectedAccountID == nil
                || transaction.account?.id == selectedAccountID
            let matchesType: Bool
            switch selectedType {
            case .all:
                matchesType = true
            case .expenses:
                matchesType = transaction.isExpense
            case .income:
                matchesType = !transaction.isExpense
            case .transfers:
                matchesType = false
            }
            let matchesDate =
                !useDateRange
                || (
                    Calendar.current.startOfDay(for: startDate)
                        <= transaction.timestamp
                        && transaction.timestamp
                            <= Calendar.current.endOfDay(for: endDate)
                )
            let matchesMinimum =
                minimumAmountMinor == nil
                || transaction.amountMinor >= (minimumAmountMinor ?? 0)
            let matchesMaximum =
                maximumAmountMinor == nil
                || transaction.amountMinor <= (maximumAmountMinor ?? Int64.max)
            return matchesSearch && matchesCategory && matchesAccount
                && matchesType && matchesDate && matchesMinimum && matchesMaximum
        }
    }

    private var filteredTransfers: [TransferItem] {
        transfers.filter { transfer in
            let matchesSearch =
                searchText.isEmpty
                || (transfer.note ?? "").localizedCaseInsensitiveContains(searchText)
                || transfer.fromAccountName.localizedCaseInsensitiveContains(searchText)
                || transfer.toAccountName.localizedCaseInsensitiveContains(searchText)
                || transfer.timestamp.formatted(date: .abbreviated, time: .shortened)
                    .localizedCaseInsensitiveContains(searchText)
                || MoneyFormatter.string(
                    minorUnits: transfer.amountMinor,
                    currencyCode: transfer.currencyCode
                )
                .localizedCaseInsensitiveContains(searchText)
            let matchesCategory = selectedCategoryID == nil
            let matchesAccount =
                selectedAccountID == nil
                || transfer.fromAccount?.id == selectedAccountID
                || transfer.toAccount?.id == selectedAccountID
            let matchesType = selectedType == .all || selectedType == .transfers
            let matchesDate =
                !useDateRange
                || (
                    Calendar.current.startOfDay(for: startDate)
                        <= transfer.timestamp
                        && transfer.timestamp
                            <= Calendar.current.endOfDay(for: endDate)
                )
            let matchesMinimum =
                minimumAmountMinor == nil
                || transfer.amountMinor >= (minimumAmountMinor ?? 0)
            let matchesMaximum =
                maximumAmountMinor == nil
                || transfer.amountMinor <= (maximumAmountMinor ?? Int64.max)
            return matchesSearch && matchesCategory && matchesAccount
                && matchesType && matchesDate && matchesMinimum && matchesMaximum
        }
    }

    private var filtered: [LedgerListItem] {
        let filteredItems =
            filteredTransactions.map(LedgerListItem.transaction)
            + filteredTransfers.map(LedgerListItem.transfer)

        switch selectedSort {
        case .newestFirst:
            return filteredItems.sorted { $0.timestamp > $1.timestamp }
        case .oldestFirst:
            return filteredItems.sorted { $0.timestamp < $1.timestamp }
        case .highestAmount:
            return filteredItems.sorted { $0.amountMinor > $1.amountMinor }
        case .lowestAmount:
            return filteredItems.sorted { $0.amountMinor < $1.amountMinor }
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

    private var filteredExpenseMinor: Int64 {
        filteredTransactions.filter(\.isExpense).reduce(Int64(0)) { $0 + $1.amountMinor }
    }

    private var filteredIncomeMinor: Int64 {
        filteredTransactions.filter { !$0.isExpense }.reduce(Int64(0)) { $0 + $1.amountMinor }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                transactionSummary
                compactFilterSection

                if filtered.isEmpty {
                    GlassCard {
                        EmptyStateView(
                            icon: "list.bullet.rectangle",
                            title: "No matching transactions",
                            message:
                                "Your transactions will appear here as you add them."
                        )
                    }
                } else {
                    ForEach(grouped, id: \.0) { day, items in
                        transactionSection(day: day, items: items)
                    }
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
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    appState.presentNewTransaction()
                } label: {
                    Image(systemName: "plus")
                }
            }
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
    }

    private var transactionSummary: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    SummaryMetricTile(
                        title: "Income",
                        value: MoneyFormatter.string(
                            minorUnits: filteredIncomeMinor,
                            currencyCode: appState.selectedCurrencyCode,
                            showsSign: filteredIncomeMinor > 0
                        ),
                        caption: "\(filteredTransactions.filter { !$0.isExpense }.count) entries",
                        icon: "arrow.down.circle.fill",
                        tint: appState.themePalette.positive
                    )
                    SummaryMetricTile(
                        title: "Expenses",
                        value: MoneyFormatter.string(
                            minorUnits: filteredExpenseMinor,
                            currencyCode: appState.selectedCurrencyCode
                        ),
                        caption: "\(filteredTransactions.filter(\.isExpense).count) entries",
                        icon: "arrow.up.circle.fill",
                        tint: appState.themePalette.caution
                    )
                }

                HStack {
                    Label("\(filtered.count) shown", systemImage: "list.bullet.rectangle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(netText)
                        .moneyStyle(size: 14, weight: .semibold)
                        .foregroundStyle(netMinor >= 0 ? appState.themePalette.positive : appState.themePalette.caution)
                }
            }
        }
    }

    private var netMinor: Int64 {
        filteredIncomeMinor - filteredExpenseMinor
    }

    private var netText: String {
        let amount = MoneyFormatter.string(
            minorUnits: abs(netMinor),
            currencyCode: appState.selectedCurrencyCode
        )
        if netMinor > 0 { return "+\(amount)" }
        if netMinor < 0 { return "-\(amount)" }
        return amount
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

            GlassCard(padding: 14) {
                VStack(spacing: 6) {
                    ForEach(items) { item in
                        switch item {
                        case .transaction(let transaction):
                            Button {
                                appState.presentEditTransaction(transaction)
                            } label: {
                                TransactionRowView(
                                    transaction: transaction,
                                    currencyCode: appState.selectedCurrencyCode
                                )
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) {
                                    delete(transaction)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        case .transfer(let transfer):
                            Button {
                                appState.presentEditTransfer(transfer)
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
                        }
                        if item.id != items.last?.id {
                            Divider()
                        }
                    }
                }
            }
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
            .padding(10)
            .background(
                .thinMaterial,
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
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )

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
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    Color.primary.opacity(0.08),
                                    in: RoundedRectangle(
                                        cornerRadius: FloatTheme.tileRadius,
                                        style: .continuous
                                    )
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        Button("Clear", action: clearFilters)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Color.primary.opacity(0.08),
                                in: RoundedRectangle(
                                    cornerRadius: FloatTheme.tileRadius,
                                    style: .continuous
                                )
                            )
                    }
                }
            }
        }
    }

    private func dayTotal(_ items: [LedgerListItem]) -> String {
        let transactions = items.compactMap(\.transaction)
        let income = transactions.filter { !$0.isExpense }.reduce(Int64(0)) { $0 + $1.amountMinor }
        let expenses = transactions.filter(\.isExpense).reduce(Int64(0)) { $0 + $1.amountMinor }
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
        .background(
            .ultraThinMaterial,
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
            .strokeBorder(Color.primary.opacity(0.08))
        )
        .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
    }

    private func delete(_ transaction: TransactionItem) {
        deletedSnapshot = DeletedTransactionSnapshot(transaction: transaction)
        try? TransactionRepository(modelContext: modelContext)
            .delete(transaction)
        withAnimation { showingUndo = true }
    }

    private func delete(_ transfer: TransferItem) {
        try? TransferRepository(modelContext: modelContext).delete(transfer)
    }

    private func undoDelete() {
        guard let snapshot = deletedSnapshot else { return }
        modelContext.insert(snapshot.makeTransaction(
            categories: categories,
            accounts: accounts
        ))
        try? modelContext.save()
        withAnimation { showingUndo = false }
        deletedSnapshot = nil
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
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background(
                Color.primary.opacity(0.045),
                in: RoundedRectangle(
                    cornerRadius: FloatTheme.tileRadius,
                    style: .continuous
                )
            )
    }
}

private enum TransactionTypeFilter: String, CaseIterable, Identifiable {
    case all
    case expenses
    case income
    case transfers

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .expenses: "Expenses"
        case .income: "Income"
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
        case .transaction(let transaction): transaction.timestamp
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
    case highestAmount
    case lowestAmount

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newestFirst: "Newest first"
        case .oldestFirst: "Oldest first"
        case .highestAmount: "Highest amount"
        case .lowestAmount: "Lowest amount"
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
    let timestamp: Date
    let categoryID: UUID?
    let accountID: UUID?
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
            timestamp: timestamp,
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
