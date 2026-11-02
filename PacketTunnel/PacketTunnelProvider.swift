import NetworkExtension

/// Pro: system-wide DNS filtering. Only the tunnel's DNS address is routed into it,
/// so regular traffic never passes through sing-box — it just answers DNS and blocks listed domains.
final class PacketTunnelProvider: NEPacketTunnelProvider {
    private let core = LibboxCore()

    override func startTunnel(options: [String: NSObject]?) async throws {
        guard SharedStore.isPro else { throw TunnelError.message("Spamurai Pro is required for system-wide blocking") }
        try await core.start(provider: self, configJson: try DNSConfig.make())
    }

    override func stopTunnel(with reason: NEProviderStopReason) async {
        core.stop()
    }

    override func handleAppMessage(_ messageData: Data) async -> Data? {
        String(data: messageData, encoding: .utf8) == "version" ? core.version.data(using: .utf8) : nil
    }
}

enum DNSConfig {
    static let tunAddress = "172.19.0.1/30"
    /// sing-box advertises the next address after the tun address as the DNS server.
    static let dnsAddress = "172.19.0.2/32"

    static func make() throws -> String {
        let listPath = SharedStore.downloadedDNSListURL()?.path
            ?? Bundle.main.path(forResource: "dns", ofType: "json")

        var ruleSets: [[String: Any]] = []
        var dnsRules: [[String: Any]] = []
        if let listPath {
            ruleSets.append(["type": "local", "tag": "block", "format": "source", "path": listPath])
            dnsRules.append(["rule_set": ["block"], "action": "predefined", "rcode": "NXDOMAIN"])
        }

        let config: [String: Any] = [
            "log": ["level": "warn"],
            "dns": [
                "servers": [["type": "https", "tag": "cloudflare", "server": "1.1.1.1"]],
                "rules": dnsRules,
                "final": "cloudflare",
            ],
            "inbounds": [[
                "type": "tun",
                "tag": "tun-in",
                "address": [tunAddress],
                "auto_route": true,
                "route_address": [dnsAddress],
            ]],
            "outbounds": [["type": "direct", "tag": "direct"]],
            "route": [
                "rule_set": ruleSets,
                "rules": [["port": 53, "action": "hijack-dns"]],
                "final": "direct",
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: config)
        return String(decoding: data, as: UTF8.self)
    }
}

enum TunnelError: LocalizedError {
    case noAppGroup
    case message(String)

    var errorDescription: String? {
        switch self {
        case .noAppGroup: "App Group container is unavailable"
        case .message(let text): text
        }
    }
}
