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
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(
                    title: "Objects",
                    actionTitle: "Add",
                    action: {
                        objectEditor = ObjectTypeEditorPresentation(
                            flow: flow,
                            objectType: nil
                        )
                    }
                )

                if objectTypes.isEmpty {
                    GlassCard {
                        EmptyStateView(
                            icon: "list.bullet.rectangle",
                            title: "No objects",
                            message: "Add an object type before creating records."
                        )
                    }
                } else {
                    ForEach(objectTypes) { objectType in
                        NavigationLink {
                            FlowObjectConfigurationView(objectType: objectType)
                        } label: {
                            ObjectTypeCard(objectType: objectType)
                        }
                        .buttonStyle(.plain)
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

                SectionHeader(
                    title: "Relations",
                    actionTitle: "Add",
                    action: {
                        relationEditor = RelationEditorPresentation(flow: flow)
                    }
                )

                if relations.isEmpty {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("No relations")
                                .font(.headline)
                            Text("Create links between object types for generated relation fields.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    ForEach(relations) { relation in
                        GlassCard(padding: 14) {
                            HStack(spacing: 12) {
                                FloatIconBadge(
                                    icon: relation.kind == .hasMany
                                        ? "rectangle.stack.fill"
                                        : "arrowshape.turn.up.left.fill",
                                    tint: Color(hex: flow.colorHex),
                                    size: 34
                                )
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(relation.name)
                                        .font(.subheadline.weight(.semibold))
                                    Text(relationSummary(relation))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                        }
                    }
                }

                SectionHeader(
                    title: "Transaction actions",
                    actionTitle: "Add",
                    action: {
                        actionEditor = TransactionActionEditorPresentation(
                            flow: flow,
                            action: nil
                        )
                    }
                )

                if transactionActions.isEmpty {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("No transaction actions")
                                .font(.headline)
                            Text("Create a transaction automatically when a record is finalized.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    ForEach(transactionActions) { action in
                        TransactionActionCard(action: action)
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
            }
            .padding(20)
            .padding(.bottom, 120)
        }
        .navigationTitle("Configuration")
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

private struct TransactionActionCard: View {
    let action: CustomFlowTransactionActionItem

    private var tint: Color {
        Color(hex: action.flow?.colorHex ?? "#0E7C7B")
    }

    var body: some View {
        GlassCard(padding: 14) {
            HStack(spacing: 12) {
                FloatIconBadge(
                    icon: "arrow.triangle.2.circlepath",
                    tint: tint,
                    size: 34
                )
                VStack(alignment: .leading, spacing: 4) {
                    Text(action.name)
                        .font(.subheadline.weight(.semibold))
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Text(action.isExpense ? "Expense" : "Income")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var summary: String {
        let object = action.sourceObjectType?.name ?? String(localized: "Unknown")
        let trigger = action.trigger.title
        return "\(object) · \(trigger)"
    }
}
