import Charts
import SwiftUI
import WidgetKit

// MARK: - Data

struct StatsEntry: TimelineEntry {
    let date: Date
    let active: Bool
    let today: DayStats
    let week: [DayStats]
    let allTime: Int
    let trackers: [Insights.Tracker]
    let recent: [JournalEntry]

    static let placeholder: StatsEntry = {
        let blocked = [820, 1100, 960, 1400, 1210, 990, 1284]
        let week = (0..<7).map { i in
            DayStats(day: DayStats.dayKey(Calendar.current.date(byAdding: .day, value: i - 6, to: .now)!),
                     blocked: blocked[i], total: blocked[i] * 5)
        }
        return StatsEntry(
            date: .now, active: true, today: week[6], week: week, allTime: 48_310,
            trackers: [.init(name: "Google", hits: 512), .init(name: "Meta", hits: 233),
                       .init(name: "AppLovin", hits: 141), .init(name: "TikTok", hits: 98)],
            recent: [JournalEntry(domain: "googleads.g.doubleclick.net", blocked: true, date: .now),
                     JournalEntry(domain: "graph.facebook.com", blocked: true, date: .now.addingTimeInterval(-40)),
                     JournalEntry(domain: "ms.applovin.com", blocked: true, date: .now.addingTimeInterval(-95))]
        )
    }()
}

struct StatsProvider: TimelineProvider {
    func placeholder(in context: Context) -> StatsEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (StatsEntry) -> Void) {
        completion(context.isPreview ? .placeholder : current())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StatsEntry>) -> Void) {
        // The tunnel reloads widgets when it starts/stops; counts refresh on this schedule.
        completion(Timeline(entries: [current()], policy: .after(.now.addingTimeInterval(15 * 60))))
    }

    private func current() -> StatsEntry {
        let journal = StatsStore.readJournal()
        let today = DayStats.dayKey()
        let todays = journal.filter { DayStats.dayKey($0.date) == today }
        return StatsEntry(
            date: .now,
            active: SharedStore.tunnelActive,
            today: StatsStore.today,
            week: lastSevenDays(StatsStore.history),
            allTime: StatsStore.blockedAllTime,
            trackers: Insights.topTrackers(todays, limit: 4),
            recent: Array(journal.filter(\.blocked).prefix(3))
        )
    }

    /// Always seven slots ending today, so the chart keeps its shape on day one.
    private func lastSevenDays(_ history: [DayStats]) -> [DayStats] {
        (0..<7).map { offset in
            let key = DayStats.dayKey(Calendar.current.date(byAdding: .day, value: offset - 6, to: .now)!)
            return history.first { $0.day == key } ?? DayStats(day: key)
        }
    }
}

// MARK: - Style

private enum Palette {
    static let crimson = Color(red: 0.90, green: 0.16, blue: 0.24)
    static let ember = Color(red: 1.00, green: 0.45, blue: 0.25)
    static let jade = Color(red: 0.20, green: 0.80, blue: 0.55)
    static let blade = LinearGradient(colors: [ember, crimson], startPoint: .topLeading, endPoint: .bottomTrailing)
}

/// The app icon's split shield as a vector, for headers and the lock screen.
struct ShieldGlyph: View {
    var active = true

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            ZStack {
                ShieldPath().fill(active ? AnyShapeStyle(Palette.blade) : AnyShapeStyle(Color.gray.opacity(0.6)))
                Path { p in
                    p.move(to: CGPoint(x: s * 0.86, y: s * 0.12))
                    p.addLine(to: CGPoint(x: s * 0.14, y: s * 0.88))
                }
                .stroke(Color.black, lineWidth: max(1, s * 0.07))
                Path { p in
                    p.move(to: CGPoint(x: s * 0.84, y: s * 0.14))
                    p.addLine(to: CGPoint(x: s * 0.16, y: s * 0.86))
                }
                .stroke(Color.white.opacity(active ? 0.95 : 0.4), lineWidth: max(0.5, s * 0.025))
            }
            .frame(width: s, height: s)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

private struct ShieldPath: Shape {
    func path(in r: CGRect) -> Path {
        // Same curves as scripts/make_icon.swift, scaled from its 1024 canvas.
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: r.minX + (x - 200) / 624 * r.width, y: r.minY + (y - 170) / 700 * r.height)
        }
        var p = Path()
        p.move(to: pt(512, 180))
        p.addCurve(to: pt(790, 290), control1: pt(600, 245), control2: pt(700, 280))
        p.addCurve(to: pt(512, 860), control1: pt(800, 560), control2: pt(700, 760))
        p.addCurve(to: pt(234, 290), control1: pt(324, 760), control2: pt(224, 560))
        p.addCurve(to: pt(512, 180), control1: pt(324, 280), control2: pt(424, 245))
        p.closeSubpath()
        return p
    }
}

