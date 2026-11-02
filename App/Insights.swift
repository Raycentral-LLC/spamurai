import Foundation

/// "Who is tracking you": groups blocked lookups by the company behind the domain.
enum Insights {
    struct Tracker: Identifiable, Hashable {
        let name: String
        let hits: Int
        var id: String { name }
    }

    /// Registrable domain (eTLD+1) for common cases: ads.example.co.uk → example.co.uk.
    static func registrable(_ domain: String) -> String {
        let parts = domain.split(separator: ".").map(String.init)
        guard parts.count > 2 else { return domain }
        let secondLevel = ["co", "com", "net", "org", "gov", "edu", "ac", "or", "ne", "go"]
        if parts[parts.count - 1].count == 2, secondLevel.contains(parts[parts.count - 2]) {
            return parts.suffix(3).joined(separator: ".")
        }
        return parts.suffix(2).joined(separator: ".")
    }

    static func company(for domain: String) -> String? {
        companies[registrable(domain)]
    }

    /// Top companies (or domains, when unknown) among blocked lookups.
    static func topTrackers(_ entries: [JournalEntry], limit: Int = 5) -> [Tracker] {
        var hits: [String: Int] = [:]
        for entry in entries where entry.blocked {
            hits[company(for: entry.domain) ?? registrable(entry.domain), default: 0] += entry.count
        }
        return hits.map { Tracker(name: $0.key, hits: $0.value) }
            .sorted { $0.hits == $1.hits ? $0.name < $1.name : $0.hits > $1.hits }
            .prefix(limit)
            .map { $0 }
    }

    private static let companies: [String: String] = {
        let groups: [String: [String]] = [
            "Google": ["doubleclick.net", "googleadservices.com", "googlesyndication.com", "google-analytics.com",
                       "googletagmanager.com", "googletagservices.com", "app-measurement.com", "crashlytics.com",
                       "admob.com", "2mdn.net", "gstatic.com", "google.com", "googleapis.com", "youtube.com"],
            "Meta": ["facebook.com", "facebook.net", "fbcdn.net", "instagram.com", "whatsapp.net", "fbsbx.com"],
            "Amazon": ["amazon-adsystem.com", "amazon.com", "amazonaws.com", "assoc-amazon.com"],
            "Microsoft": ["bing.com", "clarity.ms", "msn.com", "microsoft.com", "live.com", "linkedin.com"],
            "TikTok": ["tiktokv.com", "tiktok.com", "byteoversea.com", "pangle.io", "pangleglobal.com", "ibytedtos.com"],
            "Apple": ["apple.com", "icloud.com", "apple-dns.net", "aaplimg.com", "mzstatic.com", "cdn-apple.com"],
            "Yandex": ["yandex.ru", "yandex.net", "yandex.com", "yadro.ru", "adfox.ru"],
            "VK": ["vk.com", "mail.ru", "userapi.com", "mycdn.me", "ok.ru", "vk.ru"],
            "Unity Ads": ["unity3d.com", "unityads.unity3d.com"],
            "AppLovin": ["applovin.com", "applvn.com"],
            "ironSource": ["supersonicads.com", "ironsrc.com", "ironsrc.mobi"],
            "Criteo": ["criteo.com", "criteo.net"],
            "Adjust": ["adjust.com", "adjust.net.in"],
            "AppsFlyer": ["appsflyer.com", "appsflyersdk.com"],
            "Branch": ["branch.io", "app.link"],
            "X": ["twitter.com", "ads-twitter.com", "x.com", "twimg.com"],
            "Snap": ["snapchat.com", "sc-static.net", "snapads.com"],
            "Taboola": ["taboola.com"],
            "Outbrain": ["outbrain.com"],
            "Hotjar": ["hotjar.com"],
            "Mixpanel": ["mixpanel.com"],
            "Amplitude": ["amplitude.com"],
            "Segment": ["segment.io", "segment.com"],
            "Sentry": ["sentry.io"],
            "OneSignal": ["onesignal.com"],
        ]
        var map: [String: String] = [:]
        for (company, domains) in groups { for d in domains { map[d] = company } }
        return map
    }()
}
