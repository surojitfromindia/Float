import SwiftData
import SwiftUI

struct FlowDetailView: View {
    @Environment(\.modelContext) private var modelContext
    let flow: CustomFlowItem
    @State private var flowEditor: FlowEditorPresentation?
    @State private var objectEditor: ObjectTypeEditorPresentation?
    @State private var relationEditor: RelationEditorPresentation?
    @State private var actionEditor: TransactionActionEditorPresentation?
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
                            FlowObjectTypeView(objectType: objectType)
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
        .navigationTitle(flow.name)
        .floatBackground()
        .toolbar {
            Button {
                showingHelp = true
            } label: {
                Image(systemName: "questionmark.circle")
            }
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
            } label: {
                Image(systemName: "ellipsis.circle")
            }
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
        .sheet(isPresented: $showingHelp) {
            FlowHelpSheet()
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

    private func relationSummary(_ relation: CustomFlowRelationItem) -> String {
        let source = relation.sourceObjectType?.name ?? String(localized: "Unknown")
        let target = relation.targetObjectType?.name ?? String(localized: "Unknown")
        return "\(source) -> \(target)"
    }
}

private struct ObjectTypeCard: View {
    let objectType: CustomFlowObjectTypeItem

    private var tint: Color {
        Color(hex: objectType.flow?.colorHex ?? "#0E7C7B")
    }

    private var recordCount: Int {
        objectType.records.filter { $0.status != .archived }.count
    }

