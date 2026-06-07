import SwiftData
import SwiftUI

struct GoalsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @Query(sort: \GoalItem.createdAt, order: .reverse) private var goals:
        [GoalItem]
    @State private var showingEditor = false
    @State private var editingGoal: GoalItem?
    @State private var contributionGoal: GoalItem?
    @State private var showCompleted = true

    private var visibleGoals: [GoalItem] {
        goals.filter { showCompleted || !$0.achieved }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                GlassCard {
                    Toggle("Show completed", isOn: $showCompleted)
                }

                if visibleGoals.isEmpty {
                    GlassCard {
                        EmptyStateView(
                            icon: "target",
                            title: goals.isEmpty
                                ? "No goals yet"
                                : "No visible goals",
                            message: goals.isEmpty
                                ? "Create a goal to reserve money before spending."
                                : "Completed goals are hidden for now."
                        )
                    }
                }

                ForEach(visibleGoals) { goal in
                    GoalCard(
                        goal: goal,
                        currencyCode: appState.selectedCurrencyCode,
                        onEdit: {
                            editingGoal = goal
                            showingEditor = true
                        },
                        onContribute: {
                            contributionGoal = goal
                        },
                        onDelete: {
                            delete(goal)
                        }
                    )
                }
            }
            .padding(20)
            .padding(.bottom, 120)
        }
        .navigationTitle("Goals")
        .floatBackground()
        .toolbar {
            Button {
                editingGoal = nil
                showingEditor = true
            } label: {
                Image(systemName: "plus")
            }
        }
        .sheet(isPresented: $showingEditor) {
            GoalEditorView(goal: editingGoal)
        }
        .sheet(item: $contributionGoal) { goal in
            GoalContributionSheet(goal: goal)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    private func delete(_ goal: GoalItem) {
        try? GoalRepository(modelContext: modelContext).delete(goal)
    }
}

private struct GoalCard: View {
    let goal: GoalItem
    let currencyCode: String
    let onEdit: () -> Void
    let onContribute: () -> Void
    let onDelete: () -> Void

    private var tint: Color {
        Color(hex: goal.colorHex)
    }

    private var progress: Double {
        Double(goal.savedMinor) / Double(max(goal.targetMinor, 1))
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    FloatProgressRing(
                        progress: progress,
                        tint: tint,
                        lineWidth: 7
                    )
                    .frame(width: 52, height: 52)

                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 7) {
                            Text(goal.name)
                                .font(.headline)
                                .lineLimit(1)
                            if goal.achieved {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundStyle(Color(hex: "#1B8A5A"))
                            }
                        }
                        Text(
                            "\(money(goal.savedMinor)) of \(money(goal.targetMinor))"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        if let targetDate = goal.targetDate {
                            Text("Target \(targetDate.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.tertiary)
                        }
                    }

                    Spacer(minLength: 8)

                    VStack(alignment: .trailing, spacing: 4) {
                        Text(money(max(0, goal.targetMinor - goal.savedMinor)))
                            .moneyStyle(size: 14, weight: .semibold)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        Text("remaining")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                ProgressView(value: min(max(progress, 0), 1))
                    .tint(tint)

                HStack(spacing: 10) {
                    Button(action: onContribute) {
                        Label("Contribute", systemImage: "plus.circle.fill")
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.borderless)

                    Spacer()

                    Button(action: onEdit) {
                        Label("Edit", systemImage: "pencil")
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.borderless)
                }
            }
        }
        .opacity(goal.achieved ? 0.72 : 1)
        .contentShape(Rectangle())
        .contextMenu {
            Button(role: .destructive, action: onDelete) {
                Label {
                    Text("Delete")
                        .foregroundStyle(.red)
                } icon: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
            }
            .tint(.red)
        }
    }

    private func money(_ amount: Int64) -> String {
        MoneyFormatter.string(minorUnits: amount, currencyCode: currencyCode)
    }
}

