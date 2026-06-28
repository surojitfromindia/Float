import SwiftUI

struct FlowDetailView: View {
    let flow: CustomFlowItem
    @State private var showingConfiguration = false
    @State private var showingHelp = false

    private var objectTypes: [CustomFlowObjectTypeItem] {
        flow.objectTypes
            .filter { !$0.archived }
            .sorted { lhs, rhs in
                if lhs.sortOrder == rhs.sortOrder {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhs.sortOrder < rhs.sortOrder
            }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(title: "Objects")

                if objectTypes.isEmpty {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 14) {
                            EmptyStateView(
                                icon: "list.bullet.rectangle",
                                title: "No objects",
                                message: "Add an object type before creating records."
                            )

                            Button("Open Configuration") {
                                showingConfiguration = true
                            }
                            .font(.subheadline.weight(.medium))
                        }
                    }
                } else {
                    ForEach(objectTypes) { objectType in
                        NavigationLink {
                            FlowObjectTypeView(objectType: objectType)
                        } label: {
                            ObjectTypeCard(objectType: objectType)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(20)
            .padding(.bottom, 120)
        }
        .navigationTitle(flow.name)
        .floatBackground()
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showingConfiguration = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .accessibilityLabel("Configuration")

                Button {
                    showingHelp = true
                } label: {
                    Image(systemName: "questionmark.circle")
                }
            }
        }
        .navigationDestination(isPresented: $showingConfiguration) {
            FlowConfigurationView(flow: flow)
        }
        .sheet(isPresented: $showingHelp) {
            FlowHelpSheet()
        }
    }
}
