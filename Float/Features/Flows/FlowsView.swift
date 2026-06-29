import SwiftData
import SwiftUI

struct FlowsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @Query(sort: \CustomFlowItem.sortOrder) private var allFlows: [CustomFlowItem]
    @State private var editor: FlowEditorPresentation?
    @State private var starterMessage: String?
    @State private var showingHelp = false

    private var flows: [CustomFlowItem] {
        filterActiveProfile(allFlows)
            .filter { !$0.archived }
            .sorted { lhs, rhs in
                if lhs.sortOrder == rhs.sortOrder {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhs.sortOrder < rhs.sortOrder
            }
    }

    var body: some View {
        List {
            Section {
                if flows.isEmpty {
                    FlowsEmptyRow()
                }

                if let starterMessage {
                    Text(starterMessage)
                        .font(.footnote)
                        .foregroundStyle(appState.themePalette.caution)
                }

                ForEach(flows) { flow in
                    NavigationLink {
                        FlowDetailView(flow: flow)
                    } label: {
                        FlowRow(flow: flow)
                    }
                    .contextMenu {
                        Button {
                            editor = FlowEditorPresentation(flow: flow)
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            archive(flow)
                        } label: {
                            Label("Archive", systemImage: "archivebox")
                        }
                    }
                }
            } header: {
                Text("Flows")
            }

            if flows.isEmpty {
                Section("Starter flows") {
                    ForEach(FlowStarterTemplate.allCases) { template in
                        Button {
                            installStarter(template)
                        } label: {
                            StarterTemplateRow(template: template)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .navigationTitle("Flows")
        .floatBackground()
        .toolbar {
            Button {
                showingHelp = true
            } label: {
                Image(systemName: "questionmark.circle")
            }
            Menu {
                Button {
                    editor = FlowEditorPresentation(flow: nil)
                } label: {
                    Label("New Flow", systemImage: "plus")
                }
                Divider()
                ForEach(FlowStarterTemplate.allCases) { template in
                    Button {
                        installStarter(template)
                    } label: {
                        Label(template.title, systemImage: template.iconKey)
                    }
                }
            } label: {
                Image(systemName: "plus")
            }
        }
        .sheet(item: $editor) { presentation in
            FlowEditorSheet(flow: presentation.flow)
        }
        .sheet(isPresented: $showingHelp) {
            FlowHelpSheet()
        }
    }

    private func archive(_ flow: CustomFlowItem) {
        flow.archived = true
        flow.updatedAt = Date()
        try? modelContext.save()
    }

    private func installStarter(_ template: FlowStarterTemplate) {
        do {
            let repository = CustomFlowRepository(modelContext: modelContext)
            _ = try template.install(using: repository)
            starterMessage = nil
        } catch {
            starterMessage = error.localizedDescription
        }
    }
}

private struct FlowRow: View {
    let flow: CustomFlowItem

    private var tint: Color { Color(hex: flow.colorHex) }

    var body: some View {
        Label {
            Text(flow.name)
                .font(.body.weight(.medium))
                .lineLimit(1)
        } icon: {
            Image(systemName: flow.iconKey)
                .font(.body.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 28)
        }
        .padding(.vertical, 5)
    }
}

private struct FlowsEmptyRow: View {
    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text("No flows")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                Text("Create a custom flow for lists, drafts, and records.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.body.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 28)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

private struct StarterTemplateRow: View {
    let template: FlowStarterTemplate

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(template.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(template.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        } icon: {
            Image(systemName: template.iconKey)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color(hex: template.colorHex))
                .frame(width: 28)
        }
        .padding(.vertical, 4)
    }
}

struct FlowHelpSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let steps = [
        FlowHelpStep(
            icon: "square.grid.2x2.fill",
            title: String(localized: "Start with a flow"),
            message: String(localized: "Install a starter flow or create a blank one for your own list, tracker, or workflow.")
        ),
        FlowHelpStep(
            icon: "rectangle.stack.fill",
            title: String(localized: "Add object types"),
            message: String(localized: "Object types are the record lists inside a flow, such as Products, Shopping Trips, Line Items, Subscriptions, or Loans.")
        ),
        FlowHelpStep(
            icon: "textformat.123",
            title: String(localized: "Create fields"),
            message: String(localized: "Fields define what each record captures: text, money, numbers, dates, checkboxes, choices, accounts, categories, people, relations, and formulas.")
        ),
        FlowHelpStep(
            icon: "link",
            title: String(localized: "Connect records"),
            message: String(localized: "Relations let one record point to another, or let a parent record hold many child rows, like a shopping trip with multiple grocery items.")
        ),
        FlowHelpStep(
            icon: "function",
            title: String(localized: "Calculate values"),
            message: String(localized: "Formula fields can add totals, line amounts, remaining balances, status summaries, date differences, relation lookups, and child-row sums.")
        ),
        FlowHelpStep(
            icon: "arrow.triangle.2.circlepath",
            title: String(localized: "Finalize into transactions"),
            message: String(localized: "A transaction action can create or update one linked Float transaction from a finalized record using field values or fixed defaults.")
        )
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    FlowHelpIntro()

                    VStack(alignment: .leading, spacing: 18) {
                        FlowHelpSectionTitle(
                            title: String(localized: "Build path"),
                            subtitle: String(localized: "Create the structure first, then add records and automation.")
                        )

                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                                FlowHelpStepRow(
                                    index: index + 1,
                                    step: step,
                                    isLast: index == steps.count - 1
                                )
                            }
                        }
                    }

                    FlowHelpDivider()

                    FlowHelpArticleSection(
                        icon: "cart.fill",
                        title: String(localized: "Grocery example"),
                        message: String(localized: "Create Products and Shopping Trips, relate trip items back to the trip, calculate line totals and the trip total, then finalize the trip to create one linked transaction.")
                    )

                    FlowHelpArticleSection(
                        icon: "pencil.and.list.clipboard",
                        title: String(localized: "Editing finalized records"),
                        message: String(localized: "Finalized records stay editable. If your edits affect a linked transaction, Float asks whether to update that transaction or only save the record.")
                    )
                }
                .padding(.horizontal, 24)
                .padding(.top, 22)
                .padding(.bottom, 36)
            }
            .navigationTitle("Flow Help")
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

private struct FlowHelpIntro: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Color(hex: "#0E7C7B"))
                .accessibilityHidden(true)

            Text("How flows work")
                .font(.largeTitle.weight(.bold))
                .lineLimit(2)
                .minimumScaleFactor(0.82)

            Text("Flows are low-code trackers built from the same core pieces: objects, fields, relations, formulas, records, and optional transaction actions.")
                .font(.body)
                .lineSpacing(3)
                .foregroundStyle(.secondary)
        }
    }
}

