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
                AccountItem.self, CategoryItem.self, PersonItem.self, TransactionItem.self,
                TransactionPersonTagItem.self, TransactionTemplateItem.self, TransactionTemplateGroupItem.self,
                TransactionTemplateGroupEntryItem.self, ReceiptCaptureItem.self,
                ReceiptLineItem.self, AttachmentItem.self, RecurringRuleItem.self,
                RecurringRulePersonTagItem.self, GoalItem.self, BudgetPeriodItem.self,
                HouseholdMemberItem.self, HouseholdExpenseItem.self,
                HouseholdExpenseSplitItem.self, HouseholdBillItem.self,
                HouseholdAllowanceItem.self, HouseholdActivityItem.self,
            ],
            inMemory: true
        )
        .environmentObject(AppState())
}
