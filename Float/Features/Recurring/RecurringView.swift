import SwiftData
import SwiftUI

struct RecurringView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \RecurringRuleItem.nextRunDate) private var rules:
        [RecurringRuleItem]
    @State private var showingEditor = false
    @State private var editingRule: RecurringRuleItem?
    @State private var rulePendingDeletion: RecurringRuleItem?

    var body: some View {
        List {
            if rules.isEmpty {
                EmptyStateView(
                    icon: "repeat",
                    title: "No recurring rules",
                    message:
                        "Add predictable bills or income to keep Safe-to-Spend current."
                )
                .listRowBackground(Color.clear)
            }
            ForEach(rules) { rule in
                Button {
                    editingRule = rule
                    showingEditor = true
                } label: {
                    HStack {
                        Image(
                            systemName: rule.isExpense
                                ? "arrow.down.circle.fill"
                                : "arrow.up.circle.fill"
                        )
                        .foregroundStyle(tint(for: rule))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(
                                rule.note?.isEmpty == false
                                    ? rule.note ?? "Recurring"
                                    : rule.category?.name ?? "Recurring"
                            )
                            .font(.headline)
                            .foregroundStyle(rule.active ? .primary : .secondary)
                            Text(
                                "Next: \(rule.nextRunDate.formatted(date: .abbreviated, time: .omitted))"
                            )
                            .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 6) {
                            Text(rule.cadence.title).font(
                                .caption.weight(.semibold)
                            )
                            Text(rule.active ? "Active" : "Inactive")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(tint(for: rule))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    tint(for: rule).opacity(rule.active ? 0.14 : 0.10),
                                    in: Capsule()
                                )
                        }
                    }
                }
                .opacity(rule.active ? 1 : 0.62)
                .buttonStyle(.plain)
                .swipeActions(edge: .leading) {
                    Button(rule.active ? "Deactivate" : "Activate") {
                        rule.active.toggle()
                        rule.updatedAt = Date()
                        try? modelContext.save()
                    }
                    .tint(rule.active ? .orange : .green)
                }
                .swipeActions {
                    Button(role: .destructive) {
                        rulePendingDeletion = rule
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle("Recurring")
        .toolbar {
            Button {
                editingRule = nil
                showingEditor = true
            } label: {
                Image(systemName: "plus")
            }
        }
        .sheet(isPresented: $showingEditor) {
            RecurringEditorView(rule: editingRule)
        }
        .confirmationDialog(
            "Delete recurring rule?",
            isPresented: Binding(
                get: { rulePendingDeletion != nil },
                set: { isPresented in
                    if !isPresented {
                        rulePendingDeletion = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Rule", role: .destructive, action: deletePendingRule)
            Button("Cancel", role: .cancel) {
                rulePendingDeletion = nil
            }
        } message: {
            Text("Future transactions will no longer be created from this rule.")
        }
        .onAppear {
            MaterializeRecurringTransactionsUseCase.run(
                modelContext: modelContext
            )
        }
    }

    private func tint(for rule: RecurringRuleItem) -> Color {
        guard rule.active else {
            return .secondary
        }

        return rule.isExpense ? Color(hex: "#B4613B") : Color(hex: "#1B8A5A")
    }

    private func deletePendingRule() {
        guard let rulePendingDeletion else {
            return
        }

        modelContext.delete(rulePendingDeletion)
        try? modelContext.save()
        self.rulePendingDeletion = nil
    }
}

struct RecurringEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
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
                HStack {
                    TextField("Amount minor units", text: $amountText)
                        .keyboardType(.numberPad)
                    CurrencyAmountPreview(
                        minorUnits: amountMinor,
                        currencyCode: appState.selectedCurrencyCode
                    )
                }
                Picker("Type", selection: $isExpense) {
                    Text("Expense").tag(true)
                    Text("Income").tag(false)
                }
                Picker("Cadence", selection: $cadence) {
                    ForEach(RecurringCadence.allCases) {
                        Text($0.title).tag($0)
                    }
                }
                DatePicker(
                    "Next run",
                    selection: $nextRunDate,
                    displayedComponents: .date
                )
                Picker(
                    "Category",
                    selection: Binding(
                        get: { selectedCategory?.id },
                        set: { id in
                            selectedCategory = categories.first { $0.id == id }
                        }
                    )
                ) {
                    Text("None").tag(UUID?.none)
                    ForEach(categories) { Text($0.name).tag(Optional($0.id)) }
                }
                AccountPicker(
                    selectedAccount: $selectedAccount,
                    accounts: accounts
                )
                TextField("Note", text: $note)
            }
            .navigationTitle(rule == nil ? "New Rule" : "Edit Rule")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                }
            }
            .onAppear {
                guard let rule else {
                    selectedCategory = categories.first
                    selectedAccount = accounts.first
                    return
                }
                amountText = "\(rule.amountMinor)"
                isExpense = rule.isExpense
                cadence = rule.cadence
                nextRunDate = rule.nextRunDate
                selectedCategory = rule.category
                selectedAccount = rule.account
                note = rule.note ?? ""
            }
        }
    }

    private var amountMinor: Int64 {
        Int64(amountText) ?? 0
    }

    private func save() {
        let amount = amountMinor
        if let rule {
            rule.amountMinor = amount
            rule.isExpense = isExpense
            rule.cadence = cadence
            rule.nextRunDate = nextRunDate
            rule.category = selectedCategory
            rule.account = selectedAccount
            rule.note = note.isEmpty ? nil : note
            rule.updatedAt = Date()
        } else {
            modelContext.insert(
                RecurringRuleItem(
                    amountMinor: amount,
                    isExpense: isExpense,
                    category: selectedCategory,
                    account: selectedAccount,
                    note: note.isEmpty ? nil : note,
                    cadence: cadence,
                    nextRunDate: nextRunDate
                )
            )
        }
        try? modelContext.save()
        dismiss()
    }
}
