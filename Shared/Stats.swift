import Foundation

/// One DNS lookup as shown in the journal. Repeat lookups of a domain within a few seconds
/// (A + AAAA + HTTPS for one connection) are folded into one entry.
struct JournalEntry: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var domain: String
    var blocked: Bool
    var date: Date
    var count: Int = 1
    /// Kept away by Focus Shield rather than the ad/tracker lists.
    var focus: Bool?
}

struct DayStats: Codable, Equatable {
    var day: String // yyyy-MM-dd, device-local
    var blocked = 0
    var total = 0
    /// Distractions held off by Focus Shield (optional: older stored days lack it).
    var focus: Int?

    var blockedShare: Double { total == 0 ? 0 : Double(blocked) / Double(total) }

    static func dayKey(_ date: Date = Date()) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

/// Stats and journal shared through the App Group: the tunnel writes, the app and widget read.
enum StatsStore {
    static let journalLimit = 500
    private static let todayKey = "stats.today"
    private static let allTimeKey = "stats.blockedAllTime"
    private static let historyKey = "stats.history" // last 7 days, oldest first

    private static var container: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppConfig.appGroup)
    }

    static var journalURL: URL? { container?.appendingPathComponent("Library/Caches/journal.json") }

    static var today: DayStats {
        get {
            guard let data = SharedStore.defaults?.data(forKey: todayKey),
                  let stats = try? JSONDecoder().decode(DayStats.self, from: data),
                  stats.day == DayStats.dayKey() else { return DayStats(day: DayStats.dayKey()) }
            return stats
        }
        set { SharedStore.defaults?.set(try? JSONEncoder().encode(newValue), forKey: todayKey) }
    }

    static var blockedAllTime: Int {
        get { SharedStore.defaults?.integer(forKey: allTimeKey) ?? 0 }
        set { SharedStore.defaults?.set(newValue, forKey: allTimeKey) }
    }

    /// Up to 7 finished-or-current days, oldest first (for the widget chart).
    static var history: [DayStats] {
        get {
            guard let data = SharedStore.defaults?.data(forKey: historyKey),
                  let days = try? JSONDecoder().decode([DayStats].self, from: data) else { return [] }
            return days
        }
        set { SharedStore.defaults?.set(try? JSONEncoder().encode(Array(newValue.suffix(7))), forKey: historyKey) }
    }

    /// Adds counts to today, rolling the day over when the date changed.
    static func record(blocked: Int, total: Int, focus: Int = 0) {
        var stats = today
        stats.blocked += blocked
        stats.total += total
        stats.focus = (stats.focus ?? 0) + focus
        today = stats
        blockedAllTime += blocked
        var days = history.filter { $0.day != stats.day }
        days.append(stats)
        history = days
    }

    static func readJournal() -> [JournalEntry] {
        guard let url = journalURL, let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return (try? decoder.decode([JournalEntry].self, from: data)) ?? []
    }

    static func writeJournal(_ entries: [JournalEntry]) {
        guard let url = journalURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(Array(entries.prefix(journalLimit))) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}

/// User's own allow/block lists (Pro). Matching is by domain suffix, like the built-in list.
enum CustomRules {
    private static let allowKey = "rules.allow"
    private static let blockKey = "rules.block"

    static var allow: [String] {
        get { SharedStore.defaults?.stringArray(forKey: allowKey) ?? [] }
        set { SharedStore.defaults?.set(normalized(newValue), forKey: allowKey) }
    }

    static var block: [String] {
        get { SharedStore.defaults?.stringArray(forKey: blockKey) ?? [] }
        set { SharedStore.defaults?.set(normalized(newValue), forKey: blockKey) }
    }

    /// Lowercased, trimmed, deduplicated, sorted; drops anything that isn't a plain domain.
    static func normalized(_ domains: [String]) -> [String] {
        let cleaned = domains.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .map { $0.hasPrefix("*.") ? String($0.dropFirst(2)) : $0 }
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".")) }
            .filter { $0.contains(".") && $0.allSatisfy { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" } }
        return Array(Set(cleaned)).sorted()
    }
}
