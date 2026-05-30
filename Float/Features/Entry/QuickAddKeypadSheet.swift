import SwiftUI
import SwiftData

struct QuickAddKeypadSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @Query(sort: \CategoryItem.sortOrder) private var categories: [CategoryItem]
    @Query(sort: \AccountItem.createdAt) private var accounts: [AccountItem]

    let transactionToEdit: TransactionItem?
    @State private var keypadText = ""
    @State private var isExpense = true
    @State private var selectedCategory: CategoryItem?
    @State private var selectedAccount: AccountItem?
    @State private var note = ""
    @State private var timestamp = Date()

    private var amountMinor: Int64 { MoneyParser.parseMinorUnits(from: keypadText) }
    private var visibleCategories: [CategoryItem] { categories.filter { !$0.archived && $0.isIncome != isExpense }.prefix(8).map { $0 } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    Picker("Type", selection: $isExpense) {
                        Text("Expense").tag(true)
                        Text("Income").tag(false)
                    }
                    .pickerStyle(.segmented)

                    Text(MoneyFormatter.string(minorUnits: amountMinor, currencyCode: appState.selectedCurrencyCode))
                        .moneyStyle(size: 46, weight: .bold)
                        .contentTransition(.numericText())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)

                    keypad

                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Category")
                        FlowLayout(spacing: 8) {
                            ForEach(visibleCategories) { category in
                                Button {
                                    selectedCategory = category
                                    Haptics.tick()
                                } label: {
                                    CategoryChip(category: category, isSelected: selectedCategory?.id == category.id)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    GlassCard {
                        VStack(spacing: 12) {
                            AccountPicker(selectedAccount: $selectedAccount, accounts: accounts.filter { !$0.archived })
                            Divider()
                            TextField("Note", text: $note, axis: .vertical)
                                .textFieldStyle(.plain)
                            DatePicker("Date", selection: $timestamp, displayedComponents: [.date])
                        }
                    }

                    Button(action: save) {
                        Label(transactionToEdit == nil ? "Save transaction" : "Save changes", systemImage: "checkmark.circle.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(amountMinor > 0 ? Color(hex: "#0E7C7B") : Color.secondary.opacity(0.3), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .foregroundStyle(.white)
                    }
                    .disabled(amountMinor == 0)
                }
                .padding(20)
            }
            .navigationTitle(transactionToEdit == nil ? "Add" : "Edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .floatBackground()
            .onAppear(perform: configureDefaults)
        }
    }

    private var keypad: some View {
        let keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "00", "0", "delete.left"]
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
            ForEach(keys, id: \.self) { key in
                Button {
                    if key == "delete.left" {
                        keypadText = MoneyParser.deleteLast(from: keypadText)
                    } else {
                        keypadText = MoneyParser.keypadText(afterAppending: key, to: keypadText)
                    }
                    Haptics.tick()
                } label: {
                    Group {
                        if key == "delete.left" { Image(systemName: key) } else { Text(key) }
                    }
                    .font(.title2.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 58)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
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
        selectedCategory = categories.first { $0.id.uuidString == appState.lastUsedCategoryID } ?? categories.first { $0.name == "Other" && !$0.isIncome } ?? categories.first { !$0.isIncome }
        selectedAccount = accounts.first { $0.id.uuidString == appState.lastUsedAccountID } ?? accounts.first { !$0.archived }
    }

    private func save() {
        let cleanNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if let transactionToEdit {
            transactionToEdit.amountMinor = amountMinor
            transactionToEdit.isExpense = isExpense
            transactionToEdit.timestamp = timestamp
            transactionToEdit.category = selectedCategory
            transactionToEdit.account = selectedAccount
            transactionToEdit.note = cleanNote.isEmpty ? nil : cleanNote
            transactionToEdit.updatedAt = Date()
        } else {
            let transaction = TransactionItem(amountMinor: amountMinor, isExpense: isExpense, timestamp: timestamp, category: selectedCategory, account: selectedAccount, note: cleanNote.isEmpty ? nil : cleanNote)
            modelContext.insert(transaction)
        }
        appState.lastUsedCategoryID = selectedCategory?.id.uuidString ?? ""
        appState.lastUsedAccountID = selectedAccount?.id.uuidString ?? ""
        try? modelContext.save()
        Haptics.confirm()
        dismiss()
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
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: spacing)], spacing: spacing) { content }
        }
    }
}
