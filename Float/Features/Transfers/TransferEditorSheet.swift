import SwiftData
import SwiftUI

struct TransferEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @Query(sort: \AccountItem.createdAt) private var accounts: [AccountItem]

    let transferToEdit: TransferItem?
    var initialTimestamp: Date?

    @State private var amountText = ""
    @State private var fromAccount: AccountItem?
    @State private var toAccount: AccountItem?
    @State private var timestamp = Date()
    @State private var note = ""
    @State private var validationMessage: String?

    private var activeAccounts: [AccountItem] {
        accounts.filter { !$0.archived }
    }

    private var amountMinor: Int64 {
        BudgetAmountField.minorUnits(
            fromMajorAmount: amountText,
            currencyCode: appState.selectedCurrencyCode
        )
    }

    private var sameCurrencyAccounts: [AccountItem] {
        guard let fromAccount else { return activeAccounts }
        return activeAccounts.filter { $0.currencyCode == fromAccount.currencyCode }
    }

    private var canSave: Bool {
        amountMinor > 0
            && fromAccount != nil
            && toAccount != nil
            && fromAccount?.id != toAccount?.id
            && fromAccount?.currencyCode == toAccount?.currencyCode
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    amountHeader
                    accountCard
                    detailsCard

                    if let validationMessage {
                        Text(validationMessage)
                            .font(.footnote)
                            .foregroundStyle(appState.themePalette.caution)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if transferToEdit != nil {
                        Button(role: .destructive, action: deleteTransfer) {
                            Label {
                                Text("Delete transfer")
                            } icon: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.red)
                            }
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .tint(.red)
                        .buttonStyle(.borderless)
                    }
                }
                .padding(20)
                .padding(.bottom, 24)
            }
            .navigationTitle(transferToEdit == nil ? "Transfer" : "Edit Transfer")
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDismissControls()
            .floatBackground()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(transferToEdit == nil ? "Save" : "Done", action: save)
                        .disabled(!canSave)
                }
            }
            .onAppear(perform: configure)
            .onChange(of: fromAccount?.id) { _, _ in
                guard let fromAccount else { return }
                if toAccount?.id == fromAccount.id
                    || toAccount?.currencyCode != fromAccount.currencyCode {
                    toAccount = sameCurrencyAccounts.first { $0.id != fromAccount.id }
                }
            }
        }
    }

    private var amountHeader: some View {
        GlassCard {
            VStack(spacing: 12) {
                FloatIconBadge(
                    icon: "arrow.left.arrow.right.circle.fill",
                    tint: appState.themePalette.accent,
                    size: 46
                )
                TextField("Amount", text: $amountText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text(
                    MoneyFormatter.string(
                        minorUnits: amountMinor,
                        currencyCode: fromAccount?.currencyCode
                            ?? appState.selectedCurrencyCode
                    )
                )
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
            }
        }
    }

    private var accountCard: some View {
        GlassCard {
            VStack(spacing: 14) {
                accountPicker(
                    title: "From",
                    account: $fromAccount,
                    accounts: activeAccounts,
                    icon: "arrow.up.circle.fill",
                    tint: appState.themePalette.caution
                )
                Divider()
                accountPicker(
                    title: "To",
                    account: $toAccount,
                    accounts: sameCurrencyAccounts.filter { $0.id != fromAccount?.id },
                    icon: "arrow.down.circle.fill",
                    tint: appState.themePalette.positive
                )
            }
        }
    }

    private var detailsCard: some View {
        GlassCard {
            VStack(spacing: 14) {
                TextField("Note", text: $note, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...3)
                Divider()
                DatePicker(
                    "Date",
                    selection: $timestamp,
                    displayedComponents: [.date, .hourAndMinute]
                )
            }
        }
    }

    private func accountPicker(
        title: String,
        account: Binding<AccountItem?>,
        accounts: [AccountItem],
        icon: String,
        tint: Color
    ) -> some View {
        HStack(spacing: 12) {
            FloatIconBadge(icon: icon, tint: tint, size: 34)
            Text(title)
                .font(.subheadline.weight(.semibold))
            Spacer()
            Menu {
                Picker(
                    title,
                    selection: Binding(
                        get: { account.wrappedValue?.id },
                        set: { id in
                            account.wrappedValue = accounts.first { $0.id == id }
                        }
                    )
                ) {
                    Text("Select").tag(UUID?.none)
                    ForEach(accounts) { item in
                        Text(item.name).tag(Optional(item.id))
                    }
                }
                .labelsHidden()
            } label: {
                HStack(spacing: 4) {
                    Text(account.wrappedValue?.name ?? "Select")
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.semibold))
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: 170, alignment: .trailing)
                .contentShape(Rectangle())
            }
        }
    }

    private func configure() {
        guard let transferToEdit else {
            timestamp = initialTimestamp ?? Date()
            let preferredFrom = activeAccounts.first {
                $0.id.uuidString == appState.lastUsedAccountID
            } ?? activeAccounts.first
            fromAccount = preferredFrom
            if let preferredFrom {
                toAccount = activeAccounts.first {
                    $0.currencyCode == preferredFrom.currencyCode
                        && $0.id != preferredFrom.id
                }
            }
            return
        }

        amountText = BudgetAmountField.majorAmountString(
            minorUnits: transferToEdit.amountMinor,
            currencyCode: transferToEdit.currencyCode
        )
        fromAccount = transferToEdit.fromAccount
        toAccount = transferToEdit.toAccount
        timestamp = transferToEdit.timestamp
        note = transferToEdit.note ?? ""
    }

    private func save() {
        guard
            let fromAccount,
            let toAccount,
            fromAccount.id != toAccount.id,
            fromAccount.currencyCode == toAccount.currencyCode
        else {
            validationMessage = "Choose two different accounts with the same currency."
            return
        }

        do {
            if let transferToEdit {
                try TransferRepository(modelContext: modelContext).update(
                    transferToEdit,
                    amountMinor: amountMinor,
                    fromAccount: fromAccount,
                    toAccount: toAccount,
                    timestamp: timestamp,
                    note: note
                )
            } else {
                _ = try TransferRepository(modelContext: modelContext).create(
                    amountMinor: amountMinor,
                    fromAccount: fromAccount,
                    toAccount: toAccount,
                    timestamp: timestamp,
                    note: note
                )
            }
            appState.lastUsedAccountID = fromAccount.id.uuidString
            Haptics.confirm()
            dismiss()
        } catch {
            validationMessage = error.localizedDescription
        }
    }

    private func deleteTransfer() {
        guard let transferToEdit else { return }
        try? TransferRepository(modelContext: modelContext).delete(transferToEdit)
        Haptics.tick()
        dismiss()
    }
}
