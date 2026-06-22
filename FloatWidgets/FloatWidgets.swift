import Foundation
import AppIntents
import SwiftUI
import WidgetKit

private struct FloatWidgetSnapshot: Codable {
    let safeToSpendMinor: Int64
    let dailyAllowanceMinor: Int64
    let daysRemaining: Int
    let periodProgress: Double
    let statusText: String
    let currencyCode: String
    let updatedAt: Date
    let todayExpensesMinor: Int64?
    let nextRecurringTitle: String?
    let nextRecurringAmountMinor: Int64?
    let topBudgetAlertTitle: String?
    let topBudgetAlertProgress: Double?

    static let fallback = FloatWidgetSnapshot(
        safeToSpendMinor: 0,
        dailyAllowanceMinor: 0,
        daysRemaining: 0,
        periodProgress: 0,
        statusText: String(localized: "Open Float to update"),
        currencyCode: Locale.current.currency?.identifier ?? "USD",
        updatedAt: Date(),
        todayExpensesMinor: nil,
        nextRecurringTitle: nil,
        nextRecurringAmountMinor: nil,
        topBudgetAlertTitle: nil,
        topBudgetAlertProgress: nil
    )
}

private struct SafeToSpendEntry: TimelineEntry {
    let date: Date
    let snapshot: FloatWidgetSnapshot
}

private struct SafeToSpendProvider: TimelineProvider {
    private let appGroupIdentifier = "group.com.reducer.Float"
    private let snapshotKey = "float.safeToSpend.widgetSnapshot"

    func placeholder(in context: Context) -> SafeToSpendEntry {
        SafeToSpendEntry(
            date: Date(),
            snapshot: FloatWidgetSnapshot(
                safeToSpendMinor: 422_100,
                dailyAllowanceMinor: 60_300,
                daysRemaining: 7,
                periodProgress: 0.45,
                statusText: String(localized: "On track"),
                currencyCode: Locale.current.currency?.identifier ?? "USD",
                updatedAt: Date(),
                todayExpensesMinor: 18_700,
                nextRecurringTitle: "Rent",
                nextRecurringAmountMinor: 180_000,
                topBudgetAlertTitle: "Dining is close",
                topBudgetAlertProgress: 0.86
            )
        )
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (SafeToSpendEntry) -> Void
    ) {
        completion(SafeToSpendEntry(date: Date(), snapshot: loadSnapshot()))
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<SafeToSpendEntry>) -> Void
    ) {
        let entry = SafeToSpendEntry(date: Date(), snapshot: loadSnapshot())
        let nextUpdate = Calendar.current.date(
            byAdding: .minute,
            value: 45,
            to: Date()
        ) ?? Date().addingTimeInterval(45 * 60)
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private func loadSnapshot() -> FloatWidgetSnapshot {
        guard
            let userDefaults = UserDefaults(suiteName: appGroupIdentifier),
            let data = userDefaults.data(forKey: snapshotKey),
            let snapshot = try? JSONDecoder().decode(FloatWidgetSnapshot.self, from: data)
        else {
            return .fallback
        }
        return snapshot
    }
}

struct FloatSafeToSpendWidget: Widget {
    private let kind = "FloatSafeToSpendWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SafeToSpendProvider()) { entry in
            SafeToSpendWidgetView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Safe to spend")
        .description("See what is safe to spend from your Lock Screen.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryRectangular,
            .accessoryCircular,
            .accessoryInline,
        ])
    }
}

