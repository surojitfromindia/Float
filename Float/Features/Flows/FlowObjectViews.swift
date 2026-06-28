import SwiftData
import SwiftUI

struct ObjectTypeCard: View {
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

struct FlowObjectTypeView: View {
    @Environment(\.modelContext) private var modelContext
    let objectType: CustomFlowObjectTypeItem
    @State private var recordEditor: RecordEditorPresentation?
    @State private var actionMessage: String?
    @State private var showingConfiguration = false

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
                SectionHeader(title: "Records")

                if let actionMessage {
                    GlassCard(padding: 12) {
                        Text(actionMessage)
                            .font(.footnote)
                            .foregroundStyle(Color(hex: "#B4613B"))
                    }
                }

                if objectType.activeFields.isEmpty {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 14) {
                            EmptyStateView(
                                icon: "text.badge.plus",
                                title: "No fields",
                                message: "Add fields to generate the record form."
                            )

                            Button("Open Configuration") {
                                showingConfiguration = true
                            }
                            .font(.subheadline.weight(.medium))
                        }
                    }
                } else if records.isEmpty {
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
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button(action: presentRecordEditor) {
                    Image(systemName: "plus")
                }

                Button {
                    showingConfiguration = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .accessibilityLabel("Configuration")
            }
        }
        .navigationDestination(isPresented: $showingConfiguration) {
            FlowObjectConfigurationView(objectType: objectType)
        }
        .sheet(item: $recordEditor) { presentation in
            FlowRecordEditorView(
                objectType: presentation.objectType,
                record: presentation.record
            )
        }
    }

    private func presentRecordEditor() {
        guard !objectType.activeFields.isEmpty else {
            showingConfiguration = true
            return
        }

        recordEditor = RecordEditorPresentation(
            objectType: objectType,
            record: nil
        )
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
