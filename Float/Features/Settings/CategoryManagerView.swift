import SwiftData
import SwiftUI

struct CategoryManagerView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CategoryItem.sortOrder) private var categories: [CategoryItem]
    @State private var showingEditor = false
    @State private var editingCategory: CategoryItem?

    var body: some View {
        List {
            ForEach(categories) { category in
                Button {
                    editingCategory = category
                    showingEditor = true
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editingCategory = nil
                    showingEditor = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add category")
            }
        }
        .sheet(isPresented: $showingEditor) {
            CategoryEditorView(
                category: editingCategory,
                nextSortOrder: categories.count
            )
        }
    }
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
        "fork.knife", "car.fill", "doc.text.fill", "basket.fill", "bag.fill",
        "cross.case.fill", "play.tv.fill", "banknote.fill", "house.fill",
        "gift.fill", "airplane", "square.grid.2x2.fill",
    ]

    private let colorOptions = [
        "#0E7C7B", "#1B8A5A", "#3B82F6", "#8B5CF6",
        "#B4613B", "#D08A62", "#EC4899", "#5A6B6B",
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
                    TextField("Hex color", text: $colorHex)
                        .textInputAutocapitalization(.characters)
                }
            }
            .navigationTitle(category == nil ? "New Category" : "Edit Category")
            .keyboardDismissControls()
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
