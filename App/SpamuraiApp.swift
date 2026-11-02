import SwiftUI

@main
struct SpamuraiApp: App {
    @StateObject private var filters = FilterUpdater()
    @StateObject private var store = Store()
    @StateObject private var tunnel = TunnelManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(filters)
                .environmentObject(store)
                .environmentObject(tunnel)
        }
    }
}
