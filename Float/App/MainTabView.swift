import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedTab = FloatTab.home

    var body: some View {
        TabView(selection: $selectedTab) {
            DeferredTabContent(tab: .home, selection: $selectedTab) {
                NavigationStack { HomeView() }
            }
                .tabItem { Label("Home", systemImage: "square.grid.2x2") }
                .tag(FloatTab.home)
            DeferredTabContent(tab: .transactions, selection: $selectedTab) {
                NavigationStack { TransactionsView() }
            }
                .tabItem { Label("List", systemImage: "line.3.horizontal.decrease") }
                .tag(FloatTab.transactions)
            DeferredTabContent(tab: .settlements, selection: $selectedTab) {
                NavigationStack { SettlementsView() }
            }
                .tabItem { Label("Settlements", systemImage: "person.2.fill") }
                .tag(FloatTab.settlements)
            DeferredTabContent(tab: .insights, selection: $selectedTab) {
                NavigationStack { InsightsView() }
            }
                .tabItem {
                    Label("Stats", systemImage: "chart.xyaxis.line")
                }
                .tag(FloatTab.insights)
            DeferredTabContent(tab: .settings, selection: $selectedTab) {
                NavigationStack { SettingsView() }
            }
                .tabItem { Label("More", systemImage: "ellipsis") }
                .tag(FloatTab.settings)
        }
        .tint(appState.themePalette.accent)
        .toolbarBackground(.thinMaterial, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .onAppear {
            selectedTab = appState.selectedTab
        }
        .onChange(of: selectedTab) { _, newTab in
            appState.selectTabFromTabBar(newTab)
        }
        .onChange(of: appState.selectedTabRouteID) { _, _ in
            selectedTab = appState.selectedTab
        }
        .sheet(isPresented: $appState.isEntrySheetPresented) {
            QuickAddKeypadSheet(
                transactionToEdit: appState.editingTransaction,
                initialTimestamp: appState.newTransactionTimestamp,
                initialIsExpense: appState.newTransactionIsExpense,
                initialAmountMinor: appState.newTransactionAmountMinor,
                initialNote: appState.newTransactionNote
            )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $appState.isReceiptCapturePresented) {
            ReceiptCaptureFlow()
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
        .id(appState.activeProfileID)
    }
}

private struct DeferredTabContent<Content: View>: View {
    let tab: FloatTab
    @Binding var selection: FloatTab
    @State private var hasLoaded = false
    private let content: () -> Content

    init(
        tab: FloatTab,
        selection: Binding<FloatTab>,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.tab = tab
        self._selection = selection
        self.content = content
    }

    var body: some View {
        Group {
            if hasLoaded || selection == tab {
                content()
            } else {
                Color.clear
            }
        }
        .onAppear(perform: markLoadedIfSelected)
        .onChange(of: selection) { _, _ in
            markLoadedIfSelected()
        }
    }

    private func markLoadedIfSelected() {
        if selection == tab {
            hasLoaded = true
        }
    }
}
