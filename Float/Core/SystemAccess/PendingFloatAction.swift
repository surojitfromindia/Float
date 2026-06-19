import Foundation

enum PendingFloatActionKind: String, Codable {
    case addExpense
    case addIncome
    case addTransfer
    case openDestination
    case openSearchResult
}

enum FloatDestination: String, CaseIterable, Codable, Identifiable {
    case home
    case transactions
    case calendar
    case reports
    case settings
    case budget
    case goals
    case recurring
    case templates
    case templateGroups
    case categories
    case accounts
    case people
    case settlements
    case reviewQueue

    var id: String { rawValue }
}

struct PendingFloatAction: Codable {
    static let appGroupIdentifier = "group.com.reducer.Float"
    static let storageKey = "float.pendingAction"

    let kind: PendingFloatActionKind
    var destination: FloatDestination?
    var spotlightItemIdentifier: String?
    var createdAt = Date()

    static func save(_ action: PendingFloatAction) {
        guard
            let defaults = UserDefaults(suiteName: appGroupIdentifier),
            let data = try? JSONEncoder().encode(action)
        else {
            return
        }
        defaults.set(data, forKey: storageKey)
    }

    static func consume() -> PendingFloatAction? {
        guard
            let defaults = UserDefaults(suiteName: appGroupIdentifier),
            let data = defaults.data(forKey: storageKey),
            let action = try? JSONDecoder().decode(PendingFloatAction.self, from: data)
        else {
            return nil
        }
        defaults.removeObject(forKey: storageKey)
        return action
    }
}
