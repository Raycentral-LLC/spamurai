import Foundation

/// Code shared between the app and all extensions. Keep it free of UIKit/SafariServices.
enum AppConfig {
    static let appGroup = "group.com.raycentral.spamurai"
    static let bundlePrefix = "com.raycentral.spamurai"
    // TODO: point to your own domain once GitHub Pages (or R2) is set up.
    static let filtersBaseURL = URL(string: "https://rahattt.github.io/spamurai")!
}

enum BlockerList: String, CaseIterable, Identifiable, Hashable {
    case ads, privacy

    var id: String { rawValue }
    var title: String {
        switch self {
        case .ads: "Ads"
        case .privacy: "Trackers"
        }
    }
    var extensionID: String { "\(AppConfig.bundlePrefix).ContentBlocker\(rawValue.capitalized)" }
    var remoteURL: URL { AppConfig.filtersBaseURL.appendingPathComponent("safari/\(rawValue).json") }
}

enum SharedStore {
    static var defaults: UserDefaults? { UserDefaults(suiteName: AppConfig.appGroup) }

    /// Location of a downloaded rule list inside the App Group container.
    static func listURL(_ list: BlockerList) -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppConfig.appGroup)?
            .appendingPathComponent("lists/\(list.rawValue).json")
    }

    /// Downloaded list if present, otherwise nil (extension falls back to its bundled copy).
    static func downloadedListURL(_ list: BlockerList) -> URL? {
        guard let url = listURL(list), FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    static let dnsRemoteURL = AppConfig.filtersBaseURL.appendingPathComponent("dns/default.srs")

    /// Binary sing-box rule-set (.srs) used by the Pro DNS tunnel. Binary, not JSON: parsing a
    /// 190k-domain JSON list exceeds the ~50 MB Network Extension memory limit.
    static func dnsListURL() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppConfig.appGroup)?
            .appendingPathComponent("lists/dns.srs")
    }

    static func downloadedDNSListURL() -> URL? {
        guard let url = dnsListURL(), FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    static var lastUpdate: Date? {
        get { defaults?.object(forKey: "lastUpdate") as? Date }
        set { defaults?.set(newValue, forKey: "lastUpdate") }
    }

    static var isPro: Bool {
        get { defaults?.bool(forKey: "isPro") ?? false }
        set { defaults?.set(newValue, forKey: "isPro") }
    }

    #if DEBUG
    /// Debug builds only: unlock Pro without a purchase, for on-device testing.
    static var debugPro: Bool {
        get { defaults?.bool(forKey: "debugPro") ?? false }
        set { defaults?.set(newValue, forKey: "debugPro") }
    }

    /// Debug log shared by the app and extensions (Library/Caches/diag.log in the App Group).
    static func diag(_ line: String) {
        guard let url = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppConfig.appGroup)?
            .appendingPathComponent("Library/Caches/diag.log") else { return }
        let entry = "\(Date().formatted(.iso8601)) [\(Bundle.main.bundleURL.lastPathComponent)] \(line)\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(entry.utf8))
            try? handle.close()
        } else {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? Data(entry.utf8).write(to: url)
        }
    }
    #endif
}
