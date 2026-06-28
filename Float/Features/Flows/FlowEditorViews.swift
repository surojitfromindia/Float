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
        flow.objectTypes.filter { !$0.archived }.sortedBySortOrder()
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
                if kind == .formula {
                    FormulaBuilderView(
                        objectType: objectType,
                        editingFieldID: field?.id,
                        definition: $formulaDefinition
                    )
                } else if kind != .relation {
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
        do {
            let repository = CustomFlowRepository(modelContext: modelContext)
            let relation = relationID.flatMap { id in
                availableRelations.first { $0.id == id }
            }
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
                    defaultValueRaw: defaultValueRaw,
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
                    defaultValueRaw: defaultValueRaw,
                    formulaDefinitionRaw: formulaRaw,
                    relation: relation
                )
            }
            dismiss()
        } catch {
            validationMessage = error.localizedDescription
        }
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
        flow.objectTypes.filter { !$0.archived }.sortedBySortOrder()
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

    var body: some View {
        NavigationStack {
            Form {
                Section("Record") {
                    TextField("Title", text: $title)
                    Picker("Status", selection: $status) {
                        ForEach(CustomFlowRecordStatus.allCases.filter { $0 != .archived }) { status in
                            Text(status.title).tag(status)
                        }
                    }
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
                            .foregroundStyle(Color(hex: "#B4613B"))
                    }
                }
            }
            .navigationTitle(record == nil ? "New Record" : "Edit Record")
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
            .onAppear(perform: configure)
        }
    }

    @ViewBuilder
    private func fieldInput(_ field: CustomFlowFieldItem) -> some View {
        switch field.kind {
        case .text:
            TextField(field.name, text: textBinding(for: field))
        case .notes:
            TextField(field.name, text: textBinding(for: field), axis: .vertical)
                .lineLimit(2...5)
        case .number:
            TextField(field.name, text: numberBinding(for: field))
                .keyboardType(.decimalPad)
        case .money:
            HStack {
                TextField(field.name, text: amountBinding(for: field))
                    .keyboardType(.decimalPad)
                CurrencyAmountPreview(
                    minorUnits: MoneyParser.parseDisplayAmountMinor(
                        from: draft(for: field).amountText,
                        currencyCode: appState.selectedCurrencyCode
                    ),
                    currencyCode: appState.selectedCurrencyCode
                )
            }
        case .dateTime:
            DatePicker(
                field.name,
                selection: dateBinding(for: field),
                displayedComponents: [.date, .hourAndMinute]
            )
        case .checkbox:
            Toggle(field.name, isOn: boolBinding(for: field))
        case .choice:
            Picker(field.name, selection: textBinding(for: field)) {
                Text("Choose").tag("")
                ForEach(field.choiceOptions, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
        case .relation:
            Picker(field.name, selection: relatedRecordBinding(for: field)) {
                Text("Choose").tag(Optional<UUID>.none)
                ForEach(relatedRecords(for: field)) { record in
                    Text(record.title).tag(Optional(record.id))
                }
            }
        case .category:
            Picker(field.name, selection: categoryBinding(for: field)) {
                Text("Choose").tag(Optional<UUID>.none)
                ForEach(categories) { category in
                    Label(category.name, systemImage: category.iconKey)
                        .tag(Optional(category.id))
                }
            }
        case .account:
            Picker(field.name, selection: accountBinding(for: field)) {
                Text("Choose").tag(Optional<UUID>.none)
                ForEach(accounts) { account in
                    Label(account.name, systemImage: account.type.icon)
                        .tag(Optional(account.id))
                }
            }
        case .person:
            Picker(field.name, selection: personBinding(for: field)) {
                Text("Choose").tag(Optional<UUID>.none)
                ForEach(people) { person in
                    Text(person.name).tag(Optional(person.id))
                }
            }
        case .formula:
            LabeledContent(field.name) {
                let result = formulaDisplay(for: field)
                Text(result.text)
                    .foregroundStyle(result.isError ? Color(hex: "#B4613B") : .secondary)
            }
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

            for field in objectType.activeFields where field.kind != .formula {
                let draft = draft(for: field)
                _ = try repository.upsertValue(
                    for: savedRecord,
                    field: field,
                    draft: valueDraft(for: field, draft: draft)
                )
            }
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
                    draftValues: draftFormulaValues
                )
            )
            return (value.displayText(currencyCode: appState.selectedCurrencyCode) ?? String(localized: "No value"), false)
        } catch {
            return (error.localizedDescription, true)
        }
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
        case .formula: "function"
        case .notes: "note.text"
        case .category: "tag.fill"
        case .account: "wallet.pass.fill"
        case .person: "person.fill"
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
