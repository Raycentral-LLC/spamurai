import SwiftUI

@main
struct SpamuraiApp: App {
    @StateObject private var filters = FilterUpdater()
    @StateObject private var store = Store()
    @StateObject private var tunnel = TunnelManager()
    @StateObject private var live = LiveStats()
    @AppStorage("onboarded") private var onboarded = false

    var body: some Scene {
        WindowGroup {
            ZStack {
                if onboarded {
                    ContentView().transition(.opacity)
                } else {
                    OnboardingView(done: $onboarded).transition(.opacity)
                }
            }
            .environmentObject(filters)
            .environmentObject(store)
            .environmentObject(tunnel)
            .environmentObject(live)
            .tint(Theme.crimson)
            // The samurai look is built for dark; a forced scheme keeps glass and glows consistent.
            .preferredColorScheme(.dark)
            .onAppear { live.start() }
        }
    }
}
