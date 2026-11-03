import AppIntents
import SwiftUI
import WidgetKit

@main
struct SpamuraiWidgets: WidgetBundle {
    var body: some Widget {
        SpamuraiWidget()
        FocusShieldControl()
        PauseControl()
    }
}

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

/// Control Center / Lock Screen / Action button toggle for Focus Shield.
struct FocusShieldControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.raycentral.spamurai.focus", provider: FocusValue()) { isOn in
            ControlWidgetToggle("Focus Shield", isOn: isOn, action: SetFocusShieldIntent()) { on in
                Label(on ? "Blocking distractions" : "Off", systemImage: on ? "moon.circle.fill" : "moon.circle")
            }
            .tint(.red)
        }
        .displayName("Focus Shield")
        .description("Block social, video and other distracting apps.")
    }

    struct FocusValue: ControlValueProvider {
        var previewValue: Bool { false }
        func currentValue() async throws -> Bool { FocusShield.current.manualOn }
    }
}

/// One tap when a site breaks: let everything through for 5 minutes.
struct PauseControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.raycentral.spamurai.pause") {
            ControlWidgetButton(action: PauseBlockingIntent(minutes: 5)) {
                Label("Pause 5 min", systemImage: "pause.circle")
            }
        }
        .displayName("Pause Ad Blocking")
        .description("Let everything through for 5 minutes, then resume automatically.")
    }
}

#Preview(as: .systemSmall) { SpamuraiWidget() } timeline: { StatsEntry.placeholder }
#Preview(as: .systemMedium) { SpamuraiWidget() } timeline: { StatsEntry.placeholder }
#Preview(as: .systemLarge) { SpamuraiWidget() } timeline: { StatsEntry.placeholder }
