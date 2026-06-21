import SwiftData
import SwiftUI

struct AccountManagerView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @Query(sort: \AccountItem.createdAt) private var allAccounts: [AccountItem]
    @State private var editorPresentation: AccountEditorPresentation?
    @State private var balanceStates: [UUID: AccountBalanceLoadState] = [:]

    private var accounts: [AccountItem] { filterActiveProfile(allAccounts) }

    var body: some View {
        List {
            ForEach(accounts) { account in
                HStack(spacing: 12) {
                    Button {
                        editorPresentation = AccountEditorPresentation(
                            account: account
                        )
                    } label: {
                        accountInfo(account)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    balanceControl(for: account)

                    if account.archived {
                        Text("Archived")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
                .contextMenu {
                    Button {
                        editorPresentation = AccountEditorPresentation(
                            account: account
                        )
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }

                    Button(role: .destructive) {
                        delete(account)
                    } label: {
                        redDeleteLabel
                    }
                    .tint(.red)
                } preview: {
                    accountPreviewRow(account)
                        .padding(16)
                        .frame(maxWidth: 420)
                }
            }
        }
        .navigationTitle("Accounts")
        .scrollContentBackground(.hidden)
        .floatBackground()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editorPresentation = AccountEditorPresentation(
                        account: nil
                    )
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add account")
            }
        }
        .sheet(item: $editorPresentation) { presentation in
            AccountEditorView(
                account: presentation.account,
                defaultCurrencyCode: appState.selectedCurrencyCode
            )
        }
        .onAppear {
            processSpotlightRequest(appState.pendingSpotlightRequest)
        }
        .onChange(of: appState.pendingSpotlightRequest?.id) { _, _ in
            processSpotlightRequest(appState.pendingSpotlightRequest)
        }
        .onChange(of: editorPresentation?.id) { _, presentationID in
            if presentationID == nil {
                balanceStates.removeAll()
            }
        }
    }

    private func accountInfo(_ account: AccountItem) -> some View {
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
        }
    }

    private func accountPreviewRow(_ account: AccountItem) -> some View {
        HStack(spacing: 12) {
            accountInfo(account)

            Spacer()

            if account.archived {
                Text("Archived")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var redDeleteLabel: some View {
        Label {
            Text("Delete")
                .foregroundStyle(.red)
        } icon: {
            Image(systemName: "trash")
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private func balanceControl(for account: AccountItem) -> some View {
        switch balanceStates[account.id] {
        case .some(.loading):
            ProgressView()
                .controlSize(.small)
        case .some(.loaded(let balanceMinor)):
            HStack(spacing: 6) {
                Text(
                    MoneyFormatter.string(
                        minorUnits: balanceMinor,
                        currencyCode: account.currencyCode
                    )
                )
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)

                Button {
                    loadBalance(for: account)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Refresh balance")
            }
        case .some(.failed):
            Button("Retry") {
                loadBalance(for: account)
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.borderless)
        case nil:
            Button("Check balance") {
                loadBalance(for: account)
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.borderless)
        }
    }

    private func delete(_ account: AccountItem) {
        try? AccountRepository(modelContext: modelContext)
            .deleteIfUnused(account)
    }

    private func processSpotlightRequest(_ request: FloatSpotlightNavigationRequest?) {
        guard let request, request.target.kind == .account else { return }
        if let account = fetchAccount(id: request.target.id) {
            editorPresentation = AccountEditorPresentation(account: account)
        }
        appState.consumeSpotlightRequest(request)
    }

    private func fetchAccount(id: UUID) -> AccountItem? {
        let descriptor = FetchDescriptor<AccountItem>(
            predicate: #Predicate<AccountItem> { account in
                account.id == id
            }
        )
        return filterActiveProfile((try? modelContext.fetch(descriptor)) ?? []).first
    }

    private func loadBalance(for account: AccountItem) {
        balanceStates[account.id] = .loading

        do {
            let transactions = try fetchTransactions(for: account)
            let transfers = try fetchTransfers(for: account)
            let balance = AccountBalanceUseCase.balance(
                for: account,
                transactions: transactions,
                transfers: transfers
            )
            balanceStates[account.id] = .loaded(balance)
        } catch {
            balanceStates[account.id] = .failed
        }
    }

    private func fetchTransactions(for account: AccountItem) throws -> [TransactionItem] {
        let accountID = account.id
        let descriptor = FetchDescriptor<TransactionItem>(
            predicate: #Predicate<TransactionItem> { transaction in
                transaction.account?.id == accountID
            }
        )
        return filterActiveProfile(try modelContext.fetch(descriptor))
    }

    private func fetchTransfers(for account: AccountItem) throws -> [TransferItem] {
        let accountID = account.id
        let descriptor = FetchDescriptor<TransferItem>(
            predicate: #Predicate<TransferItem> { transfer in
                transfer.fromAccount?.id == accountID
                    || transfer.toAccount?.id == accountID
            }
        )
        return filterActiveProfile(try modelContext.fetch(descriptor))
    }
}

private struct AccountEditorPresentation: Identifiable {
    let id = UUID()
    let account: AccountItem?
}

private enum AccountBalanceLoadState {
    case loading
    case loaded(Int64)
    case failed
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
        guard (try? modelContext.save()) != nil else { return }
        FloatSpotlightIndexer.scheduleReindex(modelContext: modelContext)
        dismiss()
    }
}
