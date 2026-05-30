import SwiftUI
import SwiftData

@main
struct FloatApp: App {
    @StateObject private var appState = AppState()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            AccountItem.self,
            CategoryItem.self,
            TransactionItem.self,
            RecurringRuleItem.self,
            GoalItem.self,
            BudgetPeriodItem.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environmentObject(appState)
        }
        .modelContainer(sharedModelContainer)
    }
}
