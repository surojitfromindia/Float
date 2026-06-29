import SwiftUI

struct FormulaBuilderView: View {
    let objectType: CustomFlowObjectTypeItem
    let editingFieldID: UUID?
    @Binding var definition: CustomFlowFormulaDefinition
    @State private var showingHelp = false

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Build a calculated field")
                        .font(.subheadline.weight(.semibold))
                    Text("Choose a result type, then fill in the inputs it needs.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                FormulaNodeEditor(
                    objectType: objectType,
                    editingFieldID: editingFieldID,
                    role: String(localized: "Result"),
                    node: $definition.root
                )
            }
            .padding(.vertical, 4)
        } header: {
            HStack(spacing: 6) {
                Text("Formula")
                Button {
                    showingHelp = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color(hex: "#0E7C7B"))
                .accessibilityLabel("Formula help")
            }
        }
        .sheet(isPresented: $showingHelp) {
            FormulaHelpSheet()
        }
    }
}

private struct FormulaNodeEditor: View {
    let objectType: CustomFlowObjectTypeItem
    let editingFieldID: UUID?
    let role: String
    var depth = 0
    @Binding var node: CustomFlowFormulaNode

    private var nodeKind: Binding<FormulaNodeKind> {
        Binding(
            get: { FormulaNodeKind(node: node) },
            set: { node = $0.defaultNode(objectType: objectType, editingFieldID: editingFieldID) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FormulaNodeHeader(
                role: role,
                kind: nodeKind,
                summary: summary(for: node),
                depth: depth
            )

            switch node {
            case .number(let value):
                FormulaInputRow("Value", systemImage: "number") {
                    TextField(
                        "Number",
                        value: Binding(
                            get: { value },
                            set: { node = .number($0) }
                        ),
                        format: .number
                    )
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                }
            case .text(let value):
                FormulaInputRow("Text", systemImage: "text.quote") {
                    TextField(
                        "Text",
                        text: Binding(
                            get: { value },
                            set: { node = .text($0) }
                        )
                    )
                    .multilineTextAlignment(.trailing)
                }
            case .bool(let value):
                FormulaInputRow("Value", systemImage: "checkmark.circle") {
                    Toggle(
                        "True or false",
                        isOn: Binding(
                            get: { value },
                            set: { node = .bool($0) }
                        )
                    )
                    .labelsHidden()
                }
            case .field(let fieldID):
                fieldPicker(
                    "Field",
                    icon: "square.text.square",
                    selection: Binding(
                        get: { Optional(fieldID) },
                        set: { newValue in
                            if let newValue {
                                node = .field(newValue)
                            }
                        }
                    ),
                    fields: availableFields
                )
            case .arithmetic(let op, let lhs, let rhs):
                FormulaInputRow("Operation", systemImage: "function") {
                    Picker(
                        "Operation",
                        selection: Binding(
                            get: { op },
                            set: { node = .arithmetic($0, lhs, rhs) }
                        )
                    ) {
                        Text(CustomFlowFormulaArithmeticOperator.add.title)
                            .tag(CustomFlowFormulaArithmeticOperator.add)
                        Text(CustomFlowFormulaArithmeticOperator.subtract.title)
                            .tag(CustomFlowFormulaArithmeticOperator.subtract)
                        Text(CustomFlowFormulaArithmeticOperator.multiply.title)
                            .tag(CustomFlowFormulaArithmeticOperator.multiply)
                        Text(CustomFlowFormulaArithmeticOperator.divide.title)
                            .tag(CustomFlowFormulaArithmeticOperator.divide)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
                nested("Left") {
                    FormulaNodeEditor(
                        objectType: objectType,
                        editingFieldID: editingFieldID,
                        role: String(localized: "Left value"),
                        depth: depth + 1,
                        node: Binding(
                            get: { lhs },
                            set: { node = .arithmetic(op, $0, rhs) }
                        )
                    )
                }
                nested("Right") {
                    FormulaNodeEditor(
                        objectType: objectType,
                        editingFieldID: editingFieldID,
                        role: String(localized: "Right value"),
                        depth: depth + 1,
                        node: Binding(
                            get: { rhs },
                            set: { node = .arithmetic(op, lhs, $0) }
                        )
                    )
                }
            case .comparison(let op, let lhs, let rhs):
                FormulaInputRow("Rule", systemImage: "equal.circle") {
                    Picker(
                        "Comparison",
                        selection: Binding(
                            get: { op },
                            set: { node = .comparison($0, lhs, rhs) }
                        )
                    ) {
                        Text(CustomFlowFormulaComparisonOperator.equal.title)
                            .tag(CustomFlowFormulaComparisonOperator.equal)
                        Text(CustomFlowFormulaComparisonOperator.notEqual.title)
                            .tag(CustomFlowFormulaComparisonOperator.notEqual)
                        Text(CustomFlowFormulaComparisonOperator.greaterThan.title)
                            .tag(CustomFlowFormulaComparisonOperator.greaterThan)
                        Text(CustomFlowFormulaComparisonOperator.greaterThanOrEqual.title)
                            .tag(CustomFlowFormulaComparisonOperator.greaterThanOrEqual)
                        Text(CustomFlowFormulaComparisonOperator.lessThan.title)
                            .tag(CustomFlowFormulaComparisonOperator.lessThan)
                        Text(CustomFlowFormulaComparisonOperator.lessThanOrEqual.title)
                            .tag(CustomFlowFormulaComparisonOperator.lessThanOrEqual)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
                nested("Left") {
                    FormulaNodeEditor(
                        objectType: objectType,
                        editingFieldID: editingFieldID,
                        role: String(localized: "Left value"),
                        depth: depth + 1,
                        node: Binding(
                            get: { lhs },
                            set: { node = .comparison(op, $0, rhs) }
                        )
                    )
                }
                nested("Right") {
                    FormulaNodeEditor(
                        objectType: objectType,
                        editingFieldID: editingFieldID,
                        role: String(localized: "Right value"),
                        depth: depth + 1,
                        node: Binding(
                            get: { rhs },
                            set: { node = .comparison(op, lhs, $0) }
                        )
                    )
                }
            case .condition(let condition, let thenNode, let elseNode):
                nested("When") {
                    FormulaNodeEditor(
                        objectType: objectType,
                        editingFieldID: editingFieldID,
                        role: String(localized: "Condition test"),
                        depth: depth + 1,
                        node: Binding(
                            get: { condition },
                            set: { node = .condition(condition: $0, then: thenNode, else: elseNode) }
                        )
                    )
                }
                nested("Then") {
                    FormulaNodeEditor(
                        objectType: objectType,
                        editingFieldID: editingFieldID,
                        role: String(localized: "If true"),
                        depth: depth + 1,
                        node: Binding(
                            get: { thenNode },
                            set: { node = .condition(condition: condition, then: $0, else: elseNode) }
                        )
                    )
                }
                nested("Otherwise") {
                    FormulaNodeEditor(
                        objectType: objectType,
                        editingFieldID: editingFieldID,
                        role: String(localized: "If false"),
                        depth: depth + 1,
                        node: Binding(
                            get: { elseNode },
                            set: { node = .condition(condition: condition, then: thenNode, else: $0) }
                        )
                    )
                }
            case .today:
                FormulaStaticNote(
                    icon: "calendar",
                    text: String(localized: "Uses today's date.")
                )
            case .addDays(let date, let days):
                nested("Date") {
                    FormulaNodeEditor(
                        objectType: objectType,
                        editingFieldID: editingFieldID,
                        role: String(localized: "Start date"),
                        depth: depth + 1,
                        node: Binding(
                            get: { date },
                            set: { node = .addDays(date: $0, days: days) }
                        )
                    )
                }
                nested("Days") {
                    FormulaNodeEditor(
                        objectType: objectType,
                        editingFieldID: editingFieldID,
                        role: String(localized: "Days to add"),
                        depth: depth + 1,
                        node: Binding(
                            get: { days },
                            set: { node = .addDays(date: date, days: $0) }
                        )
                    )
                }
            case .daysBetween(let start, let end):
                nested("Start") {
                    FormulaNodeEditor(
                        objectType: objectType,
                        editingFieldID: editingFieldID,
                        role: String(localized: "Start date"),
                        depth: depth + 1,
                        node: Binding(
                            get: { start },
                            set: { node = .daysBetween(start: $0, end: end) }
                        )
                    )
                }
                nested("End") {
                    FormulaNodeEditor(
                        objectType: objectType,
                        editingFieldID: editingFieldID,
                        role: String(localized: "End date"),
                        depth: depth + 1,
                        node: Binding(
                            get: { end },
                            set: { node = .daysBetween(start: start, end: $0) }
                        )
                    )
                }
            case .relationLookup(let relationFieldID, let targetFieldID):
                fieldPicker(
                    "Relation field",
                    icon: "link",
                    selection: Binding(
                        get: { Optional(relationFieldID) },
                        set: { newValue in
                            if let newValue {
                                let nextTarget = targetFields(for: newValue).first?.id ?? targetFieldID
                                node = .relationLookup(relationFieldID: newValue, targetFieldID: nextTarget)
                            }
                        }
                    ),
                    fields: relationFields
                )
                fieldPicker(
                    "Target field",
                    icon: "target",
                    selection: Binding(
                        get: { Optional(targetFieldID) },
                        set: { newValue in
                            if let newValue {
                                node = .relationLookup(relationFieldID: relationFieldID, targetFieldID: newValue)
                            }
                        }
                    ),
                    fields: targetFields(for: relationFieldID)
                )
            case .childSum(let relationID, let fieldID):
                FormulaInputRow("Child relation", systemImage: "rectangle.stack") {
                    Picker(
                        "Child relation",
                        selection: Binding(
                            get: { Optional(relationID) },
                            set: { newValue in
                                if let newValue {
                                    let nextField = childFields(for: newValue).first?.id ?? fieldID
                                    node = .childSum(relationID: newValue, fieldID: nextField)
                                }
                            }
                        )
                    ) {
                        Text("Choose").tag(Optional<UUID>.none)
                        ForEach(childRelations) { relation in
                            Text(relation.name).tag(Optional(relation.id))
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
                fieldPicker(
                    "Child field",
                    icon: "sum",
                    selection: Binding(
                        get: { Optional(fieldID) },
                        set: { newValue in
                            if let newValue {
                                node = .childSum(relationID: relationID, fieldID: newValue)
                            }
                        }
                    ),
                    fields: childFields(for: relationID)
                )
            }
        }
        .padding(depth == 0 ? 0 : 10)
        .background(depth == 0 ? Color.clear : Color.primary.opacity(0.018), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var availableFields: [CustomFlowFieldItem] {
        objectType.activeFields.filter {
            $0.id != editingFieldID && $0.kind != .lineItem
        }
    }

    private var relationFields: [CustomFlowFieldItem] {
        availableFields.filter { $0.kind == .relation }
    }

    private var childRelations: [CustomFlowRelationItem] {
        objectType.flow?.relations
            .filter { !$0.archived }
            .filter {
                $0.sourceObjectType?.id == objectType.id
                    || $0.targetObjectType?.id == objectType.id
            }
            .sortedBySortOrder() ?? []
    }

    @ViewBuilder
    private func fieldPicker(
        _ title: LocalizedStringResource,
        icon: String,
        selection: Binding<UUID?>,
        fields: [CustomFlowFieldItem]
    ) -> some View {
        FormulaInputRow(title, systemImage: icon) {
            Picker(title, selection: selection) {
                Text("Choose").tag(Optional<UUID>.none)
                ForEach(fields) { field in
                    Text(field.name).tag(Optional(field.id))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
    }

    @ViewBuilder
    private func nested<Content: View>(
        _ title: LocalizedStringResource,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content()
                .padding(.leading, 10)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(Color(hex: "#0E7C7B").opacity(0.2))
                        .frame(width: 2)
                }
        }
    }

    private func targetFields(for relationFieldID: UUID) -> [CustomFlowFieldItem] {
        guard let relationField = relationFields.first(where: { $0.id == relationFieldID }),
              let relation = relationField.relation
        else { return [] }
        let target = relation.targetObjectType?.id == objectType.id
            ? relation.sourceObjectType
            : relation.targetObjectType
        return target?.activeFields.filter { $0.kind != .lineItem } ?? []
    }

    private func childFields(for relationID: UUID) -> [CustomFlowFieldItem] {
        guard let relation = childRelations.first(where: { $0.id == relationID }) else { return [] }
        let child = relation.targetObjectType?.id == objectType.id
            ? relation.sourceObjectType
            : relation.targetObjectType
        return child?.activeFields.filter {
            [.number, .money, .formula].contains($0.kind)
        } ?? []
    }

    private func summary(for node: CustomFlowFormulaNode) -> String {
        switch node {
        case .number:
            String(localized: "Fixed number")
        case .text:
            String(localized: "Fixed text")
        case .bool:
            String(localized: "True or false value")
        case .field(let fieldID):
            availableFields.first(where: { $0.id == fieldID })?.name ?? String(localized: "Choose a field")
        case .arithmetic(let op, _, _):
            String(localized: "Combines two values with \(op.title).")
        case .comparison(let op, _, _):
            String(localized: "Checks whether two values match \(op.title).")
        case .condition:
            String(localized: "Returns one value when a rule is true and another when it is false.")
        case .today:
            String(localized: "The current date when the formula runs.")
        case .addDays:
            String(localized: "Adds a number of days to a date.")
        case .daysBetween:
            String(localized: "Counts the days between two dates.")
        case .relationLookup:
            String(localized: "Reads a field from a related record.")
        case .childSum:
            String(localized: "Adds values from related child rows.")
        }
    }
}

private struct FormulaNodeHeader: View {
    let role: String
    @Binding var kind: FormulaNodeKind
    let summary: String
    let depth: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: kind.icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(hex: "#0E7C7B"))
                    .frame(width: 22, height: 22)
                    .background(Color(hex: "#0E7C7B").opacity(0.12), in: Circle())
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(role)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(kind.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }

                Spacer(minLength: 8)

                FormulaKindMenu(kind: $kind)
            }

            Text(summary)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct FormulaKindMenu: View {
    @Binding var kind: FormulaNodeKind

    var body: some View {
        Menu {
            Picker("Formula type", selection: $kind) {
                ForEach(FormulaNodeKind.allCases) { option in
                    Label(option.title, systemImage: option.icon)
                        .tag(option)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(kind.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .truncationMode(.tail)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(.blue)
            .frame(maxWidth: 118, alignment: .trailing)
            .contentShape(Rectangle())
        }
    }
}

private struct FormulaInputRow<Content: View>: View {
    let title: LocalizedStringResource
    let systemImage: String
    @ViewBuilder let content: Content

    init(
        _ title: LocalizedStringResource,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Label {
                Text(title)
                    .font(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            } icon: {
                Image(systemName: systemImage)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
            }

            Spacer(minLength: 8)

            content
                .font(.caption)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(Color.primary.opacity(0.02), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

private struct FormulaStaticNote: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(hex: "#0E7C7B"))
                .frame(width: 18)
                .accessibilityHidden(true)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 8)
    }
}

private struct FormulaHelpSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let examples = [
        FormulaHelpExample(
            title: String(localized: "Line total"),
            expression: String(localized: "Quantity x Price"),
            detail: String(localized: "Use Arithmetic when one calculated value depends on two fields.")
        ),
        FormulaHelpExample(
            title: String(localized: "Remaining balance"),
            expression: String(localized: "Amount borrowed - Repaid"),
            detail: String(localized: "Use Arithmetic with money fields to calculate what is still due.")
        ),
        FormulaHelpExample(
            title: String(localized: "Status summary"),
            expression: String(localized: "If Remaining balance is 0, show Repaid."),
            detail: String(localized: "Use Condition when the value should change based on a rule.")
        ),
        FormulaHelpExample(
            title: String(localized: "Trip total"),
            expression: String(localized: "Sum all child expense rows"),
            detail: String(localized: "Use Child-row sum when a parent record needs totals from related rows.")
        )
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: "function")
                            .font(.system(size: 32, weight: .semibold))
                            .foregroundStyle(Color(hex: "#0E7C7B"))
                            .accessibilityHidden(true)

                        Text("Formula builder")
                            .font(.largeTitle.weight(.bold))
                            .lineLimit(2)
                            .minimumScaleFactor(0.82)

                        Text("Formulas calculate a field from fixed values, other fields, dates, related records, or child rows. Pick the result type first, then fill each required input.")
                            .font(.body)
                            .lineSpacing(3)
                            .foregroundStyle(.secondary)
                    }

                    FormulaHelpSection(
                        title: String(localized: "How to read the builder"),
                        items: [
                            String(localized: "Result is the final value saved for this formula field."),
                            String(localized: "Nested inputs show the parts used to build that result, such as left and right values."),
                            String(localized: "Change any type menu to replace that part of the formula without writing code.")
                        ]
                    )

                    FormulaHelpSection(
                        title: String(localized: "Available formula types"),
                        items: [
                            String(localized: "Field value reads another field from the same record."),
                            String(localized: "Arithmetic adds, subtracts, multiplies, or divides two values."),
                            String(localized: "Condition returns one value when a comparison is true and another when it is false."),
                            String(localized: "Date helpers can use today, add days, or count days between dates."),
                            String(localized: "Relation lookup reads a value from a connected record."),
                            String(localized: "Child-row sum totals values from related child records.")
                        ]
                    )

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Useful examples")
                            .font(.title3.weight(.semibold))

                        ForEach(examples) { example in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(example.title)
                                    .font(.headline)
                                Text(example.expression)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color(hex: "#0E7C7B"))
                                Text(example.detail)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)

                            if example.id != examples.last?.id {
                                Divider()
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 22)
                .padding(.bottom, 36)
            }
            .navigationTitle("Formula Help")
            .navigationBarTitleDisplayMode(.inline)
            .floatBackground()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct FormulaHelpSection: View {
    let title: String
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3.weight(.semibold))

            VStack(alignment: .leading, spacing: 10) {
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Circle()
                            .fill(Color(hex: "#0E7C7B"))
                            .frame(width: 5, height: 5)
                            .padding(.top, 8)
                            .accessibilityHidden(true)
                        Text(item)
                            .font(.subheadline)
                            .lineSpacing(2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

private struct FormulaHelpExample: Identifiable {
    let id = UUID()
    let title: String
    let expression: String
    let detail: String
}

private enum FormulaNodeKind: String, CaseIterable, Identifiable {
    case number
    case text
    case bool
    case field
    case arithmetic
    case comparison
    case condition
    case today
    case addDays
    case daysBetween
    case relationLookup
    case childSum

    var id: String { rawValue }

    init(node: CustomFlowFormulaNode) {
        switch node {
        case .number: self = .number
        case .text: self = .text
        case .bool: self = .bool
        case .field: self = .field
        case .arithmetic: self = .arithmetic
        case .comparison: self = .comparison
        case .condition: self = .condition
        case .today: self = .today
        case .addDays: self = .addDays
        case .daysBetween: self = .daysBetween
        case .relationLookup: self = .relationLookup
        case .childSum: self = .childSum
        }
    }

    var title: String {
        switch self {
        case .number: String(localized: "Number")
        case .text: String(localized: "Text")
        case .bool: String(localized: "True or false")
        case .field: String(localized: "Field value")
        case .arithmetic: String(localized: "Arithmetic")
        case .comparison: String(localized: "Comparison")
        case .condition: String(localized: "Condition")
        case .today: String(localized: "Today")
        case .addDays: String(localized: "Add days")
        case .daysBetween: String(localized: "Days between")
        case .relationLookup: String(localized: "Relation lookup")
        case .childSum: String(localized: "Child-row sum")
        }
    }

    var icon: String {
        switch self {
        case .number: "number"
        case .text: "text.quote"
        case .bool: "checkmark.circle"
        case .field: "square.text.square"
        case .arithmetic: "function"
        case .comparison: "equal.circle"
        case .condition: "arrow.triangle.branch"
        case .today: "calendar"
        case .addDays: "calendar.badge.plus"
        case .daysBetween: "calendar.badge.clock"
        case .relationLookup: "link"
        case .childSum: "sum"
        }
    }

    func defaultNode(
        objectType: CustomFlowObjectTypeItem,
        editingFieldID: UUID?
    ) -> CustomFlowFormulaNode {
        let fields = objectType.activeFields.filter { $0.id != editingFieldID }
        let firstField = fields.first?.id ?? UUID()
        let relationField = fields.first { $0.kind == .relation }
        let childRelation = objectType.flow?.relations.first {
            !$0.archived
                && ($0.sourceObjectType?.id == objectType.id || $0.targetObjectType?.id == objectType.id)
        }
        let childObject = childRelation?.targetObjectType?.id == objectType.id
            ? childRelation?.sourceObjectType
            : childRelation?.targetObjectType
        switch self {
        case .number:
            return .number(0)
        case .text:
            return .text("")
        case .bool:
            return .bool(false)
        case .field:
            return .field(firstField)
        case .arithmetic:
            return .arithmetic(.add, .field(firstField), .number(0))
        case .comparison:
            return .comparison(.greaterThan, .field(firstField), .number(0))
        case .condition:
            return .condition(condition: .bool(true), then: .text(""), else: .text(""))
        case .today:
            return .today
        case .addDays:
            return .addDays(date: .today, days: .number(0))
        case .daysBetween:
            return .daysBetween(start: .today, end: .today)
        case .relationLookup:
            return .relationLookup(
                relationFieldID: relationField?.id ?? UUID(),
                targetFieldID: relationField?.relation?.targetObjectType?.activeFields.first?.id ?? UUID()
            )
        case .childSum:
            return .childSum(
                relationID: childRelation?.id ?? UUID(),
                fieldID: childObject?.activeFields.first(where: {
                    [.number, .money, .formula].contains($0.kind)
                })?.id ?? UUID()
            )
        }
    }
}
