import SwiftUI

struct FlowDetailView: View {
    let flow: CustomFlowItem
    @State private var showingConfiguration = false
    @State private var showingHelp = false

    private var objectTypes: [CustomFlowObjectTypeItem] {
        flow.objectTypes
            .filter { !$0.archived && !$0.hiddenInFlow }
            .sorted { lhs, rhs in
                if lhs.sortOrder == rhs.sortOrder {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhs.sortOrder < rhs.sortOrder
            }
    }

    var body: some View {
        List {
            Section("Objects") {
                if objectTypes.isEmpty {
                    FlowDetailEmptyObjectsRow {
                        showingConfiguration = true
                    }
                } else {
                    ForEach(objectTypes) { objectType in
                        NavigationLink {
                            FlowObjectTypeView(objectType: objectType)
                        } label: {
                            FlowDetailObjectRow(objectType: objectType)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
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

private struct FlowDetailObjectRow: View {
    let objectType: CustomFlowObjectTypeItem

    var body: some View {
        Label {
            Text(objectType.name)
                .font(.body.weight(.medium))
                .lineLimit(1)
        } icon: {
            Image(systemName: objectType.iconKey)
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28)
        }
        .padding(.vertical, 5)
    }
}

private struct FlowDetailEmptyObjectsRow: View {
    let openConfiguration: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                VStack(alignment: .leading, spacing: 3) {
                    Text("No objects")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Text("Add an object type before creating records.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "list.bullet.rectangle")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 28)
            }

            Button("Open Configuration", action: openConfiguration)
                .font(.subheadline.weight(.semibold))
        }
        .padding(.vertical, 4)
    }
}
