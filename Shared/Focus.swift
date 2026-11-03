import Foundation

/// Focus Shield (Pro): blocks whole categories of distracting services at the DNS level —
/// on demand, on a schedule, or while an iOS Focus with Spamurai's filter is on.
struct FocusShield: Codable, Equatable {
    enum Category: String, Codable, CaseIterable, Identifiable, Hashable {
        case social, video, news, games, shopping

        var id: String { rawValue }

        var title: String {
            switch self {
            case .social: "Social"
            case .video: "Video"
            case .news: "News"
            case .games: "Games"
            case .shopping: "Shopping"
            }
        }

        var icon: String {
            switch self {
            case .social: "bubble.left.and.bubble.right.fill"
            case .video: "play.rectangle.fill"
            case .news: "newspaper.fill"
            case .games: "gamecontroller.fill"
            case .shopping: "bag.fill"
            }
        }

        /// Domain suffixes the category's apps and sites depend on.
        var domains: [String] {
            switch self {
            case .social:
                ["instagram.com", "cdninstagram.com", "facebook.com", "fbcdn.net", "fbsbx.com", "threads.net",
                 "tiktok.com", "tiktokv.com", "tiktokcdn.com", "tiktokcdn-us.com", "musical.ly",
                 "twitter.com", "x.com", "twimg.com", "t.co", "snapchat.com", "sc-cdn.net", "snapkit.com",
                 "reddit.com", "redd.it", "redditmedia.com", "redditstatic.com", "pinterest.com", "pinimg.com",
                 "linkedin.com", "licdn.com", "vk.com", "vk.ru", "userapi.com", "ok.ru", "tumblr.com", "bsky.app"]
            case .video:
                ["youtube.com", "youtu.be", "ytimg.com", "googlevideo.com", "youtube-nocookie.com", "youtubei.googleapis.com",
                 "netflix.com", "nflxvideo.net", "nflximg.net", "twitch.tv", "ttvnw.net", "jtvnw.net", "kick.com",
                 "primevideo.com", "disneyplus.com", "hulu.com", "max.com", "rutube.ru", "vimeo.com"]
            case .news:
                ["cnn.com", "bbc.com", "bbc.co.uk", "nytimes.com", "foxnews.com", "theguardian.com",
                 "washingtonpost.com", "reuters.com", "apnews.com", "news.google.com", "news.yahoo.com",
                 "nbcnews.com", "ria.ru", "lenta.ru", "rbc.ru", "meduza.io", "kommersant.ru", "news.ycombinator.com"]
            case .games:
                ["roblox.com", "rbxcdn.com", "epicgames.com", "fortnite.com", "supercell.com", "clashroyale.com",
                 "steampowered.com", "steamcommunity.com", "minecraft.net", "playstation.com", "xbox.com", "king.com"]
            case .shopping:
                ["amazon.com", "aliexpress.com", "alicdn.com", "temu.com", "shein.com", "ebay.com", "etsy.com",
                 "wildberries.ru", "ozon.ru", "walmart.com", "wish.com"]
            }
        }
    }

    var categories: Set<Category> = [.social, .video]
    var manualOn = false
    var scheduleOn = false
    /// Calendar weekdays, 1 = Sunday … 7 = Saturday.
    var days: Set<Int> = [2, 3, 4, 5, 6]
    var startMinute = 9 * 60
    var endMinute = 17 * 60
    /// Categories requested by an active iOS Focus filter; nil when no such Focus is on.
    var focusFilter: Set<Category>?

    // MARK: State

    func inSchedule(at date: Date = Date()) -> Bool {
        guard scheduleOn, !days.isEmpty, startMinute != endMinute else { return false }
        let cal = Calendar.current
        let minute = cal.component(.hour, from: date) * 60 + cal.component(.minute, from: date)
        let weekday = cal.component(.weekday, from: date)
        if startMinute < endMinute {
            return days.contains(weekday) && minute >= startMinute && minute < endMinute
        }
        // Overnight window: the part after midnight belongs to the previous day's schedule.
        let yesterday = weekday == 1 ? 7 : weekday - 1
        return (days.contains(weekday) && minute >= startMinute) || (days.contains(yesterday) && minute < endMinute)
    }

    /// Categories blocked right now (empty = shield is down).
    func activeCategories(at date: Date = Date()) -> Set<Category> {
        var active: Set<Category> = []
        if manualOn || inSchedule(at: date) { active.formUnion(categories) }
        if let focusFilter { active.formUnion(focusFilter) }
        return active
    }

    func isActive(at date: Date = Date()) -> Bool { !activeCategories(at: date).isEmpty }

    /// Next schedule boundary after `date`, so the tunnel can re-evaluate exactly then.
    func nextBoundary(after date: Date = Date()) -> Date? {
        guard scheduleOn else { return nil }
        let cal = Calendar.current
        let today = cal.startOfDay(for: date)
        return (0...8).flatMap { day -> [Date] in
            guard let base = cal.date(byAdding: .day, value: day, to: today) else { return [] }
            return [startMinute, endMinute].compactMap { cal.date(byAdding: .minute, value: $0, to: base) }
        }
        .filter { $0 > date }
        .min()
    }

    var activeDomains: [String] {
        activeCategories().flatMap(\.domains).sorted()
    }

    // MARK: Storage

    private static let key = "focusShield"

    static var current: FocusShield {
        get {
            guard let data = SharedStore.defaults?.data(forKey: key),
                  let shield = try? JSONDecoder().decode(FocusShield.self, from: data) else { return FocusShield() }
            return shield
        }
        set {
            SharedStore.defaults?.set(try? JSONEncoder().encode(newValue), forKey: key)
            SharedStore.notifyTunnel()
        }
    }
}

extension SharedStore {
    static let reloadNotification = "com.raycentral.spamurai.reload"

    /// Tells a running tunnel to rebuild its config (rules, pause, Focus Shield). A Darwin
    /// notification, so it works from the app, widgets, controls and Focus filters alike.
    static func notifyTunnel() {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                             CFNotificationName(reloadNotification as CFString), nil, nil, true)
    }
}
