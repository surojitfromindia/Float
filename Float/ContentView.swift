import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        AppRootView()
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [AccountItem.self, CategoryItem.self, TransactionItem.self, RecurringRuleItem.self, GoalItem.self, BudgetPeriodItem.self], inMemory: true)
        .environmentObject(AppState())
}
