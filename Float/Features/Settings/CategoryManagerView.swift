import SwiftData
import SwiftUI

struct CategoryManagerView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CategoryItem.sortOrder) private var categories: [CategoryItem]
    @State private var editorPresentation: CategoryEditorPresentation?

    var body: some View {
        List {
            ForEach(categories) { category in
                Button {
                    editorPresentation = CategoryEditorPresentation(
                        category: category
                    )
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(
                                    Color(hex: category.colorHex).opacity(0.16)
                                )
                            Image(systemName: category.iconKey)
                                .foregroundStyle(Color(hex: category.colorHex))
                        }
                        .frame(width: 36, height: 36)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(category.name)
                                .font(.headline)
                            Text(category.isIncome ? "Income" : "Expense")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if category.archived {
                            Text("Archived")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .onDelete {
                let repository = CategoryRepository(modelContext: modelContext)
                $0.map { categories[$0] }.forEach {
                    try? repository.deleteIfUnused($0)
                }
            }
        }
        .navigationTitle("Categories")
        .scrollContentBackground(.hidden)
        .floatBackground()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editorPresentation = CategoryEditorPresentation(
                        category: nil
                    )
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add category")
            }
        }
        .sheet(item: $editorPresentation) { presentation in
            CategoryEditorView(
                category: presentation.category,
                nextSortOrder: categories.count
            )
        }
    }
}

private struct CategoryEditorPresentation: Identifiable {
    let id = UUID()
    let category: CategoryItem?
}

private struct CategoryEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let category: CategoryItem?
    let nextSortOrder: Int

    @State private var name = ""
    @State private var iconKey = "square.grid.2x2.fill"
    @State private var colorHex = "#0E7C7B"
    @State private var isIncome = false
    @State private var archived = false

    private let iconOptions = [
        "fork.knife", "cup.and.saucer.fill", "basket.fill", "cart.fill",
        "bag.fill", "tshirt.fill", "car.fill", "bus.fill", "tram.fill",
        "bicycle", "fuelpump.fill", "airplane", "house.fill", "bed.double.fill",
        "bolt.fill", "wifi", "phone.fill", "doc.text.fill", "creditcard.fill",
        "building.columns.fill", "shield.fill", "cross.case.fill", "pills.fill",
        "heart.fill", "stethoscope", "dumbbell.fill", "graduationcap.fill",
        "book.fill", "play.tv.fill", "gamecontroller.fill", "music.note",
        "film.fill", "sportscourt.fill", "gift.fill", "repeat.circle.fill",
        "wrench.adjustable.fill", "hammer.fill", "briefcase.fill",
        "laptopcomputer", "desktopcomputer", "banknote.fill",
        "chart.line.uptrend.xyaxis", "arrow.uturn.backward.circle.fill",
        "sparkles", "square.grid.2x2.fill",
    ]

    private let colorOptions = [
        "#0E7C7B", "#14B8A6", "#0EA5E9", "#3B82F6",
        "#2563EB", "#6366F1", "#7C3AED", "#8B5CF6",
        "#A855F7", "#C026D3", "#DB2777", "#EC4899",
        "#F43F5E", "#EF4444", "#F97316", "#F59E0B",
        "#B4613B", "#D08A62", "#84CC16", "#22C55E",
        "#16A34A", "#1B8A5A", "#059669", "#0F766E",
        "#0891B2", "#64748B", "#5A6B6B", "#111827",
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Name", text: $name)
                    Toggle("Income category", isOn: $isIncome)
                    Toggle("Archived", isOn: $archived)
                }

                Section("Icon") {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 44))],
                        spacing: 12
                    ) {
                        ForEach(iconOptions, id: \.self) { icon in
                            Button {
                                iconKey = icon
                            } label: {
                                Image(systemName: icon)
                                    .font(.headline)
                                    .frame(width: 42, height: 42)
                                    .background(
                                        iconKey == icon
                                            ? Color(hex: colorHex).opacity(0.2)
                                            : Color.primary.opacity(0.06),
                                        in: Circle()
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Color") {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 34))],
                        spacing: 12
                    ) {
                        ForEach(colorOptions, id: \.self) { color in
                            Button {
                                colorHex = color
                            } label: {
                                Circle()
                                    .fill(Color(hex: color))
                                    .frame(width: 32, height: 32)
                                    .overlay(
                                        Circle()
                                            .strokeBorder(
                                                Color.primary.opacity(colorHex == color ? 0.2 : 0),
                                                lineWidth: 3
                                            )
                                    )
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
                    TextField("Hex color", text: $colorHex)
                        .textInputAutocapitalization(.characters)
                }
            }
            .navigationTitle(category == nil ? "New Category" : "Edit Category")
            .keyboardDismissControls()
            .scrollContentBackground(.hidden)
            .floatBackground()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(
                            name.trimmingCharacters(in: .whitespacesAndNewlines)
                                .isEmpty
                        )
                }
            }
            .onAppear(perform: configure)
        }
    }

    private func configure() {
        guard let category else { return }
        name = category.name
        iconKey = category.iconKey
        colorHex = category.colorHex
        isIncome = category.isIncome
        archived = category.archived
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let category {
            category.name = trimmedName
            category.iconKey = iconKey
            category.colorHex = colorHex
            category.isIncome = isIncome
            category.archived = archived
            category.updatedAt = Date()
        } else {
            modelContext.insert(
                CategoryItem(
                    name: trimmedName,
                    iconKey: iconKey,
                    colorHex: colorHex,
                    isIncome: isIncome,
                    sortOrder: nextSortOrder,
                    archived: archived,
                    isDefault: false
                )
            )
        }
        try? modelContext.save()
        dismiss()
    }
}
