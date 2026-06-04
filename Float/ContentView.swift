import SwiftData
import SwiftUI

struct ContentView: View {
    var body: some View {
        AppRootView()
    }
}

#Preview {
    ContentView()
        .modelContainer(
            for: [
                AccountItem.self, CategoryItem.self, TransactionItem.self,
                TransactionTemplateItem.self, TransactionTemplateGroupItem.self,
                TransactionTemplateGroupEntryItem.self, RecurringRuleItem.self,
                GoalItem.self, BudgetPeriodItem.self,
            ],
            inMemory: true
        )
        .environmentObject(AppState())
}
