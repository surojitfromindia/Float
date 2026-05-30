import SwiftUI
import SwiftData

struct TransactionsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @Query(sort: \TransactionItem.timestamp, order: .reverse) private var transactions: [TransactionItem]
    @Query(sort: \CategoryItem.sortOrder) private var categories: [CategoryItem]
    @Query(sort: \AccountItem.createdAt) private var accounts: [AccountItem]
    @State private var searchText = ""
    @State private var selectedCategoryID: UUID?
    @State private var selectedAccountID: UUID?
    @State private var deletedTransaction: TransactionItem?

    private var filtered: [TransactionItem] {
        transactions.filter { transaction in
            let matchesSearch = searchText.isEmpty || (transaction.note ?? "").localizedCaseInsensitiveContains(searchText) || (transaction.category?.name ?? "").localizedCaseInsensitiveContains(searchText)
            let matchesCategory = selectedCategoryID == nil || transaction.category?.id == selectedCategoryID
            let matchesAccount = selectedAccountID == nil || transaction.account?.id == selectedAccountID
            return matchesSearch && matchesCategory && matchesAccount
        }
    }

    private var grouped: [(Date, [TransactionItem])] {
        Dictionary(grouping: filtered) { Calendar.current.startOfDay(for: $0.timestamp) }
            .map { ($0.key, $0.value.sorted { $0.timestamp > $1.timestamp }) }
            .sorted { $0.0 > $1.0 }
    }

    var body: some View {
        List {
            filterSection
            if filtered.isEmpty {
                EmptyStateView(icon: "list.bullet.rectangle", title: "No matching transactions", message: "Your transactions will appear here as you add them.")
                    .listRowBackground(Color.clear)
            } else {
                ForEach(grouped, id: \.0) { day, items in
                    Section(day.formatted(date: .complete, time: .omitted)) {
                        ForEach(items) { transaction in
                            Button { appState.presentEditTransaction(transaction) } label: {
                                TransactionRowView(transaction: transaction, currencyCode: appState.selectedCurrencyCode)
                            }
                            .buttonStyle(.plain)
                            .swipeActions {
                                Button(role: .destructive) {
                                    deletedTransaction = transaction
                                    modelContext.delete(transaction)
                                    try? modelContext.save()
                                } label: { Label("Delete", systemImage: "trash") }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Transactions")
        .searchable(text: $searchText, prompt: "Search notes or categories")
        .scrollContentBackground(.hidden)
        .floatBackground()
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { appState.presentNewTransaction() } label: { Image(systemName: "plus") } } }
    }

    private var filterSection: some View {
        Section {
            Picker("Category", selection: $selectedCategoryID) {
                Text("All categories").tag(UUID?.none)
                ForEach(categories.filter { !$0.archived }) { Text($0.name).tag(Optional($0.id)) }
            }
            Picker("Account", selection: $selectedAccountID) {
                Text("All accounts").tag(UUID?.none)
                ForEach(accounts.filter { !$0.archived }) { Text($0.name).tag(Optional($0.id)) }
            }
        }
    }
}
