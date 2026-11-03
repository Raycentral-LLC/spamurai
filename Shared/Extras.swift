import Foundation

/// Spamurai's own additions to the system-wide list: telemetry and ad-measurement endpoints that
/// the AdGuard DNS filter leaves alone but that apps don't need to work. Keep it conservative —
/// anything here applies to every user.
enum ExtraBlocklist {
    static let domains: [String] = [
        // TikTok / ByteDance telemetry and conversion tracking (not the TikTok app's content).
        "log.byteoversea.com", "mon.byteoversea.com", "mon-va.byteoversea.com",
        "log-va.tiktokv.com", "mon.tiktokv.com", "mon-va.tiktokv.com",
        "analytics.tiktok.com", "analytics-sg.tiktok.com", "business-api.tiktok.com",
        // Ad measurement / attribution SDKs.
        // (Adjust and Branch are left out: their domains also serve ordinary links people tap.)
        "app-measurement.com", "appsflyersdk.com", "kochava.com", "singular.net",
    ]
}
