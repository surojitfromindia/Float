import SwiftUI

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
            .background(
                .ultraThinMaterial,
                in: RoundedRectangle(
                    cornerRadius: FloatTheme.radius,
                    style: .continuous
                )
            )
            .overlay(
                RoundedRectangle(
                    cornerRadius: FloatTheme.radius,
                    style: .continuous
                )
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.08), radius: 24, x: 0, y: 14)
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
                .background(
                    .thinMaterial,
                    in: RoundedRectangle(
                        cornerRadius: FloatTheme.controlRadius,
                        style: .continuous
                    )
                )
                .overlay(
                    RoundedRectangle(
                        cornerRadius: FloatTheme.controlRadius,
                        style: .continuous
                    )
                        .stroke(Color.primary.opacity(0.08))
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
            .background(
                .thinMaterial,
                in: RoundedRectangle(
                    cornerRadius: FloatTheme.tileRadius,
                    style: .continuous
                )
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
    let title: String
    var actionTitle: String?
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
    let title: String
    let value: String
    let caption: String?
    let icon: String
    let tint: Color

    init(
        title: String,
        value: String,
        caption: String? = nil,
        icon: String,
        tint: Color
    ) {
        self.title = title
        self.value = value
        self.caption = caption
        self.icon = icon
        self.tint = tint
    }

    var body: some View {
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
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            tint.opacity(0.08),
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
            .strokeBorder(tint.opacity(0.16), lineWidth: 1)
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
    let title: String
    let message: String

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
                .foregroundStyle(.white)
                .frame(width: 64, height: 64)
                .background(accent, in: Circle())
                .shadow(
                    color: accent.opacity(0.32),
                    radius: 22,
                    x: 0,
                    y: 12
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
        let timestamp = transaction.timestamp.formatted(date: .abbreviated, time: .shortened)
        return "\(transaction.accountName) • \(timestamp)"
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
                    (transaction.isExpense ? "" : "+")
                        + MoneyFormatter.string(
                            minorUnits: transaction.amountMinor,
                            currencyCode: currencyCode
                        )
                )
                .moneyStyle(size: 15, weight: .semibold)
                .foregroundStyle(
                    transaction.isExpense ? .primary : Color(hex: "#1B8A5A")
                )
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
        return "\(transfer.fromAccountName) -> \(transfer.toAccountName) • \(timestamp)"
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
            ForEach(accounts) { account in
                Label(account.name, systemImage: account.type.icon).tag(
                    Optional(account.id)
                )
            }
        }
        .pickerStyle(.menu)
    }
}

extension View {
    func keyboardDismissControls() -> some View {
        self
            .scrollDismissesKeyboard(.interactively)
    }
}
