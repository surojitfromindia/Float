import SwiftData
import SwiftUI

struct FlowEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let flow: CustomFlowItem?
    @State private var name = ""
    @State private var iconKey = "rectangle.stack.fill"
    @State private var colorHex = "#0E7C7B"
    @State private var validationMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                TextField("Icon", text: $iconKey)
                    .textInputAutocapitalization(.never)
                TextField("Color", text: $colorHex)
                    .textInputAutocapitalization(.never)
                if let validationMessage {
                    Text(validationMessage)
                        .font(.footnote)
                        .foregroundStyle(Color(hex: "#B4613B"))
                }
            }
            .navigationTitle(flow == nil ? "New Flow" : "Edit Flow")
            .keyboardDismissControls()
            .scrollContentBackground(.hidden)
            .floatBackground()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                }
            }
            .onAppear(perform: configure)
        }
    }

    private func configure() {
        guard let flow else { return }
        name = flow.name
        iconKey = flow.iconKey
        colorHex = flow.colorHex
    }

    private func save() {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            validationMessage = String(localized: "Enter a name.")
            return
        }
        do {
            let repository = CustomFlowRepository(modelContext: modelContext)
            if let flow {
                try repository.updateFlow(
                    flow,
                    name: name,
                    iconKey: iconKey,
                    colorHex: colorHex,
                    sortOrder: flow.sortOrder,
                    archived: flow.archived
                )
            } else {
                _ = try repository.createFlow(
                    name: name,
                    iconKey: iconKey,
                    colorHex: colorHex
                )
            }
            dismiss()
        } catch {
            validationMessage = error.localizedDescription
        }
    }
}

struct ObjectTypeEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let flow: CustomFlowItem
    let objectType: CustomFlowObjectTypeItem?
    @State private var name = ""
    @State private var singularName = ""
    @State private var iconKey = "list.bullet.rectangle"
    @State private var validationMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                TextField("Plural name", text: $name)
                TextField("Singular name", text: $singularName)
                TextField("Icon", text: $iconKey)
                    .textInputAutocapitalization(.never)
                if let validationMessage {
                    Text(validationMessage)
                        .font(.footnote)
                        .foregroundStyle(Color(hex: "#B4613B"))
                }
            }
            .navigationTitle(objectType == nil ? "New Object" : "Edit Object")
            .keyboardDismissControls()
            .scrollContentBackground(.hidden)
            .floatBackground()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                }
            }
            .onAppear(perform: configure)
        }
    }

    private func configure() {
        guard let objectType else { return }
        name = objectType.name
        singularName = objectType.singularName
        iconKey = objectType.iconKey
    }

    private func save() {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            validationMessage = String(localized: "Enter a name.")
            return
        }
        do {
            let repository = CustomFlowRepository(modelContext: modelContext)
            if let objectType {
                try repository.updateObjectType(
                    objectType,
                    name: name,
                    singularName: singularName,
                    iconKey: iconKey,
                    sortOrder: objectType.sortOrder,
                    archived: objectType.archived
                )
            } else {
                _ = try repository.createObjectType(
                    in: flow,
                    name: name,
                    singularName: singularName,
                    iconKey: iconKey,
                    sortOrder: flow.objectTypes.count
                )
            }
            dismiss()
        } catch {
            validationMessage = error.localizedDescription
        }
    }
}

struct RelationEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let flow: CustomFlowItem
    @State private var name = ""
    @State private var kind = CustomFlowRelationKind.hasMany
    @State private var sourceObjectTypeID: UUID?
    @State private var targetObjectTypeID: UUID?
    @State private var validationMessage: String?

    private var objectTypes: [CustomFlowObjectTypeItem] {
        flow.objectTypes.filter { !$0.archived && !$0.hiddenInFlow }.sortedBySortOrder()
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                Picker("Kind", selection: $kind) {
                    ForEach(CustomFlowRelationKind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                Picker("Source", selection: $sourceObjectTypeID) {
                    Text("Choose").tag(Optional<UUID>.none)
                    ForEach(objectTypes) { objectType in
                        Text(objectType.name).tag(Optional(objectType.id))
                    }
                }
                Picker("Target", selection: $targetObjectTypeID) {
                    Text("Choose").tag(Optional<UUID>.none)
                    ForEach(objectTypes) { objectType in
                        Text(objectType.name).tag(Optional(objectType.id))
                    }
                }
                if let validationMessage {
                    Text(validationMessage)
                        .font(.footnote)
                        .foregroundStyle(Color(hex: "#B4613B"))
                }
            }
            .navigationTitle("New Relation")
            .keyboardDismissControls()
            .scrollContentBackground(.hidden)
            .floatBackground()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                }
            }
            .onAppear {
                sourceObjectTypeID = sourceObjectTypeID ?? objectTypes.first?.id
                targetObjectTypeID = targetObjectTypeID ?? objectTypes.dropFirst().first?.id ?? objectTypes.first?.id
            }
        }
    }

    private func save() {
        guard let source = sourceObjectTypeID.flatMap(objectType),
              let target = targetObjectTypeID.flatMap(objectType)
        else {
            validationMessage = String(localized: "Choose source and target objects.")
            return
        }
        do {
            _ = try CustomFlowRepository(modelContext: modelContext)
                .createRelation(
                    in: flow,
                    name: name,
                    kind: kind,
                    sourceObjectType: source,
                    targetObjectType: target,
                    sortOrder: flow.relations.count
                )
            dismiss()
        } catch {
            validationMessage = error.localizedDescription
        }
    }

    private func objectType(for id: UUID) -> CustomFlowObjectTypeItem? {
        objectTypes.first { $0.id == id }
    }
}

private enum LineItemConfigurationMode: String, CaseIterable, Identifiable {
    case existingObject
    case customDesign

    var id: String { rawValue }

    var title: String {
        switch self {
        case .existingObject: String(localized: "Existing object")
        case .customDesign: String(localized: "Custom design")
        }
    }
}

