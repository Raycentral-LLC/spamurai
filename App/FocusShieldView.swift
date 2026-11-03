import SwiftUI

/// Dashboard card: Focus Shield at a glance — state, categories, quick toggle.
struct FocusShieldCard: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var tunnel: TunnelManager
    @EnvironmentObject private var live: LiveStats
    @State private var shield = FocusShield.current
    @State private var toggles = 0
    let showPaywall: () -> Void

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Focus Shield") {
                    if store.isPro {
                        NavigationLink { FocusShieldView() } label: {
                            Image(systemName: "slider.horizontal.3").font(.subheadline.weight(.semibold))
                        }
                    } else {
                        Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary)
                    }
                }

                HStack(alignment: .center, spacing: 14) {
                    ZStack {
                        Circle().fill(active ? Theme.crimson.opacity(0.18) : .white.opacity(0.05)).frame(width: 52)
                        Image(systemName: active ? "moon.circle.fill" : "moon.circle")
                            .font(.system(size: 28))
                            .foregroundStyle(active ? Theme.crimson : .secondary)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(headline).font(.system(size: 17, weight: .medium))
                        Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(get: { shield.manualOn }, set: setManual))
                        .labelsHidden()
                        .tint(Theme.crimson)
                }

                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(FocusShield.Category.allCases) { category in
                            CategoryChip(category: category, selected: shield.categories.contains(category)) {
                                guard store.isPro else { return showPaywall() }
                                withAnimation(.snappy) {
                                    if shield.categories.contains(category) {
                                        shield.categories.remove(category)
                                    } else {
                                        shield.categories.insert(category)
                                    }
                                }
                                FocusShield.current = shield
                            }
                        }
                    }
                }
                .scrollIndicators(.hidden)

                if let focus = live.today.focus, focus > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "hand.raised.fill").foregroundStyle(Theme.crimson)
                        Text("\(focus.formatted()) distractions kept away today")
                            .contentTransition(.numericText(value: Double(focus)))
                    }
                    .font(.caption)
                }
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: toggles)
        .onAppear { shield = FocusShield.current }
    }

    private var active: Bool { store.isPro && shield.isActive() }

    private var headline: String {
        guard store.isPro else { return "Block distractions" }
        if shield.focusFilter != nil { return "On with your Focus" }
        if shield.manualOn { return "Shield up" }
        if shield.inSchedule() { return "On schedule" }
        return "Off"
    }

    private var detail: String {
        guard store.isPro else { return "Social, video, news — blocked in every app when you need to focus." }
        let names = shield.activeCategories().map(\.title).sorted()
        if !names.isEmpty { return "Blocking \(names.joined(separator: ", "))" }
        if shield.scheduleOn { return "Scheduled \(FocusShieldView.scheduleText(shield))" }
        return "Tap to block \(shield.categories.map(\.title).sorted().joined(separator: ", ").lowercased())"
    }

    private func setManual(_ on: Bool) {
        guard store.isPro else { return showPaywall() }
        toggles += 1
        withAnimation(.snappy) { shield.manualOn = on }
        FocusShield.current = shield
        if on, !tunnel.isOn { Task { await tunnel.setEnabled(true) } }
    }
}

private struct CategoryChip: View {
    let category: FocusShield.Category
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: category.icon).font(.caption)
                Text(category.title.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(1.2)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(Capsule().fill(selected ? Theme.crimson.opacity(0.18) : .white.opacity(0.04)))
            .overlay(Capsule().strokeBorder(selected ? Theme.crimson.opacity(0.8) : .white.opacity(0.12), lineWidth: 0.75))
            .foregroundStyle(selected ? .white : .secondary)
        }
        .buttonStyle(PressableStyle())
    }
}

/// Full settings: categories, schedule, and how to tie it to an iOS Focus.
struct FocusShieldView: View {
    @EnvironmentObject private var tunnel: TunnelManager
    @State private var shield = FocusShield.current

