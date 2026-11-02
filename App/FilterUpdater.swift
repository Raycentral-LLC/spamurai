import Foundation
import SafariServices

/// Downloads rule lists into the App Group and asks Safari to recompile them.
@MainActor
final class FilterUpdater: ObservableObject {
    @Published private(set) var enabled: [BlockerList: Bool] = [:]
    @Published private(set) var isUpdating = false
    @Published private(set) var lastUpdate: Date? = SharedStore.lastUpdate
    @Published var errorMessage: String?

    func refreshStates() async {
        for list in BlockerList.allCases {
            let state = try? await SFContentBlockerManager.stateOfContentBlocker(withIdentifier: list.extensionID)
            enabled[list] = state?.isEnabled ?? false
        }
    }

    func updateIfStale(maxAge: TimeInterval = 24 * 3600) async {
        if let lastUpdate, Date().timeIntervalSince(lastUpdate) < maxAge { return }
        await update()
    }

    func update() async {
        guard !isUpdating else { return }
        isUpdating = true
        defer { isUpdating = false }
        errorMessage = nil

        do {
            for list in BlockerList.allCases {
                try await download(from: list.remoteURL, to: SharedStore.listURL(list))
                if enabled[list] == true { try await reload(list) }
            }
            // Picked up by the DNS tunnel on its next start.
            try await download(from: SharedStore.dnsRemoteURL, to: SharedStore.dnsListURL(), expectArray: false)
            let now = Date()
            SharedStore.lastUpdate = now
            lastUpdate = now
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func download(from url: URL, to dest: URL?, expectArray: Bool = true) async throws {
        let (data, response) = try await URLSession.shared.data(from: url)
        let json = try? JSONSerialization.jsonObject(with: data)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              expectArray ? json is [Any] : json is [String: Any] else {
            throw URLError(.cannotParseResponse)
        }
        guard let dest else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try data.write(to: dest, options: .atomic)
    }

    /// If Safari rejects a downloaded list, drop it so the extension falls back to its bundled copy.
    private func reload(_ list: BlockerList) async throws {
        do {
            try await SFContentBlockerManager.reloadContentBlocker(withIdentifier: list.extensionID)
        } catch {
            if let url = SharedStore.listURL(list) { try? FileManager.default.removeItem(at: url) }
            try? await SFContentBlockerManager.reloadContentBlocker(withIdentifier: list.extensionID)
            throw error
        }
    }
}
