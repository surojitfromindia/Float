import SwiftData
import SwiftUI

@main
struct FloatApp: App {
    @StateObject private var appState = AppState()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            UserProfileItem.self,
            AccountItem.self,
            CategoryItem.self,
            PersonItem.self,
            EventCategoryItem.self,
            EventItem.self,
            TransactionItem.self,
            TransactionPersonTagItem.self,
            TransactionTemplateItem.self,
            TransactionTemplateGroupItem.self,
            TransactionTemplateGroupEntryItem.self,
            TransferItem.self,
            RecurringRuleItem.self,
            RecurringRulePersonTagItem.self,
            GoalItem.self,
            BudgetPeriodItem.self,
            CategoryBudgetItem.self,
            InsightSignalItem.self,
            MerchantAliasItem.self,
            ScenarioPlanItem.self,
            SettlementCaseItem.self,
            SettlementEntryItem.self,
            SettlementMilestoneItem.self,
        ])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )

        do {
            return try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
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
