import SwiftData
import SwiftUI

struct BulkTransactionEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @Query(sort: \TransactionTemplateGroupItem.createdAt, order: .reverse)
    private var groups: [TransactionTemplateGroupItem]
    @Query(sort: \TransactionTemplateItem.createdAt, order: .reverse)
    private var templates: [TransactionTemplateItem]

    @State private var mode = BulkEntryMode.groups
    @State private var selectedGroup: TransactionTemplateGroupItem?
    @State private var groupDraftEntries: [BulkGroupDraftEntry] = []
    @State private var selectedTemplateIDs = Set<UUID>()
    @State private var message: String?

    private var selectedTemplates: [TransactionTemplateItem] {
        switch mode {
        case .groups:
            return selectedGroupTemplates
        case .templates:
            return templates.filter { selectedTemplateIDs.contains($0.id) }
        }
    }

    private var selectedGroupTemplates: [TransactionTemplateItem] {
        groupDraftEntries.flatMap { entry -> [TransactionTemplateItem] in
            guard let template = template(for: entry.templateID) else { return [] }
            return Array(repeating: template, count: max(1, entry.multiplier))
        }
    }

    private var validSelectedTemplates: [TransactionTemplateItem] {
        selectedTemplates.filter {
            $0.amountMinor > 0 && $0.category != nil && $0.account != nil
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("Bulk mode", selection: $mode) {
                        Text("Groups").tag(BulkEntryMode.groups)
                        Text("Templates").tag(BulkEntryMode.templates)
                    }
                    .pickerStyle(.segmented)

                    switch mode {
                    case .groups:
                        groupPicker
                    case .templates:
                        templatePicker
                    }

                    previewSection

                    if let message {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(Color(hex: "#B4613B"))
                    }
                }
                .padding(20)
                .padding(.bottom, 24)
            }
            .navigationTitle("Bulk Add")
            .navigationBarTitleDisplayMode(.inline)
            .floatBackground()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create", action: createTransactions)
                        .disabled(validSelectedTemplates.isEmpty)
                }
            }
            .onAppear {
                if selectedGroup == nil, let group = groups.first {
                    select(group)
                }
            }
            .onChange(of: mode) { _, _ in message = nil }
        }
    }

    @ViewBuilder
    private var groupPicker: some View {
        if groups.isEmpty {
            GlassCard {
                EmptyStateView(
                    icon: "square.stack.3d.up.slash",
                    title: "No groups",
                    message: "Create template groups from Settings."
                )
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Groups")
                ForEach(groups) { group in
                    Button {
                        select(group)
                    } label: {
                        BulkGroupCard(
                            group: group,
                            currencyCode: appState.selectedCurrencyCode,
                            isSelected: selectedGroup?.id == group.id
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var templatePicker: some View {
        if templates.isEmpty {
            GlassCard {
                EmptyStateView(
                    icon: "square.text.square",
                    title: "No templates",
                    message: "Create templates before using bulk entry."
                )
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Templates")
                ForEach(templates) { template in
                    Button {
                        toggle(template)
                    } label: {
                        BulkTemplateSelectionRow(
                            template: template,
                            currencyCode: appState.selectedCurrencyCode,
                            isSelected: selectedTemplateIDs.contains(template.id)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var previewSection: some View {
        switch mode {
        case .groups:
            if !groupDraftEntries.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Will create")
                    GlassCard {
                        VStack(spacing: 14) {
                            ForEach($groupDraftEntries) { $entry in
                                if let template = template(for: entry.templateID) {
                                    BulkGroupDraftRow(
                                        entry: $entry,
                                        template: template,
                                        templates: templates,
                                        currencyCode: appState.selectedCurrencyCode
                                    )
                                    if entry.id != groupDraftEntries.last?.id {
                                        Divider()
                                    }
                                }
                            }
                        }
                    }
                }
            }
        case .templates:
            if !selectedTemplates.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Will create")
                    GlassCard {
                        VStack(spacing: 12) {
                            ForEach(Array(selectedTemplates.enumerated()), id: \.offset) { index, template in
                                BulkTemplateSummaryRow(
                                    template: template,
                                    currencyCode: appState.selectedCurrencyCode
                                )
                                if index < selectedTemplates.count - 1 {
                                    Divider()
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func select(_ group: TransactionTemplateGroupItem) {
        selectedGroup = group
        groupDraftEntries = group.validTemplates.map { template in
            BulkGroupDraftEntry(templateID: template.id)
        }
        message = nil
        Haptics.tick()
    }

    private func toggle(_ template: TransactionTemplateItem) {
        if selectedTemplateIDs.contains(template.id) {
            selectedTemplateIDs.remove(template.id)
        } else {
            selectedTemplateIDs.insert(template.id)
        }
        message = nil
        Haptics.tick()
    }

    private func createTransactions() {
        let invalidCount = selectedTemplates.count - validSelectedTemplates.count
        do {
            let createdCount = try TransactionRepository(modelContext: modelContext)
                .createMany(from: validSelectedTemplates, timestamp: Date())
            guard createdCount > 0 else {
                message = "Select templates with an amount, category, and account."
                return
            }
            Haptics.confirm()
            if invalidCount > 0 {
                message = "Created \(createdCount). Skipped \(invalidCount) incomplete templates."
            }
            dismiss()
        } catch {
            message = error.localizedDescription
        }
    }

    private func template(for id: UUID) -> TransactionTemplateItem? {
        templates.first { $0.id == id }
    }
}

private enum BulkEntryMode: String, CaseIterable {
    case groups
    case templates
}

private struct BulkGroupDraftEntry: Identifiable {
    let id: UUID
    var templateID: UUID
    var multiplier: Int

    init(id: UUID = UUID(), templateID: UUID, multiplier: Int = 1) {
        self.id = id
        self.templateID = templateID
        self.multiplier = multiplier
    }
}

struct TransactionTemplateGroupManagerView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @Query(sort: \TransactionTemplateGroupItem.createdAt, order: .reverse)
    private var groups: [TransactionTemplateGroupItem]
    @State private var editorPresentation: TransactionTemplateGroupEditorPresentation?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if groups.isEmpty {
                    GlassCard {
                        EmptyStateView(
                            icon: "square.stack.3d.up",
                            title: "No groups",
                            message: "Create a daily set from your transaction templates."
                        )
                    }
                }

                ForEach(groups) { group in
                    BulkGroupCard(
                        group: group,
                        currencyCode: appState.selectedCurrencyCode,
                        isSelected: false
                    )
                    .contextMenu {
                        Button {
                            editorPresentation =
                                TransactionTemplateGroupEditorPresentation(group: group)
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            delete(group)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .onTapGesture {
                        editorPresentation =
                            TransactionTemplateGroupEditorPresentation(group: group)
                    }
                }
            }
            .padding(20)
            .padding(.bottom, 120)
        }
        .navigationTitle("Template Groups")
        .floatBackground()
        .toolbar {
            Button {
                editorPresentation =
                    TransactionTemplateGroupEditorPresentation(group: nil)
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("Add template group")
        }
        .sheet(item: $editorPresentation) { presentation in
            TransactionTemplateGroupEditorView(group: presentation.group)
        }
    }

    private func delete(_ group: TransactionTemplateGroupItem) {
        try? TransactionTemplateGroupRepository(modelContext: modelContext)
            .delete(group)
    }
}

private struct TransactionTemplateGroupEditorPresentation: Identifiable {
    let id = UUID()
    let group: TransactionTemplateGroupItem?
}

private struct TransactionTemplateGroupEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @Query(sort: \TransactionTemplateItem.createdAt, order: .reverse)
    private var templates: [TransactionTemplateItem]

    let group: TransactionTemplateGroupItem?
    @State private var name = ""
    @State private var orderedEntries: [TemplateGroupEditorEntry] = []
    @State private var validationMessage: String?

    private var selectedTemplates: [TransactionTemplateItem] {
        orderedEntries.compactMap { template(for: $0.templateID) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Group name", text: $name)
                }

                Section("Included") {
                    if orderedEntries.isEmpty {
                        Text("Add templates to this group.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(orderedEntries) { entry in
                            if let template = template(for: entry.templateID) {
                                BulkTemplateSummaryRow(
                                    template: template,
                                    currencyCode: appState.selectedCurrencyCode
                                )
                            }
                        }
                        .onMove { source, destination in
                            orderedEntries.move(
                                fromOffsets: source,
                                toOffset: destination
                            )
                        }
                        .onDelete { offsets in
                            orderedEntries.remove(atOffsets: offsets)
                        }
                    }
                }

                Section("Available") {
                    if templates.isEmpty {
                        Text("No templates available.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(templates) { template in
                            Button {
                                orderedEntries.append(
                                    TemplateGroupEditorEntry(templateID: template.id)
                                )
                                validationMessage = nil
                            } label: {
                                BulkTemplateSummaryRow(
                                    template: template,
                                    currencyCode: appState.selectedCurrencyCode
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if let validationMessage {
                    Text(validationMessage)
                        .font(.footnote)
                        .foregroundStyle(Color(hex: "#B4613B"))
                }
            }
            .navigationTitle(group == nil ? "New Group" : "Edit Group")
            .scrollContentBackground(.hidden)
            .floatBackground()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .principal) {
                    if selectedTemplates.count > 1 {
                        EditButton()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear(perform: configure)
        }
    }

    private func configure() {
        guard name.isEmpty, orderedEntries.isEmpty else { return }
        if let group {
            name = group.name
            orderedEntries = group.validTemplates.map { template in
                TemplateGroupEditorEntry(templateID: template.id)
            }
        }
    }

    private func save() {
        guard !selectedTemplates.isEmpty else {
            validationMessage = "Add at least one template."
            return
        }

        do {
            let repository = TransactionTemplateGroupRepository(modelContext: modelContext)
            if let group {
                try repository.update(
                    group,
                    name: name,
                    templates: selectedTemplates
                )
            } else {
                _ = try repository.create(
                    name: name,
                    templates: selectedTemplates
                )
            }
            dismiss()
        } catch {
            validationMessage = error.localizedDescription
        }
    }

    private func template(for id: UUID) -> TransactionTemplateItem? {
        templates.first { $0.id == id }
    }
}

private struct TemplateGroupEditorEntry: Identifiable {
    let id: UUID
    var templateID: UUID

    init(id: UUID = UUID(), templateID: UUID) {
        self.id = id
        self.templateID = templateID
    }
}

private struct BulkGroupCard: View {
    let group: TransactionTemplateGroupItem
    let currencyCode: String
    let isSelected: Bool

    private var templates: [TransactionTemplateItem] {
        group.validTemplates
    }

    private var totalMinor: Int64 {
        templates.reduce(Int64(0)) { total, template in
            total + (template.isExpense ? template.amountMinor : -template.amountMinor)
        }
    }

    var body: some View {
        GlassCard {
            HStack(spacing: 14) {
                FloatIconBadge(
                    icon: "square.stack.3d.up.fill",
                    tint: Color(hex: "#0E7C7B"),
                    size: 42
                )
                VStack(alignment: .leading, spacing: 5) {
                    Text(group.displayName)
                        .font(.headline)
                        .lineLimit(1)
                    Text("\(templates.count) templates")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text(totalText)
                    .moneyStyle(size: 15, weight: .semibold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color(hex: "#1B8A5A"))
                }
            }
        }
    }

    private var totalText: String {
        let amount = MoneyFormatter.string(
            minorUnits: abs(totalMinor),
            currencyCode: currencyCode
        )
        if totalMinor < 0 {
            return "+\(amount)"
        }
        return amount
    }
}

private struct BulkTemplateSelectionRow: View {
    let template: TransactionTemplateItem
    let currencyCode: String
    let isSelected: Bool

    var body: some View {
        GlassCard(padding: 14) {
            HStack(spacing: 12) {
                BulkTemplateSummaryRow(
                    template: template,
                    currencyCode: currencyCode
                )
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color(hex: "#1B8A5A") : .secondary)
            }
        }
    }
}

private struct BulkGroupDraftRow: View {
    @Binding var entry: BulkGroupDraftEntry
    let template: TransactionTemplateItem
    let templates: [TransactionTemplateItem]
    let currencyCode: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            BulkTemplateSummaryRow(
                template: template,
                currencyCode: currencyCode
            )
            HStack(spacing: 12) {
                Menu {
                    ForEach(templates) { option in
                        Button {
                            entry.templateID = option.id
                        } label: {
                            Label(
                                option.displayTitle,
                                systemImage: option.id == entry.templateID
                                    ? "checkmark"
                                    : "arrow.triangle.2.circlepath"
                            )
                        }
                    }
                } label: {
                    Label("Swap", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption.weight(.semibold))
                }
                .disabled(templates.isEmpty)

                Spacer(minLength: 8)

                Stepper(value: $entry.multiplier, in: 1...99) {
                    Text("Qty \(entry.multiplier)")
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                }
                .fixedSize()
            }
        }
    }
}

private struct BulkTemplateSummaryRow: View {
    let template: TransactionTemplateItem
    let currencyCode: String

    var body: some View {
        HStack(spacing: 12) {
            FloatIconBadge(
                icon: template.category?.iconKey ?? "square.text.square",
                tint: Color(hex: template.category?.colorHex ?? "#0E7C7B"),
                size: 34
            )
            VStack(alignment: .leading, spacing: 3) {
                Text(template.displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(amount)
                .moneyStyle(size: 14, weight: .semibold)
                .foregroundStyle(template.isExpense ? .primary : Color(hex: "#1B8A5A"))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    private var detail: String {
        "\(template.category?.name ?? "Missing Category") • \(template.account?.name ?? "Missing Account")"
    }

    private var amount: String {
        MoneyFormatter.string(
            minorUnits: template.amountMinor,
            currencyCode: currencyCode,
            showsSign: !template.isExpense
        )
    }
}
