#if DEBUG
import SwiftUI

/// Debug only: realistic sample data and direct screen routing for App Store screenshots
/// (simulator can't run the tunnel). Launch with `-demo` and optionally `-shot <screen>`.
enum DemoMode {
    static var isOn: Bool { CommandLine.arguments.contains("-demo") }

    static var shot: String? {
        guard let i = CommandLine.arguments.firstIndex(of: "-shot"), i + 1 < CommandLine.arguments.count else { return nil }
        return CommandLine.arguments[i + 1]
    }

    static func seed() {
        guard isOn else { return }
        SharedStore.debugPro = true
        SharedStore.isPro = true
        SharedStore.tunnelActive = true
        SharedStore.lastUpdate = Date().addingTimeInterval(-3 * 3600)

        let cal = Calendar.current
        let blocked = [1_812, 2_240, 1_967, 2_610, 2_315, 1_904, 1_284]
        let days = (0..<7).map { i -> DayStats in
            let date = cal.date(byAdding: .day, value: i - 6, to: .now)!
            return DayStats(day: DayStats.dayKey(date), blocked: blocked[i], total: blocked[i] * 4 + 311, focus: i == 6 ? 47 : 30)
        }
        StatsStore.today = days[6]
        StatsStore.history = days
        StatsStore.blockedAllTime = 48_310

        var shield = FocusShield()
        shield.categories = [.social, .video]
        shield.scheduleOn = true
        shield.manualOn = true
        FocusShield.current = shield
        CustomRules.allow = ["paypal.com"]
        CustomRules.block = ["tiktok.com"]

        let sample: [(String, Bool, Int, Bool)] = [
            ("googleads.g.doubleclick.net", true, 3, false),
            ("graph.instagram.com", false, 1, true),
            ("api.weather.com", false, 2, false),
            ("app-measurement.com", true, 4, false),
            ("graph.facebook.com", true, 2, false),
            ("ms.applovin.com", true, 6, false),
            ("www.apple.com", false, 1, false),
            ("ads.unity3d.com", true, 2, false),
            ("mon.byteoversea.com", true, 1, false),
            ("i.ytimg.com", false, 1, true),
            ("pagead2.googlesyndication.com", true, 3, false),
            ("api.spotify.com", false, 2, false),
            ("supersonicads.com", true, 2, false),
            ("t.appsflyer.com", true, 1, false),
            ("cdn.wikipedia.org", false, 1, false),
            ("bat.bing.com", true, 1, false),
            ("criteo.net", true, 2, false),
            ("mail.google.com", false, 1, false),
        ]
        let entries = sample.enumerated().map { i, item in
            JournalEntry(domain: item.0, blocked: item.1, date: Date().addingTimeInterval(-Double(i) * 23),
                         count: item.1 ? item.2 * 53 : item.2, focus: item.3 ? true : nil)
        }
        StatsStore.writeJournal(entries)
        if YouTubeStats.today < 23 { (YouTubeStats.today..<23).forEach { _ in YouTubeStats.recordSkip() } }
        YouTubeStats.lastSeen = Date()
        UserDefaults.standard.set(true, forKey: "scrollHintShown")
        UserDefaults.standard.set(true, forKey: "vpnDisclosureAccepted")
    }
}
#endif
