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
    @State private var recordDetail: RecordDetailPresentation?
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
                            recordDetail = RecordDetailPresentation(
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
        .sheet(item: $recordDetail) { presentation in
            FlowRecordDetailSheet(
                objectType: presentation.objectType,
                record: presentation.record
            ) {
                let objectType = presentation.objectType
                let record = presentation.record
                recordDetail = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    recordEditor = RecordEditorPresentation(
                        objectType: objectType,
                        record: record
                    )
                }
            }
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

struct FlowRecordDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let objectType: CustomFlowObjectTypeItem
    let record: CustomFlowRecordItem
    let onEdit: () -> Void

    private var tint: Color {
        Color(hex: objectType.flow?.colorHex ?? "#0E7C7B")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Record") {
                    HStack(spacing: 12) {
                        FloatIconBadge(icon: objectType.iconKey, tint: tint, size: 34)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(record.title)
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text(record.status.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }

                    detailRow(
                        title: String(localized: "Created"),
                        value: record.createdAt.formatted(date: .abbreviated, time: .shortened)
                    )
                    detailRow(
                        title: String(localized: "Updated"),
                        value: record.updatedAt.formatted(date: .abbreviated, time: .shortened)
                    )
                }

                Section("Fields") {
                    let displayFields = objectType.activeFields
                    if displayFields.isEmpty {
                        Text("No fields configured.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(displayFields) { field in
                            fieldDisplay(field)
                        }
                    }
                }
            }
            .navigationTitle("Record Details")
            .navigationBarTitleDisplayMode(.inline)
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .floatBackground()
            .tint(tint)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Edit", action: onEdit)
                }
            }
        }
    }

    @ViewBuilder
    private func fieldDisplay(_ field: CustomFlowFieldItem) -> some View {
        if field.kind == .lineItem {
            lineItemFieldDisplay(field)
        } else if field.kind == .notes {
            VStack(alignment: .leading, spacing: 8) {
                fieldLabel(field)
                Text(displayValue(for: field))
                    .foregroundStyle(hasDisplayValue(for: field) ? .primary : .secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            HStack(spacing: 12) {
                fieldLabel(field)
                Spacer(minLength: 16)
                Text(displayValue(for: field))
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(hasDisplayValue(for: field) ? .primary : .secondary)
            }
        }
    }

    @ViewBuilder
    private func lineItemFieldDisplay(_ field: CustomFlowFieldItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            fieldLabel(field)

            let lineItems = lineItemRecords(for: field)
            if lineItems.isEmpty {
                Text("No line items yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(lineItems) { lineItem in
                    lineItemRecordRow(lineItem, parentField: field)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func lineItemRecordRow(
        _ lineItem: CustomFlowRecordItem,
        parentField: CustomFlowFieldItem
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: lineItem.objectType?.iconKey ?? parentField.kind.icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(parentField.kind.tint)
                .frame(width: 18, height: 20)

            VStack(alignment: .leading, spacing: 4) {
                Text(lineItem.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if let summary = lineItemSummary(for: lineItem, parentField: parentField) {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(.tertiary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private func fieldLabel(_ field: CustomFlowFieldItem) -> some View {
        Label {
            Text(field.name)
                .foregroundStyle(.secondary)
        } icon: {
            Image(systemName: field.kind.icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(field.kind.tint)
                .frame(width: 18)
        }
    }

    private func detailRow(title: String, value: String) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer(minLength: 16)
            Text(value)
                .multilineTextAlignment(.trailing)
        }
    }

    private func displayValue(for field: CustomFlowFieldItem) -> String {
        if field.kind == .formula {
            return formulaDisplay(for: field) ?? String(localized: "No value")
        }
        return record.value(for: field)?.displayText(for: field, currencyCode: nil)
            ?? String(localized: "No value")
    }

    private func hasDisplayValue(for field: CustomFlowFieldItem) -> Bool {
        if field.kind == .formula {
            return formulaDisplay(for: field) != nil
        }
        if field.kind == .lineItem {
            return !lineItemRecords(for: field).isEmpty
        }
        return record.value(for: field)?.displayText(for: field, currencyCode: nil) != nil
    }

    private func formulaDisplay(for field: CustomFlowFieldItem) -> String? {
        try? CustomFlowFormulaEngine.value(
            for: field,
            record: record,
            records: objectType.flow?.objectTypes.flatMap(\.records) ?? objectType.records
        ).displayText(currencyCode: nil)
    }

    private func lineItemRecords(for field: CustomFlowFieldItem) -> [CustomFlowRecordItem] {
        guard let relation = field.relation,
              let childObject = childObjectType(for: relation)
        else { return [] }

        if relation.targetObjectType?.id == objectType.id {
            return childObject.records
                .filter { $0.status != .archived }
                .filter { $0.parentRecord?.id == record.id || childRecord($0, pointsTo: record, through: relation) }
                .sorted { $0.createdAt < $1.createdAt }
        }

        return childObject.records
            .filter { $0.status != .archived }
            .filter { childRecord($0, pointsTo: record, through: relation) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    private func childRecord(
        _ childRecord: CustomFlowRecordItem,
        pointsTo parentRecord: CustomFlowRecordItem,
        through relation: CustomFlowRelationItem
    ) -> Bool {
        childRecord.values.contains { value in
            value.field?.relation?.id == relation.id
                && value.relatedRecord?.id == parentRecord.id
        }
    }

    private func childObjectType(for relation: CustomFlowRelationItem) -> CustomFlowObjectTypeItem? {
        if relation.targetObjectType?.id == objectType.id {
            return relation.sourceObjectType
        }
        if relation.sourceObjectType?.id == objectType.id {
            return relation.targetObjectType
        }
        return nil
    }

    private func lineItemSummary(
        for lineItem: CustomFlowRecordItem,
        parentField: CustomFlowFieldItem
    ) -> String? {
        guard let childObject = lineItem.objectType else { return nil }
        let values = childObject.activeFields
            .filter { !isParentRelationField($0, for: parentField) }
            .filter { $0.kind != .notes && $0.kind != .lineItem }
            .compactMap { childField -> String? in
                let value: String?
                if childField.kind == .formula {
                    value = try? CustomFlowFormulaEngine.value(
                        for: childField,
                        record: lineItem,
                        records: objectType.flow?.objectTypes.flatMap(\.records) ?? childObject.records
                    ).displayText(currencyCode: nil)
                } else {
                    value = lineItem.value(for: childField)?.displayText(for: childField, currencyCode: nil)
                }
                return value.map { "\(childField.name): \($0)" }
            }
            .prefix(3)
        let summary = values.joined(separator: " · ")
        return summary.flowNilIfBlank
    }

    private func isParentRelationField(
        _ childField: CustomFlowFieldItem,
        for parentField: CustomFlowFieldItem
    ) -> Bool {
        childField.kind == .relation
            && childField.relation?.id == parentField.relation?.id
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