private struct FlowHelpSectionTitle: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.title3.weight(.semibold))
            Text(subtitle)
                .font(.subheadline)
                .lineSpacing(2)
                .foregroundStyle(.secondary)
        }
    }
}

private struct FlowHelpStepRow: View {
    let index: Int
    let step: FlowHelpStep
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color(hex: "#0E7C7B").opacity(0.12))
                    Text("\(index)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color(hex: "#0E7C7B"))
                }
                .frame(width: 30, height: 30)
                .accessibilityHidden(true)

                if !isLast {
                    Rectangle()
                        .fill(.separator)
                        .frame(width: 1)
                        .frame(maxHeight: .infinity)
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                Label {
                    Text(step.title)
                        .font(.headline)
                } icon: {
                    Image(systemName: step.icon)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(hex: "#0E7C7B"))
                }

                Text(step.message)
                    .font(.subheadline)
                    .lineSpacing(2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, isLast ? 0 : 22)
        }
    }
}

private struct FlowHelpArticleSection: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.headline)
                    .foregroundStyle(Color(hex: "#0E7C7B"))
                    .frame(width: 22, alignment: .leading)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.title3.weight(.semibold))
            }

            Text(message)
                .font(.body)
                .lineSpacing(3)
                .foregroundStyle(.secondary)
        }
    }
}

private struct FlowHelpDivider: View {
    var body: some View {
        Rectangle()
            .fill(.separator)
            .frame(height: 1)
    }
}

private struct FlowHelpStep: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let message: String
}
