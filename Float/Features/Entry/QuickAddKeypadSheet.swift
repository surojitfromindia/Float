import SwiftData
import SwiftUI

struct QuickAddKeypadSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @Query(sort: \CategoryItem.sortOrder) private var categories: [CategoryItem]
    @Query(sort: \AccountItem.createdAt) private var accounts: [AccountItem]
    @Query(sort: \TransactionItem.timestamp, order: .reverse) private
        var transactions: [TransactionItem]

    let transactionToEdit: TransactionItem?
    @State private var keypadText = ""
    @State private var isExpense = true
    @State private var selectedCategory: CategoryItem?
    @State private var selectedAccount: AccountItem?
    @State private var note = ""
    @State private var timestamp = Date()
    @State private var validationMessage: String?

    private var amountMinor: Int64 {
        MoneyParser.parseMinorUnits(from: keypadText)
    }
    private var visibleCategories: [CategoryItem] {
        categories.filter { !$0.archived && $0.isIncome != isExpense }.prefix(8)
            .map { $0 }
    }
    private var recentCategories: [CategoryItem] {
        uniqueCategories(
            transactions.compactMap { transaction in
                guard transaction.isExpense == isExpense else { return nil }
                return transaction.category
            }
        )
        .prefix(6)
        .map { $0 }
    }
    private var mostUsedCategories: [CategoryItem] {
        let matching = transactions.filter { $0.isExpense == isExpense }
        let counts = Dictionary(grouping: matching.compactMap(\.category)) { $0.id }
            .mapValues(\.count)

        return categories
            .filter { !$0.archived && $0.isIncome != isExpense }
            .sorted {
                let lhsCount = counts[$0.id] ?? 0
                let rhsCount = counts[$1.id] ?? 0
                if lhsCount == rhsCount { return $0.sortOrder < $1.sortOrder }
                return lhsCount > rhsCount
            }
            .prefix(6)
            .map { $0 }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    Picker("Type", selection: $isExpense) {
                        Text("Expense").tag(true)
                        Text("Income").tag(false)
                    }
                    .pickerStyle(.segmented)

                    Text(
                        MoneyFormatter.string(
                            minorUnits: amountMinor,
                            currencyCode: appState.selectedCurrencyCode
                        )
                    )
                    .moneyStyle(size: 46, weight: .bold)
                    .contentTransition(.numericText())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)

                    keypad

                    categorySection

                    GlassCard {
                        VStack(spacing: 14) {
                            AccountPicker(
                                selectedAccount: $selectedAccount,
                                accounts: accounts.filter { !$0.archived }
                            )
                            Divider()
                            TextField("Note", text: $note, axis: .vertical)
                                .textFieldStyle(.plain)
                                .lineLimit(1...3)
                            DatePicker(
                                "Date",
                                selection: $timestamp,
                                displayedComponents: [.date, .hourAndMinute]
                            )
                        }
                    }

                    VStack(spacing: 10) {
                        if let validationMessage {
                            Text(validationMessage)
                                .font(.footnote)
                                .foregroundStyle(Color(hex: "#B4613B"))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityLabel(validationMessage)
                        }

                        Button(action: save) {
                            Label(
                                transactionToEdit == nil
                                    ? "Save transaction" : "Save changes",
                                systemImage: "checkmark.circle.fill"
                            )
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                amountMinor > 0
                                    ? Color(hex: "#0E7C7B")
                                    : Color.secondary.opacity(0.3),
                                in: RoundedRectangle(
                                    cornerRadius: 20,
                                    style: .continuous
                                )
                            )
                            .foregroundStyle(.white)
                        }
                        .disabled(amountMinor == 0)

                        if transactionToEdit != nil {
                            Button(role: .destructive, action: deleteTransaction) {
                                Label("Delete transaction", systemImage: "trash")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle(transactionToEdit == nil ? "Add" : "Edit")
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDismissControls()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
            .floatBackground()
            .onAppear(perform: configureDefaults)
        }
    }

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            categoryChips(title: "Recent", categories: recentCategories)
            categoryChips(title: "Most used", categories: mostUsedCategories)
            if recentCategories.isEmpty && mostUsedCategories.isEmpty {
                categoryChips(title: "Category", categories: visibleCategories)
            }
        }
    }

    @ViewBuilder
    private func categoryChips(
        title: String,
        categories: [CategoryItem]
    ) -> some View {
        if !categories.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: title)
                FlowLayout(spacing: 8) {
                    ForEach(categories) { category in
                        Button {
                            selectedCategory = category
                            validationMessage = nil
                            Haptics.tick()
                        } label: {
                            CategoryChip(
                                category: category,
                                isSelected: selectedCategory?.id == category.id
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var keypad: some View {
        let keys = [
            "1", "2", "3", "4", "5", "6", "7", "8", "9", "00", "0",
            "delete.left",
        ]
        return LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(), spacing: 10),
                count: 3
            ),
            spacing: 10
        ) {
            ForEach(keys, id: \.self) { key in
                Button {
                    if key == "delete.left" {
                        keypadText = MoneyParser.deleteLast(from: keypadText)
                    } else {
                        keypadText = MoneyParser.keypadText(
                            afterAppending: key,
                            to: keypadText
                        )
                    }
                    validationMessage = nil
                    Haptics.tick()
                } label: {
                    Group {
                        if key == "delete.left" {
                            Image(systemName: key)
                        } else {
                            Text(key)
                        }
                    }
                    .font(.title2.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 58)
                    .background(
                        .thinMaterial,
                        in: RoundedRectangle(
                            cornerRadius: 20,
                            style: .continuous
                        )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func configureDefaults() {
        guard keypadText.isEmpty else { return }
        if let transactionToEdit {
            keypadText = String(transactionToEdit.amountMinor)
            isExpense = transactionToEdit.isExpense
            selectedCategory = transactionToEdit.category
            selectedAccount = transactionToEdit.account
            note = transactionToEdit.note ?? ""
            timestamp = transactionToEdit.timestamp
            return
        }
        selectedCategory =
            categories.first {
                !$0.archived && $0.id.uuidString == appState.lastUsedCategoryID
            }
        selectedAccount =
            accounts.first {
                !$0.archived && $0.id.uuidString == appState.lastUsedAccountID
            }
    }

    private func save() {
        guard amountMinor > 0 else {
            validationMessage = "Enter an amount greater than zero."
            return
        }

        let cleanNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let category = selectedCategory ?? DefaultCategoryResolver.resolve(
            isExpense: isExpense,
            preferredID: appState.lastUsedCategoryID,
            categories: categories,
            modelContext: modelContext
        )
        let account = selectedAccount ?? DefaultAccountResolver.resolve(
            preferredID: appState.lastUsedAccountID,
            accounts: accounts,
            modelContext: modelContext,
            currencyCode: appState.selectedCurrencyCode
        )
        let repository = TransactionRepository(modelContext: modelContext)

        do {
            if let transactionToEdit {
                try repository.update(
                    transactionToEdit,
                    amountMinor: amountMinor,
                    isExpense: isExpense,
                    timestamp: timestamp,
                    category: category,
                    account: account,
                    note: cleanNote
                )
            } else {
                _ = try repository.create(
                    amountMinor: amountMinor,
                    isExpense: isExpense,
                    timestamp: timestamp,
                    category: category,
                    account: account,
                    note: cleanNote
                )
            }
            appState.lastUsedCategoryID = category.id.uuidString
            appState.lastUsedAccountID = account.id.uuidString
            Haptics.confirm()
            dismiss()
        } catch {
            validationMessage = error.localizedDescription
        }
    }

    private func deleteTransaction() {
        guard let transactionToEdit else { return }
        do {
            try TransactionRepository(modelContext: modelContext)
                .delete(transactionToEdit)
            Haptics.tick()
            dismiss()
        } catch {
            validationMessage = error.localizedDescription
        }
    }

    private func uniqueCategories(_ categories: [CategoryItem]) -> [CategoryItem] {
        var seen = Set<UUID>()
        return categories.filter { category in
            guard !category.archived, !seen.contains(category.id) else {
                return false
            }
            seen.insert(category.id)
            return true
        }
    }
}

struct FlowLayout<Content: View>: View {
    let spacing: CGFloat
    let content: Content

    init(spacing: CGFloat = 8, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: spacing) { content }
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 120), spacing: spacing)],
                spacing: spacing
            ) { content }
        }
    }
}
