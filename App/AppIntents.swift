import AppIntents
import NetworkExtension

/// iOS Focus filter: Settings → Focus → (a Focus) → Add Filter → Spamurai.
/// While that Focus is on, the chosen categories are blocked across every app.
struct SpamuraiFocusFilter: SetFocusFilterIntent {
    static let title: LocalizedStringResource = "Spamurai Focus Shield"
    static let description = IntentDescription("Block distracting apps and sites while this Focus is on.")

    @Parameter(title: "Social media", default: true) var social: Bool
    @Parameter(title: "Video", default: true) var video: Bool
    @Parameter(title: "News", default: false) var news: Bool
    @Parameter(title: "Games", default: false) var games: Bool
    @Parameter(title: "Shopping", default: false) var shopping: Bool

    var displayRepresentation: DisplayRepresentation {
        let names = categories.map(\.title).sorted()
        return DisplayRepresentation(title: "Focus Shield",
                                     subtitle: names.isEmpty ? "Nothing blocked" : "Blocks \(names.joined(separator: ", "))")
    }

    private var categories: Set<FocusShield.Category> {
        var set: Set<FocusShield.Category> = []
        if social { set.insert(.social) }
        if video { set.insert(.video) }
        if news { set.insert(.news) }
        if games { set.insert(.games) }
        if shopping { set.insert(.shopping) }
        return set
    }

    /// Called when the Focus turns on and when it turns off; `current` throws once it's off.
    func perform() async throws -> some IntentResult {
        let active = try? await Self.current
        var shield = FocusShield.current
        shield.focusFilter = active?.categories
        FocusShield.current = shield
        if active != nil { await TunnelManager.ensureRunning() }
        return .result()
    }
}

struct SpamuraiShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: SetFocusShieldIntent(on: true),
                    phrases: ["Start Focus Shield in \(.applicationName)", "Block distractions with \(.applicationName)"],
                    shortTitle: "Focus Shield On", systemImageName: "moon.circle.fill")
        AppShortcut(intent: SetFocusShieldIntent(on: false),
                    phrases: ["Stop Focus Shield in \(.applicationName)"],
                    shortTitle: "Focus Shield Off", systemImageName: "moon.circle")
        AppShortcut(intent: PauseBlockingIntent(minutes: 5),
                    phrases: ["Pause \(.applicationName)", "Pause ad blocking in \(.applicationName)"],
                    shortTitle: "Pause 5 Minutes", systemImageName: "pause.circle")
    }
}
