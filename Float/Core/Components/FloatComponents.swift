import SwiftUI

struct GlassCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(20)
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
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
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
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
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
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 64, height: 64)
                .background(Color(hex: "#0E7C7B"), in: Circle())
                .shadow(
                    color: Color(hex: "#0E7C7B").opacity(0.32),
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
            in: Capsule()
        )
        .foregroundStyle(isSelected ? Color(hex: category.colorHex) : .primary)
    }
}

struct TransactionRowView: View {
    let transaction: TransactionItem
    let currencyCode: String

    var body: some View {
        HStack(spacing: 12) {
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
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 4) {
                Text(transaction.categoryName)
                    .font(.subheadline.weight(.semibold))
                Text(
                    transaction.note?.isEmpty == false
                        ? transaction.note ?? ""
                        : transaction.accountName
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                Text(transaction.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer()
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
        }
        .padding(.vertical, 6)
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
