import Foundation
import SwiftUI

extension View {
    func transactionSectionGlassSurface(
        _ glass: Glass = .regular,
        cornerRadius: CGFloat = FloatTheme.controlRadius
    ) -> some View {
        let shape = RoundedRectangle(
            cornerRadius: cornerRadius,
            style: .continuous
        )

        return self
            .glassEffect(glass, in: .rect(cornerRadius: cornerRadius))
            .overlay(
                shape.strokeBorder(
                    Color.primary.opacity(0.07),
                    lineWidth: 1
                )
            )
    }

    @ViewBuilder
    func floatGlassSurface(
        cornerRadius: CGFloat = FloatTheme.tileRadius,
        material: Material = .thinMaterial,
        tint: Color? = nil,
        interactive: Bool = false,
        strokeOpacity: Double = 0.08,
        shadowOpacity: Double = 0,
        shadowRadius: CGFloat = 0,
        shadowY: CGFloat = 0
    ) -> some View {
        let shape = RoundedRectangle(
            cornerRadius: cornerRadius,
            style: .continuous
        )

        if #available(iOS 26.0, *) {
            if let tint {
                if interactive {
                    self
                        .glassEffect(
                            .regular.tint(tint.opacity(0.14)).interactive(),
                            in: .rect(cornerRadius: cornerRadius)
                        )
                        .overlay(shape.strokeBorder(Color.primary.opacity(strokeOpacity), lineWidth: 1))
                        .shadow(color: .black.opacity(shadowOpacity), radius: shadowRadius, y: shadowY)
                } else {
                    self
                        .glassEffect(
                            .regular.tint(tint.opacity(0.14)),
                            in: .rect(cornerRadius: cornerRadius)
                        )
                        .overlay(shape.strokeBorder(Color.primary.opacity(strokeOpacity), lineWidth: 1))
                        .shadow(color: .black.opacity(shadowOpacity), radius: shadowRadius, y: shadowY)
                }
            } else if interactive {
                self
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
                    .overlay(shape.strokeBorder(Color.primary.opacity(strokeOpacity), lineWidth: 1))
                    .shadow(color: .black.opacity(shadowOpacity), radius: shadowRadius, y: shadowY)
            } else {
                self
                    .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
                    .overlay(shape.strokeBorder(Color.primary.opacity(strokeOpacity), lineWidth: 1))
                    .shadow(color: .black.opacity(shadowOpacity), radius: shadowRadius, y: shadowY)
            }
        } else {
            self
                .background(material, in: shape)
                .background((tint ?? Color.clear).opacity(0.07), in: shape)
                .overlay(shape.strokeBorder(Color.primary.opacity(strokeOpacity), lineWidth: 1))
                .shadow(color: .black.opacity(shadowOpacity), radius: shadowRadius, y: shadowY)
        }
    }

    @ViewBuilder
    func floatGlassCircle(
        material: Material = .thinMaterial,
        tint: Color? = nil,
        interactive: Bool = false,
        strokeOpacity: Double = 0.08,
        shadowOpacity: Double = 0,
        shadowRadius: CGFloat = 0,
        shadowY: CGFloat = 0
    ) -> some View {
        if #available(iOS 26.0, *) {
            if let tint {
                if interactive {
                    self
                        .glassEffect(
                            .regular.tint(tint.opacity(0.16)).interactive(),
                            in: .circle
                        )
                        .overlay(Circle().strokeBorder(Color.primary.opacity(strokeOpacity), lineWidth: 1))
                        .shadow(color: .black.opacity(shadowOpacity), radius: shadowRadius, y: shadowY)
                } else {
                    self
                        .glassEffect(
                            .regular.tint(tint.opacity(0.16)),
                            in: .circle
                        )
                        .overlay(Circle().strokeBorder(Color.primary.opacity(strokeOpacity), lineWidth: 1))
                        .shadow(color: .black.opacity(shadowOpacity), radius: shadowRadius, y: shadowY)
                }
            } else if interactive {
                self
                    .glassEffect(.regular.interactive(), in: .circle)
                    .overlay(Circle().strokeBorder(Color.primary.opacity(strokeOpacity), lineWidth: 1))
                    .shadow(color: .black.opacity(shadowOpacity), radius: shadowRadius, y: shadowY)
            } else {
                self
                    .glassEffect(.regular, in: .circle)
                    .overlay(Circle().strokeBorder(Color.primary.opacity(strokeOpacity), lineWidth: 1))
                    .shadow(color: .black.opacity(shadowOpacity), radius: shadowRadius, y: shadowY)
            }
        } else {
            self
                .background(material, in: Circle())
                .background((tint ?? Color.clear).opacity(0.1), in: Circle())
                .overlay(Circle().strokeBorder(Color.primary.opacity(strokeOpacity), lineWidth: 1))
                .shadow(color: .black.opacity(shadowOpacity), radius: shadowRadius, y: shadowY)
        }
    }
}

