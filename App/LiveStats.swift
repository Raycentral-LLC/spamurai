import SwiftUI

/// Polls what the tunnel writes to the App Group (every 1.5 s while the app is active) and
/// publishes it with animation, so counters tick and new lookups slide in.
@MainActor
final class LiveStats: ObservableObject {
    @Published private(set) var today = StatsStore.today
    @Published private(set) var week = StatsStore.history
    @Published private(set) var allTime = StatsStore.blockedAllTime
    @Published private(set) var entries: [JournalEntry] = StatsStore.readJournal()
    /// Bumps whenever something new got blocked — drives the orb's pulse.
    @Published private(set) var blockPulse = 0

    private var task: Task<Void, Never>?

    var topTrackers: [Insights.Tracker] { Insights.topTrackers(entries) }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                self?.refresh()
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    func refresh() {
        let newToday = StatsStore.today
        let newEntries = StatsStore.readJournal()
        let newlyBlocked = newToday.blocked - today.blocked
        withAnimation(.snappy(duration: 0.45)) {
            if newToday != today { today = newToday }
            if newEntries != entries { entries = newEntries }
            week = StatsStore.history
            allTime = StatsStore.blockedAllTime
            if newlyBlocked > 0 { blockPulse += 1 }
        }
    }
}
