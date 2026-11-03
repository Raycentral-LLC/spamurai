@preconcurrency import NetworkExtension

/// Installs and toggles the DNS-filtering tunnel (Pro). On-demand keeps it on across network changes.
@MainActor
final class TunnelManager: ObservableObject {
    @Published private(set) var status: NEVPNStatus = .invalid
    @Published var errorMessage: String?
    @Published private(set) var pausedUntil = SharedStore.pausedUntil
    /// App Review 5.4: the data-use statement must be shown before the VPN is first used.
    @Published var showDisclosure = false

    private static let disclosureKey = "vpnDisclosureAccepted"
    var disclosureAccepted: Bool { UserDefaults.standard.bool(forKey: Self.disclosureKey) }

    func acceptDisclosure() async {
        UserDefaults.standard.set(true, forKey: Self.disclosureKey)
        showDisclosure = false
        await setEnabled(true)
    }

    private var manager: NETunnelProviderManager?
    private var observer: NSObjectProtocol?

    var isOn: Bool { [.connected, .connecting, .reasserting].contains(status) }

    func load() async {
        manager = (try? await NETunnelProviderManager.loadAllFromPreferences())?.first
        observe()
        status = manager?.connection.status ?? .invalid
    }

    func setEnabled(_ on: Bool) async {
        if on, !disclosureAccepted {
            showDisclosure = true
            return
        }
        errorMessage = nil
        do {
            if on {
                let m = manager ?? NETunnelProviderManager()
                let proto = NETunnelProviderProtocol()
                proto.providerBundleIdentifier = "\(AppConfig.bundlePrefix).PacketTunnel"
                proto.serverAddress = "Spamurai DNS"
                m.protocolConfiguration = proto
                m.localizedDescription = "Spamurai"
                m.isEnabled = true
                let always = NEOnDemandRuleConnect()
                always.interfaceTypeMatch = .any
                m.onDemandRules = [always]
                m.isOnDemandEnabled = true
                try await m.saveToPreferences()
                try await m.loadFromPreferences()
                manager = m
                observe()
                try m.connection.startVPNTunnel()
            } else if let m = manager {
                // Disable on-demand first, or iOS reconnects right away.
                m.isOnDemandEnabled = false
                try await m.saveToPreferences()
                m.connection.stopVPNTunnel()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Lets everything through for a while; the tunnel resumes blocking on its own.
    func pause(for seconds: TimeInterval) async {
        let until = Date().addingTimeInterval(seconds)
        SharedStore.pausedUntil = until
        pausedUntil = until
        await reload()
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1e9))
            self?.pausedUntil = SharedStore.pausedUntil
        }
    }

    func resume() async {
        SharedStore.pausedUntil = nil
        pausedUntil = nil
        await reload()
    }

    /// Asks the running tunnel to re-read shared state (rules, pause, Focus Shield).
    func reload() async {
        SharedStore.notifyTunnel()
    }

    /// Starts the installed tunnel if it isn't running — used by the Focus filter, which runs
    /// in the background without the UI. Does nothing if Pro protection was never set up.
    nonisolated static func ensureRunning() async {
        guard SharedStore.isPro,
              let manager = (try? await NETunnelProviderManager.loadAllFromPreferences())?.first,
              manager.isEnabled else { return }
        let status = manager.connection.status
        if status == .disconnected || status == .invalid {
            try? manager.connection.startVPNTunnel()
        }
    }

    private func observe() {
        guard observer == nil, let m = manager else { return }
        observer = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange, object: m.connection, queue: .main
        ) { [weak self] note in
            guard let status = (note.object as? NEVPNConnection)?.status else { return }
            Task { @MainActor in self?.status = status }
        }
    }
}
