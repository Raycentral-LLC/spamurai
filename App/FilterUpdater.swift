import Foundation
import SafariServices
import UIKit

/// Downloads rule lists into the App Group and asks Safari to recompile them.
@MainActor
final class FilterUpdater: ObservableObject {
    @Published private(set) var enabled: [BlockerList: Bool] = [:]
    @Published private(set) var youTube = YouTubeState.unknown

    enum YouTubeState { case unknown, off, needsSiteAccess, on }
    @Published private(set) var isUpdating = false
    @Published private(set) var lastUpdate: Date? = SharedStore.lastUpdate
    @Published var errorMessage: String?

    func refreshStates() async {
        for list in BlockerList.allCases {
            let state = try? await SFContentBlockerManager.stateOfContentBlocker(withIdentifier: list.extensionID)
            enabled[list] = state?.isEnabled ?? false
        }
        youTube = await youTubeState()
        #if DEBUG
        if DemoMode.isOn {
            BlockerList.allCases.forEach { enabled[$0] = true }
            youTube = .on
        }
        #endif
    }

    /// iOS 26.2+ reports whether the extension is on; on any version, the extension pinging the
    /// app from youtube.com proves the site is allowed too.
    private func youTubeState() async -> YouTubeState {
        let seen = YouTubeStats.lastSeen != nil
        if #available(iOS 26.2, *) {
            guard let state = try? await SFSafariExtensionManager.stateOfExtension(withIdentifier: BlockerList.youTubeExtensionID)
            else { return seen ? .on : .unknown }
            if !state.isEnabled { return .off }
            return seen ? .on : .needsSiteAccess
        }
        return seen ? .on : .unknown
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
            try await download(from: SharedStore.dnsRemoteURL, to: SharedStore.dnsListURL(), format: .ruleSet)
            let now = Date()
            SharedStore.lastUpdate = now
            lastUpdate = now
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private enum Format { case safariRules, ruleSet }

    private func download(from url: URL, to dest: URL?, format: Format = .safariRules) async throws {
        let (data, response) = try await URLSession.shared.data(from: url)
        let valid = switch format {
        case .safariRules: (try? JSONSerialization.jsonObject(with: data)) is [Any]
        case .ruleSet: data.starts(with: Array("SRS".utf8))
        }
        guard (response as? HTTPURLResponse)?.statusCode == 200, valid else {
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

/// Opens Settings at Safari's extension list (iOS 26.2+); otherwise the app's own settings page.
@MainActor
enum SafariSettingsLink {
    static var opensExtensions: Bool {
        if #available(iOS 26.2, *) { return true }
        return false
    }

    static func open() {
        if #available(iOS 26.2, *) {
            let ids = BlockerList.allCases.map(\.extensionID) + [BlockerList.youTubeExtensionID]
            SFSafariSettings.openExtensionsSettings(forIdentifiers: ids) { error in
                if error != nil { openAppSettings() }
            }
        } else {
            openAppSettings()
        }
    }

    private static func openAppSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }
}
