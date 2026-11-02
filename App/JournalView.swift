import SwiftUI

/// Live list of DNS lookups the tunnel saw, with one-swipe allow/block.
struct JournalView: View {
    @EnvironmentObject private var tunnel: TunnelManager
    @State private var entries: [JournalEntry] = []
    @State private var today = StatsStore.today
    @State private var filter = Filter.all
    @State private var search = ""
    @State private var allow = Set(CustomRules.allow)
    @State private var block = Set(CustomRules.block)

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All", blocked = "Blocked", allowed = "Allowed"
        var id: String { rawValue }
    }

    private var visible: [JournalEntry] {
        entries.filter { entry in
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
                HStack {
                    StatTile(value: today.blocked.formatted(), label: "Blocked today", tint: .red)
                    StatTile(value: today.total.formatted(), label: "Lookups", tint: .secondary)
                    StatTile(value: today.blockedShare.formatted(.percent.precision(.fractionLength(0))),
                             label: "Blocked share", tint: .orange)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            Section {
                Picker("Show", selection: $filter) {
                    ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Section {
                if !tunnel.isOn {
                    Text("Turn on “Block in all apps” to see live activity.").foregroundStyle(.secondary)
                } else if visible.isEmpty {
                    Text("No lookups yet.").foregroundStyle(.secondary)
                }
                ForEach(visible) { entry in
                    row(entry)
                        .swipeActions(edge: .trailing) {
                            if entry.blocked || block.contains(entry.domain) {
                                Button("Allow") { setRule(entry.domain, allowed: true) }.tint(.green)
                            } else {
                                Button("Block") { setRule(entry.domain, allowed: false) }.tint(.red)
                            }
                        }
                }
            }
        }
        .navigationTitle("Activity")
        .searchable(text: $search, prompt: "Domain")
        .task {
            // The tunnel flushes every 2 s; poll while the screen is visible.
            while !Task.isCancelled {
                entries = StatsStore.readJournal()
                today = StatsStore.today
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
        }
    }

    private func row(_ entry: JournalEntry) -> some View {
        HStack(spacing: 12) {
            Image(systemName: entry.blocked ? "xmark.shield.fill" : "checkmark.circle")
                .foregroundStyle(entry.blocked ? .red : .green)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.domain).font(.callout.monospaced()).lineLimit(1).truncationMode(.middle)
                HStack(spacing: 6) {
                    Text(entry.date, style: .time)
                    if entry.count > 1 { Text("×\(entry.count)") }
                    if allow.contains(entry.domain) { Text("allowed by you").foregroundStyle(.green) }
                    if block.contains(entry.domain) { Text("blocked by you").foregroundStyle(.red) }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func setRule(_ domain: String, allowed: Bool) {
        if allowed {
            block.remove(domain)
            allow.insert(domain)
        } else {
            allow.remove(domain)
            block.insert(domain)
        }
        CustomRules.allow = Array(allow)
        CustomRules.block = Array(block)
        Task { await tunnel.reload() }
    }
}

private struct StatTile: View {
    let value: String
    let label: String
    let tint: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value).font(.title2.weight(.semibold)).foregroundStyle(tint).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }
}

/// The user's own allow/block lists.
struct RulesView: View {
    @EnvironmentObject private var tunnel: TunnelManager
    @State private var allow = CustomRules.allow
    @State private var block = CustomRules.block
    @State private var newDomain = ""

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("example.com", text: $newDomain)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    Button("Block") { add(toAllow: false) }.disabled(newDomain.isEmpty)
                    Button("Allow") { add(toAllow: true) }.disabled(newDomain.isEmpty)
                }
                .buttonStyle(.borderless)
            } footer: {
                Text("Rules apply to the domain and all its subdomains. Your allow list always wins.")
            }
            Section("Always allow") {
                ForEach(allow, id: \.self) { Text($0).font(.callout.monospaced()) }
                    .onDelete { allow.remove(atOffsets: $0); save() }
            }
            Section("Always block") {
                ForEach(block, id: \.self) { Text($0).font(.callout.monospaced()) }
                    .onDelete { block.remove(atOffsets: $0); save() }
            }
        }
        .navigationTitle("My rules")
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
        Task { await tunnel.reload() }
    }
}
