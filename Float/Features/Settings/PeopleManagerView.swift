import SwiftData
import SwiftUI

private func trimmed(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

struct PeopleManagerView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @Query(sort: \PersonItem.createdAt) private var people: [PersonItem]
    @State private var editorPresentation: PersonEditorPresentation?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(people) { person in
                    NavigationLink {
                        PersonDetailView(person: person)
                    } label: {
                        personRow(person)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 16)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            editorPresentation = PersonEditorPresentation(person: person)
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        Button {
                            archive(person)
                        } label: {
                            Label("Archive", systemImage: "archivebox")
                        }
                        Button(role: .destructive) {
                            delete(person)
                        } label: {
                            Label("Delete", systemImage: "trash")
                                .foregroundStyle(.red)
                        }
                    }

                    if person.id != people.last?.id {
                        Divider()
                            .padding(.leading, 78)
                    }
                }
            }
            .transactionSectionGlassSurface(cornerRadius: 24)
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 120)
        }
        .navigationTitle("People")
        .floatBackground()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editorPresentation = PersonEditorPresentation(person: nil)
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add person")
            }
        }
        .sheet(item: $editorPresentation) { presentation in
            PersonEditorView(person: presentation.person)
        }
    }

    private func personRow(_ person: PersonItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(hex: person.colorHex).opacity(0.96),
                                Color(hex: person.colorHex).opacity(0.62),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 42, height: 42)
                    .overlay {
                        Image(systemName: "person.2.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                    .shadow(color: Color(hex: person.colorHex).opacity(0.16), radius: 8, y: 2)

                VStack(alignment: .leading, spacing: 6) {
                    Text(person.name)
                        .font(.headline.weight(.semibold))

                    HStack(spacing: 8) {
                        countPill(
                            title: AppLocalization.format(
                                "Transactions %lld",
                                Int64(person.transactionCount)
                            ),
                            tint: Color(hex: person.colorHex)
                        )

                        if person.archived {
                            archivedPill
                        }
                    }
                }

                Spacer(minLength: 0)
            }

            if let note = trimmed(person.note) {
                Text(note)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let latestTransactionText = latestTransactionText(for: person) {
                Text(latestTransactionText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color(hex: person.colorHex).opacity(0.92))
                    .lineLimit(1)
            }
        }
    }

    private func countPill(title: String, tint: Color) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.12))
            }
    }

    private var archivedPill: some View {
        Text("Archived")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                Capsule(style: .continuous)
                    .fill(.secondary.opacity(0.12))
            }
    }

    private func archive(_ person: PersonItem) {
        person.archived = true
        person.updatedAt = Date()
        try? modelContext.save()
    }

    private func delete(_ person: PersonItem) {
        let personID = person.id
        let transactionTagDescriptor = FetchDescriptor<TransactionPersonTagItem>(
            predicate: #Predicate<TransactionPersonTagItem> { tag in
                tag.person?.id == personID
            }
        )
        let recurringTagDescriptor = FetchDescriptor<RecurringRulePersonTagItem>(
            predicate: #Predicate<RecurringRulePersonTagItem> { tag in
                tag.person?.id == personID
            }
        )
        let settlementDescriptor = FetchDescriptor<SettlementCaseItem>(
            predicate: #Predicate<SettlementCaseItem> { caseItem in
                caseItem.person?.id == personID
            }
        )

        if let transactionTags = try? modelContext.fetch(transactionTagDescriptor) {
            transactionTags.forEach { modelContext.delete($0) }
        }
        if let recurringTags = try? modelContext.fetch(recurringTagDescriptor) {
            recurringTags.forEach { modelContext.delete($0) }
        }
        if let settlementCases = try? modelContext.fetch(settlementDescriptor) {
            settlementCases.forEach { caseItem in
                if caseItem.counterpartyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    caseItem.counterpartyName = person.name
                }
                caseItem.person = nil
            }
        }
        modelContext.delete(person)
        try? modelContext.save()
    }

    private func latestTransactionText(for person: PersonItem) -> String? {
        guard let transaction = person.transactionTags
            .compactMap(\.transaction)
            .sorted(by: { $0.timestamp > $1.timestamp })
            .first
        else {
            return nil
        }

        let currencyCode = transaction.account?.currencyCode ?? appState.selectedCurrencyCode
        let amountText = signedAmountText(for: transaction, currencyCode: currencyCode)
        let dateText = transaction.timestamp.formatted(date: .abbreviated, time: .omitted)
        return AppLocalization.format("Latest transaction %@ • %@", amountText, dateText)
    }

    private func signedAmountText(for transaction: TransactionItem, currencyCode: String) -> String {
        let prefix = transaction.isPending || transaction.isExpense ? "" : "+"
        return prefix + MoneyFormatter.string(
            minorUnits: transaction.amountMinor,
            currencyCode: currencyCode
        )
    }
}

private struct PersonEditorPresentation: Identifiable {
    let id = UUID()
    let person: PersonItem?
}

