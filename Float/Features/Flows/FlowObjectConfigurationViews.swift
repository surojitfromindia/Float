import SwiftData
import SwiftUI

struct FlowObjectConfigurationView: View {
    @Environment(\.modelContext) private var modelContext
    let objectType: CustomFlowObjectTypeItem
    @State private var fieldEditor: FieldEditorPresentation?
    @State private var objectEditor: ObjectTypeEditorPresentation?

    private var recordCount: Int {
        objectType.records.filter { $0.status != .archived }.count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Object")
                        .font(.headline)
                    Spacer()
                    if objectType.flow != nil {
                        Button("Edit", action: editObject)
                            .font(.subheadline.weight(.medium))
                    }
                }

                ObjectConfigurationCard(
                    objectType: objectType,
                    recordCount: recordCount
                )

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
            }
            .padding(20)
            .padding(.bottom, 120)
        }
        .navigationTitle("Configuration")
        .floatBackground()
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
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
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
}

private struct ObjectConfigurationCard: View {
    let objectType: CustomFlowObjectTypeItem
    let recordCount: Int

    private var tint: Color {
        Color(hex: objectType.flow?.colorHex ?? "#0E7C7B")
    }

    var body: some View {
        GlassCard {
            HStack(spacing: 14) {
                FloatIconBadge(icon: objectType.iconKey, tint: tint, size: 42)
                VStack(alignment: .leading, spacing: 5) {
                    Text(objectType.name)
                        .font(.headline)
                        .lineLimit(1)
                    Text(objectType.singularName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
            }
        }
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
