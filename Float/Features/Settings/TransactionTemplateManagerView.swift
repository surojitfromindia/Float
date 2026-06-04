import SwiftData
import SwiftUI

struct TransactionTemplateManagerView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @Query(sort: \TransactionTemplateItem.createdAt, order: .reverse) private
        var templates: [TransactionTemplateItem]
    @State private var editorPresentation: TransactionTemplateEditorPresentation?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if templates.isEmpty {
                    GlassCard {
                        EmptyStateView(
                            icon: "square.text.square",
                            title: "No templates",
                            message: "Create reusable entries for coffee, groceries, bills, salary, or transfers."
                        )
                    }
                }

                ForEach(templates) { template in
                    TemplateCard(
                        template: template,
                        currencyCode: appState.selectedCurrencyCode,
                        onEdit: {
                            editorPresentation = TransactionTemplateEditorPresentation(
                                template: template
                            )
                        },
                        onDelete: {
                            delete(template)
                        }
                    )
                }
            }
            .padding(20)
            .padding(.bottom, 120)
        }
        .navigationTitle("Templates")
        .floatBackground()
        .toolbar {
            Button {
                editorPresentation = TransactionTemplateEditorPresentation(
                    template: nil
                )
            } label: {
                Image(systemName: "plus")
            }
        }
        .sheet(item: $editorPresentation) { presentation in
            TransactionTemplateEditorView(template: presentation.template)
        }
    }

    private func delete(_ template: TransactionTemplateItem) {
        try? TransactionTemplateRepository(modelContext: modelContext)
            .delete(template)
    }
}

private struct TransactionTemplateEditorPresentation: Identifiable {
    let id = UUID()
    let template: TransactionTemplateItem?
}

private struct TemplateCard: View {
    let template: TransactionTemplateItem
    let currencyCode: String
    let onEdit: () -> Void
    let onDelete: () -> Void

    private var tint: Color {
        Color(hex: template.category?.colorHex ?? "#0E7C7B")
    }

    var body: some View {
        GlassCard {
            HStack(spacing: 14) {
                FloatIconBadge(
                    icon: template.category?.iconKey ?? "square.text.square",
                    tint: tint,
                    size: 42
                )
                VStack(alignment: .leading, spacing: 5) {
                    Text(template.displayTitle)
                        .font(.headline)
                        .lineLimit(1)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                Text(amount)
                    .moneyStyle(size: 15, weight: .semibold)
                    .foregroundStyle(template.isExpense ? .primary : Color(hex: "#1B8A5A"))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .contextMenu {
            Button(action: onEdit) {
                Label("Edit", systemImage: "pencil")
            }
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
        .onTapGesture(perform: onEdit)
    }

    private var detail: String {
        let category = template.category?.name ?? "Unknown Category"
        let account = template.account?.name ?? "Unknown Account"
        return "\(category) • \(account)"
    }

    private var amount: String {
        let prefix = template.isExpense ? "" : "+"
        return prefix + MoneyFormatter.string(
            minorUnits: template.amountMinor,
            currencyCode: currencyCode
        )
    }
}

private struct TransactionTemplateEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @Query(sort: \CategoryItem.sortOrder) private var categories: [CategoryItem]
    @Query(sort: \AccountItem.createdAt) private var accounts: [AccountItem]

    let template: TransactionTemplateItem?
    @State private var title = ""
    @State private var amountText = ""
    @State private var isExpense = true
    @State private var selectedCategory: CategoryItem?
    @State private var selectedAccount: AccountItem?
    @State private var note = ""
    @State private var validationMessage: String?

    private var amountMinor: Int64 {
        BudgetAmountField.minorUnits(
            fromMajorAmount: amountText,
            currencyCode: appState.selectedCurrencyCode
        )
    }

    private var visibleCategories: [CategoryItem] {
        categories.filter { !$0.archived && $0.isIncome != isExpense }
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Template name", text: $title)

                HStack {
                    TextField("Amount", text: $amountText)
                        .keyboardType(.decimalPad)
                    CurrencyAmountPreview(
                        minorUnits: amountMinor,
                        currencyCode: appState.selectedCurrencyCode
                    )
                }

                Picker("Type", selection: $isExpense) {
                    Text("Expense").tag(true)
                    Text("Income").tag(false)
                }
                .pickerStyle(.segmented)

                Picker(
                    "Category",
                    selection: Binding(
                        get: { selectedCategory?.id },
                        set: { id in
                            selectedCategory = visibleCategories.first { $0.id == id }
                        }
                    )
                ) {
                    ForEach(visibleCategories) { category in
                        Label(category.name, systemImage: category.iconKey)
                            .tag(Optional(category.id))
                    }
                }

                AccountPicker(
                    selectedAccount: $selectedAccount,
                    accounts: accounts.filter { !$0.archived }
                )

                TextField("Note", text: $note, axis: .vertical)
                    .lineLimit(1...3)

                if let validationMessage {
                    Text(validationMessage)
                        .font(.footnote)
                        .foregroundStyle(Color(hex: "#B4613B"))
                }
            }
            .navigationTitle(template == nil ? "New Template" : "Edit Template")
            .keyboardDismissControls()
            .scrollContentBackground(.hidden)
            .floatBackground()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear(perform: configureDefaults)
            .onChange(of: isExpense) { _, _ in
                if selectedCategory?.isIncome == isExpense {
                    selectedCategory = visibleCategories.first
                }
            }
        }
    }

    private func configureDefaults() {
        guard title.isEmpty, amountText.isEmpty else { return }
        if let template {
            title = template.title
            amountText = BudgetAmountField.majorAmountString(
                minorUnits: template.amountMinor,
                currencyCode: appState.selectedCurrencyCode
            )
            isExpense = template.isExpense
            selectedCategory = template.category
            selectedAccount = template.account
            note = template.note ?? ""
            return
        }
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
    }

    private func save() {
        guard amountMinor > 0 else {
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
            let repository = TransactionTemplateRepository(modelContext: modelContext)
            if let template {
                try repository.update(
                    template,
                    title: title,
                    amountMinor: amountMinor,
                    isExpense: isExpense,
                    category: category,
                    account: account,
                    note: note
                )
            } else {
                _ = try repository.create(
                    title: title,
                    amountMinor: amountMinor,
                    isExpense: isExpense,
                    category: category,
                    account: account,
                    note: note
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
