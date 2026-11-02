import SwiftUI

/// Live list of DNS lookups the tunnel saw, with one-swipe allow/block.
struct JournalView: View {
    @EnvironmentObject private var tunnel: TunnelManager
    @EnvironmentObject private var live: LiveStats
    @State private var filter = Filter.all
    @State private var search = ""
    @State private var allow = Set(CustomRules.allow)
    @State private var block = Set(CustomRules.block)
    @State private var ruleChanged = 0

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All", blocked = "Blocked", allowed = "Allowed"
        var id: String { rawValue }
    }

    private var visible: [JournalEntry] {
        live.entries
            .filter { entry in
                switch filter {
                case .all: true
                case .blocked: entry.blocked
                case .allowed: !entry.blocked
                }
            }
            .filter { search.isEmpty || $0.domain.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        List {
            Section {
                Picker("Show", selection: $filter.animation(.snappy)) {
                    ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            Section {
                if !tunnel.isOn {
                    ContentUnavailableView("Protection is off", systemImage: "shield.slash",
                                           description: Text("Turn it on to see every app's connections live."))
                } else if visible.isEmpty {
                    ContentUnavailableView("Nothing here yet", systemImage: "waveform.path.ecg",
                                           description: Text("Lookups appear as apps go online."))
                }
                ForEach(visible) { entry in
                    JournalRow(entry: entry, rule: rule(for: entry.domain))
                        .listRowBackground(entry.blocked ? Theme.crimson.opacity(0.08) : Color.clear)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            if entry.blocked || block.contains(entry.domain) {
                                Button("Allow", systemImage: "checkmark") { setRule(entry.domain, allowed: true) }
                                    .tint(Theme.jade)
                            } else {
                                Button("Block", systemImage: "xmark.shield") { setRule(entry.domain, allowed: false) }
                                    .tint(Theme.crimson)
                            }
                        }
                        .contextMenu {
                            Button("Copy domain", systemImage: "doc.on.doc") { UIPasteboard.general.string = entry.domain }
                            Button("Always allow", systemImage: "checkmark") { setRule(entry.domain, allowed: true) }
                            Button("Always block", systemImage: "xmark.shield", role: .destructive) {
                                setRule(entry.domain, allowed: false)
                            }
                        }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AmbientBackground())
        .navigationTitle("Activity")
        .searchable(text: $search, prompt: "Search domains")
        .sensoryFeedback(.success, trigger: ruleChanged)
    }

    private func rule(for domain: String) -> JournalRow.Rule? {
        if allow.contains(domain) { return .allowed }
        if block.contains(domain) { return .blocked }
        return nil
    }

    private func setRule(_ domain: String, allowed: Bool) {
        withAnimation(.snappy) {
            if allowed {
                block.remove(domain)
                allow.insert(domain)
            } else {
                allow.remove(domain)
                block.insert(domain)
            }
        }
        CustomRules.allow = Array(allow)
        CustomRules.block = Array(block)
        ruleChanged += 1
        Task { await tunnel.reload() }
    }
}

struct JournalRow: View {
    enum Rule { case allowed, blocked }

    let entry: JournalEntry
    var rule: Rule? = nil
    var compact = false

    var body: some View {
        HStack(spacing: 12) {
            DomainBadge(domain: entry.domain, blocked: entry.blocked)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.domain)
                    .font(.system(compact ? .subheadline : .callout, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 6) {
                    if let company = Insights.company(for: entry.domain) { Text(company).fontWeight(.medium) }
                    Text(entry.date, format: .dateTime.hour().minute().second())
                    if entry.count > 1 { Text("×\(entry.count)") }
                    switch rule {
                    case .allowed: Text("allowed by you").foregroundStyle(Theme.jade)
                    case .blocked: Text("blocked by you").foregroundStyle(Theme.crimson)
                    case nil: EmptyView()
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if entry.blocked {
                Text("BLOCKED")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Theme.crimson.opacity(0.18), in: Capsule())
                    .foregroundStyle(Theme.crimson)
            }
        }
    }
}

/// The user's own allow/block lists.
struct RulesView: View {
    @EnvironmentObject private var tunnel: TunnelManager
    @State private var allow = CustomRules.allow
    @State private var block = CustomRules.block
    @State private var newDomain = ""
    @State private var saved = 0

    var body: some View {
        List {
            Section {
                TextField("example.com", text: $newDomain)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .font(.body.monospaced())
                HStack(spacing: 10) {
                    Button { add(toAllow: false) } label: { Label("Block", systemImage: "xmark.shield") }
                        .buttonStyle(.borderedProminent).tint(Theme.crimson)
                    Button { add(toAllow: true) } label: { Label("Allow", systemImage: "checkmark") }
                        .buttonStyle(.bordered).tint(Theme.jade)
                }
                .disabled(CustomRules.normalized([newDomain]).isEmpty)
            } footer: {
                Text("Rules cover the domain and all its subdomains. Your allow list always wins.")
            }
            Section("Always allow") {
                if allow.isEmpty { Text("Nothing yet").foregroundStyle(.secondary) }
                ForEach(allow, id: \.self) { domain in
                    Label { Text(domain).font(.callout.monospaced()) } icon: { DomainBadge(domain: domain) }
                }
                .onDelete { allow.remove(atOffsets: $0); save() }
            }
            Section("Always block") {
                if block.isEmpty { Text("Nothing yet").foregroundStyle(.secondary) }
                ForEach(block, id: \.self) { domain in
                    Label { Text(domain).font(.callout.monospaced()) } icon: { DomainBadge(domain: domain, blocked: true) }
                }
                .onDelete { block.remove(atOffsets: $0); save() }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AmbientBackground())
        .navigationTitle("My rules")
        .sensoryFeedback(.success, trigger: saved)
        .animation(.snappy, value: allow)
        .animation(.snappy, value: block)
    }

    private func add(toAllow: Bool) {
        guard let domain = CustomRules.normalized([newDomain]).first else { return }
        allow.removeAll { $0 == domain }
        block.removeAll { $0 == domain }
        if toAllow { allow.append(domain) } else { block.append(domain) }
        newDomain = ""
        save()
    }

    private func save() {
        CustomRules.allow = allow
        CustomRules.block = block
        allow = CustomRules.allow
        block = CustomRules.block
        saved += 1
        Task { await tunnel.reload() }
    }
}
