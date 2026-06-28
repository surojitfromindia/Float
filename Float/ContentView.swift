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
                TransactionTemplateGroupEntryItem.self, CustomFlowItem.self,
                CustomFlowObjectTypeItem.self, CustomFlowFieldItem.self,
                CustomFlowRelationItem.self, CustomFlowRecordItem.self,
                CustomFlowFieldValueItem.self, CustomFlowTransactionActionItem.self,
                CustomFlowTransactionLinkItem.self, ReceiptCaptureItem.self,
                ReceiptLineItem.self, AttachmentItem.self, RecurringRuleItem.self,
                RecurringRulePersonTagItem.self, GoalItem.self, BudgetPeriodItem.self,
                CategoryBudgetItem.self, BudgetCycleItem.self, BudgetCycleCategoryItem.self,
                HouseholdMemberItem.self, HouseholdExpenseItem.self,
                HouseholdExpenseSplitItem.self, HouseholdBillItem.self,
                HouseholdAllowanceItem.self,
            ],
            inMemory: true
        )
        .environmentObject(AppState())
}
