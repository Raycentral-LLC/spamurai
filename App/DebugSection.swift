#if DEBUG
import SafariServices
import SwiftUI

/// Debug builds only: unlock Pro and run an on-device self-test (results also go to diag.log).
struct DebugSection: View {
    @EnvironmentObject private var store: Store
    @State private var debugPro = SharedStore.debugPro
    @State private var results: [String] = []
    @State private var running = false

    var body: some View {
        Section("Debug") {
            Toggle("Unlock Pro (debug)", isOn: $debugPro)
                .onChange(of: debugPro) { _, on in
                    SharedStore.debugPro = on
                    Task { await store.refreshEntitlements() }
                }
            Button(running ? "Running…" : "Run self-test") { Task { await selfTest() } }
                .disabled(running)
            ForEach(results, id: \.self) { Text($0).font(.caption.monospaced()) }
        }
    }

    private func selfTest() async {
        running = true
        defer { running = false }
        results = []
        for list in BlockerList.allCases {
            do {
                try await SFContentBlockerManager.reloadContentBlocker(withIdentifier: list.extensionID)
                log("safari \(list.rawValue): compiled OK")
            } catch {
                log("safari \(list.rawValue): \(error.localizedDescription)")
            }
        }
        for host in ["doubleclick.net", "googleadservices.com", "apple.com", "wikipedia.org"] {
            log("dns \(host): \(await resolve(host))")
        }
    }

    private func log(_ line: String) {
        results.append(line)
        SharedStore.diag(line)
    }

    private func resolve(_ host: String) async -> String {
        await Task.detached {
            var hints = addrinfo(ai_flags: 0, ai_family: AF_INET, ai_socktype: SOCK_STREAM,
                                 ai_protocol: 0, ai_addrlen: 0, ai_canonname: nil, ai_addr: nil, ai_next: nil)
            var res: UnsafeMutablePointer<addrinfo>?
            let rc = getaddrinfo(host, nil, &hints, &res)
            defer { if res != nil { freeaddrinfo(res) } }
            guard rc == 0, let addr = res?.pointee.ai_addr else {
                return "BLOCKED/failed (\(String(cString: gai_strerror(rc))))"
            }
            var buf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(addr, socklen_t(addr.pointee.sa_len), &buf, socklen_t(buf.count), nil, 0, NI_NUMERICHOST)
            return "resolved \(String(cString: buf))"
        }.value
    }
}
#endif
