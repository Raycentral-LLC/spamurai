import Charts
import SwiftUI
import WidgetKit

/// Home: the protection orb, live counters, what's being blocked right now and by whom.
struct ContentView: View {
    @EnvironmentObject private var filters: FilterUpdater
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var tunnel: TunnelManager
    @EnvironmentObject private var live: LiveStats
    @Environment(\.scenePhase) private var scenePhase
    @State private var showPaywall = false
    @State private var showSafariHelp = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    ProtectionOrb(mode: orbMode, blockedToday: live.today.blocked, pulse: live.blockPulse) {
                        toggleProtection()
                    }
                    .contextMenu { pauseMenu }
                    .padding(.top, 4)
                    .appear()

                    if let error = tunnel.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.yellow)
                            .transition(.opacity)
                    }

                    statsRow.appear(0.08)
                    if !store.isPro { proCard.appear(0.14) }
                    if store.isPro { liveCard.appear(0.18) }
                    trackersCard.appear(0.24)
                    weekCard.appear(0.3)
                    safariCard.appear(0.36)
                    filtersCard.appear(0.42)

                    #if DEBUG
                    Card { VStack(alignment: .leading, spacing: 10) { DebugSection() } }
                    #endif
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
            .background(AmbientBackground())
            .navigationTitle("Spamurai")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { menu }
            }
            .sheet(isPresented: $showPaywall) { PaywallView() }
            .sheet(isPresented: $showSafariHelp) { SafariHelpView().presentationDetents([.medium, .large]) }
            .task {
                #if DEBUG
                if CommandLine.arguments.contains("-paywall") { showPaywall = true }
                #endif
                await filters.refreshStates()
                await tunnel.load()
                await store.load()
                await filters.updateIfStale()
            }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active:
                    live.start()
                    Task { await filters.refreshStates() }
                case .background:
                    live.stop()
                    WidgetCenter.shared.reloadAllTimelines()
                default: break
                }
            }
            .onChange(of: store.isPro) { _, pro in
                if !pro, tunnel.isOn { Task { await tunnel.setEnabled(false) } }
            }
            .animation(.snappy, value: store.isPro)
            .animation(.snappy, value: tunnel.errorMessage)
        }
    }

    // MARK: - Orb

    private var orbMode: ProtectionOrb.Mode {
        guard store.isPro else { return .safariOnly }
        if let until = tunnel.pausedUntil, tunnel.isOn { return .paused(until: until) }
        switch tunnel.status {
        case .connected: return .on
        case .connecting, .reasserting: return .connecting
        default: return .off
        }
    }

    private func toggleProtection() {
        guard store.isPro else {
            showPaywall = true
            return
        }
        Task {
            if tunnel.pausedUntil != nil, tunnel.isOn {
                await tunnel.resume()
            } else {
                await tunnel.setEnabled(!tunnel.isOn)
            }
        }
    }

    @ViewBuilder private var pauseMenu: some View {
        if store.isPro, tunnel.isOn {
            if tunnel.pausedUntil != nil {
                Button("Resume blocking", systemImage: "play.fill") { Task { await tunnel.resume() } }
            } else {
                Button("Pause for 5 minutes", systemImage: "pause") { Task { await tunnel.pause(for: 300) } }
                Button("Pause for 1 hour", systemImage: "clock") { Task { await tunnel.pause(for: 3600) } }
            }
        }
    }

    // MARK: - Sections

    private var statsRow: some View {
        HStack(spacing: 10) {
            StatTile(value: live.today.blocked, label: "Blocked today", style: AnyShapeStyle(Theme.blade))
            StatTile(value: Int((live.today.blockedShare * 100).rounded()), suffix: "%",
                     label: "Of lookups", style: AnyShapeStyle(Color.orange))
            StatTile(value: live.allTime, label: "All time", style: AnyShapeStyle(Color.primary))
        }
    }

    private var proCard: some View {
        Button { showPaywall = true } label: {
            HStack(spacing: 14) {
                Image(systemName: "bolt.shield.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.white)
                    .symbolEffect(.pulse)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Block ads in every app").font(.headline).foregroundStyle(.white)
                    Text("Games, social, news — not just Safari. Try 1 week free.")
                        .font(.subheadline).foregroundStyle(.white.opacity(0.85))
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.white.opacity(0.8))
            }
            .padding(18)
            .background(Theme.blade, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: Theme.crimson.opacity(0.4), radius: 20, y: 10)
        }
        .buttonStyle(PressableStyle())
    }

    private var liveCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Live") {
                    NavigationLink { JournalView() } label: {
                        Text("See all").font(.subheadline.weight(.semibold))
                    }
                }
                if !tunnel.isOn {
                    Text("Turn protection on to watch apps' connections in real time.")
                        .font(.subheadline).foregroundStyle(.secondary)
                } else if live.entries.isEmpty {
                    Text("Waiting for the first lookup…").font(.subheadline).foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 10) {
                        ForEach(live.entries.prefix(6)) { entry in
                            JournalRow(entry: entry, compact: true)
                                .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity),
                                                        removal: .opacity))
                        }
                    }
                }
            }
        }
    }

    private var trackersCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader("Who's tracking you")
                let trackers = live.topTrackers
                if trackers.isEmpty {
                    Text(store.isPro ? "Nothing blocked yet today." : "With Pro, see which companies try to follow you across apps.")
                        .font(.subheadline).foregroundStyle(.secondary)
                } else {
                    let top = trackers.first?.hits ?? 1
                    ForEach(trackers) { tracker in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                DomainBadge(domain: tracker.name).scaleEffect(0.8).frame(width: 26, height: 26)
                                Text(tracker.name).font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(tracker.hits.formatted())
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .contentTransition(.numericText(value: Double(tracker.hits)))
                            }
                            GeometryReader { geo in
                                Capsule().fill(.white.opacity(0.06))
                                    .overlay(alignment: .leading) {
                                        Capsule().fill(Theme.blade)
                                            .frame(width: max(8, geo.size.width * CGFloat(tracker.hits) / CGFloat(top)))
                                    }
                            }
                            .frame(height: 6)
                        }
                    }
                }
            }
        }
    }

    private var weekCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader("This week")
                Chart(Array(live.week.enumerated()), id: \.offset) { item in
                    BarMark(x: .value("Day", weekday(item.element.day)), y: .value("Blocked", item.element.blocked))
                        .foregroundStyle(Theme.blade)
                        .cornerRadius(5)
                        .opacity(item.offset == live.week.count - 1 ? 1 : 0.55)
                }
                .chartYAxis { AxisMarks(position: .leading) { _ in AxisValueLabel() } }
                .frame(height: 150)
                .overlay {
                    if live.week.isEmpty {
                        Text("Your week fills in as Spamurai works.").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var safariCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Safari") {
                    Button("How to enable") { showSafariHelp = true }.font(.subheadline.weight(.semibold))
                }
                ForEach(BlockerList.allCases) { list in
                    let on = filters.enabled[list] == true
                    HStack {
                        Image(systemName: list == .ads ? "rectangle.slash" : "eye.slash")
                            .frame(width: 26)
                            .foregroundStyle(on ? Theme.jade : .secondary)
                        Text(list.title)
                        Spacer()
                        Text(on ? "On" : "Off")
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background((on ? Theme.jade : Color.gray).opacity(0.2), in: Capsule())
                            .foregroundStyle(on ? Theme.jade : .secondary)
                            .contentTransition(.interpolate)
                    }
                    .animation(.snappy, value: on)
                }
            }
        }
    }

    private var filtersCard: some View {
        Card {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Filter lists").font(.headline)
                    Text(filters.lastUpdate.map { "Updated \($0.formatted(.relative(presentation: .named)))" } ?? "Built-in lists")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if let error = filters.errorMessage {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }
                }
                Spacer()
                Button {
                    Task { await filters.update() }
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.title3.weight(.semibold))
                        .rotationEffect(.degrees(filters.isUpdating ? 360 : 0))
                        .animation(filters.isUpdating ? .linear(duration: 0.9).repeatForever(autoreverses: false) : .snappy,
                                   value: filters.isUpdating)
                        .padding(10)
                        .background(.white.opacity(0.08), in: Circle())
                }
                .disabled(filters.isUpdating)
            }
        }
    }

    private var menu: some View {
        Menu {
            if store.isPro { NavigationLink { RulesView() } label: { Label("My rules", systemImage: "list.bullet") } }
            Button("Restore purchases", systemImage: "arrow.clockwise") { Task { await store.restore() } }
            Button("How to enable Safari", systemImage: "safari") { showSafariHelp = true }
        } label: {
            Image(systemName: "ellipsis.circle").font(.title3)
        }
    }

    private func weekday(_ key: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        guard let date = f.date(from: key) else { return key }
        return date.formatted(.dateTime.weekday(.narrow))
    }
}

