import Foundation

struct AccountBalanceSnapshot: Identifiable {
    let account: AccountItem
    let balanceMinor: Int64

    var id: UUID { account.id }
}

enum AccountBalanceUseCase {
    static func balances(
        accounts: [AccountItem],
        transactions: [TransactionItem],
        transfers: [TransferItem]
    ) -> [AccountBalanceSnapshot] {
        accounts.map { account in
            AccountBalanceSnapshot(
                account: account,
                balanceMinor: balance(
                    for: account,
                    transactions: transactions,
                    transfers: transfers
                )
            )
        }
    }

    static func balance(
        for account: AccountItem,
        transactions: [TransactionItem],
        transfers: [TransferItem]
    ) -> Int64 {
        account.openingBalanceMinor
            + transactionNet(for: account, transactions: transactions)
            + transferNet(for: account, transfers: transfers)
    }

    static func totalBalance(
        accounts: [AccountItem],
        transactions: [TransactionItem],
        transfers: [TransferItem]
    ) -> Int64 {
        accounts
            .filter { !$0.archived }
            .reduce(Int64(0)) { total, account in
                total + balance(
                    for: account,
                    transactions: transactions,
                    transfers: transfers
                )
            }
    }

    private static func transactionNet(
        for account: AccountItem,
        transactions: [TransactionItem]
    ) -> Int64 {
        transactions
            .filter { $0.isPosted && $0.account?.id == account.id }
            .reduce(Int64(0)) { total, transaction in
                total + (transaction.isExpense ? -transaction.amountMinor : transaction.amountMinor)
            }
    }

    private static func transferNet(
        for account: AccountItem,
        transfers: [TransferItem]
    ) -> Int64 {
        transfers.reduce(Int64(0)) { total, transfer in
            var net = total
            if transfer.fromAccount?.id == account.id {
                net -= transfer.amountMinor
            }
            if transfer.toAccount?.id == account.id {
                net += transfer.amountMinor
            }
            return net
        }
    }
}
