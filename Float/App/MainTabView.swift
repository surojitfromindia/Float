import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        TabView {
            NavigationStack { HomeView() }
                .tabItem { Label("Home", systemImage: "house") }
            NavigationStack { TransactionsView() }
                .tabItem { Label("List", systemImage: "list.bullet") }
            NavigationStack { InsightsView() }
                .tabItem {
                    Label("Stats", systemImage: "chart.line.uptrend.xyaxis")
                }
            NavigationStack { SettingsView() }
                .tabItem { Label("More", systemImage: "gearshape.fill") }
        }
        .tint(appState.themePalette.accent)
        .toolbarBackground(.thinMaterial, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .sheet(isPresented: $appState.isEntrySheetPresented) {
            QuickAddKeypadSheet(transactionToEdit: appState.editingTransaction)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }
}