    var body: some View {
        GlassCard {
            HStack(spacing: 14) {
                FloatIconBadge(icon: objectType.iconKey, tint: tint, size: 42)
                VStack(alignment: .leading, spacing: 5) {
                    Text(objectType.name)
                        .font(.headline)
                        .lineLimit(1)
                    Text(
                        String(
                            localized: "\(objectType.activeFields.count) fields · \(recordCount) records"
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
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

private struct FlowObjectTypeView: View {
    @Environment(\.modelContext) private var modelContext
    let objectType: CustomFlowObjectTypeItem
    @State private var recordEditor: RecordEditorPresentation?
    @State private var fieldEditor: FieldEditorPresentation?
    @State private var objectEditor: ObjectTypeEditorPresentation?
    @State private var actionMessage: String?

    private var records: [CustomFlowRecordItem] {
        objectType.records
            .filter { $0.status != .archived }
            .sorted { lhs, rhs in
                if lhs.sortOrder == rhs.sortOrder {
                    return lhs.createdAt > rhs.createdAt
                }
                return lhs.sortOrder < rhs.sortOrder
            }
    }

    private var transactionActions: [CustomFlowTransactionActionItem] {
        objectType.flow?.transactionActions
            .filter { $0.active && $0.sourceObjectType?.id == objectType.id }
            .sorted { $0.name < $1.name } ?? []
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(
                    title: "Fields",
                    actionTitle: "Add",
                    action: {
                        fieldEditor = FieldEditorPresentation(
                            objectType: objectType,
                            field: nil
                        )
                    }
                )

                if objectType.activeFields.isEmpty {
                    GlassCard {
                        EmptyStateView(
                            icon: "text.badge.plus",
                            title: "No fields",
                            message: "Add fields to generate the record form."
                        )
                    }
                } else {
                    ForEach(objectType.activeFields) { field in
                        FieldRow(field: field)
                            .contextMenu {
                                Button {
                                    fieldEditor = FieldEditorPresentation(
                                        objectType: objectType,
                                        field: field
                                    )
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                Button(role: .destructive) {
                                    archive(field)
                                } label: {
                                    Label("Archive", systemImage: "archivebox")
                                }
                            }
                    }
                }

                SectionHeader(
                    title: "Records",
                    actionTitle: "Add",
                    action: {
                        recordEditor = RecordEditorPresentation(
                            objectType: objectType,
                            record: nil
                        )
                    }
                )

                if let actionMessage {
                    GlassCard(padding: 12) {
                        Text(actionMessage)
                            .font(.footnote)
                            .foregroundStyle(Color(hex: "#B4613B"))
                    }
                }

                if records.isEmpty {
                    GlassCard {
                        EmptyStateView(
                            icon: objectType.iconKey,
                            title: "No records",
                            message: "Create a record from this generated form."
                        )
                    }
                } else {
                    ForEach(records) { record in
                        Button {
                            recordEditor = RecordEditorPresentation(
                                objectType: objectType,
                                record: record
                            )
                        } label: {
                            RecordCard(
                                record: record,
                                objectType: objectType,
                                transactionActions: transactionActions
                            )
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                recordEditor = RecordEditorPresentation(
                                    objectType: objectType,
                                    record: record
                                )
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            ForEach(transactionActions) { action in
                                Button {
                                    materialize(record, action: action)
                                } label: {
                                    Label(
                                        transactionActionTitle(for: record, action: action),
                                        systemImage: "arrow.triangle.2.circlepath"
                                    )
                                }
                            }
                            Button(role: .destructive) {
                                archive(record)
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
        .navigationTitle(objectType.name)
        .floatBackground()
        .toolbar {
            Menu {
                Button {
                    recordEditor = RecordEditorPresentation(
                        objectType: objectType,
                        record: nil
                    )
                } label: {
                    Label("Add Record", systemImage: "plus")
                }
                Button {
                    fieldEditor = FieldEditorPresentation(
                        objectType: objectType,
                        field: nil
                    )
                } label: {
                    Label("Add Field", systemImage: "text.badge.plus")
                }
                if let flow = objectType.flow {
                    Button {
                        objectEditor = ObjectTypeEditorPresentation(
                            flow: flow,
                            objectType: objectType
                        )
                    } label: {
                        Label("Edit Object", systemImage: "pencil")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
        .sheet(item: $recordEditor) { presentation in
            FlowRecordEditorView(
                objectType: presentation.objectType,
                record: presentation.record
            )
        }
        .sheet(item: $fieldEditor) { presentation in
            FieldEditorSheet(
                objectType: presentation.objectType,
                field: presentation.field
            )
        }
        .sheet(item: $objectEditor) { presentation in
            ObjectTypeEditorSheet(
                flow: presentation.flow,
                objectType: presentation.objectType
            )
        }
    }

    private func archive(_ field: CustomFlowFieldItem) {
        field.archived = true
        field.updatedAt = Date()
        objectType.updatedAt = Date()
        objectType.flow?.updatedAt = Date()
        try? modelContext.save()
    }

    private func archive(_ record: CustomFlowRecordItem) {
        record.status = .archived
        record.updatedAt = Date()
        try? modelContext.save()
    }

    private func materialize(
        _ record: CustomFlowRecordItem,
        action: CustomFlowTransactionActionItem
    ) {
        do {
            _ = try CustomFlowRepository(modelContext: modelContext)
                .materializeTransaction(for: record, action: action)
            actionMessage = String(localized: "Transaction linked.")
        } catch {
            actionMessage = error.localizedDescription
        }
    }

    private func transactionActionTitle(
        for record: CustomFlowRecordItem,
        action: CustomFlowTransactionActionItem
    ) -> String {
        if record.transactionLinks.first(where: { $0.action?.id == action.id })?.transaction == nil {
            return String(localized: "Create linked transaction")
        }
        return String(localized: "Update linked transaction")
    }
}

private struct FieldRow: View {
    let field: CustomFlowFieldItem

    var body: some View {
        GlassCard(padding: 14) {
            HStack(spacing: 12) {
                FloatIconBadge(
                    icon: field.kind.icon,
                    tint: Color(hex: field.objectType?.flow?.colorHex ?? "#0E7C7B"),
                    size: 34
                )
                VStack(alignment: .leading, spacing: 3) {
                    Text(field.name)
                        .font(.subheadline.weight(.semibold))
                    Text(field.kind.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let formulaIssue {
                        Text(formulaIssue.message)
                            .font(.caption2)
                            .foregroundStyle(Color(hex: "#B4613B"))
                            .lineLimit(2)
                    }
                }
                Spacer()
                if field.required {
                    Text("Required")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var formulaIssue: CustomFlowFormulaValidationIssue? {
        guard field.kind == .formula,
              let objectType = field.objectType
        else { return nil }
        return CustomFlowFormulaEngine.validate(field: field, in: objectType).first
    }
}

private struct RecordCard: View {
    let record: CustomFlowRecordItem
    let objectType: CustomFlowObjectTypeItem
    let transactionActions: [CustomFlowTransactionActionItem]

    private var tint: Color {
        Color(hex: objectType.flow?.colorHex ?? "#0E7C7B")
    }

    var body: some View {
        GlassCard {
            HStack(spacing: 14) {
                FloatIconBadge(icon: objectType.iconKey, tint: tint, size: 42)
                VStack(alignment: .leading, spacing: 5) {
                    Text(record.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text(recordSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(record.status.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    if let transactionStatus {
                        Text(transactionStatus)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(transactionStatus == String(localized: "Unlinked") ? Color(hex: "#B4613B") : .secondary)
                    }
                }
            }
        }
    }

    private var transactionStatus: String? {
        guard !transactionActions.isEmpty,
              record.status == .finalized
        else { return nil }
        let matchingLinks = record.transactionLinks.filter { link in
            transactionActions.contains { $0.id == link.action?.id }
        }
        if matchingLinks.contains(where: { $0.transaction != nil }) {
            return String(localized: "Linked")
        }
        return String(localized: "Unlinked")
    }

    private var recordSummary: String {
        let values = objectType.activeFields
            .filter { $0.kind != .notes }
            .prefix(3)
            .compactMap { field -> String? in
                if field.kind == .formula {
                    return try? CustomFlowFormulaEngine.value(
                        for: field,
                        record: record,
                        records: objectType.flow?.objectTypes.flatMap(\.records) ?? objectType.records
                    ).displayText(currencyCode: nil)
                }
                return record.value(for: field)?.displayText(for: field, currencyCode: nil)
            }
        return values.isEmpty
            ? record.createdAt.formatted(date: .abbreviated, time: .omitted)
            : values.joined(separator: " · ")
    }
}
