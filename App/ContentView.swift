import SwiftUI
import WidgetKit

struct ContentView: View {
    @EnvironmentObject private var filters: FilterUpdater
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var tunnel: TunnelManager
    @Environment(\.scenePhase) private var scenePhase
    @State private var showPaywall = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(BlockerList.allCases) { list in
                        let on = filters.enabled[list] == true
                        LabeledContent(list.title) {
                            Image(systemName: on ? "checkmark.circle.fill" : "xmark.circle")
                                .foregroundStyle(on ? .green : .secondary)
                        }
                    }
                } header: {
                    Text("Safari")
                } footer: {
                    Text("Turn on Spamurai in Settings → Apps → Safari → Extensions.")
                }

                Section("Filters") {
                    LabeledContent("Last update") {
                        Text(filters.lastUpdate?.formatted(.relative(presentation: .named)) ?? "Never")
                    }
                    Button {
                        Task { await filters.update() }
                    } label: {
                        if filters.isUpdating { ProgressView() } else { Text("Update now") }
                    }
                    .disabled(filters.isUpdating)
                    if let error = filters.errorMessage {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }
                }

                Section {
                    if store.isPro {
                        Toggle("Block in all apps", isOn: Binding(
                            get: { tunnel.isOn },
                            set: { on in Task { await tunnel.setEnabled(on) } }
                        ))
                        if let error = tunnel.errorMessage {
                            Text(error).font(.footnote).foregroundStyle(.red)
                        }
                        NavigationLink {
                            JournalView()
                        } label: {
                            LabeledContent("Activity", value: "\(StatsStore.today.blocked.formatted()) blocked today")
                        }
                        NavigationLink("My rules") { RulesView() }
                    } else {
                        Button("Get Spamurai Pro") { showPaywall = true }
                    }
                } header: {
                    Text("Pro")
                } footer: {
                    Text("Blocks ads and trackers in every app via a local DNS filter. Uses the VPN slot, so it can't run alongside another VPN.")
                }

                #if DEBUG
                DebugSection()
                #endif
            }
            .navigationTitle("Spamurai")
            .sheet(isPresented: $showPaywall) { PaywallView() }
            .task {
                await filters.refreshStates()
                await tunnel.load()
                await store.load()
                await filters.updateIfStale()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await filters.refreshStates() } }
                if phase == .background { WidgetCenter.shared.reloadAllTimelines() }
            }
            .onChange(of: store.isPro) { _, pro in
                if !pro, tunnel.isOn { Task { await tunnel.setEnabled(false) } }
            }
        }
    }
}
