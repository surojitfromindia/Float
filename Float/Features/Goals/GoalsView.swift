import SwiftData
import SwiftUI

struct GoalsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @Query(sort: \GoalItem.createdAt, order: .reverse) private var goals:
        [GoalItem]
    @State private var showingEditor = false
    @State private var editingGoal: GoalItem?

    var body: some View {
        List {
            if goals.isEmpty {
                EmptyStateView(
                    icon: "target",
                    title: "No goals yet",
                    message: "Create a goal to reserve money before spending."
                )
                .listRowBackground(Color.clear)
            }
            ForEach(goals) { goal in
                Button {
                    editingGoal = goal
                    showingEditor = true
                } label: {
                    HStack(spacing: 14) {
                        FloatProgressRing(
                            progress: Double(goal.savedMinor)
                                / Double(max(goal.targetMinor, 1)),
                            tint: Color(hex: goal.colorHex),
                            lineWidth: 7
                        )
                        .frame(width: 48, height: 48)
                        VStack(alignment: .leading) {
                            Text(goal.name).font(.headline)
                            Text(
                                "\(MoneyFormatter.string(minorUnits: goal.savedMinor, currencyCode: appState.selectedCurrencyCode)) saved"
                            )
                            .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if goal.achieved {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(Color(hex: "#1B8A5A"))
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .onDelete { offsets in
                offsets.map { goals[$0] }.forEach(modelContext.delete)
                try? modelContext.save()
            }
        }
        .navigationTitle("Goals")
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
            }
            .navigationTitle(goal == nil ? "New Goal" : "Edit Goal")
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
        if let goal {
            goal.name = name
            goal.targetMinor = target
            goal.savedMinor = saved
            goal.targetDate = hasDate ? targetDate : nil
            goal.achieved = saved >= target && target > 0
            goal.updatedAt = Date()
        } else {
            modelContext.insert(
                GoalItem(
                    name: name,
                    targetMinor: target,
                    savedMinor: saved,
                    targetDate: hasDate ? targetDate : nil,
                    achieved: saved >= target && target > 0
                )
            )
        }
        try? modelContext.save()
        dismiss()
    }
}
