import SwiftData
import SwiftUI

struct ReviewQueueView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @Query(sort: \TransactionItem.timestamp, order: .reverse) private var allTransactions:
        [TransactionItem]
    @Query(sort: \TransactionTemplateItem.createdAt, order: .reverse) private var allTemplates:
        [TransactionTemplateItem]
    @State private var editingTransaction: TransactionItem?
    @State private var message: String?

    private var transactions: [TransactionItem] { filterActiveProfile(allTransactions) }
    private var templates: [TransactionTemplateItem] { filterActiveProfile(allTemplates) }

    private var issues: [ReviewIssue] {
        ReviewIssueBuilder.issues(for: transactions.filter(\.isPosted))
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                if issues.isEmpty {
                    EmptyStateView(
                        icon: "checkmark.seal.fill",
                        title: "Nothing to review",
                        message: "Transactions with missing details, likely duplicates, or unusually high amounts will appear here."
                    )
                    .padding(20)
                    .floatGlassSurface(cornerRadius: FloatTheme.controlRadius)
                } else {
                    ForEach(issues) { issue in
                        reviewCard(issue)
                    }
                }
            }
            .padding(20)
            .padding(.bottom, 40)
        }
        .navigationTitle("Review Queue")
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
        .sheet(item: $editingTransaction) { transaction in
            QuickAddKeypadSheet(transactionToEdit: transaction)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    private func reviewCard(_ issue: ReviewIssue) -> some View {
        GlassCard(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    FloatIconBadge(
                        icon: issue.icon,
                        tint: issue.tint,
                        size: 36
                    )
                    VStack(alignment: .leading, spacing: 4) {
                        Text(issue.title)
                            .font(.headline)
                        Text(issue.message)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                TransactionRowView(
                    transaction: issue.transaction,
                    currencyCode: appState.selectedCurrencyCode
                )
                .padding(12)
                .floatGlassSurface(cornerRadius: FloatTheme.controlRadius)

                HStack(spacing: 8) {
                    Button {
                        editingTransaction = issue.transaction
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .buttonStyle(.bordered)

                    if canCreateTemplate(from: issue.transaction) {
                        Button {
                            createTemplate(from: issue.transaction)
                        } label: {
                            Label("Template", systemImage: "square.text.square")
                        }
                        .buttonStyle(.bordered)
                    }

                    Spacer()

                    Button(role: .destructive) {
                        delete(issue.transaction)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Delete transaction")
                }
            }
        }
    }

    private func canCreateTemplate(from transaction: TransactionItem) -> Bool {
        guard transaction.category != nil, transaction.account != nil else { return false }
        return !templates.contains {
            $0.amountMinor == transaction.amountMinor
                && $0.isExpense == transaction.isExpense
                && $0.category?.id == transaction.category?.id
                && $0.account?.id == transaction.account?.id
                && ($0.note ?? "") == (transaction.note ?? "")
        }
    }

    private func createTemplate(from transaction: TransactionItem) {
        guard let category = transaction.category, let account = transaction.account else {
            showMessage("Add category and account first.")
            return
        }

        do {
            _ = try TransactionTemplateRepository(modelContext: modelContext).create(
                title: transaction.note ?? category.name,
                amountMinor: transaction.amountMinor,
                isExpense: transaction.isExpense,
                category: category,
                account: account,
                note: transaction.note
            )
            showMessage("Template saved.")
            Haptics.confirm()
        } catch {
            showMessage(error.localizedDescription)
        }
    }

    private func delete(_ transaction: TransactionItem) {
        do {
            try TransactionRepository(modelContext: modelContext).delete(transaction)
            showMessage("Transaction deleted.")
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

private struct ReviewIssue: Identifiable {
    enum Kind {
        case missingCategory
        case missingAccount
        case likelyDuplicate
        case highValue
    }

    let id: String
    let kind: Kind
    let transaction: TransactionItem

    var title: String {
        switch kind {
        case .missingCategory: "Missing category"
        case .missingAccount: "Missing account"
        case .likelyDuplicate: "Likely duplicate"
        case .highValue: "Large transaction"
        }
    }

    var message: String {
        switch kind {
        case .missingCategory:
            "Add a category so reports and budgets stay accurate."
        case .missingAccount:
            "Assign an account so balances remain correct."
        case .likelyDuplicate:
            "This looks similar to another transaction on the same day."
        case .highValue:
            "Check this amount before it affects your safe-to-spend number."
        }
    }

    var icon: String {
        switch kind {
        case .missingCategory: "tag.slash.fill"
        case .missingAccount: "building.columns"
        case .likelyDuplicate: "doc.on.doc.fill"
        case .highValue: "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch kind {
        case .missingCategory, .missingAccount:
            Color(hex: "#B4613B")
        case .likelyDuplicate:
            Color(hex: "#8B5CF6")
        case .highValue:
            Color(hex: "#0E7C7B")
        }
    }
}

private enum ReviewIssueBuilder {
    static func issues(for transactions: [TransactionItem]) -> [ReviewIssue] {
        var issues: [ReviewIssue] = []
        let duplicateIDs = duplicateTransactionIDs(in: transactions)
        let highValueThreshold = highValueMinorThreshold(for: transactions)

        for transaction in transactions.prefix(250) {
            if transaction.category == nil {
                issues.append(issue(.missingCategory, transaction: transaction))
            }
            if transaction.account == nil {
                issues.append(issue(.missingAccount, transaction: transaction))
            }
            if duplicateIDs.contains(transaction.id) {
                issues.append(issue(.likelyDuplicate, transaction: transaction))
            }
            if transaction.amountMinor >= highValueThreshold {
                issues.append(issue(.highValue, transaction: transaction))
            }
        }

        return Array(issues.prefix(40))
    }

    private static func issue(
        _ kind: ReviewIssue.Kind,
        transaction: TransactionItem
    ) -> ReviewIssue {
        ReviewIssue(
            id: "\(transaction.id.uuidString)-\(kind)",
            kind: kind,
            transaction: transaction
        )
    }

    private static func duplicateTransactionIDs(in transactions: [TransactionItem]) -> Set<UUID> {
        var groups: [String: [TransactionItem]] = [:]
        let calendar = Calendar.current
        for transaction in transactions {
            let day = calendar.startOfDay(for: transaction.timestamp).timeIntervalSince1970
            let key = [
                transaction.amountMinor.description,
                transaction.isExpense.description,
                transaction.category?.id.uuidString ?? "none",
                transaction.account?.id.uuidString ?? "none",
                transaction.note ?? "",
                Int(day).description,
            ].joined(separator: "|")
            groups[key, default: []].append(transaction)
        }

        return groups.values.reduce(into: Set<UUID>()) { result, group in
            guard group.count > 1 else { return }
            group.dropFirst().forEach { result.insert($0.id) }
        }
    }

    private static func highValueMinorThreshold(for transactions: [TransactionItem]) -> Int64 {
        let expenses = transactions
            .filter(\.isPostedExpense)
            .map(\.amountMinor)
            .filter { $0 > 0 }
        guard !expenses.isEmpty else { return Int64.max }
        let average = expenses.reduce(Int64(0), +) / Int64(expenses.count)
        return max(average * 3, 10_000)
    }
}
