import AppIntents
import WidgetKit

// Intents compiled into both the app and the widget extension, so Control Center controls,
// Shortcuts and Siri can run them without opening the app. They only touch App Group state and
// ping the tunnel (SharedStore.notifyTunnel), which works from any process.

struct SetFocusShieldIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Turn Focus Shield On or Off"
    static let description = IntentDescription("Blocks or unblocks distracting apps and sites (Spamurai Pro).")

    @Parameter(title: "Focus Shield on")
    var value: Bool

    init() {}
    init(on: Bool) { value = on }

    func perform() async throws -> some IntentResult {
        var shield = FocusShield.current
        shield.manualOn = value
        FocusShield.current = shield
        WidgetCenter.shared.reloadAllTimelines()
        ControlCenter.shared.reloadAllControls()
        return .result()
    }
}

struct PauseBlockingIntent: AppIntent {
    static let title: LocalizedStringResource = "Pause Ad Blocking"
    static let description = IntentDescription("Lets everything through for a few minutes, then resumes on its own.")

    @Parameter(title: "Minutes", default: 5, controlStyle: .stepper, inclusiveRange: (1, 120))
    var minutes: Int

    init() {}
    init(minutes: Int) { self.minutes = minutes }

    static var parameterSummary: some ParameterSummary { Summary("Pause ad blocking for \(\.$minutes) minutes") }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        SharedStore.pausedUntil = Date().addingTimeInterval(TimeInterval(minutes * 60))
        SharedStore.notifyTunnel()
        ControlCenter.shared.reloadAllControls()
        return .result(dialog: "Ad blocking paused for \(minutes) minutes.")
    }
}

struct ResumeBlockingIntent: AppIntent {
    static let title: LocalizedStringResource = "Resume Ad Blocking"

    func perform() async throws -> some IntentResult {
        SharedStore.pausedUntil = nil
        SharedStore.notifyTunnel()
        ControlCenter.shared.reloadAllControls()
        return .result()
    }
}
