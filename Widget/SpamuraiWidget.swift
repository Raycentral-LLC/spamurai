import Charts
import SwiftUI
import WidgetKit

struct StatsEntry: TimelineEntry {
    let date: Date
    let today: DayStats
    let week: [DayStats]
    let allTime: Int

    static let placeholder = StatsEntry(
        date: .now,
        today: DayStats(day: DayStats.dayKey(), blocked: 1_284, total: 6_420),
        week: (0..<7).map { DayStats(day: "\($0)", blocked: [820, 1100, 960, 1400, 1210, 990, 1284][$0], total: 6000) },
        allTime: 48_310
    )
}

struct StatsProvider: TimelineProvider {
    func placeholder(in context: Context) -> StatsEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (StatsEntry) -> Void) {
        completion(context.isPreview ? .placeholder : current())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StatsEntry>) -> Void) {
        // The tunnel can't push reloads cheaply; refresh on a schedule (the app also reloads on background).
        completion(Timeline(entries: [current()], policy: .after(.now.addingTimeInterval(15 * 60))))
    }

    private func current() -> StatsEntry {
        StatsEntry(date: .now, today: StatsStore.today, week: StatsStore.history, allTime: StatsStore.blockedAllTime)
    }
}

struct SpamuraiWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: StatsEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: entry.today.blockedShare) {
                Image(systemName: "shield.lefthalf.filled")
            } currentValueLabel: {
                Text(entry.today.blocked.formatted(.number.notation(.compactName)))
            }
            .gaugeStyle(.accessoryCircularCapacity)
        case .accessoryRectangular:
            VStack(alignment: .leading) {
                Label("Spamurai", systemImage: "shield.lefthalf.filled").font(.headline)
                Text("\(entry.today.blocked.formatted()) blocked today")
                Text("\(share) of lookups").foregroundStyle(.secondary)
            }
        case .accessoryInline:
            Label("\(entry.today.blocked.formatted()) blocked", systemImage: "shield.lefthalf.filled")
        case .systemMedium:
            HStack(spacing: 16) {
                summary
                chart
            }
        default:
            summary
        }
    }

    private var share: String { entry.today.blockedShare.formatted(.percent.precision(.fractionLength(0))) }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Spamurai", systemImage: "shield.lefthalf.filled")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.red)
            Spacer(minLength: 0)
            Text(entry.today.blocked.formatted())
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .contentTransition(.numericText())
            Text("blocked today").font(.caption).foregroundStyle(.secondary)
            Text("\(share) of \(entry.today.total.formatted()) lookups")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var chart: some View {
        Chart(Array(entry.week.enumerated()), id: \.offset) { item in
            BarMark(x: .value("Day", item.offset), y: .value("Blocked", item.element.blocked))
                .foregroundStyle(item.offset == entry.week.count - 1 ? Color.red : Color.red.opacity(0.35))
                .cornerRadius(3)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .overlay(alignment: .topTrailing) {
            if entry.week.isEmpty { Text("No data yet").font(.caption2).foregroundStyle(.secondary) }
        }
    }
}

@main
struct SpamuraiWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SpamuraiStats", provider: StatsProvider()) { entry in
            SpamuraiWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Blocked today")
        .description("Ads and trackers Spamurai blocked across your apps.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
