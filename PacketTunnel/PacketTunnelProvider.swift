import NetworkExtension
import WidgetKit

/// Pro: system-wide DNS filtering. Only the tunnel's DNS address is routed into it,
/// so regular traffic never passes through sing-box — it just answers DNS and blocks listed domains.
final class PacketTunnelProvider: NEPacketTunnelProvider {
    private let core = LibboxCore()
    private let journal = QueryJournal()
    private var resumeTask: Task<Void, Never>?

    override func startTunnel(options: [String: NSObject]?) async throws {
        guard SharedStore.isPro else { throw TunnelError.message("Spamurai Pro is required for system-wide blocking") }
        #if DEBUG
        SharedStore.diag("start: \(Memory.report()) list=\(SharedStore.downloadedDNSListURL()?.lastPathComponent ?? "bundled")")
        do {
            try await core.start(provider: self, configJson: try DNSConfig.make())
        } catch {
            SharedStore.diag("start failed: \(error.localizedDescription) \(Memory.report())")
            throw error
        }
        SharedStore.diag("started: \(Memory.report())")
        journal.start()
        scheduleResume()
        markActive(true)
        Task {
            var elapsed: UInt64 = 0
            for delay in [5, 25, 90] + Array(repeating: 600, count: 36) as [UInt64] {
                try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
                elapsed += delay
                SharedStore.diag("after \(elapsed)s: \(Memory.report())")
            }
        }
        #else
        try await core.start(provider: self, configJson: try DNSConfig.make())
        journal.start()
        scheduleResume()
        markActive(true)
        #endif
    }

    override func stopTunnel(with reason: NEProviderStopReason) async {
        #if DEBUG
        SharedStore.diag("stopTunnel reason=\(reason.rawValue) \(Memory.report())")
        #endif
        resumeTask?.cancel()
        journal.stop()
        core.stop()
        markActive(false)
    }

    /// App → tunnel messages: "version"; "reload" re-reads custom rules, pause state and the list
    /// (the app sets `SharedStore.pausedUntil` before sending it to pause or resume).
    override func handleAppMessage(_ messageData: Data) async -> Data? {
        switch String(data: messageData, encoding: .utf8) {
        case "version":
            return core.version.data(using: .utf8)
        case "reload":
            do {
                try await core.reload(configJson: try DNSConfig.make())
                scheduleResume()
                return Data("ok".utf8)
            } catch {
                return Data(error.localizedDescription.utf8)
            }
        default:
            return nil
        }
    }

    private func markActive(_ active: Bool) {
        SharedStore.tunnelActive = active
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Re-arms blocking when a pause ends — here, so it happens even with the app closed.
    private func scheduleResume() {
        resumeTask?.cancel()
        guard let until = SharedStore.pausedUntil else { return }
        resumeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(0, until.timeIntervalSinceNow) * 1e9))
            guard !Task.isCancelled, let self else { return }
            try? await self.core.reload(configJson: try DNSConfig.make())
        }
    }
}

enum DNSConfig {
    static let tunAddress = "172.19.0.1/30"
    /// sing-box advertises the next address after the tun address as the DNS server.
    static let dnsAddress = "172.19.0.2/32"

    static func make() throws -> String {
        let listPath = SharedStore.downloadedDNSListURL()?.path
            ?? Bundle.main.path(forResource: "dns", ofType: "srs")

        var ruleSets: [[String: Any]] = []
        var dnsRules: [[String: Any]] = []
        let paused = SharedStore.pausedUntil != nil
        // Order matters: the user's allow list wins over everything, then their block list.
        let allow = CustomRules.allow, block = CustomRules.block
        if !allow.isEmpty, !paused {
            dnsRules.append(["domain_suffix": allow, "action": "route", "server": "cloudflare"])
        }
        if !block.isEmpty, !paused {
            dnsRules.append(["domain_suffix": block, "action": "predefined", "rcode": "NXDOMAIN"])
        }
        if let listPath, !paused {
            ruleSets.append(["type": "local", "tag": "block", "format": "binary", "path": listPath])
            dnsRules.append(["rule_set": ["block"], "action": "predefined", "rcode": "NXDOMAIN"])
        }

        #if DEBUG
        let logPath = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppConfig.appGroup)?
            .appendingPathComponent("Library/Caches/box.log").path ?? ""
        let log: [String: Any] = ["level": "debug", "output": logPath, "timestamp": true]
        #else
        // Debug level is what carries per-query lines; they go only to the in-memory buffer
        // that QueryJournal reads, never to disk.
        let log: [String: Any] = ["level": "debug"]
        #endif
        let config: [String: Any] = [
            "log": log,
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

#if DEBUG
import os

enum Memory {
    /// Current footprint (what iOS counts against the extension limit) and headroom left.
    static func report() -> String {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        let footprint = kr == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1
        let available = Double(os_proc_available_memory()) / 1_048_576
        return String(format: "footprint=%.1fMB available=%.1fMB", footprint, available)
    }
}
#endif
