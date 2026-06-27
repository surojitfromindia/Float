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

                actionSection(for: issue)
            }
        }
    }

    @ViewBuilder
    private func actionSection(for issue: ReviewIssue) -> some View {
        let showsTemplate = canCreateTemplate(from: issue.transaction)

        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                reviewActionButton(
                    title: "Edit",
                    systemImage: "pencil",
                    tint: appState.themePalette.accent
                ) {
                    editingTransaction = issue.transaction
                }

                if showsTemplate {
                    reviewActionButton(
                        title: "Template",
                        systemImage: "square.text.square",
                        tint: Color(hex: "#5A6B6B")
                    ) {
                        createTemplate(from: issue.transaction)
                    }
                }

                reviewActionButton(
                    title: issue.resolveLabel,
                    systemImage: issue.resolveIcon,
                    tint: issue.tint
                ) {
                    resolve(issue)
                }

                reviewDeleteButton {
                    delete(issue.transaction)
                }
            }

            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    reviewActionButton(
                        title: "Edit",
                        systemImage: "pencil",
                        tint: appState.themePalette.accent
                    ) {
                        editingTransaction = issue.transaction
                    }

                    if showsTemplate {
                        reviewActionButton(
                            title: "Template",
                            systemImage: "square.text.square",
                            tint: Color(hex: "#5A6B6B")
                        ) {
                            createTemplate(from: issue.transaction)
                        }
                    }
                }

                HStack(spacing: 8) {
                    reviewActionButton(
                        title: issue.resolveLabel,
                        systemImage: issue.resolveIcon,
                        tint: issue.tint
                    ) {
                        resolve(issue)
                    }

                    reviewDeleteButton {
                        delete(issue.transaction)
                    }
                }
            }
        }
    }

    private func reviewActionButton(
        title: String,
        systemImage: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.9)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.horizontal, 14)
                .foregroundStyle(tint)
                .floatGlassSurface(
                    cornerRadius: FloatTheme.controlRadius,
                    tint: tint,
                    interactive: true,
                    strokeOpacity: 0.05
                )
        }
        .buttonStyle(.plain)
    }

    private func reviewDeleteButton(action: @escaping () -> Void) -> some View {
        Button(role: .destructive, action: action) {
            Image(systemName: "trash")
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 44, height: 44)
                .foregroundStyle(Color(hex: "#B4613B"))
                .floatGlassSurface(
                    cornerRadius: FloatTheme.controlRadius,
                    tint: Color(hex: "#B4613B"),
                    interactive: true,
                    strokeOpacity: 0.05
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Delete transaction")
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

    private func resolve(_ issue: ReviewIssue) {
        let repository = TransactionRepository(modelContext: modelContext)
        do {
            switch issue.kind {
            case .likelyDuplicate:
                guard let signature = issue.duplicateGroupSignature else { return }
                try repository.dismissDuplicateGroup(
                    signature: signature,
                    for: issue.transaction
                )
                showMessage(String(localized: "Marked as not a duplicate."))
            case .missingCategory, .missingAccount, .highValue:
                try repository.dismissReviewIssue(issue.kind, for: issue.transaction)
                showMessage(String(localized: "Marked resolved"))
            }
            Haptics.confirm()
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
    let id: String
    let kind: TransactionReviewIssueKind
    let transaction: TransactionItem
    let duplicateGroupSignature: String?

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
            String(localized: "This looks similar to another transaction within a few minutes.")
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

    var resolveLabel: String {
        switch kind {
        case .likelyDuplicate:
            String(localized: "Not a duplicate")
        case .missingCategory, .missingAccount, .highValue:
            String(localized: "Mark resolved")
        }
    }

    var resolveIcon: String {
        switch kind {
        case .likelyDuplicate:
            "checkmark.shield"
        case .missingCategory, .missingAccount, .highValue:
            "checkmark.circle"
        }
    }
}

private enum ReviewIssueBuilder {
    static func issues(for transactions: [TransactionItem]) -> [ReviewIssue] {
        var issues: [ReviewIssue] = []
        let duplicateGroupSignatures = TransactionDuplicateDetector
            .duplicateGroupSignaturesByTransactionID(in: transactions)
        let highValueThreshold = highValueMinorThreshold(for: transactions)

        for transaction in transactions.prefix(250) {
            if transaction.category == nil,
               !transaction.isReviewIssueDismissed(.missingCategory) {
                issues.append(issue(.missingCategory, transaction: transaction))
            }
            if transaction.account == nil,
               !transaction.isReviewIssueDismissed(.missingAccount) {
                issues.append(issue(.missingAccount, transaction: transaction))
            }
            if let duplicateGroupSignature = duplicateGroupSignatures[transaction.id] {
                issues.append(
                    issue(
                        .likelyDuplicate,
                        transaction: transaction,
                        duplicateGroupSignature: duplicateGroupSignature
                    )
                )
            }
            if transaction.amountMinor >= highValueThreshold,
               !transaction.isReviewIssueDismissed(.highValue) {
                issues.append(issue(.highValue, transaction: transaction))
            }
        }

        return Array(issues.prefix(40))
    }

    private static func issue(
        _ kind: TransactionReviewIssueKind,
        transaction: TransactionItem,
        duplicateGroupSignature: String? = nil
    ) -> ReviewIssue {
        ReviewIssue(
            id: "\(transaction.id.uuidString)-\(kind)",
            kind: kind,
            transaction: transaction,
            duplicateGroupSignature: duplicateGroupSignature
        )
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