struct GoalEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    let goal: GoalItem?
    @State private var name = ""
    @State private var targetText = ""
    @State private var savedText = ""
    @State private var targetDate = Date()
    @State private var hasDate = false
    @State private var colorHex = "#0E7C7B"
    @State private var validationMessage: String?

    private let colorOptions = [
        "#0E7C7B", "#1B8A5A", "#3B82F6", "#8B5CF6",
        "#B4613B", "#D08A62", "#EC4899", "#5A6B6B",
    ]

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                HStack {
                    TextField("Target minor units", text: $targetText)
                        .keyboardType(.numberPad)
                    CurrencyAmountPreview(
                        minorUnits: targetMinor,
                        currencyCode: appState.selectedCurrencyCode
                    )
                }
                HStack {
                    TextField("Saved minor units", text: $savedText)
                        .keyboardType(.numberPad)
                    CurrencyAmountPreview(
                        minorUnits: savedMinor,
                        currencyCode: appState.selectedCurrencyCode
                    )
                }
                Toggle("Target date", isOn: $hasDate)
                if hasDate {
                    DatePicker(
                        "Date",
                        selection: $targetDate,
                        displayedComponents: .date
                    )
                }
                Section("Color") {
                    HStack(spacing: 12) {
                        ForEach(colorOptions, id: \.self) { color in
                            Button {
                                colorHex = color
                            } label: {
                                Circle()
                                    .fill(Color(hex: color))
                                    .frame(width: 30, height: 30)
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
                if let validationMessage {
                    Text(validationMessage)
                        .font(.footnote)
                        .foregroundStyle(Color(hex: "#B4613B"))
                }
            }
            .navigationTitle(goal == nil ? "New Goal" : "Edit Goal")
            .keyboardDismissControls()
            .scrollContentBackground(.hidden)
            .floatBackground()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(name.isEmpty)
                }
            }
            .onAppear {
                guard let goal else { return }
                name = goal.name
                targetText = "\(goal.targetMinor)"
                savedText = "\(goal.savedMinor)"
                targetDate = goal.targetDate ?? Date()
                hasDate = goal.targetDate != nil
                colorHex = goal.colorHex
            }
        }
    }

    private var targetMinor: Int64 {
        Int64(targetText) ?? 0
    }

    private var savedMinor: Int64 {
        Int64(savedText) ?? 0
    }

    private func save() {
        let target = targetMinor
        let saved = savedMinor
        guard target > 0 else {
            validationMessage = "Enter a target amount greater than zero."
            return
        }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let repository = GoalRepository(modelContext: modelContext)
            if let goal {
                try repository.update(
                    goal,
                    name: trimmedName,
                    targetMinor: target,
                    savedMinor: saved,
                    targetDate: hasDate ? targetDate : nil,
                    colorHex: colorHex
                )
            } else {
                _ = try repository.create(
                    name: trimmedName,
                    targetMinor: target,
                    savedMinor: saved,
                    targetDate: hasDate ? targetDate : nil,
                    colorHex: colorHex
                )
            }
            dismiss()
        } catch {
            validationMessage = error.localizedDescription
        }
    }
}

struct GoalContributionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    let goal: GoalItem
    @State private var amountText = ""
    @State private var mode = ContributionMode.add
    @State private var validationMessage: String?

    private var amountMinor: Int64 {
        BudgetAmountField.minorUnits(
            fromMajorAmount: amountText,
            currencyCode: appState.selectedCurrencyCode
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Mode", selection: $mode) {
                    ForEach(ContributionMode.allCases) {
                        Text($0.title).tag($0)
                    }
                }
                .pickerStyle(.segmented)
                HStack {
                    TextField("Amount", text: $amountText)
                        .keyboardType(.decimalPad)
                    CurrencyAmountPreview(
                        minorUnits: amountMinor,
                        currencyCode: appState.selectedCurrencyCode
                    )
                }
                Section("Current goal") {
                    goalRow("Saved", goal.savedMinor)
                    goalRow("Remaining", max(0, goal.targetMinor - goal.savedMinor))
                    if let targetDate = goal.targetDate {
                        Text("Target \(targetDate.formatted(date: .abbreviated, time: .omitted))")
                            .foregroundStyle(.secondary)
                    }
                }
                if let validationMessage {
                    Text(validationMessage)
                        .font(.footnote)
                        .foregroundStyle(Color(hex: "#B4613B"))
                }
            }
            .navigationTitle("Contribution")
            .keyboardDismissControls()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(amountMinor == 0)
                }
            }
        }
    }

    private func goalRow(_ title: String, _ amount: Int64) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(
                MoneyFormatter.string(
                    minorUnits: amount,
                    currencyCode: appState.selectedCurrencyCode
                )
            )
            .moneyStyle(size: 15, weight: .semibold)
        }
    }

    private func save() {
        guard amountMinor > 0 else {
            validationMessage = "Enter an amount greater than zero."
            return
        }
        do {
            let repository = GoalRepository(modelContext: modelContext)
            switch mode {
            case .add:
                try repository.addContribution(amountMinor, to: goal)
            case .reduce:
                try repository.reduceContribution(amountMinor, from: goal)
            }
            dismiss()
        } catch {
            validationMessage = error.localizedDescription
        }
    }
}

private enum ContributionMode: String, CaseIterable, Identifiable {
    case add
    case reduce

    var id: String { rawValue }

    var title: String {
        switch self {
        case .add: "Add"
        case .reduce: "Reduce"
        }
    }
}
