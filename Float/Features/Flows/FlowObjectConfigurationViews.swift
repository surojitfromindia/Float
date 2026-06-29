import SwiftData
import SwiftUI

struct FlowObjectConfigurationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let objectType: CustomFlowObjectTypeItem
    @State private var fieldEditor: FieldEditorPresentation?
    @State private var objectEditor: ObjectTypeEditorPresentation?
    @State private var showingDeleteAlert = false

    private var recordCount: Int {
        objectType.records.filter { $0.status != .archived }.count
    }

    var body: some View {
        Form {
            Section {
                ObjectConfigurationSummaryRow(
                    objectType: objectType,
                    recordCount: recordCount
                )
            } header: {
                HStack {
                    Text("Object")
                    Spacer()
                    if objectType.flow != nil {
                        Button("Edit", action: editObject)
                            .font(.caption.weight(.semibold))
                            .textCase(nil)
                    }
                }
                .textCase(nil)
            }

            Section {
                if objectType.activeFields.isEmpty {
                    Label {
                        Text("Add fields to generate the record form.")
                            .foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: "text.badge.plus")
                            .foregroundStyle(.tertiary)
                    }
                } else {
                    ForEach(objectType.activeFields) { field in
                        Button {
                            fieldEditor = FieldEditorPresentation(
                                objectType: objectType,
                                field: field
                            )
                        } label: {
                            ObjectConfigurationFieldRow(field: field)
                        }
                        .buttonStyle(.plain)
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
            } header: {
                HStack {
                    Text("Fields")
                    Spacer()
                    Button("Add") {
                        fieldEditor = FieldEditorPresentation(
                            objectType: objectType,
                            field: nil
                        )
                    }
                    .font(.caption.weight(.semibold))
                    .textCase(nil)
                }
                .textCase(nil)
            }
        }
        .navigationTitle("Configuration")
        .navigationBarTitleDisplayMode(.inline)
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .floatBackground()
        .tint(tint)
        .toolbar {
            Menu {
                Button {
                    fieldEditor = FieldEditorPresentation(
                        objectType: objectType,
                        field: nil
                    )
                } label: {
                    Label("Add Field", systemImage: "text.badge.plus")
                }
                if objectType.flow != nil {
                    Button(action: editObject) {
                        Label("Edit Object", systemImage: "pencil")
                    }
                    Divider()
                    Button(role: .destructive) {
                        showingDeleteAlert = true
                    } label: {
                        Label {
                            Text("Delete")
                        } icon: {
                            Image(systemName: "trash")
                                .foregroundStyle(.red)
                        }
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
        .alert("Delete object?", isPresented: $showingDeleteAlert) {
            Button("Delete", role: .destructive, action: deleteObject)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes the object, its fields, and all records.")
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

    private func editObject() {
        guard let flow = objectType.flow else { return }
        objectEditor = ObjectTypeEditorPresentation(
            flow: flow,
            objectType: objectType
        )
    }

    private func archive(_ field: CustomFlowFieldItem) {
        field.archived = true
        field.updatedAt = Date()
        objectType.updatedAt = Date()
        objectType.flow?.updatedAt = Date()
        try? modelContext.save()
    }

    private func deleteObject() {
        guard let flow = objectType.flow else { return }
        let objectID = objectType.id
        let fieldIDs = Set(objectType.fields.map(\.id))

        for relation in flow.relations where
            relation.sourceObjectType?.id == objectID
                || relation.targetObjectType?.id == objectID {
            modelContext.delete(relation)
        }

        for action in flow.transactionActions where
            action.sourceObjectType?.id == objectID
                || action.amountField.map({ fieldIDs.contains($0.id) }) == true
                || action.categoryField.map({ fieldIDs.contains($0.id) }) == true
                || action.accountField.map({ fieldIDs.contains($0.id) }) == true
                || action.dateField.map({ fieldIDs.contains($0.id) }) == true
                || action.noteField.map({ fieldIDs.contains($0.id) }) == true {
            modelContext.delete(action)
        }

        flow.updatedAt = Date()
        modelContext.delete(objectType)
        try? modelContext.save()
        dismiss()
    }

    private var tint: Color {
        Color(hex: objectType.flow?.colorHex ?? "#0E7C7B")
    }
}

private struct ObjectConfigurationSummaryRow: View {
    let objectType: CustomFlowObjectTypeItem
    let recordCount: Int

    private var tint: Color {
        Color(hex: objectType.flow?.colorHex ?? "#0E7C7B")
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: objectType.iconKey)
                .font(.headline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(objectType.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(objectType.singularName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(metadata)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)
        }
        .padding(.vertical, 4)
    }

    private var metadata: String {
        String(localized: "\(objectType.activeFields.count) fields · \(recordCount) records")
    }
}

private struct ObjectConfigurationFieldRow: View {
    let field: CustomFlowFieldItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: field.kind.icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(field.name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if field.required {
                        Text("Required")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.tertiary.opacity(0.18), in: Capsule())
                    }
                }

                Text(field.kind.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let formulaIssue {
                    Text(formulaIssue.message)
                        .font(.caption)
                        .foregroundStyle(Color(hex: "#B4613B"))
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private var formulaIssue: CustomFlowFormulaValidationIssue? {
        guard field.kind == .formula,
              let objectType = field.objectType
        else { return nil }
        return CustomFlowFormulaEngine.validate(field: field, in: objectType).first
    }
}
