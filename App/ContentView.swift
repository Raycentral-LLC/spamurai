import Charts
import SwiftUI
import WidgetKit

/// Home: a full-screen hero (glass shards that assemble into the shield when protected),
/// then live activity, trackers and settings below the fold.
struct ContentView: View {
    @EnvironmentObject private var filters: FilterUpdater
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var tunnel: TunnelManager
    @EnvironmentObject private var live: LiveStats
    @Environment(\.scenePhase) private var scenePhase
    @State private var showPaywall = false
    @State private var showSafariHelp = false
    @State private var showRescue = false
    @State private var taps = 0
    @State private var scroll = ScrollPosition(edge: .top)
    /// The one-time "there's more below" nudge.
    @AppStorage("scrollHintShown") private var scrollHintShown = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    // Slightly shorter than the screen so the stats peek in from the bottom.
                    hero.containerRelativeFrame(.vertical) { height, _ in height * 0.84 }

                    statsRow.appear(0.08).id("stats")
                    if !store.isPro { proCard.appear(0.14) }
                    FocusShieldCard { showPaywall = true }.appear(0.16)
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
                .scrollTargetLayout()
            }
            .scrollPosition($scroll)
            .scrollIndicators(.hidden)
            .background(AmbientBackground())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSafariHelp = true } label: { Image(systemName: "questionmark.circle") }
                }
                ToolbarItem(placement: .principal) { Caps("Spamurai", color: .white.opacity(0.85)) }
                ToolbarItem(placement: .topBarTrailing) { menu }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .tint(.white)
            .sheet(isPresented: $showPaywall) { PaywallView() }
            .sheet(isPresented: $showSafariHelp) { SafariHelpView().presentationDetents([.medium, .large]) }
            .sheet(isPresented: $showRescue) { RescueView().presentationDetents([.medium, .large]) }
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

    // MARK: - Hero

    private enum Status { case safariOnly, off, connecting, on, paused(Date) }

    private var status: Status {
        #if DEBUG
        // Screenshots in the simulator, where the tunnel can't run.
        if CommandLine.arguments.contains("-demoOn") { return .on }
        #endif
        guard store.isPro else { return .safariOnly }
        if let until = tunnel.pausedUntil, tunnel.isOn { return .paused(until) }
        switch tunnel.status {
        case .connected: return .on
        case .connecting, .reasserting: return .connecting
        default: return .off
        }
    }

    private var shardPhase: ShardField.Phase {
        switch status {
        case .on: .assembled
        case .connecting: .gathering
        case .paused: .paused
        case .off, .safariOnly: .scattered
        }
    }

    private var isOn: Bool { if case .on = status { true } else { false } }

    private var hero: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                ModeChip(title: "Safari", on: filters.enabled.values.contains(true))
                ModeChip(title: "All apps", on: isOn)
            }
            .padding(.top, 8)
            .appear()

            ShardField(phase: shardPhase, pulse: live.blockPulse)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { toggleProtection() }
                .contextMenu { pauseMenu }
                .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.5), trigger: live.blockPulse)

            VStack(spacing: 10) {
                Caps(statusCaption, color: isOn ? Theme.crimson : .secondary)
                    .contentTransition(.opacity)
                statusTitle
                    .font(.system(size: 30, weight: .light))
                    .monospacedDigit()
                if let error = tunnel.errorMessage {
                    Text(error).font(.caption).foregroundStyle(.yellow).multilineTextAlignment(.center)
                }
            }
            .animation(.easeInOut(duration: 0.4), value: statusCaption)
            .padding(.bottom, 22)

            Button(buttonTitle) {
                taps += 1
                toggleProtection()
            }
            .buttonStyle(OutlineButtonStyle(active: isOn))
            .sensoryFeedback(.impact(weight: .medium), trigger: taps)
            .padding(.bottom, isOn ? 6 : 18)

            if isOn {
                Button("Something broken?") { showRescue = true }
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.bottom, 8)
                    .transition(.opacity)
            }

            Button {
                withAnimation(.smooth(duration: 0.7)) { scroll.scrollTo(id: "stats", anchor: .top) }
            } label: {
                VStack(spacing: 6) {
                    Caps("Stats & activity", color: .white.opacity(0.75))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.75))
                        .symbolEffect(.bounce.down, options: .repeat(.periodic(delay: 1.4)))
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .task { await nudgeOnce() }
        }
    }

    /// First visit only: lift the page a little and let it fall back, showing it scrolls.
    private func nudgeOnce() async {
        guard !scrollHintShown else { return }
        try? await Task.sleep(nanoseconds: 1_600_000_000)
        withAnimation(.spring(response: 0.55, dampingFraction: 0.75)) { scroll.scrollTo(y: 170) }
        try? await Task.sleep(nanoseconds: 900_000_000)
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) { scroll.scrollTo(edge: .top) }
        scrollHintShown = true
    }

    private var statusCaption: String {
        switch status {
        case .on: "Protected · every app"
        case .connecting: "Arming"
        case .paused: "Paused"
        case .off: "Protection off"
        case .safariOnly: "Safari only"
        }
    }

    @ViewBuilder private var statusTitle: some View {
        switch status {
        case .on:
            HStack(spacing: 8) {
                Text(live.today.blocked.formatted())
                    .contentTransition(.numericText(value: Double(live.today.blocked)))
                Text("blocked").foregroundStyle(.secondary)
            }
        case .paused(let until):
            Text("Resumes \(until, style: .relative)").font(.system(size: 22, weight: .light))
        case .connecting:
            Text("Gathering the blade")
        case .off:
            Text("Tap to arm")
        case .safariOnly:
            Text("Unlock every app")
        }
    }

    private var buttonTitle: String {
        switch status {
        case .on: "Protected"
        case .connecting: "Connecting"
        case .paused: "Resume"
        case .off: "Protect"
        case .safariOnly: "Go Pro"
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
            StatTile(value: live.today.blocked, label: "Today", style: AnyShapeStyle(Theme.crimson))
            StatTile(value: Int((live.today.blockedShare * 100).rounded()), suffix: "%",
                     label: "Share", style: AnyShapeStyle(Color.white))
            StatTile(value: live.allTime, label: "All time", style: AnyShapeStyle(Color.white))
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
            .background(
                LinearGradient(colors: [Theme.crimson.opacity(0.35), Theme.crimson.opacity(0.08)],
                               startPoint: .leading, endPoint: .trailing),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.crimson.opacity(0.6), lineWidth: 0.75))
            .shadow(color: Theme.crimson.opacity(0.35), radius: 18)
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
                HStack {
                    Image(systemName: "play.rectangle")
                        .frame(width: 26)
                        .foregroundStyle(store.isPro ? Theme.crimson : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("YouTube ads")
                        Text(store.isPro ? "\(YouTubeStats.today) skipped today" : "Skip them in Safari with Pro")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(store.isPro ? "Set up" : "Pro") {
                        if store.isPro { showSafariHelp = true } else { showPaywall = true }
                    }
                    .font(.caption.weight(.bold))
                    .buttonStyle(.bordered)
                    .tint(Theme.crimson)
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
            NavigationLink { AboutView() } label: { Label("About & licenses", systemImage: "info.circle") }
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
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(style)
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(value)))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Caps(label)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.08), lineWidth: 0.75))
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
        ("play.rectangle", "Pro: turn on Spamurai YouTube, then set youtube.com to Allow"),
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

/// Small status capsule at the top of the hero.
private struct ModeChip: View {
    let title: String
    let on: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(on ? Theme.jade : Color.white.opacity(0.25))
                .frame(width: 6, height: 6)
                .shadow(color: on ? Theme.jade : .clear, radius: 4)
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.6)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().strokeBorder(.white.opacity(on ? 0.3 : 0.12), lineWidth: 0.75))
        .foregroundStyle(on ? .white : .secondary)
        .animation(.easeInOut, value: on)
    }
}
