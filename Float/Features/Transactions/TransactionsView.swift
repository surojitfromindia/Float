import SwiftData
import SwiftUI

struct TransactionsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @Query(sort: \TransactionItem.timestamp, order: .reverse) private
        var transactions: [TransactionItem]
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

    private var filtered: [TransactionItem] {
        let filteredTransactions = transactions.filter { transaction in
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

        switch selectedSort {
        case .newestFirst:
            return filteredTransactions.sorted { $0.timestamp > $1.timestamp }
        case .oldestFirst:
            return filteredTransactions.sorted { $0.timestamp < $1.timestamp }
        case .highestAmount:
            return filteredTransactions.sorted { $0.amountMinor > $1.amountMinor }
        case .lowestAmount:
            return filteredTransactions.sorted { $0.amountMinor < $1.amountMinor }
        }
    }

    private var grouped: [(Date, [TransactionItem])] {
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
        List {
            compactFilterSection
            if filtered.isEmpty {
                EmptyStateView(
                    icon: "list.bullet.rectangle",
                    title: "No matching transactions",
                    message:
                        "Your transactions will appear here as you add them."
                )
            } else {
                ForEach(grouped, id: \.0) { day, items in
                    Section(day.formatted(date: .complete, time: .omitted)) {
                        ForEach(items) { transaction in
                            Button {
                                appState.presentEditTransaction(transaction)
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
                        }
                    }
                }
            }
        }
        .navigationTitle("Transactions")
        .searchable(text: $searchText, prompt: "Search notes, accounts, amounts")
        .keyboardDismissControls()
        .scrollContentBackground(.hidden)
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
                clearFilters: clearFilters
            )
        }
    }

    private var compactFilterSection: some View {
        Section {
            HStack(spacing: 10) {
                Menu {
                    Picker("Sort", selection: $selectedSort) {
                        ForEach(TransactionSortOption.allCases) {
                            Text($0.title).tag($0)
                        }
                    }
                } label: {
                    Label(selectedSort.title, systemImage: "arrow.up.arrow.down")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                }

                Menu {
                    Picker("Type", selection: $selectedType) {
                        ForEach(TransactionTypeFilter.allCases) {
                            Text($0.title).tag($0)
                        }
                    }
                } label: {
                    Label(selectedType.title, systemImage: "tray.full")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Button {
                    showingFilters = true
                } label: {
                    Label("Filters", systemImage: hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                        .font(.subheadline.weight(.semibold))
                }
            }

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
                                .background(Color.primary.opacity(0.08), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }

                        Button("Clear", action: clearFilters)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.primary.opacity(0.08), in: Capsule())
                    }
                }
            }
        }
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
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
        .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
    }

    private func delete(_ transaction: TransactionItem) {
        deletedSnapshot = DeletedTransactionSnapshot(transaction: transaction)
        try? TransactionRepository(modelContext: modelContext)
            .delete(transaction)
        withAnimation { showingUndo = true }
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

private enum TransactionTypeFilter: String, CaseIterable, Identifiable {
    case all
    case expenses
    case income

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .expenses: "Expenses"
        case .income: "Income"
        }
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

    var body: some View {
        NavigationStack {
            Form {
                Section("Type") {
                    Picker("Type", selection: $selectedType) {
                        ForEach(TransactionTypeFilter.allCases) {
                            Text($0.title).tag($0)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Category") {
                    Picker("Category", selection: $selectedCategoryID) {
                        Text("All categories").tag(UUID?.none)
                        ForEach(categories.filter { !$0.archived }) {
                            Text($0.name).tag(Optional($0.id))
                        }
                    }
                }

                Section("Account") {
                    Picker("Account", selection: $selectedAccountID) {
                        Text("All accounts").tag(UUID?.none)
                        ForEach(accounts.filter { !$0.archived }) {
                            Text($0.name).tag(Optional($0.id))
                        }
                    }
                }

                Section("Date") {
                    Toggle("Date range", isOn: $useDateRange)
                    if useDateRange {
                        DatePicker("From", selection: $startDate, displayedComponents: .date)
                        DatePicker("To", selection: $endDate, displayedComponents: .date)
                    }
                }

                Section("Amount") {
                    TextField("Min amount", text: $minimumAmountText)
                        .keyboardType(.decimalPad)
                    TextField("Max amount", text: $maximumAmountText)
                        .keyboardType(.decimalPad)
                }

                if hasActiveFilters {
                    Section {
                        Button("Clear filters", action: clearFilters)
                    }
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDismissControls()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
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
