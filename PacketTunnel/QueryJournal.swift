import Foundation
import Libbox

/// Builds the journal and daily counters from sing-box's DNS debug log, received in-process
/// over the command server. Relevant lines (connection id in brackets):
///   [123 0ms] dns: exchange doubleclick.net. IN A
///   [123 0ms] dns: match[0] rule_set=block => predefined(NXDOMAIN)
final class QueryJournal: NSObject, LibboxCommandClientHandlerProtocol, @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.raycentral.spamurai.journal")
    private var client: LibboxCommandClient?
    private var stopped = false

    // queue-confined state
    private var entries: [JournalEntry] = []
    private var pending: [String: Int] = [:] // connection id → index in `entries`
    private var newBlocked = 0
    private var newTotal = 0
    private var newFocus = 0
    private var dirty = false
    private var flushTimer: DispatchSourceTimer?

    /// Fold repeat lookups of one domain within this window into one entry.
    private static let foldWindow: TimeInterval = 5
    private static let flushInterval: TimeInterval = 2

    func start() {
        queue.async { [weak self] in
            guard let self else { return }
            self.stopped = false
            self.entries = StatsStore.readJournal()
            self.connect()
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now() + Self.flushInterval, repeating: Self.flushInterval)
            timer.setEventHandler { [weak self] in self?.flush() }
            timer.resume()
            self.flushTimer = timer
        }
    }

    func stop() {
        queue.sync {
            stopped = true
            flushTimer?.cancel()
            flushTimer = nil
            try? client?.disconnect()
            client = nil
            flush()
        }
    }

    private func connect() {
        guard !stopped else { return }
        let options = LibboxCommandClientOptions()
        options.addCommand(LibboxCommandLog)
        guard let client = LibboxNewCommandClient(self, options) else { return retry() }
        do {
            try client.connect()
            self.client = client
        } catch {
            retry()
        }
    }

    private func retry() {
        queue.asyncAfter(deadline: .now() + 2) { [weak self] in self?.connect() }
    }

    private func flush() {
        guard dirty else { return }
        dirty = false
        StatsStore.record(blocked: newBlocked, total: newTotal, focus: newFocus)
        newBlocked = 0
        newTotal = 0
        newFocus = 0
        StatsStore.writeJournal(entries)
    }

    // MARK: - Parsing (on `queue`)

    private static let ansi = try! NSRegularExpression(pattern: "\u{1B}\\[[0-9;]*m")
    private static let exchange = try! NSRegularExpression(pattern: #"\[(\d+) [^\]]*\] dns: exchange (\S+?)\.? IN (\S+)"#)
    private static let blockedMatch = try! NSRegularExpression(pattern: #"\[(\d+) [^\]]*\] dns: match\[\d+\].*=> predefined"#)

    private func handle(_ raw: String) {
        let ns = raw as NSString
        let line = Self.ansi.stringByReplacingMatches(in: raw, range: NSRange(location: 0, length: ns.length), withTemplate: "")
        let range = NSRange(location: 0, length: (line as NSString).length)

        if let m = Self.exchange.firstMatch(in: line, range: range) {
            let id = (line as NSString).substring(with: m.range(at: 1))
            let domain = (line as NSString).substring(with: m.range(at: 2)).lowercased()
            let now = Date()
            if let i = entries.firstIndex(where: { $0.domain == domain }),
               now.timeIntervalSince(entries[i].date) < Self.foldWindow {
                entries[i].count += 1
                entries[i].date = now
                pending[id] = i
                // Folded lookups don't add to the total: one entry, one count.
            } else {
                entries.insert(JournalEntry(domain: domain, blocked: false, date: now), at: 0)
                if entries.count > StatsStore.journalLimit { entries.removeLast() }
                // Indices shift by one on insert.
                pending = pending.mapValues { $0 + 1 }.filter { $0.value < entries.count }
                pending[id] = 0
                newTotal += 1
            }
            if pending.count > 256 { pending.removeAll() }
            dirty = true
            return
        }

        if let m = Self.blockedMatch.firstMatch(in: line, range: range) {
            let id = (line as NSString).substring(with: m.range(at: 1))
            guard let i = pending.removeValue(forKey: id), i < entries.count,
                  !entries[i].blocked, entries[i].focus != true else { return }
            if line.contains("rule_set=focus") {
                // A distraction kept away, not an ad — counted separately.
                entries[i].focus = true
                newFocus += 1
            } else {
                entries[i].blocked = true
                newBlocked += 1
            }
            dirty = true
        }
    }

    // MARK: - LibboxCommandClientHandlerProtocol

    func writeLogs(_ messageList: (any LibboxLogIteratorProtocol)?) {
        guard let messageList else { return }
        var lines: [String] = []
        while messageList.hasNext() {
            if let message = messageList.next()?.message { lines.append(message) }
        }
        queue.async { lines.forEach(self.handle) }
    }

    func disconnected(_ message: String?) {
        queue.async { self.client = nil; self.retry() }
    }

    func connected() {}
    func clearLogs() {}
    func initializeClashMode(_ modeList: (any LibboxStringIteratorProtocol)?, currentMode: String?) {}
    func setDefaultLogLevel(_ level: Int32) {}
    func updateClashMode(_ newMode: String?) {}
    func write(_ events: LibboxConnectionEvents?) {}
    func writeGroups(_ message: (any LibboxOutboundGroupIteratorProtocol)?) {}
    func writeOutbounds(_ message: (any LibboxOutboundGroupItemIteratorProtocol)?) {}
    func writeStatus(_ message: LibboxStatusMessage?) {}
}