struct FieldEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let objectType: CustomFlowObjectTypeItem
    let field: CustomFlowFieldItem?
    @State private var name = ""
    @State private var key = ""
    @State private var kind = CustomFlowFieldKind.text
    @State private var required = false
    @State private var choiceOptionsRaw = ""
    @State private var defaultValueRaw = ""
    @State private var formulaDefinition = CustomFlowFormulaDefinition.empty
    @State private var relationID: UUID?
    @State private var lineItemMode = LineItemConfigurationMode.customDesign
    @State private var lineItemObjectTypeID: UUID?
    @State private var validationMessage: String?

    private var availableRelations: [CustomFlowRelationItem] {
        objectType.flow?.relations
            .filter { !$0.archived }
            .filter { relation in
                relation.sourceObjectType?.id == objectType.id
                    || relation.targetObjectType?.id == objectType.id
            }
            .sortedBySortOrder() ?? []
    }

    private var availableLineItemObjectTypes: [CustomFlowObjectTypeItem] {
        objectType.flow?.objectTypes
            .filter { !$0.archived && !$0.hiddenInFlow && $0.id != objectType.id }
            .sortedBySortOrder() ?? []
    }

    private var configuredLineItemChildObject: CustomFlowObjectTypeItem? {
        guard let relation = relationID.flatMap(relation) else { return nil }
        return childObjectType(for: relation)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                TextField("Key", text: $key)
                    .textInputAutocapitalization(.never)
                Picker("Type", selection: $kind) {
                    ForEach(CustomFlowFieldKind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                Toggle("Required", isOn: $required)
                if kind == .choice {
                    TextField("Choices", text: $choiceOptionsRaw, axis: .vertical)
                        .lineLimit(2...5)
                }
                if kind == .relation {
                    Picker("Relation", selection: $relationID) {
                        Text("Choose").tag(Optional<UUID>.none)
                        ForEach(availableRelations) { relation in
                            Text(relation.name).tag(Optional(relation.id))
                        }
                    }
                }
                if kind == .lineItem {
                    Section("Line items") {
                        Picker("Source", selection: $lineItemMode) {
                            ForEach(LineItemConfigurationMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)

                        switch lineItemMode {
                        case .existingObject:
                            Picker("Object", selection: $lineItemObjectTypeID) {
                                Text("Choose").tag(Optional<UUID>.none)
                                ForEach(availableLineItemObjectTypes) { objectType in
                                    Text(objectType.name).tag(Optional(objectType.id))
                                }
                            }
                        case .customDesign:
                            if let childObject = configuredLineItemChildObject,
                               childObject.hiddenInFlow {
                                NavigationLink {
                                    FlowObjectConfigurationView(objectType: childObject)
                                } label: {
                                    Label("Configure line item fields", systemImage: "slider.horizontal.3")
                                }
                            } else {
                                Text("Save this line item field, then reopen it to add custom fields and formulas.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if kind == .formula {
                    FormulaBuilderView(
                        objectType: objectType,
                        editingFieldID: field?.id,
                        definition: $formulaDefinition
                    )
                } else if kind != .relation && kind != .lineItem {
                    TextField("Default value", text: $defaultValueRaw)
                }
                if let validationMessage {
                    Text(validationMessage)
                        .font(.footnote)
                        .foregroundStyle(Color(hex: "#B4613B"))
                }
            }
            .navigationTitle(field == nil ? "New Field" : "Edit Field")
            .keyboardDismissControls()
            .scrollContentBackground(.hidden)
            .floatBackground()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                }
            }
            .onAppear(perform: configure)
        }
    }

    private func configure() {
        guard let field else { return }
        name = field.name
        key = field.key
        kind = field.kind
        required = field.required
        choiceOptionsRaw = field.choiceOptionsRaw ?? ""
        defaultValueRaw = field.defaultValueRaw ?? ""
        formulaDefinition = field.parsedFormulaDefinition ?? .empty
        relationID = field.relation?.id
        if field.kind == .lineItem,
           let childObject = field.relation.flatMap(childObjectType) {
            lineItemMode = childObject.hiddenInFlow ? .customDesign : .existingObject
            lineItemObjectTypeID = childObject.id
        }
    }

    private func save() {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            validationMessage = String(localized: "Enter a name.")
            return
        }
        let formulaRaw = kind == .formula ? formulaDefinition.rawValue : nil
        if kind == .formula {
            let validationField = field ?? CustomFlowFieldItem(
                id: field?.id ?? UUID(),
                profileID: objectType.profileID,
                name: name,
                key: key,
                kind: .formula,
                formulaDefinitionRaw: formulaRaw
            )
            let issues = CustomFlowFormulaEngine.validate(
                definition: formulaDefinition,
                rootField: validationField,
                in: objectType
            )
            if let firstIssue = issues.first {
                validationMessage = firstIssue.message
                return
            }
        }
        if kind == .lineItem,
           lineItemMode == .existingObject,
           lineItemObjectTypeID.flatMap(lineItemObjectType) == nil {
            validationMessage = String(localized: "Choose a line item object.")
            return
        }
        do {
            let repository = CustomFlowRepository(modelContext: modelContext)
            let relation = try relationForSave(using: repository)
            if let field {
                try repository.updateField(
                    field,
                    name: name,
                    key: key,
                    kind: kind,
                    sortOrder: field.sortOrder,
                    required: required,
                    archived: field.archived,
                    choiceOptionsRaw: choiceOptionsRaw,
                    defaultValueRaw: kind == .lineItem ? nil : defaultValueRaw,
                    formulaDefinitionRaw: formulaRaw,
                    relation: relation
                )
            } else {
                _ = try repository.createField(
                    in: objectType,
                    name: name,
                    key: key,
                    kind: kind,
                    sortOrder: objectType.fields.count,
                    required: required,
                    choiceOptionsRaw: choiceOptionsRaw,
                    defaultValueRaw: kind == .lineItem ? nil : defaultValueRaw,
                    formulaDefinitionRaw: formulaRaw,
                    relation: relation
                )
            }
            dismiss()
        } catch {
            validationMessage = error.localizedDescription
        }
    }

    private func relationForSave(
        using repository: CustomFlowRepository
    ) throws -> CustomFlowRelationItem? {
        if kind == .relation {
            return relationID.flatMap(relation)
        }
        guard kind == .lineItem,
              let flow = objectType.flow
        else { return nil }

        let childObject: CustomFlowObjectTypeItem
        switch lineItemMode {
        case .existingObject:
            guard let selected = lineItemObjectTypeID.flatMap(lineItemObjectType) else {
                throw DataIntegrityError.invalidInput
            }
            childObject = selected
        case .customDesign:
            if let existing = relationID.flatMap(relation).flatMap(childObjectType),
               existing.hiddenInFlow {
                childObject = existing
            } else {
                let baseName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                let pluralName = baseName.isEmpty ? String(localized: "Line Items") : baseName
                childObject = try repository.createObjectType(
                    in: flow,
                    name: pluralName,
                    singularName: singularLineItemName(from: pluralName),
                    iconKey: "list.bullet.rectangle",
                    sortOrder: flow.objectTypes.count,
                    hiddenInFlow: true
                )
            }
        }

        if let existingRelation = relationID.flatMap(relation),
           childObjectType(for: existingRelation)?.id == childObject.id {
            return existingRelation
        }

        return try repository.createRelation(
            in: flow,
            name: String(localized: "\(objectType.singularName) \(childObject.singularName)"),
            kind: .belongsTo,
            sourceObjectType: childObject,
            targetObjectType: objectType,
            sortOrder: flow.relations.count
        )
    }

    private func relation(for id: UUID) -> CustomFlowRelationItem? {
        objectType.flow?.relations.first { $0.id == id }
    }

    private func lineItemObjectType(for id: UUID) -> CustomFlowObjectTypeItem? {
        objectType.flow?.objectTypes.first { $0.id == id && !$0.archived && $0.id != objectType.id }
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

    private func singularLineItemName(from name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = trimmed.lowercased()
        if lowercased == "items" {
            return String(localized: "Item")
        }
        if lowercased.hasSuffix("ies"), trimmed.count > 3 {
            return String(trimmed.dropLast(3)) + "y"
        }
        if lowercased.hasSuffix("s"), trimmed.count > 1 {
            return String(trimmed.dropLast())
        }
        if lowercased.contains("item") {
            return trimmed
        }
        return String(localized: "\(trimmed) Item")
    }
}

struct TransactionActionEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CategoryItem.sortOrder) private var allCategories: [CategoryItem]
    @Query(sort: \AccountItem.createdAt) private var allAccounts: [AccountItem]

    let flow: CustomFlowItem
    let action: CustomFlowTransactionActionItem?

    @State private var name = ""
    @State private var sourceObjectTypeID: UUID?
    @State private var trigger = CustomFlowTransactionActionTrigger.finalize
    @State private var isExpense = true
    @State private var active = true
    @State private var amountFieldID: UUID?
    @State private var categoryFieldID: UUID?
    @State private var accountFieldID: UUID?
    @State private var dateFieldID: UUID?
    @State private var noteFieldID: UUID?
    @State private var fixedAmountText = ""
    @State private var useFixedDate = false
    @State private var fixedDate = Date()
    @State private var fixedCategoryID: UUID?
    @State private var fixedAccountID: UUID?
    @State private var fixedNote = ""
    @State private var validationMessage: String?

    private var objectTypes: [CustomFlowObjectTypeItem] {
        flow.objectTypes.filter { !$0.archived && !$0.hiddenInFlow }.sortedBySortOrder()
    }

    private var selectedObjectType: CustomFlowObjectTypeItem? {
        sourceObjectTypeID.flatMap { id in
            objectTypes.first { $0.id == id }
        }
    }

    private var fields: [CustomFlowFieldItem] {
        selectedObjectType?.activeFields ?? []
    }

    private var moneyFields: [CustomFlowFieldItem] {
        fields.filter { $0.kind == .money || $0.kind == .formula }
    }

    private var categoryFields: [CustomFlowFieldItem] {
        fields.filter { $0.kind == .category }
    }

    private var accountFields: [CustomFlowFieldItem] {
        fields.filter { $0.kind == .account }
    }

    private var dateFields: [CustomFlowFieldItem] {
        fields.filter { $0.kind == .dateTime }
    }

    private var noteFields: [CustomFlowFieldItem] {
        fields.filter { [.text, .notes, .choice].contains($0.kind) }
    }

    private var categories: [CategoryItem] {
        filterActiveProfile(allCategories).filter { !$0.archived }
    }

    private var accounts: [AccountItem] {
        filterActiveProfile(allAccounts).filter { !$0.archived }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Action") {
                    TextField("Name", text: $name)
                    Picker("Source object", selection: $sourceObjectTypeID) {
                        Text("Choose").tag(Optional<UUID>.none)
                        ForEach(objectTypes) { objectType in
                            Text(objectType.name).tag(Optional(objectType.id))
                        }
                    }
                    Picker("Trigger", selection: $trigger) {
                        ForEach(CustomFlowTransactionActionTrigger.allCases) { trigger in
                            Text(trigger.title).tag(trigger)
                        }
                    }
                    Picker("Type", selection: $isExpense) {
                        Text("Expense").tag(true)
                        Text("Income").tag(false)
                    }
                    Toggle("Active", isOn: $active)
                }

                Section("Transaction mapping") {
                    fieldPicker(
                        "Amount field",
                        selection: $amountFieldID,
                        fields: moneyFields
                    )
                    TextField("Fixed amount", text: $fixedAmountText)
                        .keyboardType(.decimalPad)
                    fieldPicker(
                        "Category field",
                        selection: $categoryFieldID,
                        fields: categoryFields
                    )
                    Picker("Fixed category", selection: $fixedCategoryID) {
                        Text("Choose").tag(Optional<UUID>.none)
                        ForEach(categories) { category in
                            Label(category.name, systemImage: category.iconKey)
                                .tag(Optional(category.id))
                        }
                    }
                    fieldPicker(
                        "Account field",
                        selection: $accountFieldID,
                        fields: accountFields
                    )
                    Picker("Fixed account", selection: $fixedAccountID) {
                        Text("Choose").tag(Optional<UUID>.none)
                        ForEach(accounts) { account in
                            Label(account.name, systemImage: account.type.icon)
                                .tag(Optional(account.id))
                        }
                    }
                    fieldPicker(
                        "Date field",
                        selection: $dateFieldID,
                        fields: dateFields
                    )
                    Toggle("Use fixed date", isOn: $useFixedDate)
                    if useFixedDate {
                        DatePicker(
                            "Fixed date",
                            selection: $fixedDate,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                    }
                    fieldPicker(
                        "Note field",
                        selection: $noteFieldID,
                        fields: noteFields
                    )
                    TextField("Fixed note", text: $fixedNote, axis: .vertical)
                        .lineLimit(2...4)
                }

                if let validationMessage {
                    Section {
                        Text(validationMessage)
                            .font(.footnote)
                            .foregroundStyle(Color(hex: "#B4613B"))
                    }
                }
            }
            .navigationTitle(action == nil ? "New Transaction Action" : "Edit Transaction Action")
            .keyboardDismissControls()
            .scrollContentBackground(.hidden)
            .floatBackground()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                }
            }
            .onAppear(perform: configure)
            .onChange(of: sourceObjectTypeID) {
                reconcileFieldSelections()
            }
        }
    }

    @ViewBuilder
    private func fieldPicker(
        _ title: LocalizedStringResource,
        selection: Binding<UUID?>,
        fields: [CustomFlowFieldItem]
    ) -> some View {
        Picker(title, selection: selection) {
            Text("Choose").tag(Optional<UUID>.none)
            ForEach(fields) { field in
                Text(field.name).tag(Optional(field.id))
            }
        }
    }

    private func configure() {
        if let action {
            name = action.name
            sourceObjectTypeID = action.sourceObjectType?.id
            trigger = action.trigger
            isExpense = action.isExpense
            active = action.active
            amountFieldID = action.amountField?.id
            categoryFieldID = action.categoryField?.id
            accountFieldID = action.accountField?.id
            dateFieldID = action.dateField?.id
            noteFieldID = action.noteField?.id
            if let fixedAmountMinor = action.fixedAmountMinor {
                fixedAmountText = Self.majorAmountText(
                    fixedAmountMinor,
                    currencyCode: MoneyFormatter.currencyCodeFromLocale()
                )
            }
            if let actionFixedDate = action.fixedDate {
                useFixedDate = true
                fixedDate = actionFixedDate
            }
            fixedCategoryID = action.fixedCategory?.id
            fixedAccountID = action.fixedAccount?.id
            fixedNote = action.fixedNote ?? ""
        } else {
            name = String(localized: "Create transaction")
            sourceObjectTypeID = objectTypes.first?.id
            amountFieldID = moneyFields.first?.id
            categoryFieldID = categoryFields.first?.id
            accountFieldID = accountFields.first?.id
            dateFieldID = dateFields.first?.id
            noteFieldID = noteFields.first?.id
        }
        reconcileFieldSelections()
    }

    private func reconcileFieldSelections() {
        if !moneyFields.contains(where: { $0.id == amountFieldID }) {
            amountFieldID = nil
        }
        if !categoryFields.contains(where: { $0.id == categoryFieldID }) {
            categoryFieldID = nil
        }
        if !accountFields.contains(where: { $0.id == accountFieldID }) {
            accountFieldID = nil
        }
        if !dateFields.contains(where: { $0.id == dateFieldID }) {
            dateFieldID = nil
        }
        if !noteFields.contains(where: { $0.id == noteFieldID }) {
            noteFieldID = nil
        }
    }

    private func save() {
        guard let sourceObjectType = selectedObjectType else {
            validationMessage = String(localized: "Choose a source object.")
            return
        }
        let amountField = amountFieldID.flatMap(field)
        let fixedAmountMinor = fixedAmountText.flowNilIfBlank.map {
            MoneyParser.parseDisplayAmountMinor(
                from: $0,
                currencyCode: MoneyFormatter.currencyCodeFromLocale()
            )
        }
        let categoryField = categoryFieldID.flatMap(field)
        let accountField = accountFieldID.flatMap(field)
        let fixedCategory = fixedCategoryID.flatMap(category)
        let fixedAccount = fixedAccountID.flatMap(account)
        guard amountField != nil || (fixedAmountMinor ?? 0) > 0 else {
            validationMessage = String(localized: "Choose an amount field or fixed amount.")
            return
        }
        guard categoryField != nil || fixedCategory != nil else {
            validationMessage = String(localized: "Choose a category field or fixed category.")
            return
        }
        guard accountField != nil || fixedAccount != nil else {
            validationMessage = String(localized: "Choose an account field or fixed account.")
            return
        }

        do {
            let repository = CustomFlowRepository(modelContext: modelContext)
            if let action {
                try repository.updateTransactionAction(
                    action,
                    name: name,
                    sourceObjectType: sourceObjectType,
                    trigger: trigger,
                    isExpense: isExpense,
                    active: active,
                    amountField: amountField,
                    categoryField: categoryField,
                    accountField: accountField,
                    dateField: dateFieldID.flatMap(field),
                    noteField: noteFieldID.flatMap(field),
                    fixedAmountMinor: fixedAmountMinor,
                    fixedDate: useFixedDate ? fixedDate : nil,
                    fixedCategory: fixedCategory,
                    fixedAccount: fixedAccount,
                    fixedNote: fixedNote
                )
            } else {
                _ = try repository.createTransactionAction(
                    in: flow,
                    name: name,
                    sourceObjectType: sourceObjectType,
                    trigger: trigger,
                    isExpense: isExpense,
                    amountField: amountField,
                    categoryField: categoryField,
                    accountField: accountField,
                    dateField: dateFieldID.flatMap(field),
                    noteField: noteFieldID.flatMap(field),
                    fixedAmountMinor: fixedAmountMinor,
                    fixedDate: useFixedDate ? fixedDate : nil,
                    fixedCategory: fixedCategory,
                    fixedAccount: fixedAccount,
                    fixedNote: fixedNote
                )
            }
            dismiss()
        } catch {
            validationMessage = error.localizedDescription
        }
    }

    private func field(for id: UUID) -> CustomFlowFieldItem? {
        fields.first { $0.id == id }
    }

    private func category(for id: UUID) -> CategoryItem? {
        categories.first { $0.id == id }
    }

    private func account(for id: UUID) -> AccountItem? {
        accounts.first { $0.id == id }
    }

    private static func majorAmountText(
        _ amountMinor: Int64,
        currencyCode: String
    ) -> String {
        let fractionDigits = MoneyFormatter.fractionDigits(for: currencyCode)
        let divisor = pow(10.0, Double(fractionDigits))
        let major = Double(amountMinor) / divisor
        return major.formatted(.number.precision(.fractionLength(0...fractionDigits)))
    }
}

