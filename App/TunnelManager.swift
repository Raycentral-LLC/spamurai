@preconcurrency import NetworkExtension

/// Installs and toggles the DNS-filtering tunnel (Pro). On-demand keeps it on across network changes.
@MainActor
final class TunnelManager: ObservableObject {
    @Published private(set) var status: NEVPNStatus = .invalid
    @Published var errorMessage: String?

    private var manager: NETunnelProviderManager?
    private var observer: NSObjectProtocol?

    var isOn: Bool { [.connected, .connecting, .reasserting].contains(status) }

    func load() async {
        manager = (try? await NETunnelProviderManager.loadAllFromPreferences())?.first
        observe()
        status = manager?.connection.status ?? .invalid
    }

    func setEnabled(_ on: Bool) async {
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

    /// Asks the running tunnel to re-read custom rules and the list. No-op when it's off.
    func reload() async {
        guard isOn, let session = manager?.connection as? NETunnelProviderSession else { return }
        try? session.sendProviderMessage(Data("reload".utf8)) { _ in }
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