private struct StatTile: View {
    let value: Int
    var suffix = ""
    let label: String
    let style: AnyShapeStyle

    var body: some View {
        VStack(spacing: 4) {
            Text("\(value.formatted())\(suffix)")
                .font(.system(.title2, design: .rounded).weight(.bold))
                .foregroundStyle(style)
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(value)))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// Step-by-step for turning on the Safari extensions (Apple offers no deep link to that screen).
struct SafariHelpView: View {
    @Environment(\.dismiss) private var dismiss
    private let steps: [(String, String)] = [
        ("gear", "Open the Settings app"),
        ("square.grid.2x2", "Tap Apps, then Safari"),
        ("puzzlepiece.extension", "Tap Extensions"),
        ("checkmark.circle", "Turn on Spamurai Ads and Spamurai Privacy"),
    ]

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 22) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(spacing: 16) {
                        Text("\(index + 1)")
                            .font(.headline.monospacedDigit())
                            .frame(width: 34, height: 34)
                            .background(Theme.blade, in: Circle())
                            .foregroundStyle(.white)
                        Image(systemName: step.0).font(.title3).frame(width: 28)
                        Text(step.1).font(.body)
                    }
                    .appear(Double(index) * 0.08)
                }
                Spacer()
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            .padding(24)
            .navigationTitle("Enable in Safari")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
    }
}
