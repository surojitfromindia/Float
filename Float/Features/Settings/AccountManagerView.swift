import SwiftData
import SwiftUI

struct AccountManagerView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @Query(sort: \AccountItem.createdAt) private var accounts: [AccountItem]
    @Query(sort: \TransactionItem.timestamp, order: .reverse) private
        var transactions: [TransactionItem]
    @Query(sort: \TransferItem.timestamp, order: .reverse) private
        var transfers: [TransferItem]
    @State private var showingEditor = false
    @State private var editingAccount: AccountItem?

    var body: some View {
        List {
            ForEach(accounts) { account in
                Button {
                    editingAccount = account
                    showingEditor = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: account.type.icon)
                            .font(.headline)
                            .foregroundStyle(appState.themePalette.accent)
                            .frame(width: 36, height: 36)
                            .background(
                                appState.themePalette.accent.opacity(0.14),
                                in: Circle()
                            )

                        VStack(alignment: .leading, spacing: 3) {
                            Text(account.name)
                                .font(.headline)
                            Text(
                                "\(account.type.title) • \(account.currencyCode)"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(
                            MoneyFormatter.string(
                                minorUnits: AccountBalanceUseCase.balance(
                                    for: account,
                                    transactions: transactions,
                                    transfers: transfers
                                ),
                                currencyCode: account.currencyCode
                            )
                        )
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                        if account.archived {
                            Text("Archived")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .onDelete {
                let repository = AccountRepository(modelContext: modelContext)
                $0.map { accounts[$0] }.forEach {
                    try? repository.deleteIfUnused($0)
                }
            }
        }
        .navigationTitle("Accounts")
        .scrollContentBackground(.hidden)
        .floatBackground()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editingAccount = nil
                    showingEditor = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add account")
            }
        }
        .sheet(isPresented: $showingEditor) {
            AccountEditorView(
                account: editingAccount,
                defaultCurrencyCode: appState.selectedCurrencyCode
            )
        }
    }
}

private struct AccountEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let account: AccountItem?
    let defaultCurrencyCode: String

    @State private var name = ""
    @State private var type: AccountType = .cash
    @State private var openingBalanceText = "0"
    @State private var currencyCode = ""
    @State private var archived = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Name", text: $name)
                    Picker("Type", selection: $type) {
                        ForEach(AccountType.allCases) { type in
                            Label(type.title, systemImage: type.icon).tag(type)
                        }
                    }
                    TextField("Currency code", text: $currencyCode)
                        .textInputAutocapitalization(.characters)
                    HStack {
                        TextField(
                            "Opening balance minor units",
                            text: $openingBalanceText
                        )
                        .keyboardType(.numberPad)
                        CurrencyAmountPreview(
                            minorUnits: openingBalanceMinor,
                            currencyCode: previewCurrencyCode
                        )
                    }
                    Toggle("Archived", isOn: $archived)
                }

                Section {
                    Text(
                        "Amounts are stored in minor units. Example: ₹123.45 is 12345."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(account == nil ? "New Account" : "Edit Account")
            .keyboardDismissControls()
            .scrollContentBackground(.hidden)
            .floatBackground()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(
                            name.trimmingCharacters(in: .whitespacesAndNewlines)
                                .isEmpty
                                || currencyCode.trimmingCharacters(
                                    in: .whitespacesAndNewlines
                                ).isEmpty
                        )
                }
            }
            .onAppear(perform: configure)
        }
    }

    private var openingBalanceMinor: Int64 {
        Int64(openingBalanceText) ?? 0
    }

    private var previewCurrencyCode: String {
        let trimmedCurrency = currencyCode.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).uppercased()
        return trimmedCurrency.isEmpty ? defaultCurrencyCode : trimmedCurrency
    }

    private func configure() {
        guard let account else {
            currencyCode = defaultCurrencyCode
            return
        }
        name = account.name
        type = account.type
        openingBalanceText = "\(account.openingBalanceMinor)"
        currencyCode = account.currencyCode
        archived = account.archived
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCurrency = currencyCode.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).uppercased()
        let openingBalance = openingBalanceMinor
        if let account {
            account.name = trimmedName
            account.type = type
            account.openingBalanceMinor = openingBalance
            account.currencyCode = trimmedCurrency
            account.archived = archived
            account.updatedAt = Date()
        } else {
            modelContext.insert(
                AccountItem(
                    name: trimmedName,
                    type: type,
                    openingBalanceMinor: openingBalance,
                    currencyCode: trimmedCurrency,
                    archived: archived
                )
            )
        }
        try? modelContext.save()
        dismiss()
    }
}
