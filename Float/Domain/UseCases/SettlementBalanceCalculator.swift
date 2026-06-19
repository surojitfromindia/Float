import Foundation

struct SettlementBalanceSnapshot: Equatable {
    let initialAmountMinor: Int64
    let additionsMinor: Int64
    let adjustmentsMinor: Int64
    let reductionsMinor: Int64
    let paymentsMinor: Int64
    let grossDueMinor: Int64
    let dueMinor: Int64
    let remainingMinor: Int64
    let creditMinor: Int64
    let status: SettlementCaseStatus

    var hasPayments: Bool {
        paymentsMinor > 0
    }
}

enum SettlementBalanceCalculator {
    static func snapshot(for entries: [SettlementEntryItem]) -> SettlementBalanceSnapshot {
        var initialAmountMinor: Int64 = 0
        var additionsMinor: Int64 = 0
        var adjustmentsMinor: Int64 = 0
        var reductionsMinor: Int64 = 0
        var paymentsMinor: Int64 = 0

        for entry in entries {
            switch entry.kind {
            case .initialAmount:
                initialAmountMinor += entry.amountMinor
            case .addition:
                additionsMinor += entry.amountMinor
            case .payment:
                paymentsMinor += entry.amountMinor
            case .adjustment:
                adjustmentsMinor += entry.amountMinor
            case .discount, .waived, .correctionDown:
                reductionsMinor += entry.amountMinor
            }
        }

        let grossDueMinor = initialAmountMinor + additionsMinor + adjustmentsMinor
        let dueMinor = max(0, grossDueMinor - reductionsMinor)
        let remainingMinor = max(0, dueMinor - paymentsMinor)
        let creditMinor = max(0, paymentsMinor - dueMinor)
        let status: SettlementCaseStatus

        if creditMinor > 0 {
            status = .overpaid
        } else if reductionsMinor > 0 && dueMinor == paymentsMinor {
            status = .writtenOff
        } else if dueMinor > 0 && remainingMinor == 0 {
            status = .settled
        } else if paymentsMinor > 0 {
            status = .partiallyPaid
        } else {
            status = .unpaid
        }

        return SettlementBalanceSnapshot(
            initialAmountMinor: initialAmountMinor,
            additionsMinor: additionsMinor,
            adjustmentsMinor: adjustmentsMinor,
            reductionsMinor: reductionsMinor,
            paymentsMinor: paymentsMinor,
            grossDueMinor: grossDueMinor,
            dueMinor: dueMinor,
            remainingMinor: remainingMinor,
            creditMinor: creditMinor,
            status: status
        )
    }
}
