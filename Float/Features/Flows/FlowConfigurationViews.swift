import SwiftData
import SwiftUI

struct FlowConfigurationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let flow: CustomFlowItem
    @State private var flowEditor: FlowEditorPresentation?
    @State private var objectEditor: ObjectTypeEditorPresentation?
    @State private var relationEditor: RelationEditorPresentation?
    @State private var actionEditor: TransactionActionEditorPresentation?
    @State private var showingDeleteAlert = false

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

    private var relations: [CustomFlowRelationItem] {
        flow.relations
            .filter { !$0.archived }
            .sorted { lhs, rhs in
                if lhs.sortOrder == rhs.sortOrder {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhs.sortOrder < rhs.sortOrder
            }
    }

    private var transactionActions: [CustomFlowTransactionActionItem] {
        flow.transactionActions
            .filter(\.active)
            .sorted { lhs, rhs in
                if lhs.createdAt == rhs.createdAt {
                    return lhs.name < rhs.name
                }
                return lhs.createdAt < rhs.createdAt
            }
    }

    var body: some View {
        List {
            Section {
                if objectTypes.isEmpty {
                    ConfigurationEmptyRow(
                        icon: "list.bullet.rectangle",
                        title: "No objects",
                        message: "Add an object type before creating records."
                    )
                } else {
                    ForEach(objectTypes) { objectType in
                        NavigationLink {
                            FlowObjectConfigurationView(objectType: objectType)
                        } label: {
                            ConfigurationObjectRow(objectType: objectType)
                        }
                        .contextMenu {
                            Button {
                                objectEditor = ObjectTypeEditorPresentation(
                                    flow: flow,
                                    objectType: objectType
                                )
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                archive(objectType)
                            } label: {
                                Label("Archive", systemImage: "archivebox")
                            }
                        }
                    }
                }
            } header: {
                ConfigurationSectionHeader(title: "Objects") {
                    objectEditor = ObjectTypeEditorPresentation(
                        flow: flow,
                        objectType: nil
                    )
                }
            }

            Section {
                if relations.isEmpty {
                    ConfigurationEmptyRow(
                        icon: "link",
                        title: "No relations",
                        message: "Create links between object types for generated relation fields."
                    )
                } else {
                    ForEach(relations) { relation in
                        ConfigurationRelationRow(
                            relation: relation,
                            summary: relationSummary(relation)
                        )
                    }
                }
            } header: {
                ConfigurationSectionHeader(title: "Relations") {
                    relationEditor = RelationEditorPresentation(flow: flow)
                }
            }

            Section {
                if transactionActions.isEmpty {
                    ConfigurationEmptyRow(
                        icon: "arrow.triangle.2.circlepath",
                        title: "No transaction actions",
                        message: "Create a transaction automatically when a record is finalized."
                    )
                } else {
                    ForEach(transactionActions) { action in
                        ConfigurationTransactionActionRow(action: action)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                actionEditor = TransactionActionEditorPresentation(
                                    flow: flow,
                                    action: action
                                )
                            }
                            .contextMenu {
                                Button {
                                    actionEditor = TransactionActionEditorPresentation(
                                        flow: flow,
                                        action: action
                                    )
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                Button(role: .destructive) {
                                    archive(action)
                                } label: {
                                    Label("Archive", systemImage: "archivebox")
                                }
                            }
                    }
                }
            } header: {
                ConfigurationSectionHeader(title: "Transaction actions") {
                    actionEditor = TransactionActionEditorPresentation(
                        flow: flow,
                        action: nil
                    )
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .navigationTitle("Configuration")
        .navigationBarTitleDisplayMode(.large)
        .floatBackground()
        .toolbar {
            Menu {
                Button {
                    flowEditor = FlowEditorPresentation(flow: flow)
                } label: {
                    Label("Edit Flow", systemImage: "pencil")
                }
                Button {
                    objectEditor = ObjectTypeEditorPresentation(
                        flow: flow,
                        objectType: nil
                    )
                } label: {
                    Label("Add Object", systemImage: "rectangle.stack.badge.plus")
                }
                Button {
                    relationEditor = RelationEditorPresentation(flow: flow)
                } label: {
                    Label("Add Relation", systemImage: "link.badge.plus")
                }
                Button {
                    actionEditor = TransactionActionEditorPresentation(
                        flow: flow,
                        action: nil
                    )
                } label: {
                    Label("Add Transaction Action", systemImage: "arrow.triangle.2.circlepath")
                }
                Divider()
                Button(role: .destructive) {
                    showingDeleteAlert = true
                } label: {
                    Label("Delete", systemImage: "trash")
                        .foregroundStyle(.red)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
        .alert("Delete flow?", isPresented: $showingDeleteAlert) {
            Button("Delete", role: .destructive, action: deleteFlow)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes the flow, its configuration, and all records. Linked transactions stay in your ledger.")
        }
        .sheet(item: $flowEditor) { presentation in
            FlowEditorSheet(flow: presentation.flow)
        }
        .sheet(item: $objectEditor) { presentation in
            ObjectTypeEditorSheet(
                flow: presentation.flow,
                objectType: presentation.objectType
            )
        }
        .sheet(item: $relationEditor) { presentation in
            RelationEditorSheet(flow: presentation.flow)
        }
        .sheet(item: $actionEditor) { presentation in
            TransactionActionEditorSheet(
                flow: presentation.flow,
                action: presentation.action
            )
        }
    }

    private func archive(_ objectType: CustomFlowObjectTypeItem) {
        objectType.archived = true
        objectType.updatedAt = Date()
        flow.updatedAt = Date()
        try? modelContext.save()
    }

    private func archive(_ action: CustomFlowTransactionActionItem) {
        try? CustomFlowRepository(modelContext: modelContext)
            .archiveTransactionAction(action)
    }

    private func deleteFlow() {
        try? CustomFlowRepository(modelContext: modelContext).delete(flow)
        dismiss()
    }

    private func relationSummary(_ relation: CustomFlowRelationItem) -> String {
        let source = relation.sourceObjectType?.name ?? String(localized: "Unknown")
        let target = relation.targetObjectType?.name ?? String(localized: "Unknown")
        return "\(source) -> \(target)"
    }
}

private struct ConfigurationSectionHeader: View {
    let title: LocalizedStringResource
    let action: () -> Void

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Button("Add", action: action)
                .font(.subheadline.weight(.semibold))
                .textCase(nil)
        }
    }
}

private struct ConfigurationEmptyRow: View {
    let icon: String
    let title: LocalizedStringResource
    let message: LocalizedStringResource

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: icon)
                .font(.body.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 28)
        }
        .padding(.vertical, 4)
    }
}

private struct ConfigurationObjectRow: View {
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

private struct ConfigurationRelationRow: View {
    let relation: CustomFlowRelationItem
    let summary: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(relation.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        } icon: {
            Image(
                systemName: relation.kind == .hasMany
                    ? "rectangle.stack"
                    : "arrowshape.turn.up.left"
            )
            .font(.body.weight(.medium))
            .foregroundStyle(.secondary)
            .frame(width: 28)
        }
        .padding(.vertical, 4)
    }
}

private struct ConfigurationTransactionActionRow: View {
    let action: CustomFlowTransactionActionItem

    var body: some View {
        Label {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(action.name)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(action.isExpense ? "Expense" : "Income")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.body.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 28)
        }
        .padding(.vertical, 4)
    }

    private var summary: String {
        let object = action.sourceObjectType?.name ?? String(localized: "Unknown")
        let trigger = action.trigger.title
        return "\(object) · \(trigger)"
    }
}