private struct WCaps: View {
    let text: String
    var color: Color = .white.opacity(0.55)

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .semibold))
            .tracking(1.6)
            .foregroundStyle(color)
            .lineLimit(1)
    }
}

private struct Header: View {
    let active: Bool
    var showStatus = true

    var body: some View {
        HStack(spacing: 6) {
            ShieldGlyph(active: active).frame(width: 14, height: 14)
            WCaps(text: "Spamurai", color: .white.opacity(0.8))
            Spacer(minLength: 4)
            if showStatus {
                HStack(spacing: 4) {
                    Circle().fill(active ? Palette.jade : Color.gray).frame(width: 5, height: 5)
                    WCaps(text: active ? "On" : "Off", color: active ? Palette.jade : .gray)
                }
            }
        }
    }
}

private struct BigNumber: View {
    let value: Int
    let active: Bool
    var size: CGFloat = 38

    var body: some View {
        Text(value.formatted())
            .font(.system(size: size, weight: .light))
            .monospacedDigit()
            .foregroundStyle(active ? AnyShapeStyle(Palette.blade) : AnyShapeStyle(Color.white.opacity(0.6)))
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            .contentTransition(.numericText(value: Double(value)))
    }
}

private struct WeekBars: View {
    let week: [DayStats]
    var labels = false

    var body: some View {
        Chart(Array(week.enumerated()), id: \.offset) { item in
            BarMark(x: .value("Day", label(item.element.day, index: item.offset)),
                    y: .value("Blocked", max(item.element.blocked, 0)))
                .foregroundStyle(item.offset == week.count - 1 ? AnyShapeStyle(Palette.blade)
                                                              : AnyShapeStyle(Color.white.opacity(0.22)))
                .cornerRadius(2)
        }
        .chartYAxis(.hidden)
        .chartXAxis {
            if labels {
                AxisMarks { _ in
                    AxisValueLabel().font(.system(size: 9, weight: .medium)).foregroundStyle(Color.white.opacity(0.45))
                }
            }
        }
        .chartXAxis(labels ? .visible : .hidden)
    }

    private func label(_ key: String, index: Int) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        guard let date = f.date(from: key) else { return "\(index)" }
        // Narrow weekdays repeat (T, T, S, S); keep them unique for the chart's x domain.
        return date.formatted(.dateTime.weekday(.narrow)) + String(repeating: "\u{200B}", count: index)
    }
}

private struct TrackerRows: View {
    let trackers: [Insights.Tracker]
    let limit: Int

    var body: some View {
        let shown = Array(trackers.prefix(limit))
        let top = max(1, shown.first?.hits ?? 1)
        VStack(alignment: .leading, spacing: 7) {
            ForEach(shown) { tracker in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(tracker.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(tracker.hits.formatted()).font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    GeometryReader { geo in
                        Capsule().fill(.white.opacity(0.08))
                            .overlay(alignment: .leading) {
                                Capsule().fill(Palette.blade)
                                    .frame(width: max(4, geo.size.width * CGFloat(tracker.hits) / CGFloat(top)))
                            }
                    }
                    .frame(height: 3)
                }
            }
            if shown.isEmpty {
                Text("Nothing blocked yet today").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
            }
        }
    }
}

// MARK: - Families

struct SpamuraiWidgetView: View {
    @Environment(\.widgetFamily) private var environmentFamily
    let entry: StatsEntry
    /// Lets the app's debug gallery render a specific family outside WidgetKit.
    var family: WidgetFamily? = nil

