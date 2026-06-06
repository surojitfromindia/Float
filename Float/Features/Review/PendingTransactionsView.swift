import SwiftData
import SwiftUI

struct PendingTransactionsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @Query(sort: \TransactionItem.timestamp, order: .reverse) private var transactions:
        [TransactionItem]
    @State private var editingTransaction: TransactionItem?
    @State private var conversionInitialIsExpense: Bool?
    @State private var message: String?

    private var pendingTransactions: [TransactionItem] {
        transactions
            .filter(\.isPending)
            .sorted { $0.displayDate < $1.displayDate }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                if pendingTransactions.isEmpty {
                    EmptyStateView(
                        icon: "checkmark.seal.fill",
                        title: "No pending transactions",
                        message: "Expected income or expenses will appear here until they are converted."
                    )
                    .padding(20)
                    .floatGlassSurface(cornerRadius: FloatTheme.controlRadius)
                } else {
                    ForEach(pendingTransactions) { transaction in
                        pendingCard(transaction)
                    }
                }
            }
            .padding(20)
            .padding(.bottom, 40)
        }
        .navigationTitle("Pending")
        .floatBackground()
        .overlay(alignment: .bottom) {
            if let message {
                Text(message)
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.bottom, 14)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sheet(item: $editingTransaction, onDismiss: {
            conversionInitialIsExpense = nil
        }) { transaction in
            QuickAddKeypadSheet(
                transactionToEdit: transaction,
                initialIsExpense: conversionInitialIsExpense
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    private func pendingCard(_ transaction: TransactionItem) -> some View {
        GlassCard(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                TransactionRowView(
                    transaction: transaction,
                    currencyCode: appState.selectedCurrencyCode
                )

                HStack(spacing: 8) {
                    Button {
                        convert(transaction, isExpense: true)
                    } label: {
                        PendingConversionButton(
                            title: "Expense",
                            systemImage: "minus.circle",
                            tint: appState.themePalette.caution
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Convert to expense")

                    Button {
                        convert(transaction, isExpense: false)
                    } label: {
                        PendingConversionButton(
                            title: "Income",
                            systemImage: "plus.circle",
                            tint: appState.themePalette.positive
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Convert to income")

                    Button {
                        editingTransaction = transaction
                    } label: {
                        PendingIconButton(systemImage: "pencil", tint: appState.themePalette.accent)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Edit pending transaction")

                    Button(role: .destructive) {
                        delete(transaction)
                    } label: {
                        PendingIconButton(systemImage: "trash", tint: appState.themePalette.caution)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Delete pending transaction")
                }
            }
        }
    }

    private func convert(_ transaction: TransactionItem, isExpense: Bool) {
        conversionInitialIsExpense = isExpense
        editingTransaction = transaction
    }

    private func delete(_ transaction: TransactionItem) {
        do {
            try TransactionRepository(modelContext: modelContext).delete(transaction)
            showMessage("Pending transaction deleted.")
            Haptics.tick()
        } catch {
            showMessage(error.localizedDescription)
        }
    }

    private func showMessage(_ text: String) {
        withAnimation(.easeInOut(duration: 0.18)) {
            message = text
        }
        Task {
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.18)) {
                    if message == text {
                        message = nil
                    }
                }
            }
        }
    }
}

private struct PendingConversionButton: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .foregroundStyle(tint)
        .frame(maxWidth: .infinity, minHeight: 40)
        .padding(.horizontal, 10)
        .background(
            tint.opacity(0.12),
            in: Capsule(style: .continuous)
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(tint.opacity(0.14), lineWidth: 1)
        )
    }
}

private struct PendingIconButton: View {
    let systemImage: String
    let tint: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(tint)
            .frame(width: 40, height: 40)
            .background(
                tint.opacity(0.12),
                in: Circle()
            )
            .overlay(
                Circle()
                    .strokeBorder(tint.opacity(0.14), lineWidth: 1)
            )
    }
}