struct GlassCard<Content: View>: View {
    let content: Content
    let padding: CGFloat

    init(padding: CGFloat = 20, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.padding = padding
    }

    var body: some View {
        content
            .padding(padding)
            .floatGlassSurface(
                cornerRadius: FloatTheme.radius,
                material: .ultraThinMaterial,
                strokeOpacity: 0.08,
                shadowOpacity: 0.08,
                shadowRadius: 24,
                shadowY: 14
            )
    }
}

struct GlassButton<Label: View>: View {
    let action: () -> Void
    let label: Label

    init(action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
        self.action = action
        self.label = label()
    }

    var body: some View {
        Button(action: action) {
            label
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .floatGlassSurface(
                    cornerRadius: FloatTheme.controlRadius,
                    interactive: true,
                    strokeOpacity: 0.08
                )
        }
        .buttonStyle(.plain)
    }
}

struct GlassTextField: View {
    let title: String
    @Binding var text: String

    var body: some View {
        TextField(title, text: $text)
            .textFieldStyle(.plain)
            .padding(14)
            .floatGlassSurface(
                cornerRadius: FloatTheme.tileRadius,
                material: .thinMaterial,
                strokeOpacity: 0.06
            )
    }
}

struct FloatProgressRing: View {
    let progress: Double
    let tint: Color
    var lineWidth: CGFloat = 10

    var body: some View {
        ZStack {
            Circle().stroke(.primary.opacity(0.08), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(
                    tint,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
        .animation(
            .spring(response: 0.5, dampingFraction: 0.85),
            value: progress
        )
    }
}

struct SectionHeader: View {
    let title: LocalizedStringResource
    var actionTitle: LocalizedStringResource?
    var action: (() -> Void)?

    var body: some View {
        HStack {
            Text(title).font(.headline)
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action).font(
                    .subheadline.weight(.medium)
                )
            }
        }
        .foregroundStyle(.primary)
    }
}

struct FloatIconBadge: View {
    let icon: String
    let tint: Color
    var size: CGFloat = 34

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.12), in: Circle())
    }
}