    var body: some View {
        List {
            Section {
                ForEach(FocusShield.Category.allCases) { category in
                    Toggle(isOn: binding(for: category)) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(category.title)
                                Text(examples(category)).font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: category.icon).foregroundStyle(Theme.crimson)
                        }
                    }
                    .tint(Theme.crimson)
                }
            } header: {
                Text("What to block")
            } footer: {
                Text("Blocked in every app and browser while the shield is up — apps just won't load new content.")
            }

            Section {
                Toggle("Block on a schedule", isOn: $shield.scheduleOn.animation(.snappy)).tint(Theme.crimson)
                if shield.scheduleOn {
                    DayPicker(days: $shield.days)
                    DatePicker("From", selection: minutes($shield.startMinute), displayedComponents: .hourAndMinute)
                    DatePicker("Until", selection: minutes($shield.endMinute), displayedComponents: .hourAndMinute)
                }
            } header: {
                Text("Schedule")
            } footer: {
                if shield.scheduleOn { Text("Runs \(Self.scheduleText(shield)), even when Spamurai is closed.") }
            }

            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Settings → Focus", systemImage: "gear")
                    Label("Choose a Focus, e.g. Work or Sleep", systemImage: "moon.fill")
                    Label("Focus Filters → Add Filter → Spamurai", systemImage: "plus.circle")
                }
                .font(.subheadline)
                .padding(.vertical, 4)
                if shield.focusFilter != nil {
                    Label("A Focus with Spamurai's filter is on now", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Theme.jade)
                }
            } header: {
                Text("Turn on with iOS Focus")
            } footer: {
                Text("Your shield then rises and falls with the Focus — automatically. Add the Focus Shield control to Control Center for a one-tap switch.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(AmbientBackground())
        .navigationTitle("Focus Shield")
        .onChange(of: shield) { _, new in FocusShield.current = new }
        .onAppear { shield = FocusShield.current }
    }

    private func binding(for category: FocusShield.Category) -> Binding<Bool> {
        Binding(
            get: { shield.categories.contains(category) },
            set: { on in
                if on { shield.categories.insert(category) } else { shield.categories.remove(category) }
            }
        )
    }

    private func examples(_ category: FocusShield.Category) -> String {
        switch category {
        case .social: "Instagram, TikTok, X, Facebook, Reddit, VK"
        case .video: "YouTube, Netflix, Twitch"
        case .news: "CNN, BBC, NYT, RBC, Lenta"
        case .games: "Roblox, Fortnite, Supercell, Steam"
        case .shopping: "Amazon, AliExpress, Temu, Shein, Ozon"
        }
    }

    /// Binds minutes-since-midnight to a Date for DatePicker.
    private func minutes(_ value: Binding<Int>) -> Binding<Date> {
        Binding(
            get: { Calendar.current.startOfDay(for: .now).addingTimeInterval(TimeInterval(value.wrappedValue * 60)) },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                value.wrappedValue = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            }
        )
    }

    static func scheduleText(_ shield: FocusShield) -> String {
        let symbols = Calendar.current.shortWeekdaySymbols
        let order = (0..<7).map { (Calendar.current.firstWeekday - 1 + $0) % 7 + 1 }
        let days = order.filter { shield.days.contains($0) }.map { symbols[$0 - 1] }
        func time(_ m: Int) -> String {
            Calendar.current.startOfDay(for: .now).addingTimeInterval(TimeInterval(m * 60))
                .formatted(date: .omitted, time: .shortened)
        }
        let dayText = shield.days.count == 7 ? "every day" : days.joined(separator: " ")
        return "\(dayText), \(time(shield.startMinute))–\(time(shield.endMinute))"
    }
}

private struct DayPicker: View {
    @Binding var days: Set<Int>

    var body: some View {
        let symbols = Calendar.current.veryShortWeekdaySymbols
        let order = (0..<7).map { (Calendar.current.firstWeekday - 1 + $0) % 7 + 1 }
        HStack {
            ForEach(order, id: \.self) { day in
                let on = days.contains(day)
                Button {
                    withAnimation(.snappy) { if on { days.remove(day) } else { days.insert(day) } }
                } label: {
                    Text(symbols[day - 1])
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(on ? Theme.crimson : .white.opacity(0.06)))
                        .foregroundStyle(on ? .white : .secondary)
                }
                .buttonStyle(.plain)
                if day != order.last { Spacer(minLength: 0) }
            }
        }
        .sensoryFeedback(.selection, trigger: days)
    }
}

/// "Something broken?" — what was blocked in the last two minutes, with one-tap fixes.
struct RescueView: View {
    @EnvironmentObject private var live: LiveStats
    @EnvironmentObject private var tunnel: TunnelManager
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String> = []
    @State private var done = 0

    private struct Group: Identifiable {
        let name: String
        let domains: [String]
        var id: String { name }
    }

    private var groups: [Group] {
        let cutoff = Date().addingTimeInterval(-120)
        let recent = live.entries.filter { $0.blocked && $0.date > cutoff }
        let byOwner = Dictionary(grouping: recent) { Insights.company(for: $0.domain) ?? Insights.registrable($0.domain) }
        return byOwner.map { Group(name: $0.key, domains: Array(Set($0.value.map(\.domain))).sorted()) }
            .sorted { $0.domains.count > $1.domains.count }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if groups.isEmpty {
                        ContentUnavailableView("Nothing blocked just now", systemImage: "checkmark.shield",
                                               description: Text("Spamurai hasn't blocked anything in the last 2 minutes, so it's probably not the cause. You can still pause to be sure."))
                    }
                    ForEach(groups) { group in
                        Button {
                            withAnimation(.snappy) {
                                if selected.contains(group.name) { selected.remove(group.name) } else { selected.insert(group.name) }
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: selected.contains(group.name) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selected.contains(group.name) ? Theme.jade : .secondary)
                                    .contentTransition(.symbolEffect(.replace))
                                DomainBadge(domain: group.domains[0], blocked: true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(group.name).font(.headline)
                                    Text(group.domains.joined(separator: ", "))
                                        .font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(2)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Blocked in the last 2 minutes")
                } footer: {
                    if !groups.isEmpty { Text("Pick what the broken app or site needs and allow it. Ads from other companies stay blocked.") }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AmbientBackground())
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    if !selected.isEmpty {
                        Button("Allow \(selected.count == 1 ? "it" : "\(selected.count)")") { allowSelected() }
                            .buttonStyle(PrimaryButtonStyle(gradient: Theme.calm))
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    Button("Pause blocking for 5 minutes") {
                        Task { await tunnel.pause(for: 300) }
                        done += 1
                        dismiss()
                    }
                    .buttonStyle(OutlineButtonStyle(active: false))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .animation(.snappy, value: selected)
            }
            .navigationTitle("Something broken?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .sensoryFeedback(.success, trigger: done)
        }
    }

    private func allowSelected() {
        let domains = groups.filter { selected.contains($0.name) }.flatMap(\.domains)
        CustomRules.allow = CustomRules.allow + domains
        Task { await tunnel.reload() }
        done += 1
        dismiss()
    }
}
