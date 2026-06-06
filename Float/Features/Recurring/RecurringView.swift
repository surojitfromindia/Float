import SwiftData
import SwiftUI

struct RecurringView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @Query(sort: \RecurringRuleItem.nextRunDate) private var rules:
        [RecurringRuleItem]
    @State private var editingRule: RecurringRuleItem?
    @State private var showingNewRuleEditor = false
    @State private var rulePendingDeletion: RecurringRuleItem?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if rules.isEmpty {
                    GlassCard {
                        EmptyStateView(
                            icon: "repeat",
                            title: "No recurring rules",
                            message:
                                "Add predictable bills or income to keep Safe-to-Spend current."
                        )
                    }
                }

                ForEach(rules) { rule in
                    RecurringRuleCard(
                        rule: rule,
                        currencyCode: appState.selectedCurrencyCode,
                        tint: tint(for: rule),
                        cadenceText: cadenceText(for: rule),
                        onEdit: {
                            editingRule = rule
                        },
                        onToggleActive: {
                            toggleActive(rule)
                        },
                        onDelete: {
                            rulePendingDeletion = rule
                        }
                    )
                }
            }
            .padding(20)
            .padding(.bottom, 120)
        }
        .navigationTitle("Recurring")
        .floatBackground()
        .toolbar {
            Button {
                showingNewRuleEditor = true
            } label: {
                Image(systemName: "plus")
            }
        }
        .sheet(item: $editingRule) { rule in
            RecurringEditorView(rule: rule)
        }
        .sheet(isPresented: $showingNewRuleEditor) {
            RecurringEditorView(rule: nil)
        }
        .alert(
            "Delete recurring rule?",
            isPresented: Binding(
                get: { rulePendingDeletion != nil },
                set: { isPresented in
                    if !isPresented {
                        rulePendingDeletion = nil
                    }
                }
            )
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
        if let colorHex = rule.category?.colorHex, !colorHex.isEmpty {
            return Color(hex: colorHex)
        }

        guard rule.active else {
            return .secondary
        }

        return rule.isExpense ? Color(hex: "#B4613B") : Color(hex: "#1B8A5A")
    }

    private func cadenceText(for rule: RecurringRuleItem) -> String {
        rule.intervalCount == 1
            ? rule.cadence.title
            : "Every \(rule.intervalCount) \(rule.cadence.title.lowercased())s"
    }

    private func deletePendingRule() {
        guard let rulePendingDeletion else {
            return
        }

        try? RecurringRepository(modelContext: modelContext)
            .delete(rulePendingDeletion)
        self.rulePendingDeletion = nil
    }

    private func toggleActive(_ rule: RecurringRuleItem) {
        rule.active.toggle()
        rule.updatedAt = Date()
        try? modelContext.save()
    }
}

private struct RecurringRuleCard: View {
    let rule: RecurringRuleItem
    let currencyCode: String
    let tint: Color
    let cadenceText: String
    let onEdit: () -> Void
    let onToggleActive: () -> Void
    let onDelete: () -> Void

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    FloatIconBadge(
                        icon: rule.category?.iconKey ?? "repeat",
                        tint: tint,
                        size: 42
                    )

                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(rule.active ? .primary : .secondary)
                            .lineLimit(1)
                        Text(
                            "\(rule.account?.name ?? "Unknown Account") • Next \(rule.nextRunDate.formatted(date: .abbreviated, time: .omitted))"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    }

                    Spacer(minLength: 8)