struct SummaryMetricTile: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: LocalizedStringResource
    let value: String
    let caption: LocalizedStringResource?
    let captionText: String?
    let icon: String
    let tint: Color

    init(
        title: LocalizedStringResource,
        value: String,
        caption: LocalizedStringResource? = nil,
        icon: String,
        tint: Color
    ) {
        self.title = title
        self.value = value
        self.caption = caption
        self.captionText = nil
        self.icon = icon
        self.tint = tint
    }

    init(
        title: LocalizedStringResource,
        value: String,
        captionText: String?,
        icon: String,
        tint: Color
    ) {
        self.title = title
        self.value = value
        self.caption = nil
        self.captionText = captionText
        self.icon = icon
        self.tint = tint
    }

    private var fillOpacity: Double {
        colorScheme == .dark ? 0.18 : 0.08
    }

    private var liftOpacity: Double {
        colorScheme == .dark ? 0.08 : 0
    }

    private var strokeOpacity: Double {
        colorScheme == .dark ? 0.28 : 0.16
    }

    var body: some View {
        let shape = RoundedRectangle(
            cornerRadius: FloatTheme.tileRadius,
            style: .continuous
        )

        HStack(alignment: .top, spacing: 10) {
            FloatIconBadge(icon: icon, tint: tint, size: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .moneyStyle(size: 15, weight: .semibold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                if let caption {
                    Text(caption)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                } else if let captionText {
                    Text(captionText)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.primary.opacity(liftOpacity),
            in: shape
        )
        .background(
            tint.opacity(fillOpacity),
            in: shape
        )
        .overlay(
            shape.strokeBorder(tint.opacity(strokeOpacity), lineWidth: 1)
        )
    }
}

struct CurrencyAmountPreview: View {
    let minorUnits: Int64
    let currencyCode: String

    var body: some View {
        Text(
            MoneyFormatter.string(
                minorUnits: minorUnits,
                currencyCode: currencyCode
            )
        )
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .accessibilityLabel("Formatted amount")
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: LocalizedStringResource
    let message: LocalizedStringResource

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
    }
}

struct FloatingAddButton: View {
    @AppStorage("selectedThemeMode") private var selectedThemeMode = "float"
    let action: () -> Void

    private var accent: Color {
        FloatTheme.palette(for: selectedThemeMode).accent
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(accent)
                .frame(width: 64, height: 64)
                .floatGlassCircle(
                    tint: accent,
                    interactive: true,
                    strokeOpacity: 0.12,
                    shadowOpacity: 0.16,
                    shadowRadius: 22,
                    shadowY: 12
                )
        }
        .accessibilityLabel("Add transaction")
    }
}

struct CategoryChip: View {
    let category: CategoryItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: category.iconKey)
            Text(category.name)
        }
        .font(.subheadline.weight(.medium))
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            isSelected
                ? Color(hex: category.colorHex).opacity(0.22)
                : Color.primary.opacity(0.06),
            in: RoundedRectangle(
                cornerRadius: FloatTheme.tileRadius,
                style: .continuous
            )
        )
        .overlay(
            RoundedRectangle(
                cornerRadius: FloatTheme.tileRadius,
                style: .continuous
            )
            .strokeBorder(Color(hex: category.colorHex).opacity(isSelected ? 0.22 : 0), lineWidth: 1)
        )
        .foregroundStyle(isSelected ? Color(hex: category.colorHex) : .primary)
    }
}

struct TransactionRowView: View {
    let transaction: TransactionItem
    let currencyCode: String

    private var noteText: String? {
        guard let note = transaction.note?.trimmingCharacters(in: .whitespacesAndNewlines),
              !note.isEmpty
        else {
            return nil
        }
        return note
    }

    private var accountAndTimeText: String {
        if transaction.isPending {
            let dueDate = transaction.displayDate.formatted(date: .abbreviated, time: .omitted)
            return AppLocalization.format("Pending • Due %@", dueDate)
        }
        let timestamp = transaction.timestamp.formatted(date: .abbreviated, time: .shortened)
        return AppLocalization.format("%@ • %@", transaction.accountName, timestamp)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(
                        Color(hex: transaction.categoryColorHex)
                            .opacity(0.16)
                    )
                    Image(systemName: transaction.categoryIconKey)
                    .foregroundStyle(
                        Color(hex: transaction.categoryColorHex)
                    )
                }
                .font(.subheadline.weight(.semibold))
                .frame(width: 34, height: 34)

                Text(transaction.categoryName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(
                    (transaction.isPending || transaction.isExpense ? "" : "+")
                        + MoneyFormatter.string(
                            minorUnits: transaction.amountMinor,
                            currencyCode: currencyCode
                        )
                )
                .moneyStyle(size: 15, weight: .semibold)
                .foregroundStyle(
                    transaction.isPending
                        ? .secondary
                        : transaction.isExpense ? .primary : Color(hex: "#1B8A5A")
                )
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(minWidth: 88, alignment: .trailing)
            }

            VStack(alignment: .leading, spacing: 2) {
                if let people = transaction.personSummary {
                    HStack(spacing: 4) {
                        Image(systemName: "person.2.fill")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.primary.opacity(0.56))

                        Text(people)
                            .font(.caption2)
                            .foregroundStyle(Color.primary.opacity(0.62))
                            .lineLimit(1)
                    }
                }

                if let noteText {
                    Text(noteText)
                        .font(.caption2)
                        .foregroundStyle(Color.primary.opacity(0.68))
                        .lineLimit(1)
                }

