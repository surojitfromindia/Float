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

    static let fallback = FloatWidgetSnapshot(
        safeToSpendMinor: 0,
        dailyAllowanceMinor: 0,
        daysRemaining: 0,
        periodProgress: 0,
        statusText: "Open Float to update",
        currencyCode: Locale.current.currency?.identifier ?? "USD",
        updatedAt: Date()
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
                statusText: "On track",
                currencyCode: Locale.current.currency?.identifier ?? "USD",
                updatedAt: Date()
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

@main
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
        case .accessoryCircular:
            circularView
        case .accessoryInline:
            Text(inlineText)
        default:
            rectangularView
        }
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
                Text(hasData ? shortCompactMoney(entry.snapshot.safeToSpendMinor) : "Open")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(hasData ? "safe" : "Float")
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

    private var inlineText: String {
        if !hasData {
            return entry.snapshot.statusText
        }
        return "Safe \(shortMoney(entry.snapshot.safeToSpendMinor)) left"
    }

    private var headlineText: String {
        hasData ? shortMoney(entry.snapshot.safeToSpendMinor) : "Open Float"
    }

    private var detailText: String {
        guard hasData else {
            return "to update"
        }
        return "\(entry.snapshot.daysRemaining)d left - \(entry.snapshot.statusText)"
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