struct FlowRecordEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @Query(sort: \CategoryItem.sortOrder) private var allCategories: [CategoryItem]
    @Query(sort: \AccountItem.createdAt) private var allAccounts: [AccountItem]
    @Query(sort: \PersonItem.createdAt) private var allPeople: [PersonItem]
    @Query(sort: \CustomFlowRecordItem.createdAt, order: .reverse) private var allRecords:
        [CustomFlowRecordItem]

    let objectType: CustomFlowObjectTypeItem
    let record: CustomFlowRecordItem?
    @State private var title = ""
    @State private var status = CustomFlowRecordStatus.draft
    @State private var draftValues: [UUID: CustomFlowDraftValue] = [:]
    @State private var lineItemDrafts: [UUID: [CustomFlowLineItemDraft]] = [:]
    @State private var viewingLineItem: CustomFlowLineItemSelection?
    @State private var editingLineItem: CustomFlowLineItemSelection?
    @State private var validationMessage: String?
    @State private var showLinkedTransactionUpdatePrompt = false

    private var categories: [CategoryItem] {
        filterActiveProfile(allCategories).filter { !$0.archived }
    }
    private var accounts: [AccountItem] {
        filterActiveProfile(allAccounts).filter { !$0.archived }
    }
    private var people: [PersonItem] {
        filterActiveProfile(allPeople).filter { !$0.archived }
    }
    private var records: [CustomFlowRecordItem] {
        filterActiveProfile(allRecords).filter { $0.status != .archived }
    }
    private var editableStatuses: [CustomFlowRecordStatus] {
        CustomFlowRecordStatus.allCases.filter { $0 != .archived }
    }
    private var palette: FloatThemePalette { appState.themePalette }

    var body: some View {
        NavigationStack {
            Form {
                Section("Record") {
                    TextField("Title", text: $title)

                    Picker("Status", selection: $status) {
                        ForEach(editableStatuses) { status in
                            Text(status.title).tag(status)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Fields") {
                    if objectType.activeFields.isEmpty {
                        Text("Add fields before editing records.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(objectType.activeFields) { field in
                            fieldInput(field)
                        }
                    }
                }

                if let validationMessage {
                    Section {
                        Text(validationMessage)
                            .font(.footnote)
                            .foregroundStyle(palette.caution)
                    }
                }
            }
            .navigationTitle(record == nil ? "New Record" : "Edit Record")
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDismissControls()
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .floatBackground()
            .tint(palette.accent)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                }
            }
            .alert("Update linked transaction?", isPresented: $showLinkedTransactionUpdatePrompt) {
                Button("Save Only", role: .cancel) {
                    performSave(updateLinkedTransactions: false)
                }
                Button("Update Transaction") {
                    performSave(updateLinkedTransactions: true)
                }
            } message: {
                Text("This finalized record is linked to a Float transaction. Update the linked transaction with these edits?")
            }
            .sheet(item: $viewingLineItem) { selection in
                lineItemViewSheet(selection)
            }
            .sheet(item: $editingLineItem) { selection in
                lineItemEditorSheet(selection)
            }
            .onAppear(perform: configure)
        }
    }

    @ViewBuilder
    private func fieldInput(_ field: CustomFlowFieldItem) -> some View {
        switch field.kind {
        case .text:
            HStack(spacing: 12) {
                fieldRowLabel(field)
                Spacer(minLength: 16)
                TextField(field.name, text: textBinding(for: field))
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
            }
        case .notes:
            VStack(alignment: .leading, spacing: 8) {
                fieldRowLabel(field)
                TextField(field.name, text: textBinding(for: field), axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(2...5)
            }
        case .number:
            HStack(spacing: 12) {
                fieldRowLabel(field)
                Spacer(minLength: 16)
                TextField(field.name, text: numberBinding(for: field))
                    .textFieldStyle(.plain)
                    .keyboardType(.decimalPad)
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
            }
        case .money:
            HStack(spacing: 12) {
                fieldRowLabel(field)
                Spacer(minLength: 16)
                VStack(alignment: .trailing, spacing: 3) {
                    TextField(field.name, text: amountBinding(for: field))
                        .textFieldStyle(.plain)
                        .keyboardType(.decimalPad)
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)

                    CurrencyAmountPreview(
                        minorUnits: MoneyParser.parseDisplayAmountMinor(
                            from: draft(for: field).amountText,
                            currencyCode: appState.selectedCurrencyCode
                        ),
                        currencyCode: appState.selectedCurrencyCode
                    )
                }
            }
        case .dateTime:
            DatePicker(
                selection: dateBinding(for: field),
                displayedComponents: [.date, .hourAndMinute]
            ) {
                fieldRowLabel(field)
            }
            .datePickerStyle(.compact)
        case .checkbox:
            Toggle(isOn: boolBinding(for: field)) {
                fieldRowLabel(field)
            }
        case .choice:
            Picker(selection: textBinding(for: field)) {
                Text("Choose").tag("")
                ForEach(field.choiceOptions, id: \.self) { option in
                    Text(option).tag(option)
                }
            } label: {
                fieldRowLabel(field)
            }
            .pickerStyle(.menu)
        case .relation:
            Picker(selection: relatedRecordBinding(for: field)) {
                Text("Choose").tag(Optional<UUID>.none)
                ForEach(relatedRecords(for: field)) { record in
                    Text(record.title).tag(Optional(record.id))
                }
            } label: {
                fieldRowLabel(field)
            }
            .pickerStyle(.menu)
        case .lineItem:
            lineItemInput(field)
        case .category:
            Picker(selection: categoryBinding(for: field)) {
                Text("Choose").tag(Optional<UUID>.none)
                ForEach(categories) { category in
                    Label(category.name, systemImage: category.iconKey)
                        .tag(Optional(category.id))
                }
            } label: {
                fieldRowLabel(field)
            }
            .pickerStyle(.menu)
        case .account:
            Picker(selection: accountBinding(for: field)) {
                Text("Choose").tag(Optional<UUID>.none)
                ForEach(accounts) { account in
                    Label(account.name, systemImage: account.type.icon)
                        .tag(Optional(account.id))
                }
            } label: {
                fieldRowLabel(field)
            }
            .pickerStyle(.menu)
        case .person:
            Picker(selection: personBinding(for: field)) {
                Text("Choose").tag(Optional<UUID>.none)
                ForEach(people) { person in
                    Text(person.name).tag(Optional(person.id))
                }
            } label: {
                fieldRowLabel(field)
            }
            .pickerStyle(.menu)
        case .formula:
            let result = formulaDisplay(for: field)
            VStack(alignment: .leading, spacing: 8) {
                fieldRowLabel(field)

                HStack {
                    Text("Result")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(result.text)
                        .monospacedDigit()
                        .foregroundStyle(result.isError ? palette.caution : .primary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .multilineTextAlignment(.trailing)

                    Image(systemName: "equal")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(palette.positive)
                }
            }
        }
    }

    private func lineItemInput(_ field: CustomFlowFieldItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                fieldRowLabel(field)
                Spacer()
                Button {
                    addLineItem(to: field)
                } label: {
                    Label("Add", systemImage: "plus.circle.fill")
                }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.borderless)
                .disabled(lineItemChildObject(for: field) == nil)
            }

            if let childObject = lineItemChildObject(for: field) {
                let drafts = lineItemDrafts[field.id] ?? []
                if drafts.isEmpty {
                    Text("No line items yet.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(drafts) { draft in
                        lineItemRow(
                            parentField: field,
                            childObject: childObject,
                            draft: draft
                        )
                    }
                }
            } else {
                Text("Configure this line item field before editing rows.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func lineItemRow(
        parentField: CustomFlowFieldItem,
        childObject: CustomFlowObjectTypeItem,
        draft: CustomFlowLineItemDraft
    ) -> some View {
        HStack(spacing: 10) {
            Button {
                editingLineItem = CustomFlowLineItemSelection(
                    parentFieldID: parentField.id,
                    draftID: draft.id
                )
            } label: {
                lineItemRowSummary(
                    parentField: parentField,
                    childObject: childObject,
                    draft: draft
                )
            }
            .buttonStyle(.plain)

            Button(role: .destructive) {
                removeLineItem(parentField: parentField, draftID: draft.id)
            } label: {
                Image(systemName: "trash")
                    .font(.body.weight(.medium))
                    .foregroundStyle(palette.caution)
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Remove line item")
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(.tertiary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private func lineItemRowSummary(
        parentField: CustomFlowFieldItem,
        childObject: CustomFlowObjectTypeItem,
        draft: CustomFlowLineItemDraft
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: childObject.iconKey)
                .font(.caption.weight(.semibold))
                .foregroundStyle(parentField.kind.tint)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 4) {
                Text(draft.title.flowNilIfBlank ?? childObject.singularName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                let summary = lineItemSummaryText(
                    parentField: parentField,
                    childObject: childObject,
                    draft: draft
                )
                if !summary.isEmpty {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    private func lineItemViewSheet(_ selection: CustomFlowLineItemSelection) -> some View {
        NavigationStack {
            Form {
                if let parentField = objectType.activeFields.first(where: { $0.id == selection.parentFieldID }),
                   let childObject = lineItemChildObject(for: parentField),
                   let draft = lineItemDraft(parentField: parentField, draftID: selection.draftID) {
                    Section("Line item") {
                        HStack(spacing: 12) {
                            Label {
                                Text("Title")
                                    .foregroundStyle(.secondary)
                            } icon: {
                                Image(systemName: childObject.iconKey)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(parentField.kind.tint)
                                    .frame(width: 18)
                            }

                            Spacer(minLength: 16)

                            Text(draft.title.flowNilIfBlank ?? childObject.singularName)
                                .multilineTextAlignment(.trailing)
                        }
                    }

                    Section("Fields") {
                        let displayFields = childObject.activeFields.filter {
                            !isParentRelationField($0, for: parentField)
                        }
                        if displayFields.isEmpty {
                            Text("No fields configured.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(displayFields) { childField in
                                lineItemFieldDisplay(
                                    parentField: parentField,
                                    childObject: childObject,
                                    childField: childField,
                                    draft: draft
                                )
                            }
                        }
                    }
                } else {
                    Text("This line item is no longer available.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Line Item")
            .navigationBarTitleDisplayMode(.inline)
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .floatBackground()
            .tint(palette.accent)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        viewingLineItem = nil
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Edit") {
                        viewingLineItem = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            editingLineItem = selection
                        }
                    }
                }
            }
        }
    }

    private func lineItemEditorSheet(_ selection: CustomFlowLineItemSelection) -> some View {
        NavigationStack {
            Form {
                if let parentField = objectType.activeFields.first(where: { $0.id == selection.parentFieldID }),
                   let childObject = lineItemChildObject(for: parentField),
                   lineItemDraft(parentField: parentField, draftID: selection.draftID) != nil {
                    Section("Line item") {
                        TextField(
                            "Title",
                            text: lineItemTitleBinding(
                                parentField: parentField,
                                draftID: selection.draftID
                            )
                        )
                    }

                    Section("Fields") {
                        let editableFields = childObject.activeFields.filter {
                            !isParentRelationField($0, for: parentField)
                        }
                        if editableFields.isEmpty {
                            Text("No fields configured.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(editableFields) { childField in
                                lineItemFieldInput(
                                    parentField: parentField,
                                    childObject: childObject,
                                    childField: childField,
                                    draftID: selection.draftID
                                )
                            }
                        }
                    }
                } else {
                    Text("This line item is no longer available.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Edit Line Item")
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDismissControls()
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .floatBackground()
            .tint(palette.accent)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        editingLineItem = nil
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        editingLineItem = nil
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func lineItemFieldDisplay(
        parentField: CustomFlowFieldItem,
        childObject: CustomFlowObjectTypeItem,
        childField: CustomFlowFieldItem,
        draft: CustomFlowLineItemDraft
    ) -> some View {
        if childField.kind == .notes {
            VStack(alignment: .leading, spacing: 8) {
                fieldRowLabel(childField)
                Text(
                    lineItemDisplayValue(
                        parentField: parentField,
                        childObject: childObject,
                        childField: childField,
                        draft: draft
                    )
                )
                .foregroundStyle(lineItemHasDisplayValue(childField: childField, draft: draft) ? .primary : .secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            HStack(spacing: 12) {
                fieldRowLabel(childField)
                Spacer(minLength: 16)
                Text(
                    lineItemDisplayValue(
                        parentField: parentField,
                        childObject: childObject,
                        childField: childField,
                        draft: draft
                    )
                )
                .multilineTextAlignment(.trailing)
                .foregroundStyle(lineItemHasDisplayValue(childField: childField, draft: draft) ? .primary : .secondary)
            }
        }
    }

    private func lineItemDisplayValue(
        parentField: CustomFlowFieldItem,
        childObject: CustomFlowObjectTypeItem,
        childField: CustomFlowFieldItem,
        draft: CustomFlowLineItemDraft
    ) -> String {
        if childField.kind == .checkbox {
            let value = draft.values[childField.id] ?? CustomFlowDraftValue()
            return value.bool ? String(localized: "Yes") : String(localized: "No")
        }

        if childField.kind == .formula {
            let result = lineItemFormulaDisplay(
                parentField: parentField,
                childObject: childObject,
                childField: childField,
                draftID: draft.id
            )
            return result.text.flowNilIfBlank ?? String(localized: "No value")
        }

        return lineItemSummaryValue(
            parentField: parentField,
            childObject: childObject,
            childField: childField,
            draft: draft
        ) ?? String(localized: "No value")
    }

    private func lineItemHasDisplayValue(
        childField: CustomFlowFieldItem,
        draft: CustomFlowLineItemDraft
    ) -> Bool {
        let value = draft.values[childField.id] ?? CustomFlowDraftValue()
        switch childField.kind {
        case .text, .notes, .choice:
            return value.text.flowNilIfBlank != nil
        case .number:
            return value.numberText.flowNilIfBlank != nil
        case .money:
            return value.amountText.flowNilIfBlank != nil
        case .dateTime:
            return true
        case .checkbox:
            return value.bool
        case .relation:
            return value.relatedRecordID != nil
        case .lineItem:
            return false
        case .category:
            return value.categoryID != nil
        case .account:
            return value.accountID != nil
        case .person:
            return value.personID != nil
        case .formula:
            return true
        }
    }

    private func lineItemSummaryText(
        parentField: CustomFlowFieldItem,
        childObject: CustomFlowObjectTypeItem,
        draft: CustomFlowLineItemDraft
    ) -> String {
        childObject.activeFields
            .filter { !isParentRelationField($0, for: parentField) }
            .compactMap { childField in
                lineItemSummaryValue(
                    parentField: parentField,
                    childObject: childObject,
                    childField: childField,
                    draft: draft
                ).map { "\(childField.name): \($0)" }
            }
            .prefix(2)
            .joined(separator: " · ")
    }

    private func lineItemSummaryValue(
        parentField: CustomFlowFieldItem,
        childObject: CustomFlowObjectTypeItem,
        childField: CustomFlowFieldItem,
        draft: CustomFlowLineItemDraft
    ) -> String? {
        let value = draft.values[childField.id] ?? CustomFlowDraftValue()
        switch childField.kind {
        case .text, .notes, .choice:
            return value.text.flowNilIfBlank
        case .number:
            return value.numberText.flowNilIfBlank
        case .money:
            let amountMinor = MoneyParser.parseDisplayAmountMinor(
                from: value.amountText,
                currencyCode: appState.selectedCurrencyCode
            )
            guard amountMinor != 0 || !value.amountText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            return MoneyFormatter.string(
                minorUnits: amountMinor,
                currencyCode: appState.selectedCurrencyCode
            )
        case .dateTime:
            return value.date.formatted(date: .abbreviated, time: .shortened)
        case .checkbox:
            return value.bool ? String(localized: "Yes") : nil
        case .relation:
            return value.relatedRecordID.flatMap(recordForID)?.title
        case .lineItem:
            return nil
        case .category:
            return value.categoryID.flatMap(categoryForID)?.name
        case .account:
            return value.accountID.flatMap(accountForID)?.name
        case .person:
            return value.personID.flatMap(personForID)?.name
        case .formula:
            let result = lineItemFormulaDisplay(
                parentField: parentField,
                childObject: childObject,
                childField: childField,
                draftID: draft.id
            )
            return result.isError ? nil : result.text.flowNilIfBlank
        }
    }

    @ViewBuilder
    private func lineItemFieldInput(
        parentField: CustomFlowFieldItem,
        childObject: CustomFlowObjectTypeItem,
        childField: CustomFlowFieldItem,
        draftID: UUID
    ) -> some View {
        switch childField.kind {
        case .text:
            HStack(spacing: 12) {
                fieldRowLabel(childField)
                Spacer(minLength: 16)
                TextField(childField.name, text: lineItemTextBinding(parentField: parentField, childField: childField, draftID: draftID))
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
            }
        case .notes:
            VStack(alignment: .leading, spacing: 8) {
                fieldRowLabel(childField)
                TextField(childField.name, text: lineItemTextBinding(parentField: parentField, childField: childField, draftID: draftID), axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(2...5)
            }
        case .number:
            HStack(spacing: 12) {
                fieldRowLabel(childField)
                Spacer(minLength: 16)
                TextField(childField.name, text: lineItemNumberBinding(parentField: parentField, childField: childField, draftID: draftID))
                    .textFieldStyle(.plain)
                    .keyboardType(.decimalPad)
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
            }
        case .money:
            HStack(spacing: 12) {
                fieldRowLabel(childField)
                Spacer(minLength: 16)
                VStack(alignment: .trailing, spacing: 3) {
                    TextField(childField.name, text: lineItemAmountBinding(parentField: parentField, childField: childField, draftID: draftID))
                        .textFieldStyle(.plain)
                        .keyboardType(.decimalPad)
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)

                    CurrencyAmountPreview(
                        minorUnits: MoneyParser.parseDisplayAmountMinor(
                            from: lineItemDraftValue(parentField: parentField, childField: childField, draftID: draftID).amountText,
                            currencyCode: appState.selectedCurrencyCode
                        ),
                        currencyCode: appState.selectedCurrencyCode
                    )
                }
            }
        case .dateTime:
            DatePicker(
                selection: lineItemDateBinding(parentField: parentField, childField: childField, draftID: draftID),
                displayedComponents: [.date, .hourAndMinute]
            ) {
                fieldRowLabel(childField)
            }
            .datePickerStyle(.compact)
        case .checkbox:
            Toggle(isOn: lineItemBoolBinding(parentField: parentField, childField: childField, draftID: draftID)) {
                fieldRowLabel(childField)
            }
        case .choice:
            Picker(selection: lineItemTextBinding(parentField: parentField, childField: childField, draftID: draftID)) {
                Text("Choose").tag("")
                ForEach(childField.choiceOptions, id: \.self) { option in
                    Text(option).tag(option)
                }
            } label: {
                fieldRowLabel(childField)
            }
            .pickerStyle(.menu)
        case .relation:
            Picker(selection: lineItemRelatedRecordBinding(parentField: parentField, childField: childField, draftID: draftID)) {
                Text("Choose").tag(Optional<UUID>.none)
                ForEach(relatedRecords(for: childField)) { record in
                    Text(record.title).tag(Optional(record.id))
                }
            } label: {
                fieldRowLabel(childField)
            }
            .pickerStyle(.menu)
        case .lineItem:
            Text("Nested line items are not supported in line item rows.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .category:
            Picker(selection: lineItemCategoryBinding(parentField: parentField, childField: childField, draftID: draftID)) {
                Text("Choose").tag(Optional<UUID>.none)
                ForEach(categories) { category in
                    Label(category.name, systemImage: category.iconKey)
                        .tag(Optional(category.id))
                }
            } label: {
                fieldRowLabel(childField)
            }
            .pickerStyle(.menu)
        case .account:
            Picker(selection: lineItemAccountBinding(parentField: parentField, childField: childField, draftID: draftID)) {
                Text("Choose").tag(Optional<UUID>.none)
                ForEach(accounts) { account in
                    Label(account.name, systemImage: account.type.icon)
                        .tag(Optional(account.id))
                }
            } label: {
                fieldRowLabel(childField)
            }
            .pickerStyle(.menu)
        case .person:
            Picker(selection: lineItemPersonBinding(parentField: parentField, childField: childField, draftID: draftID)) {
                Text("Choose").tag(Optional<UUID>.none)
                ForEach(people) { person in
                    Text(person.name).tag(Optional(person.id))
                }
            } label: {
                fieldRowLabel(childField)
            }
            .pickerStyle(.menu)
        case .formula:
            let result = lineItemFormulaDisplay(parentField: parentField, childObject: childObject, childField: childField, draftID: draftID)
            VStack(alignment: .leading, spacing: 8) {
                fieldRowLabel(childField)

                HStack {
                    Text("Result")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(result.text)
                        .monospacedDigit()
                        .foregroundStyle(result.isError ? palette.caution : .primary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .multilineTextAlignment(.trailing)

                    Image(systemName: "equal")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(palette.positive)
                }
            }
        }
    }

    private func fieldRowLabel(_ field: CustomFlowFieldItem) -> some View {
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

    private func configure() {
        title = record?.title ?? objectType.singularName
        status = record?.status ?? .draft
        var values: [UUID: CustomFlowDraftValue] = [:]
        for field in objectType.activeFields {
            let existing = record?.value(for: field)
            values[field.id] = CustomFlowDraftValue(
                field: field,
                value: existing,
                currencyCode: appState.selectedCurrencyCode
            )
        }
        draftValues = values
        var lineItems: [UUID: [CustomFlowLineItemDraft]] = [:]
        for field in objectType.activeFields where field.kind == .lineItem {
            guard let childObject = lineItemChildObject(for: field) else {
                lineItems[field.id] = []
                continue
            }
            lineItems[field.id] = persistedLineItemRecords(for: field, parent: record).map {
                CustomFlowLineItemDraft(
                    record: $0,
                    childObject: childObject,
                    currencyCode: appState.selectedCurrencyCode
                )
            }
        }
        lineItemDrafts = lineItems
    }

    private func save() {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            validationMessage = String(localized: "Enter a title.")
            return
        }
        if shouldPromptForLinkedTransactionUpdate {
            showLinkedTransactionUpdatePrompt = true
            return
        }
        performSave(updateLinkedTransactions: true)
    }

    private func performSave(updateLinkedTransactions: Bool) {
        do {
            let repository = CustomFlowRecordRepository(modelContext: modelContext)
            let savedRecord: CustomFlowRecordItem
            if let record {
                try repository.updateRecord(
                    record,
                    title: title,
                    sortOrder: record.sortOrder,
                    parentRecord: record.parentRecord,
                    parentRelation: record.parentRelation
                )
                try repository.setStatus(record, status: status)
                savedRecord = record
            } else {
                savedRecord = try repository.createRecord(
                    objectType: objectType,
                    title: title,
                    status: status
                )
            }

            for field in objectType.activeFields where field.kind != .formula && field.kind != .lineItem {
                let draft = draft(for: field)
                _ = try repository.upsertValue(
                    for: savedRecord,
                    field: field,
                    draft: valueDraft(for: field, draft: draft)
                )
            }
            try saveLineItems(for: savedRecord, repository: repository)
            if savedRecord.status == .finalized {
                try CustomFlowRepository(modelContext: modelContext)
                    .materializeFinalizeActions(
                        for: savedRecord,
                        updateExistingLinkedTransactions: updateLinkedTransactions
                    )
            }
            dismiss()
        } catch {
            validationMessage = error.localizedDescription
        }
    }

    private func valueDraft(
        for field: CustomFlowFieldItem,
        draft: CustomFlowDraftValue
    ) -> CustomFlowFieldValueDraft {
        switch field.kind {
        case .text, .notes, .choice:
            return CustomFlowFieldValueDraft(valueRaw: draft.text)
        case .number:
            return CustomFlowFieldValueDraft(
                numberValue: Double(draft.numberText)
            )
        case .money:
            return CustomFlowFieldValueDraft(
                amountMinor: MoneyParser.parseDisplayAmountMinor(
                    from: draft.amountText,
                    currencyCode: appState.selectedCurrencyCode
                )
            )
        case .dateTime:
            return CustomFlowFieldValueDraft(dateValue: draft.date)
        case .checkbox:
            return CustomFlowFieldValueDraft(boolValue: draft.bool)
        case .relation:
            return CustomFlowFieldValueDraft(
                relatedRecord: draft.relatedRecordID.flatMap(recordForID)
            )
        case .lineItem:
            return CustomFlowFieldValueDraft()
        case .category:
            return CustomFlowFieldValueDraft(
                category: draft.categoryID.flatMap(categoryForID)
            )
        case .account:
            return CustomFlowFieldValueDraft(
                account: draft.accountID.flatMap(accountForID)
            )
        case .person:
            return CustomFlowFieldValueDraft(
                person: draft.personID.flatMap(personForID)
            )
        case .formula:
            return CustomFlowFieldValueDraft()
        }
    }

    private func saveLineItems(
        for savedRecord: CustomFlowRecordItem,
        repository: CustomFlowRecordRepository
    ) throws {
        for field in objectType.activeFields where field.kind == .lineItem {
            guard let relation = field.relation,
                  let childObject = lineItemChildObject(for: field)
            else { continue }

            let currentRecords = persistedLineItemRecords(for: field, parent: savedRecord)
            let drafts = lineItemDrafts[field.id] ?? []
            let retainedRecordIDs = Set(drafts.compactMap(\.existingRecordID))

            for existing in currentRecords where !retainedRecordIDs.contains(existing.id) {
                try repository.delete(existing)
            }

            for (index, draft) in drafts.enumerated() {
                let childRecord: CustomFlowRecordItem
                if let existingID = draft.existingRecordID,
                   let existing = currentRecords.first(where: { $0.id == existingID }) {
                    try repository.updateRecord(
                        existing,
                        title: draft.title,
                        sortOrder: index,
                        parentRecord: savedRecord,
                        parentRelation: relation
                    )
                    try repository.setStatus(existing, status: status)
                    childRecord = existing
                } else {
                    childRecord = try repository.createRecord(
                        objectType: childObject,
                        title: draft.title,
                        status: status,
                        sortOrder: index,
                        parentRecord: savedRecord,
                        parentRelation: relation
                    )
                }

                for childField in childObject.activeFields where childField.kind != .formula && childField.kind != .lineItem {
                    let fieldDraft: CustomFlowFieldValueDraft
                    if isParentRelationField(childField, for: field) {
                        fieldDraft = CustomFlowFieldValueDraft(relatedRecord: savedRecord)
                    } else {
                        fieldDraft = valueDraft(
                            for: childField,
                            draft: draft.values[childField.id] ?? CustomFlowDraftValue()
                        )
                    }
                    _ = try repository.upsertValue(
                        for: childRecord,
                        field: childField,
                        draft: fieldDraft
                    )
                }
            }
        }
    }

    private func addLineItem(to field: CustomFlowFieldItem) {
        guard let childObject = lineItemChildObject(for: field) else { return }
        var drafts = lineItemDrafts[field.id] ?? []
        drafts.append(
            CustomFlowLineItemDraft(
                childObject: childObject,
                title: String(localized: "\(childObject.singularName) \(drafts.count + 1)"),
                currencyCode: appState.selectedCurrencyCode
            )
        )
        lineItemDrafts[field.id] = drafts
    }

    private func removeLineItem(
        parentField: CustomFlowFieldItem,
        draftID: UUID
    ) {
        lineItemDrafts[parentField.id]?.removeAll { $0.id == draftID }
    }

    private func lineItemDraft(
        parentField: CustomFlowFieldItem,
        draftID: UUID
    ) -> CustomFlowLineItemDraft? {
        lineItemDrafts[parentField.id]?.first { $0.id == draftID }
    }

    private func setLineItemDraft(
        parentField: CustomFlowFieldItem,
        draftID: UUID,
        update: (inout CustomFlowLineItemDraft) -> Void
    ) {
        var drafts = lineItemDrafts[parentField.id] ?? []
        guard let index = drafts.firstIndex(where: { $0.id == draftID }) else { return }
        update(&drafts[index])
        lineItemDrafts[parentField.id] = drafts
    }

    private func lineItemDraftValue(
        parentField: CustomFlowFieldItem,
        childField: CustomFlowFieldItem,
        draftID: UUID
    ) -> CustomFlowDraftValue {
        lineItemDraft(parentField: parentField, draftID: draftID)?.values[childField.id] ?? CustomFlowDraftValue()
    }

    private func setLineItemDraftValue(
        parentField: CustomFlowFieldItem,
        childField: CustomFlowFieldItem,
        draftID: UUID,
        update: (inout CustomFlowDraftValue) -> Void
    ) {
        setLineItemDraft(parentField: parentField, draftID: draftID) { draft in
            var value = draft.values[childField.id] ?? CustomFlowDraftValue()
            update(&value)
            draft.values[childField.id] = value
        }
    }

    private func lineItemTitleBinding(
        parentField: CustomFlowFieldItem,
        draftID: UUID
    ) -> Binding<String> {
        Binding(
            get: { lineItemDraft(parentField: parentField, draftID: draftID)?.title ?? "" },
            set: { newValue in
                setLineItemDraft(parentField: parentField, draftID: draftID) { $0.title = newValue }
            }
        )
    }

    private func lineItemTextBinding(parentField: CustomFlowFieldItem, childField: CustomFlowFieldItem, draftID: UUID) -> Binding<String> {
        Binding(
            get: { lineItemDraftValue(parentField: parentField, childField: childField, draftID: draftID).text },
            set: { newValue in setLineItemDraftValue(parentField: parentField, childField: childField, draftID: draftID) { $0.text = newValue } }
        )
    }

    private func lineItemNumberBinding(parentField: CustomFlowFieldItem, childField: CustomFlowFieldItem, draftID: UUID) -> Binding<String> {
        Binding(
            get: { lineItemDraftValue(parentField: parentField, childField: childField, draftID: draftID).numberText },
            set: { newValue in setLineItemDraftValue(parentField: parentField, childField: childField, draftID: draftID) { $0.numberText = newValue } }
        )
    }

    private func lineItemAmountBinding(parentField: CustomFlowFieldItem, childField: CustomFlowFieldItem, draftID: UUID) -> Binding<String> {
        Binding(
            get: { lineItemDraftValue(parentField: parentField, childField: childField, draftID: draftID).amountText },
            set: { newValue in setLineItemDraftValue(parentField: parentField, childField: childField, draftID: draftID) { $0.amountText = newValue } }
        )
    }

    private func lineItemDateBinding(parentField: CustomFlowFieldItem, childField: CustomFlowFieldItem, draftID: UUID) -> Binding<Date> {
        Binding(
            get: { lineItemDraftValue(parentField: parentField, childField: childField, draftID: draftID).date },
            set: { newValue in setLineItemDraftValue(parentField: parentField, childField: childField, draftID: draftID) { $0.date = newValue } }
        )
    }

    private func lineItemBoolBinding(parentField: CustomFlowFieldItem, childField: CustomFlowFieldItem, draftID: UUID) -> Binding<Bool> {
        Binding(
            get: { lineItemDraftValue(parentField: parentField, childField: childField, draftID: draftID).bool },
            set: { newValue in setLineItemDraftValue(parentField: parentField, childField: childField, draftID: draftID) { $0.bool = newValue } }
        )
    }

    private func lineItemRelatedRecordBinding(parentField: CustomFlowFieldItem, childField: CustomFlowFieldItem, draftID: UUID) -> Binding<UUID?> {
        Binding(
            get: { lineItemDraftValue(parentField: parentField, childField: childField, draftID: draftID).relatedRecordID },
            set: { newValue in setLineItemDraftValue(parentField: parentField, childField: childField, draftID: draftID) { $0.relatedRecordID = newValue } }
        )
    }

    private func lineItemCategoryBinding(parentField: CustomFlowFieldItem, childField: CustomFlowFieldItem, draftID: UUID) -> Binding<UUID?> {
        Binding(
            get: { lineItemDraftValue(parentField: parentField, childField: childField, draftID: draftID).categoryID },
            set: { newValue in setLineItemDraftValue(parentField: parentField, childField: childField, draftID: draftID) { $0.categoryID = newValue } }
        )
    }

    private func lineItemAccountBinding(parentField: CustomFlowFieldItem, childField: CustomFlowFieldItem, draftID: UUID) -> Binding<UUID?> {
        Binding(
            get: { lineItemDraftValue(parentField: parentField, childField: childField, draftID: draftID).accountID },
            set: { newValue in setLineItemDraftValue(parentField: parentField, childField: childField, draftID: draftID) { $0.accountID = newValue } }
        )
    }

    private func lineItemPersonBinding(parentField: CustomFlowFieldItem, childField: CustomFlowFieldItem, draftID: UUID) -> Binding<UUID?> {
        Binding(
            get: { lineItemDraftValue(parentField: parentField, childField: childField, draftID: draftID).personID },
            set: { newValue in setLineItemDraftValue(parentField: parentField, childField: childField, draftID: draftID) { $0.personID = newValue } }
        )
    }

    private var shouldPromptForLinkedTransactionUpdate: Bool {
        guard let record,
              record.status == .finalized,
              status == .finalized
        else { return false }
        return finalizeActions.contains { action in
            guard record.transactionLinks.first(where: { $0.action?.id == action.id })?.transaction != nil
            else { return false }
            return actionAffectsLinkedTransaction(action)
        }
    }

    private var finalizeActions: [CustomFlowTransactionActionItem] {
        objectType.flow?.transactionActions.filter {
            $0.active
                && $0.trigger == .finalize
                && $0.sourceObjectType?.id == objectType.id
        } ?? []
    }

    private func actionAffectsLinkedTransaction(_ action: CustomFlowTransactionActionItem) -> Bool {
        if action.fixedAmountMinor == nil,
           mappedFieldChanged(action.amountField, formulaChangesCount: true) {
            return true
        }
        if action.fixedCategory == nil,
           mappedFieldChanged(action.categoryField) {
            return true
        }
        if action.fixedAccount == nil,
           mappedFieldChanged(action.accountField) {
            return true
        }
        if action.fixedDate == nil {
            if let dateField = action.dateField {
                if mappedFieldChanged(dateField) { return true }
            } else {
                return true
            }
        }
        if action.fixedNote == nil {
            if let noteField = action.noteField {
                if mappedFieldChanged(noteField) { return true }
            } else if title != record?.title {
                return true
            }
        }
        return false
    }

    private func mappedFieldChanged(
        _ field: CustomFlowFieldItem?,
        formulaChangesCount: Bool = false
    ) -> Bool {
        guard let field else { return false }
        if field.kind == .formula {
            return formulaChangesCount && objectType.activeFields.contains {
                $0.kind != .formula && mappedFieldChanged($0)
            }
        }
        let existing = record?.value(for: field)
        let draft = draft(for: field)
        switch field.kind {
        case .text, .notes, .choice:
            return (existing?.valueRaw ?? "") != draft.text
        case .number:
            return existing?.numberValue != Double(draft.numberText)
        case .money:
            return existing?.amountMinor != MoneyParser.parseDisplayAmountMinor(
                from: draft.amountText,
                currencyCode: appState.selectedCurrencyCode
            )
        case .dateTime:
            return existing?.dateValue != draft.date
        case .checkbox:
            return (existing?.boolValue ?? false) != draft.bool
        case .relation:
            return existing?.relatedRecord?.id != draft.relatedRecordID
        case .lineItem:
            return lineItemsChanged(for: field)
        case .category:
            return existing?.category?.id != draft.categoryID
        case .account:
            return existing?.account?.id != draft.accountID
        case .person:
            return existing?.person?.id != draft.personID
        case .formula:
            return false
        }
    }

    private func relatedRecords(for field: CustomFlowFieldItem) -> [CustomFlowRecordItem] {
        guard let relation = field.relation else { return [] }
        let targetID = relation.targetObjectType?.id == objectType.id
            ? relation.sourceObjectType?.id
            : relation.targetObjectType?.id
        return records
            .filter { $0.objectType?.id == targetID && $0.id != record?.id }
            .sorted { $0.title < $1.title }
    }

    private func lineItemChildObject(for field: CustomFlowFieldItem) -> CustomFlowObjectTypeItem? {
        guard let relation = field.relation else { return nil }
        if relation.targetObjectType?.id == objectType.id {
            return relation.sourceObjectType
        }
        if relation.sourceObjectType?.id == objectType.id {
            return relation.targetObjectType
        }
        return nil
    }

    private func persistedLineItemRecords(
        for field: CustomFlowFieldItem,
        parent: CustomFlowRecordItem?
    ) -> [CustomFlowRecordItem] {
        guard let relation = field.relation,
              let childObject = lineItemChildObject(for: field),
              let parent
        else { return [] }

        let relationFields = childObject.activeFields.filter {
            $0.kind == .relation && $0.relation?.id == relation.id
        }
        return records
            .filter { candidate in
                guard candidate.objectType?.id == childObject.id,
                      candidate.status != .archived
                else { return false }

                if candidate.parentRecord?.id == parent.id,
                   candidate.parentRelation?.id == relation.id {
                    return true
                }

                return relationFields.contains { childField in
                    candidate.value(for: childField)?.relatedRecord?.id == parent.id
                }
            }
            .sorted { lhs, rhs in
                if lhs.sortOrder == rhs.sortOrder {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhs.sortOrder < rhs.sortOrder
            }
    }

    private func isParentRelationField(
        _ childField: CustomFlowFieldItem,
        for parentField: CustomFlowFieldItem
    ) -> Bool {
        childField.kind == .relation
            && childField.relation?.id == parentField.relation?.id
    }

    private func lineItemsChanged(for field: CustomFlowFieldItem) -> Bool {
        let existing = persistedLineItemRecords(for: field, parent: record)
        let drafts = lineItemDrafts[field.id] ?? []
        if existing.map(\.id) != drafts.compactMap(\.existingRecordID) {
            return true
        }
        for draft in drafts {
            guard let existingID = draft.existingRecordID,
                  let existing = existing.first(where: { $0.id == existingID })
            else { return true }
            if draft.title != existing.title { return true }
            guard let childObject = lineItemChildObject(for: field) else { continue }
            for childField in childObject.activeFields where childField.kind != .formula && childField.kind != .lineItem && !isParentRelationField(childField, for: field) {
                if lineItemValueChanged(
                    field: childField,
                    existing: existing.value(for: childField),
                    draft: draft.values[childField.id] ?? CustomFlowDraftValue()
                ) {
                    return true
                }
            }
        }
        return false
    }

    private func lineItemValueChanged(
        field: CustomFlowFieldItem,
        existing: CustomFlowFieldValueItem?,
        draft: CustomFlowDraftValue
    ) -> Bool {
        switch field.kind {
        case .text, .notes, .choice:
            return (existing?.valueRaw ?? "") != draft.text
        case .number:
            return existing?.numberValue != Double(draft.numberText)
        case .money:
            return existing?.amountMinor != MoneyParser.parseDisplayAmountMinor(
                from: draft.amountText,
                currencyCode: appState.selectedCurrencyCode
            )
        case .dateTime:
            return existing?.dateValue != draft.date
        case .checkbox:
            return (existing?.boolValue ?? false) != draft.bool
        case .relation:
            return existing?.relatedRecord?.id != draft.relatedRecordID
        case .lineItem, .formula:
            return false
        case .category:
            return existing?.category?.id != draft.categoryID
        case .account:
            return existing?.account?.id != draft.accountID
        case .person:
            return existing?.person?.id != draft.personID
        }
    }

    private func draft(for field: CustomFlowFieldItem) -> CustomFlowDraftValue {
        draftValues[field.id] ?? CustomFlowDraftValue()
    }

    private func setDraft(
        _ field: CustomFlowFieldItem,
        update: (inout CustomFlowDraftValue) -> Void
    ) {
        var value = draft(for: field)
        update(&value)
        draftValues[field.id] = value
    }

    private func textBinding(for field: CustomFlowFieldItem) -> Binding<String> {
        Binding(
            get: { draft(for: field).text },
            set: { newValue in setDraft(field) { $0.text = newValue } }
        )
    }

    private func numberBinding(for field: CustomFlowFieldItem) -> Binding<String> {
        Binding(
            get: { draft(for: field).numberText },
            set: { newValue in setDraft(field) { $0.numberText = newValue } }
        )
    }

    private func amountBinding(for field: CustomFlowFieldItem) -> Binding<String> {
        Binding(
            get: { draft(for: field).amountText },
            set: { newValue in setDraft(field) { $0.amountText = newValue } }
        )
    }

    private func dateBinding(for field: CustomFlowFieldItem) -> Binding<Date> {
        Binding(
            get: { draft(for: field).date },
            set: { newValue in setDraft(field) { $0.date = newValue } }
        )
    }

    private func boolBinding(for field: CustomFlowFieldItem) -> Binding<Bool> {
        Binding(
            get: { draft(for: field).bool },
            set: { newValue in setDraft(field) { $0.bool = newValue } }
        )
    }

    private func relatedRecordBinding(for field: CustomFlowFieldItem) -> Binding<UUID?> {
        Binding(
            get: { draft(for: field).relatedRecordID },
            set: { newValue in setDraft(field) { $0.relatedRecordID = newValue } }
        )
    }

    private func categoryBinding(for field: CustomFlowFieldItem) -> Binding<UUID?> {
        Binding(
            get: { draft(for: field).categoryID },
            set: { newValue in setDraft(field) { $0.categoryID = newValue } }
        )
    }

    private func accountBinding(for field: CustomFlowFieldItem) -> Binding<UUID?> {
        Binding(
            get: { draft(for: field).accountID },
            set: { newValue in setDraft(field) { $0.accountID = newValue } }
        )
    }

    private func personBinding(for field: CustomFlowFieldItem) -> Binding<UUID?> {
        Binding(
            get: { draft(for: field).personID },
            set: { newValue in setDraft(field) { $0.personID = newValue } }
        )
    }

    private func recordForID(_ id: UUID) -> CustomFlowRecordItem? {
        records.first { $0.id == id }
    }

    private func categoryForID(_ id: UUID) -> CategoryItem? {
        categories.first { $0.id == id }
    }

    private func accountForID(_ id: UUID) -> AccountItem? {
        accounts.first { $0.id == id }
    }

    private func personForID(_ id: UUID) -> PersonItem? {
        people.first { $0.id == id }
    }

    private func formulaDisplay(for field: CustomFlowFieldItem) -> (text: String, isError: Bool) {
        let targetRecord = record ?? CustomFlowRecordItem(
            title: title.flowNilIfBlank ?? objectType.singularName,
            status: status
        )
        let draftFormulaValues = Dictionary(
            uniqueKeysWithValues: objectType.activeFields
                .filter { $0.kind != .formula }
                .map { ($0.id, formulaValue(for: $0, draft: draft(for: $0))) }
        )
        do {
            let value = try CustomFlowFormulaEngine.evaluate(
                field: field,
                context: CustomFlowFormulaEvaluationContext(
                    record: targetRecord,
                    objectType: objectType,
                    records: records,
                    draftValues: draftFormulaValues,
                    draftRecords: formulaDraftRecords(parentRecord: targetRecord),
                    deletedRecordIDs: deletedLineItemRecordIDs(parentRecord: targetRecord)
                )
            )
            return (value.displayText(currencyCode: appState.selectedCurrencyCode) ?? String(localized: "No value"), false)
        } catch {
            return (error.localizedDescription, true)
        }
    }

    private func lineItemFormulaDisplay(
        parentField: CustomFlowFieldItem,
        childObject: CustomFlowObjectTypeItem,
        childField: CustomFlowFieldItem,
        draftID: UUID
    ) -> (text: String, isError: Bool) {
        let parentRecord = record ?? CustomFlowRecordItem(
            title: title.flowNilIfBlank ?? objectType.singularName,
            status: status
        )
        let childRecord = CustomFlowRecordItem(
            id: draftID,
            title: lineItemDraft(parentField: parentField, draftID: draftID)?.title ?? childObject.singularName,
            status: status,
            objectType: childObject,
            parentRecord: parentRecord,
            parentRelation: parentField.relation
        )
        do {
            let value = try CustomFlowFormulaEngine.evaluate(
                field: childField,
                context: CustomFlowFormulaEvaluationContext(
                    record: childRecord,
                    objectType: childObject,
                    records: records,
                    draftRecords: formulaDraftRecords(parentRecord: parentRecord),
                    deletedRecordIDs: deletedLineItemRecordIDs(parentRecord: parentRecord)
                )
            )
            return (value.displayText(currencyCode: appState.selectedCurrencyCode) ?? String(localized: "No value"), false)
        } catch {
            return (error.localizedDescription, true)
        }
    }

    private func formulaDraftRecords(
        parentRecord: CustomFlowRecordItem
    ) -> [CustomFlowFormulaDraftRecord] {
        objectType.activeFields
            .filter { $0.kind == .lineItem }
            .flatMap { parentField -> [CustomFlowFormulaDraftRecord] in
                guard let relation = parentField.relation,
                      let childObject = lineItemChildObject(for: parentField)
                else { return [] }

                return (lineItemDrafts[parentField.id] ?? []).map { draft in
                    let values = Dictionary(
                        uniqueKeysWithValues: childObject.activeFields
                            .filter { $0.kind != .formula && $0.kind != .lineItem }
                            .map { childField -> (UUID, CustomFlowFormulaValue) in
                                if isParentRelationField(childField, for: parentField) {
                                    return (childField.id, .record(parentRecord))
                                }
                                return (
                                    childField.id,
                                    formulaValue(
                                        for: childField,
                                        draft: draft.values[childField.id] ?? CustomFlowDraftValue()
                                    )
                                )
                            }
                    )
                    return CustomFlowFormulaDraftRecord(
                        id: draft.existingRecordID ?? draft.id,
                        sourceRecordID: draft.existingRecordID,
                        objectType: childObject,
                        parentRecordID: parentRecord.id,
                        parentRelationID: relation.id,
                        status: status,
                        values: values
                    )
                }
            }
    }

    private func deletedLineItemRecordIDs(
        parentRecord: CustomFlowRecordItem
    ) -> Set<UUID> {
        var deletedIDs = Set<UUID>()
        for field in objectType.activeFields where field.kind == .lineItem {
            let retainedIDs = Set((lineItemDrafts[field.id] ?? []).compactMap(\.existingRecordID))
            for existing in persistedLineItemRecords(for: field, parent: parentRecord)
                where !retainedIDs.contains(existing.id) {
                deletedIDs.insert(existing.id)
            }
        }
        return deletedIDs
    }

    private func formulaValue(
        for field: CustomFlowFieldItem,
        draft: CustomFlowDraftValue
    ) -> CustomFlowFormulaValue {
        switch field.kind {
        case .text, .notes, .choice:
            return draft.text.flowNilIfBlank.map(CustomFlowFormulaValue.text) ?? .empty
        case .number:
            return Double(draft.numberText).map(CustomFlowFormulaValue.number) ?? .empty
        case .money:
            return .moneyMinor(
                MoneyParser.parseDisplayAmountMinor(
                    from: draft.amountText,
                    currencyCode: appState.selectedCurrencyCode
                )
            )
        case .dateTime:
            return .date(draft.date)
        case .checkbox:
            return .bool(draft.bool)
        case .relation:
            return draft.relatedRecordID.flatMap(recordForID).map(CustomFlowFormulaValue.record) ?? .empty
        case .lineItem:
            return .empty
        case .category:
            return draft.categoryID.flatMap(categoryForID).map { .text($0.name) } ?? .empty
        case .account:
            return draft.accountID.flatMap(accountForID).map { .text($0.name) } ?? .empty
        case .person:
            return draft.personID.flatMap(personForID).map { .text($0.name) } ?? .empty
        case .formula:
            return .empty
        }
    }
}

struct FlowEditorPresentation: Identifiable {
    let id = UUID()
    let flow: CustomFlowItem?
}

struct ObjectTypeEditorPresentation: Identifiable {
    let id = UUID()
    let flow: CustomFlowItem
    let objectType: CustomFlowObjectTypeItem?
}

struct RelationEditorPresentation: Identifiable {
    let id = UUID()
    let flow: CustomFlowItem
}

struct TransactionActionEditorPresentation: Identifiable {
    let id = UUID()
    let flow: CustomFlowItem
    let action: CustomFlowTransactionActionItem?
}

struct FieldEditorPresentation: Identifiable {
    let id = UUID()
    let objectType: CustomFlowObjectTypeItem
    let field: CustomFlowFieldItem?
}

struct RecordDetailPresentation: Identifiable {
    let id = UUID()
    let objectType: CustomFlowObjectTypeItem
    let record: CustomFlowRecordItem
}

struct RecordEditorPresentation: Identifiable {
    let id = UUID()
    let objectType: CustomFlowObjectTypeItem
    let record: CustomFlowRecordItem?
}

private struct CustomFlowDraftValue {
    var text = ""
    var numberText = ""
    var amountText = ""
    var date = Date()
    var bool = false
    var relatedRecordID: UUID?
    var categoryID: UUID?
    var accountID: UUID?
    var personID: UUID?

    init() {}

    init(
        field: CustomFlowFieldItem,
        value: CustomFlowFieldValueItem?,
        currencyCode: String
    ) {
        text = value?.valueRaw ?? field.defaultValueRaw ?? ""
        if let numberValue = value?.numberValue {
            numberText = String(numberValue)
        } else {
            numberText = field.defaultValueRaw ?? ""
        }
        if let amountMinor = value?.amountMinor {
            amountText = Self.majorAmountText(
                amountMinor,
                currencyCode: currencyCode
            )
        } else {
            amountText = field.defaultValueRaw ?? ""
        }
        date = value?.dateValue ?? Date()
        bool = value?.boolValue ?? false
        relatedRecordID = value?.relatedRecord?.id
        categoryID = value?.category?.id
        accountID = value?.account?.id
        personID = value?.person?.id
    }

    private static func majorAmountText(
        _ amountMinor: Int64,
        currencyCode: String
    ) -> String {
        let fractionDigits = MoneyFormatter.fractionDigits(for: currencyCode)
        let divisor = pow(10.0, Double(fractionDigits))
        let major = Double(amountMinor) / divisor
        return major.formatted(.number.precision(.fractionLength(0...fractionDigits)))
    }
}

private struct CustomFlowLineItemDraft: Identifiable {
    var id: UUID
    var existingRecordID: UUID?
    var title: String
    var values: [UUID: CustomFlowDraftValue]

    init(
        childObject: CustomFlowObjectTypeItem,
        title: String,
        currencyCode: String
    ) {
        self.id = UUID()
        self.existingRecordID = nil
        self.title = title
        self.values = Dictionary(
            uniqueKeysWithValues: childObject.activeFields.map {
                ($0.id, CustomFlowDraftValue(field: $0, value: nil, currencyCode: currencyCode))
            }
        )
    }

    init(
        record: CustomFlowRecordItem,
        childObject: CustomFlowObjectTypeItem,
        currencyCode: String
    ) {
        self.id = record.id
        self.existingRecordID = record.id
        self.title = record.title
        self.values = Dictionary(
            uniqueKeysWithValues: childObject.activeFields.map { field in
                (
                    field.id,
                    CustomFlowDraftValue(
                        field: field,
                        value: record.value(for: field),
                        currencyCode: currencyCode
                    )
                )
            }
        )
    }
}

private struct CustomFlowLineItemSelection: Identifiable {
    let parentFieldID: UUID
    let draftID: UUID

    var id: String {
        "\(parentFieldID.uuidString)-\(draftID.uuidString)"
    }
}

extension CustomFlowObjectTypeItem {
    var activeFields: [CustomFlowFieldItem] {
        fields
            .filter { !$0.archived }
            .sorted { lhs, rhs in
                if lhs.sortOrder == rhs.sortOrder {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhs.sortOrder < rhs.sortOrder
            }
    }
}

extension CustomFlowFieldValueItem {
    func displayText(
        for field: CustomFlowFieldItem,
        currencyCode: String?
    ) -> String? {
        switch field.kind {
        case .text, .notes, .choice:
            valueRaw?.flowNilIfBlank
        case .number:
            numberValue.map { String($0) }
        case .money:
            amountMinor.map {
                MoneyFormatter.string(
                    minorUnits: $0,
                    currencyCode: currencyCode ?? MoneyFormatter.currencyCodeFromLocale()
                )
            }
        case .dateTime:
            dateValue?.formatted(date: .abbreviated, time: .shortened)
        case .checkbox:
            boolValue == true ? String(localized: "Yes") : String(localized: "No")
        case .relation:
            relatedRecord?.title
        case .lineItem:
            nil
        case .category:
            category?.name
        case .account:
            account?.name
        case .person:
            person?.name
        case .formula:
            nil
        }
    }
}

extension CustomFlowFormulaValue {
    func displayText(currencyCode: String?) -> String? {
        switch self {
        case .number(let value):
            value.formatted(.number.precision(.fractionLength(0...2)))
        case .moneyMinor(let amountMinor):
            MoneyFormatter.string(
                minorUnits: amountMinor,
                currencyCode: currencyCode ?? MoneyFormatter.currencyCodeFromLocale()
            )
        case .text(let value):
            value.flowNilIfBlank
        case .bool(let value):
            value ? String(localized: "Yes") : String(localized: "No")
        case .date(let value):
            value.formatted(date: .abbreviated, time: .shortened)
        case .record(let record):
            record.title
        case .empty:
            nil
        }
    }
}

extension CustomFlowFieldKind {
    var title: String {
        switch self {
        case .text: String(localized: "Text")
        case .number: String(localized: "Number")
        case .money: String(localized: "Money")
        case .dateTime: String(localized: "Date and Time")
        case .checkbox: String(localized: "Checkbox")
        case .choice: String(localized: "Choice")
        case .relation: String(localized: "Relation")
        case .lineItem: String(localized: "Line Item")
        case .formula: String(localized: "Formula")
        case .notes: String(localized: "Notes")
        case .category: String(localized: "Category")
        case .account: String(localized: "Account")
        case .person: String(localized: "Person")
        }
    }

    var icon: String {
        switch self {
        case .text: "textformat"
        case .number: "number"
        case .money: "banknote.fill"
        case .dateTime: "calendar"
        case .checkbox: "checkmark.square.fill"
        case .choice: "list.bullet"
        case .relation: "link"
        case .lineItem: "list.bullet.rectangle"
        case .formula: "function"
        case .notes: "note.text"
        case .category: "tag.fill"
        case .account: "wallet.pass.fill"
        case .person: "person.fill"
        }
    }

    var tint: Color {
        switch self {
        case .text:
            Color(hex: "#4D86F7")
        case .number, .formula:
            Color(hex: "#8D5CF6")
        case .money, .account:
            Color(hex: "#1B8A5A")
        case .dateTime:
            Color(hex: "#0A6FAE")
        case .checkbox:
            Color(hex: "#2F9E7C")
        case .choice, .lineItem:
            Color(hex: "#E06B4E")
        case .relation, .person:
            Color(hex: "#5C8C69")
        case .notes:
            Color(hex: "#A67C55")
        case .category:
            Color(hex: "#B7791F")
        }
    }
}

extension CustomFlowFieldItem {
    var choiceOptions: [String] {
        choiceOptionsRaw?
            .split(whereSeparator: { $0 == "\n" || $0 == "," })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []
    }
}

extension CustomFlowRecordStatus {
    var title: String {
        switch self {
        case .draft: String(localized: "Draft")
        case .finalized: String(localized: "Finalized")
        case .archived: String(localized: "Archived")
        }
    }
}

extension CustomFlowRelationKind {
    var title: String {
        switch self {
        case .belongsTo: String(localized: "Belongs to")
        case .hasMany: String(localized: "Has many")
        }
    }
}

extension CustomFlowTransactionActionTrigger {
    var title: String {
        switch self {
        case .manual: String(localized: "Manual")
        case .finalize: String(localized: "On finalize")
        }
    }
}

extension CustomFlowFormulaArithmeticOperator {
    var title: String {
        switch self {
        case .add: String(localized: "Add")
        case .subtract: String(localized: "Subtract")
        case .multiply: String(localized: "Multiply")
        case .divide: String(localized: "Divide")
        }
    }
}

extension CustomFlowFormulaComparisonOperator {
    var title: String {
        switch self {
        case .equal: String(localized: "Equal")
        case .notEqual: String(localized: "Not equal")
        case .greaterThan: String(localized: "Greater than")
        case .greaterThanOrEqual: String(localized: "Greater than or equal")
        case .lessThan: String(localized: "Less than")
        case .lessThanOrEqual: String(localized: "Less than or equal")
        }
    }
}

extension Array where Element == CustomFlowObjectTypeItem {
    func sortedBySortOrder() -> [CustomFlowObjectTypeItem] {
        sorted { lhs, rhs in
            if lhs.sortOrder == rhs.sortOrder {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.sortOrder < rhs.sortOrder
        }
    }
}

extension Array where Element == CustomFlowRelationItem {
    func sortedBySortOrder() -> [CustomFlowRelationItem] {
        sorted { lhs, rhs in
            if lhs.sortOrder == rhs.sortOrder {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.sortOrder < rhs.sortOrder
        }
    }
}

extension String {
    var flowNilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