                Text(accountAndTimeText)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Color.primary.opacity(0.52))
                    .lineLimit(1)
            }
            .padding(.leading, 44)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TransferRowView: View {
    let transfer: TransferItem
    let currencyCode: String

    private var noteText: String? {
        guard let note = transfer.note?.trimmingCharacters(in: .whitespacesAndNewlines),
              !note.isEmpty
        else {
            return nil
        }
        return note
    }

    private var accountAndTimeText: String {
        let timestamp = transfer.timestamp.formatted(date: .abbreviated, time: .shortened)
        return String(
            localized: "\(transfer.fromAccountName) -> \(transfer.toAccountName) • \(timestamp)"
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(Color(hex: "#0A6FAE").opacity(0.16))
                    Image(systemName: "arrow.left.arrow.right")
                        .foregroundStyle(Color(hex: "#0A6FAE"))
                }
                .font(.subheadline.weight(.semibold))
                .frame(width: 34, height: 34)

                Text("Transfer")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(
                    MoneyFormatter.string(
                        minorUnits: transfer.amountMinor,
                        currencyCode: currencyCode
                    )
                )
                .moneyStyle(size: 15, weight: .semibold)
                .foregroundStyle(Color(hex: "#0A6FAE"))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(minWidth: 88, alignment: .trailing)
            }

            VStack(alignment: .leading, spacing: 1) {
                if let noteText {
                    Text(noteText)
                        .font(.caption2)
                        .foregroundStyle(Color.primary.opacity(0.68))
                        .lineLimit(1)
                }

                Text(accountAndTimeText)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Color.primary.opacity(0.52))
                    .lineLimit(1)
            }
            .padding(.leading, 44)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AccountPicker: View {
    @Binding var selectedAccount: AccountItem?
    let accounts: [AccountItem]

    var body: some View {
        Picker(
            "Account",
            selection: Binding(
                get: { selectedAccount?.id },
                set: { id in selectedAccount = accounts.first { $0.id == id } }
            )
        ) {
            Text("Default account").tag(UUID?.none)
            ForEach(accounts) { account in
                Label(account.name, systemImage: account.type.icon).tag(
                    Optional(account.id)
                )
            }
        }
        .pickerStyle(.menu)
    }
}

struct PeoplePicker: View {
    @Binding var selectedPersonIDs: Set<UUID>
    let people: [PersonItem]
    @State private var showingSelector = false

    private var selectedPeople: [PersonItem] {
        people.filter { selectedPersonIDs.contains($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("People", systemImage: "person.2.fill")
                Spacer()
                Button(selectedPeople.isEmpty ? "Add" : "Edit") {
                    showingSelector = true
                }
                .font(.caption.weight(.semibold))
            }

            if selectedPeople.isEmpty {
                Text("No people tagged")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(selectedPeople) { person in
                        Text(person.name)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Color(hex: person.colorHex).opacity(0.16),
                                in: Capsule()
                            )
                            .foregroundStyle(Color(hex: person.colorHex))
                    }
                }
            }
        }
        .sheet(isPresented: $showingSelector) {
            PersonSelectionSheet(
                people: people,
                selectedPersonIDs: $selectedPersonIDs
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }
}

private struct PersonSelectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    let people: [PersonItem]
    @Binding var selectedPersonIDs: Set<UUID>

    var body: some View {
        NavigationStack {
            List {
                ForEach(people) { person in
                    Button {
                        toggle(person)
                    } label: {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(Color(hex: person.colorHex).opacity(0.18))
                                .frame(width: 28, height: 28)
                                .overlay {
                                    Image(systemName: "person.fill")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(Color(hex: person.colorHex))
                                }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(person.name)
                                if let alias = nonEmpty(person.alias) {
                                    Text(alias)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                if person.archived {
                                    Text("Archived")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()

                            if selectedPersonIDs.contains(person.id) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("People")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func toggle(_ person: PersonItem) {
        if selectedPersonIDs.contains(person.id) {
            selectedPersonIDs.remove(person.id)
        } else {
            selectedPersonIDs.insert(person.id)
        }
    }

    private func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return nil }
        return trimmed
    }
}

extension View {
    func keyboardDismissControls() -> some View {
        self
            .scrollDismissesKeyboard(.interactively)
    }
}