                    VStack(alignment: .trailing, spacing: 5) {
                        Text(amount)
                            .moneyStyle(size: 14, weight: .semibold)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        Text(cadenceText)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                HStack(spacing: 10) {
                    statusBadge

                    Spacer()

                    Button(action: onToggleActive) {
                        Label(
                            rule.active ? "Deactivate" : "Activate",
                            systemImage: rule.active
                                ? "pause.circle.fill"
                                : "play.circle.fill"
                        )
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.borderless)

                    Button(action: onEdit) {
                        Label("Edit", systemImage: "pencil")
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.borderless)
                }
            }
        }
        .opacity(rule.active ? 1 : 0.62)
        .contextMenu {
            Button(role: .destructive, action: onDelete) {
                Label {
                    Text("Delete")
                        .foregroundStyle(Color(hex: "#DC2626"))
                } icon: {
                    Image(systemName: "trash")
                        .foregroundStyle(Color(hex: "#DC2626"))
                }
            }
            .tint(Color(hex: "#DC2626"))
        }
    }

    private var title: String {
        rule.note?.isEmpty == false
            ? rule.note ?? "Recurring"
            : rule.category?.name ?? "Unknown Category"
    }

    private var amount: String {
        MoneyFormatter.string(
            minorUnits: rule.amountMinor,
            currencyCode: currencyCode
        )
    }

    private var statusBadge: some View {
        Text(rule.active ? "Active" : "Inactive")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                tint.opacity(rule.active ? 0.14 : 0.10),
                in: RoundedRectangle(
                    cornerRadius: FloatTheme.tileRadius,
                    style: .continuous
                )
            )
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
    @State private var intervalCount = 1
    @State private var hasEndDate = false
    @State private var endDate = Date()
    @State private var active = true
    @State private var validationMessage: String?

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
                Stepper(
                    intervalCount == 1
                        ? "Every \(cadence.title.lowercased())"
                        : "Every \(intervalCount) \(cadence.title.lowercased())s",
                    value: $intervalCount,
                    in: 1...24
                )
                DatePicker(
                    "Next run",
                    selection: $nextRunDate,
                    displayedComponents: .date
                )
                Toggle("End date", isOn: $hasEndDate)
                if hasEndDate {
                    DatePicker(
                        "Ends",
                        selection: $endDate,
                        displayedComponents: .date
                    )
                }
                Toggle("Active", isOn: $active)
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
                    ForEach(categories.filter { !$0.archived && $0.isIncome != isExpense }) {
                        Text($0.name).tag(Optional($0.id))
                    }
                }
                AccountPicker(
                    selectedAccount: $selectedAccount,
                    accounts: accounts.filter { !$0.archived }
                )
                TextField("Note", text: $note)
                if let validationMessage {
                    Text(validationMessage)
                        .font(.footnote)
                        .foregroundStyle(Color(hex: "#B4613B"))
                }
            }
            .navigationTitle(rule == nil ? "New Rule" : "Edit Rule")
            .keyboardDismissControls()
            .scrollContentBackground(.hidden)
            .floatBackground()
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
                    selectedCategory = DefaultCategoryResolver.resolve(
                        isExpense: isExpense,
                        preferredID: appState.lastUsedCategoryID,
                        categories: categories,
                        modelContext: modelContext
                    )
                    selectedAccount = DefaultAccountResolver.resolve(
                        preferredID: appState.lastUsedAccountID,
                        accounts: accounts,
                        modelContext: modelContext,
                        currencyCode: appState.selectedCurrencyCode
                    )
                    return
                }
                amountText = "\(rule.amountMinor)"
                isExpense = rule.isExpense
                cadence = rule.cadence
                intervalCount = rule.intervalCount
                nextRunDate = rule.nextRunDate
                endDate = rule.endDate ?? Date()
                hasEndDate = rule.endDate != nil
                active = rule.active
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
        guard amount > 0 else {
            validationMessage = "Enter an amount greater than zero."
            return
        }
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
        do {
            let repository = RecurringRepository(modelContext: modelContext)
            if let rule {
                try repository.update(
                    rule,
                    amountMinor: amount,
                    isExpense: isExpense,
                    category: category,
                    account: account,
                    note: note,
                    cadence: cadence,
                    intervalCount: intervalCount,
                    nextRunDate: nextRunDate,
                    endDate: hasEndDate ? endDate : nil,
                    active: active
                )
            } else {
                _ = try repository.create(
                    amountMinor: amount,
                    isExpense: isExpense,
                    category: category,
                    account: account,
                    note: note,
                    cadence: cadence,
                    intervalCount: intervalCount,
                    nextRunDate: nextRunDate,
                    endDate: hasEndDate ? endDate : nil
                )
            }
            appState.lastUsedCategoryID = category.id.uuidString
            appState.lastUsedAccountID = account.id.uuidString
            dismiss()
        } catch {
            validationMessage = error.localizedDescription
        }
    }
}
