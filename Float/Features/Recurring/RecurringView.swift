import SwiftUI
import SwiftData

struct RecurringView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \RecurringRuleItem.nextRunDate) private var rules: [RecurringRuleItem]
    @State private var showingEditor = false
    @State private var editingRule: RecurringRuleItem?

    var body: some View {
        List {
            if rules.isEmpty {
                EmptyStateView(icon: "repeat", title: "No recurring rules", message: "Add predictable bills or income to keep Safe-to-Spend current.")
                    .listRowBackground(Color.clear)
            }
            ForEach(rules) { rule in
                Button { editingRule = rule; showingEditor = true } label: {
                    HStack {
                        Image(systemName: rule.isExpense ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                            .foregroundStyle(rule.isExpense ? Color(hex: "#B4613B") : Color(hex: "#1B8A5A"))
                        VStack(alignment: .leading) {
                            Text(rule.note?.isEmpty == false ? rule.note ?? "Recurring" : rule.category?.name ?? "Recurring")
                                .font(.headline)
                            Text("Next: \(rule.nextRunDate.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(rule.cadence.title).font(.caption.weight(.semibold))
                    }
                }
                .buttonStyle(.plain)
                .swipeActions {
                    Button(rule.active ? "Deactivate" : "Activate") { rule.active.toggle(); rule.updatedAt = Date(); try? modelContext.save() }
                }
            }
        }
        .navigationTitle("Recurring")
        .toolbar { Button { editingRule = nil; showingEditor = true } label: { Image(systemName: "plus") } }
        .sheet(isPresented: $showingEditor) { RecurringEditorView(rule: editingRule) }
        .onAppear { MaterializeRecurringTransactionsUseCase.run(modelContext: modelContext) }
    }
}

struct RecurringEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CategoryItem.sortOrder) private var categories: [CategoryItem]
    @Query(sort: \AccountItem.createdAt) private var accounts: [AccountItem]
    let rule: RecurringRuleItem?
    @State private var amountText = ""
    @State private var isExpense = true
    @State private var cadence: RecurringCadence = .monthly
    @State private var nextRunDate = Date()
    @State private var selectedCategory: CategoryItem?
    @State private var selectedAccount: AccountItem?
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Amount minor units", text: $amountText).keyboardType(.numberPad)
                Picker("Type", selection: $isExpense) { Text("Expense").tag(true); Text("Income").tag(false) }
                Picker("Cadence", selection: $cadence) { ForEach(RecurringCadence.allCases) { Text($0.title).tag($0) } }
                DatePicker("Next run", selection: $nextRunDate, displayedComponents: .date)
                Picker("Category", selection: Binding(get: { selectedCategory?.id }, set: { id in selectedCategory = categories.first { $0.id == id } })) {
                    Text("None").tag(UUID?.none); ForEach(categories) { Text($0.name).tag(Optional($0.id)) }
                }
                AccountPicker(selectedAccount: $selectedAccount, accounts: accounts)
                TextField("Note", text: $note)
            }
            .navigationTitle(rule == nil ? "New Rule" : "Edit Rule")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save) }
            }
            .onAppear {
                guard let rule else { selectedCategory = categories.first; selectedAccount = accounts.first; return }
                amountText = "\(rule.amountMinor)"; isExpense = rule.isExpense; cadence = rule.cadence; nextRunDate = rule.nextRunDate; selectedCategory = rule.category; selectedAccount = rule.account; note = rule.note ?? ""
            }
        }
    }

    private func save() {
        let amount = Int64(amountText) ?? 0
        if let rule {
            rule.amountMinor = amount; rule.isExpense = isExpense; rule.cadence = cadence; rule.nextRunDate = nextRunDate; rule.category = selectedCategory; rule.account = selectedAccount; rule.note = note.isEmpty ? nil : note; rule.updatedAt = Date()
        } else {
            modelContext.insert(RecurringRuleItem(amountMinor: amount, isExpense: isExpense, category: selectedCategory, account: selectedAccount, note: note.isEmpty ? nil : note, cadence: cadence, nextRunDate: nextRunDate))
        }
        try? modelContext.save(); dismiss()
    }
}