    private var share: String { entry.today.blockedShare.formatted(.percent.precision(.fractionLength(0))) }

    var body: some View {
        switch family ?? environmentFamily {
        case .systemSmall: small
        case .systemMedium: medium
        case .systemLarge: large
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        case .accessoryInline: Label("\(entry.today.blocked.formatted()) blocked today", systemImage: "shield.lefthalf.filled")
        default: small
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            Header(active: entry.active)
            Spacer(minLength: 6)
            BigNumber(value: entry.today.blocked, active: entry.active)
            WCaps(text: "Blocked today")
            Spacer(minLength: 8)
            WeekBars(week: entry.week).frame(height: 24)
            Text("\(share) of \(entry.today.total.formatted()) lookups")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.5))
                .padding(.top, 5)
        }
    }

    private var medium: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 0) {
                Header(active: entry.active)
                Spacer(minLength: 4)
                BigNumber(value: entry.today.blocked, active: entry.active, size: 40)
                WCaps(text: "Blocked today")
                Spacer(minLength: 6)
                HStack(spacing: 14) {
                    Metric(value: share, label: "Share")
                    Metric(value: entry.allTime.formatted(.number.notation(.compactName)), label: "All time")
                }
            }
            Rectangle().fill(.white.opacity(0.08)).frame(width: 0.5)
            VStack(alignment: .leading, spacing: 8) {
                WCaps(text: "Top trackers today")
                TrackerRows(trackers: entry.trackers, limit: 3)
                Spacer(minLength: 0)
            }
        }
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 12) {
            Header(active: entry.active)
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    BigNumber(value: entry.today.blocked, active: entry.active, size: 46)
                    WCaps(text: "Blocked today")
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 8) {
                    Metric(value: share, label: "Of lookups", alignment: .trailing)
                    Metric(value: entry.allTime.formatted(.number.notation(.compactName)), label: "All time", alignment: .trailing)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                WCaps(text: "This week")
                WeekBars(week: entry.week, labels: true).frame(height: 64)
            }
            Divider().overlay(.white.opacity(0.08))
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    WCaps(text: "Top trackers")
                    TrackerRows(trackers: entry.trackers, limit: 4)
                }
                VStack(alignment: .leading, spacing: 8) {
                    WCaps(text: "Just blocked")
                    if entry.recent.isEmpty {
                        Text("—").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                    }
                    ForEach(entry.recent) { item in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(Insights.company(for: item.domain) ?? Insights.registrable(item.domain))
                                .font(.system(size: 12, weight: .medium))
                            Text(item.domain).font(.system(size: 10).monospaced())
                                .foregroundStyle(.white.opacity(0.45))
                                .lineLimit(1).truncationMode(.middle)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var circular: some View {
        Gauge(value: entry.today.blockedShare) {
            ShieldGlyph(active: true).frame(width: 12, height: 12)
        } currentValueLabel: {
            Text(entry.today.blocked.formatted(.number.notation(.compactName)))
                .font(.system(size: 14, weight: .semibold))
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .widgetAccentable()
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                ShieldGlyph(active: true).frame(width: 11, height: 11).widgetAccentable()
                Text("SPAMURAI").font(.system(size: 10, weight: .semibold)).tracking(1.2)
                Text(entry.active ? "· ON" : "· OFF").font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            Text("\(entry.today.blocked.formatted()) blocked")
                .font(.system(size: 17, weight: .semibold))
                .widgetAccentable()
            Text(entry.trackers.first.map { "Top: \($0.name) · \(share)" } ?? "\(share) of lookups")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct Metric: View {
    let value: String
    let label: String
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        VStack(alignment: alignment, spacing: 1) {
            Text(value).font(.system(size: 15, weight: .regular)).monospacedDigit()
            WCaps(text: label)
        }
    }
}

struct WidgetBackground: View {
    var body: some View {
        ZStack {
            Color.black
            RadialGradient(colors: [Palette.crimson.opacity(0.28), .clear], center: .topLeading,
                           startRadius: 0, endRadius: 260)
        }
    }
}