private struct PersonDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    let person: PersonItem

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // details of the person.
                GlassCard {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(countsText)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.secondary)

                                if let latestTransactionText {
                                    Text(latestTransactionText)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Color(hex: person.colorHex))
                                        .lineLimit(1)
                                }

                                if person.archived {
                                    Text(String(localized: "Archived"))
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()

                            Button(action: refreshCounts) {
                                Image(systemName: "arrow.clockwise")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Refresh counts")
                        }
                    }
                }

                if !taggedTransactions.isEmpty {
                    GlassCard {
                        VStack(spacing: 10) {
                            ForEach(taggedTransactions.prefix(8)) { transaction in
                                TransactionRowView(
                                    transaction: transaction,
                                    currencyCode: transaction.account?.currencyCode ?? "USD"
                                )
                                if transaction.id != taggedTransactions.prefix(8).last?.id {
                                    Divider()
                                }
                            }
                        }
                    }
                }

                if !taggedRecurringRules.isEmpty {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Recurring rules")
                                .font(.headline)
                            ForEach(taggedRecurringRules) { rule in
                                Text(rule.note ?? rule.category?.name ?? "Recurring")
                                    .font(.subheadline)
                            }
                        }
                    }
                }
            }
            .padding(20)
            .padding(.bottom, 120)
        }
        .navigationTitle(person.name)
        .floatBackground()
    }

    private var taggedTransactions: [TransactionItem] {
        person.transactionTags
            .compactMap(\.transaction)
            .sorted { $0.timestamp > $1.timestamp }
    }

    private var taggedRecurringRules: [RecurringRuleItem] {
        person.recurringRuleTags.compactMap(\.recurringRule)
    }

    private var countsText: String {
        AppLocalization.format(
            "Transactions %lld • Recurring %lld",
            Int64(person.transactionCount),
            Int64(person.recurringRuleCount)
        )
    }

    private var latestTransactionText: String? {
        guard let transaction = taggedTransactions.first else { return nil }
        let currencyCode = transaction.account?.currencyCode ?? appState.selectedCurrencyCode
        let amountText = signedAmountText(for: transaction, currencyCode: currencyCode)
        return AppLocalization.format("Latest transaction %@", amountText)
    }

    private func refreshCounts() {
        person.transactionCount = fetchTransactionCount()
        person.recurringRuleCount = fetchRecurringRuleCount()
        person.updatedAt = Date()
        try? modelContext.save()
    }

    private func fetchTransactionCount() -> Int {
        let personID = person.id
        let descriptor = FetchDescriptor<TransactionPersonTagItem>(
            predicate: #Predicate<TransactionPersonTagItem> { tag in
                tag.person?.id == personID
            }
        )
        return (try? modelContext.fetch(descriptor).count) ?? 0
    }

    private func fetchRecurringRuleCount() -> Int {
        let personID = person.id
        let descriptor = FetchDescriptor<RecurringRulePersonTagItem>(
            predicate: #Predicate<RecurringRulePersonTagItem> { tag in
                tag.person?.id == personID
            }
        )
        return (try? modelContext.fetch(descriptor).count) ?? 0
    }

    private func signedAmountText(for transaction: TransactionItem, currencyCode: String) -> String {
        let prefix = transaction.isPending || transaction.isExpense ? "" : "+"
        return prefix + MoneyFormatter.string(
            minorUnits: transaction.amountMinor,
            currencyCode: currencyCode
        )
    }

}

private struct PersonEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let person: PersonItem?

    @State private var name = ""
    @State private var alias = ""
    @State private var note = ""
    @State private var colorHex = "#0E7C7B"
    @State private var archived = false

    private let colors = [
        "#0E7C7B", "#14B8A6", "#0EA5E9", "#3B82F6",
        "#2563EB", "#6366F1", "#7C3AED", "#8B5CF6",
        "#A855F7", "#EC4899", "#F97316", "#22C55E",
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Name", text: $name)
                    TextField("Alias", text: $alias)
                    TextField("Note", text: $note, axis: .vertical)
                        .lineLimit(1...3)
                    Toggle("Archived", isOn: $archived)
                }

                Section("Color") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 34))], spacing: 12) {
                        ForEach(colors, id: \.self) { color in
                            Button {
                                colorHex = color
                            } label: {
                                Circle()
                                    .fill(Color(hex: color))
                                    .frame(width: 32, height: 32)
                                    .overlay {
                                        if colorHex == color {
                                            Image(systemName: "checkmark")
                                                .font(.caption.bold())
                                                .foregroundStyle(.white)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle(person == nil ? "New Person" : "Edit Person")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
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
        guard let person else { return }
        name = person.name
        alias = person.alias ?? ""
        note = person.note ?? ""
        colorHex = person.colorHex
        archived = person.archived
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let person {
            person.name = trimmedName
            person.alias = trimmedValue(alias)
            person.note = trimmedValue(note)
            person.colorHex = colorHex
            person.archived = archived
            person.updatedAt = Date()
        } else {
            modelContext.insert(
                PersonItem(
                    name: trimmedName,
                    alias: alias,
                    note: note,
                    colorHex: colorHex,
                    archived: archived
                )
            )
        }
        try? modelContext.save()
        dismiss()
    }

    private func trimmedValue(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
