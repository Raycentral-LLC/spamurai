import SwiftUI
import WidgetKit

@main
struct SpamuraiWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SpamuraiStats", provider: StatsProvider()) { entry in
            SpamuraiWidgetView(entry: entry)
                .environment(\.colorScheme, .dark)
                .containerBackground(for: .widget) { WidgetBackground() }
                .widgetURL(URL(string: "spamurai://home"))
        }
        .configurationDisplayName("Spamurai")
        .description("What Spamurai blocked today, this week, and who was tracking you.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge,
                            .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

#Preview(as: .systemSmall) { SpamuraiWidget() } timeline: { StatsEntry.placeholder }
#Preview(as: .systemMedium) { SpamuraiWidget() } timeline: { StatsEntry.placeholder }
#Preview(as: .systemLarge) { SpamuraiWidget() } timeline: { StatsEntry.placeholder }
