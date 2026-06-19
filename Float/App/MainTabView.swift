import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        TabView(selection: $appState.selectedTab) {
            NavigationStack { HomeView() }
                .tabItem { Label("Home", systemImage: "square.grid.2x2") }
                .tag(FloatTab.home)
            NavigationStack { TransactionsView() }
                .tabItem { Label("List", systemImage: "line.3.horizontal.decrease") }
                .tag(FloatTab.transactions)
            NavigationStack { SettlementsView() }
                .tabItem { Label("Settlements", systemImage: "person.2.fill") }
                .tag(FloatTab.settlements)
            NavigationStack { InsightsView() }
                .tabItem {
                    Label("Stats", systemImage: "chart.xyaxis.line")
                }
                .tag(FloatTab.insights)
            NavigationStack { SettingsView() }
                .tabItem { Label("More", systemImage: "ellipsis") }
                .tag(FloatTab.settings)
        }
        .tint(appState.themePalette.accent)
        .toolbarBackground(.thinMaterial, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .sheet(isPresented: $appState.isEntrySheetPresented) {
            QuickAddKeypadSheet(
                transactionToEdit: appState.editingTransaction,
                initialTimestamp: appState.newTransactionTimestamp,
                initialIsExpense: appState.newTransactionIsExpense
            )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $appState.isTransferSheetPresented) {
            TransferEditorSheet(
                transferToEdit: appState.editingTransfer,
                initialTimestamp: appState.newTransferTimestamp
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }
}