private struct SafeToSpendWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SafeToSpendEntry

    var body: some View {
        switch family {
        case .systemSmall:
            smallHomeView
        case .systemMedium:
            mediumHomeView
        case .accessoryCircular:
            circularView
        case .accessoryInline:
            Text(inlineText)
        default:
            rectangularView
        }
    }

    private var smallHomeView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Float")
                    .font(.headline.weight(.bold))
                Spacer()
                progressRing
                    .frame(width: 24, height: 24)
            }
            Spacer(minLength: 0)
            Text(headlineText)
                .font(.title2.monospacedDigit().weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.66)
            Text("safe - \(shortMoney(entry.snapshot.dailyAllowanceMinor))/day")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                HStack(spacing: 8) {
                    widgetButton(systemImage: "minus.circle.fill", intent: AddWidgetExpenseIntent())
                    widgetButton(systemImage: "plus.circle.fill", intent: AddWidgetIncomeIntent())
                    widgetButton(systemImage: "doc.viewfinder.fill", intent: ScanWidgetReceiptIntent())
                }
            }
        .padding()
    }

    private var mediumHomeView: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Safe to spend")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(headlineText)
                    .font(.title.monospacedDigit().weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    widgetButton(systemImage: "minus.circle.fill", intent: AddWidgetExpenseIntent())
                    widgetButton(systemImage: "plus.circle.fill", intent: AddWidgetIncomeIntent())
                    widgetButton(systemImage: "arrow.left.arrow.right.circle.fill", intent: AddWidgetTransferIntent())
                    widgetButton(systemImage: "square.text.square", intent: OpenWidgetTemplatesIntent())
                    widgetButton(systemImage: "checklist", intent: OpenWidgetReviewQueueIntent())
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 8) {
                widgetMetric(
                    title: "Today",
                    value: shortMoney(entry.snapshot.todayExpensesMinor ?? 0)
                )
                widgetMetric(
                    title: "Next",
                    value: nextRecurringText
                )
                widgetMetric(
                    title: "Alert",
                    value: budgetAlertText
                )
            }
            .frame(maxWidth: 130, alignment: .leading)
        }
        .padding()
    }

    private var rectangularView: some View {
        HStack(spacing: 8) {
            progressRing
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text("Safe to spend")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(headlineText)
                    .font(.headline.monospacedDigit().weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(detailText)
                    .font(.caption2)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var circularView: some View {
        ZStack {
            progressRing
            VStack(spacing: 0) {
                Text(
                    hasData
                        ? shortCompactMoney(entry.snapshot.safeToSpendMinor)
                        : String(localized: "Open")
                )
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(
                    hasData
                        ? String(localized: "safe")
                        : String(localized: "Float")
                )
                    .font(.system(size: 8, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var progressRing: some View {
        ZStack {
            Circle()
                .stroke(.secondary.opacity(0.28), lineWidth: 3)
            Circle()
                .trim(from: 0, to: min(max(entry.snapshot.periodProgress, 0), 1))
                .stroke(
                    .primary,
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
    }

    private func widgetButton<I: AppIntent>(
        systemImage: String,
        intent: I
    ) -> some View {
        Button(intent: intent) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 28, height: 28)
                .background(.primary.opacity(0.08), in: Circle())
        }
        .buttonStyle(.plain)
    }

    private func widgetMetric(title: LocalizedStringResource, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private var inlineText: String {
        if !hasData {
            return entry.snapshot.statusText
        }
        return String(localized: "Safe \(shortMoney(entry.snapshot.safeToSpendMinor)) left")
    }

    private var headlineText: String {
        hasData ? shortMoney(entry.snapshot.safeToSpendMinor) : String(localized: "Open Float")
    }

    private var detailText: String {
        guard hasData else {
            return String(localized: "to update")
        }
        return String(
            localized: "\(entry.snapshot.daysRemaining)d left - \(entry.snapshot.statusText)"
        )
    }

    private var nextRecurringText: String {
        guard let title = entry.snapshot.nextRecurringTitle, !title.isEmpty else {
            return String(localized: "None")
        }
        if let amount = entry.snapshot.nextRecurringAmountMinor {
            return String(localized: "\(title) \(shortMoney(amount))")
        }
        return title
    }

    private var budgetAlertText: String {
        guard let title = entry.snapshot.topBudgetAlertTitle, !title.isEmpty else {
            return String(localized: "Clear")
        }
        if let progress = entry.snapshot.topBudgetAlertProgress {
            return String(localized: "\(Int((progress * 100).rounded()))% \(title)")
        }
        return title
    }

    private var hasData: Bool {
        entry.snapshot.daysRemaining > 0
    }

    private func shortMoney(_ minorUnits: Int64) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = entry.snapshot.currencyCode
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        let divisor = pow(10.0, Double(fractionDigits(for: entry.snapshot.currencyCode)))
        let number = NSDecimalNumber(decimal: Decimal(minorUnits) / Decimal(divisor))
        return formatter.string(from: number) ?? "\(entry.snapshot.currencyCode) \(minorUnits)"
    }

    private func shortCompactMoney(_ minorUnits: Int64) -> String {
        let major = Double(minorUnits) / pow(10.0, Double(fractionDigits(for: entry.snapshot.currencyCode)))
        if major >= 1_000_000 {
            return "\(Int(major / 1_000_000))M"
        }
        if major >= 1_000 {
            return "\(Int(major / 1_000))K"
        }
        return "\(Int(major))"
    }

    private func fractionDigits(for currencyCode: String) -> Int {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        return formatter.maximumFractionDigits
    }
}

@available(iOSApplicationExtension 18.0, *)
private struct FloatExpenseControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "FloatExpenseControl") {
            ControlWidgetButton(action: AddWidgetExpenseIntent()) {
                Label("Expense", systemImage: "minus.circle.fill")
            }
        }
        .displayName("Add Expense")
        .description("Open Float ready to add an expense.")
    }
}

@available(iOSApplicationExtension 18.0, *)
private struct FloatReceiptControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "FloatReceiptControl") {
            ControlWidgetButton(action: ScanWidgetReceiptIntent()) {
                Label("Scan Receipt", systemImage: "doc.viewfinder.fill")
            }
        }
        .displayName("Scan Receipt")
        .description("Open Float's receipt scanner.")
    }
}

@available(iOSApplicationExtension 18.0, *)
private struct FloatReviewControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "FloatReviewControl") {
            ControlWidgetButton(action: OpenWidgetReviewQueueIntent()) {
                Label("Review", systemImage: "checklist")
            }
        }
        .displayName("Review Queue")
        .description("Open Float's review queue.")
    }
}

@main
private struct FloatWidgetsBundle: WidgetBundle {
    var body: some Widget {
        FloatSafeToSpendWidget()
        if #available(iOSApplicationExtension 18.0, *) {
            FloatExpenseControl()
            FloatReceiptControl()
            FloatReviewControl()
        }
    }
}
