import AppIntents
import Foundation

private struct WidgetPendingFloatAction: Codable {
    static let appGroupIdentifier = "group.com.reducer.Float"
    static let storageKey = "float.pendingAction"

    let kind: String
    var destination: String?
    var createdAt = Date()

    static func save(kind: String, destination: String? = nil) {
        guard
            let defaults = UserDefaults(suiteName: appGroupIdentifier),
            let data = try? JSONEncoder().encode(
                WidgetPendingFloatAction(kind: kind, destination: destination)
            )
        else {
            return
        }
        defaults.set(data, forKey: storageKey)
    }
}

struct AddWidgetExpenseIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Expense"
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        WidgetPendingFloatAction.save(kind: "addExpense")
        return .result()
    }
}

struct AddWidgetIncomeIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Income"
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        WidgetPendingFloatAction.save(kind: "addIncome")
        return .result()
    }
}

struct AddWidgetTransferIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Transfer"
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        WidgetPendingFloatAction.save(kind: "addTransfer")
        return .result()
    }
}

struct OpenWidgetReviewQueueIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Review Queue"
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        WidgetPendingFloatAction.save(kind: "openDestination", destination: "reviewQueue")
        return .result()
    }
}

struct OpenWidgetTemplatesIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Templates"
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        WidgetPendingFloatAction.save(kind: "openDestination", destination: "templates")
        return .result()
    }
}

struct ScanWidgetReceiptIntent: AppIntent {
    static var title: LocalizedStringResource = "Scan Receipt"
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        WidgetPendingFloatAction.save(kind: "scanReceipt")
        return .result()
    }
}
