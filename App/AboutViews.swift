import SwiftUI

/// App Review 5.4: what data the VPN configuration touches and how it's used, shown before
/// system-wide blocking is first turned on (and linked from the paywall before purchase).
struct DataDisclosureView: View {
    var onContinue: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    static let points: [(icon: String, title: String, text: String)] = [
        ("network", "A local VPN configuration",
         "iOS will ask to add a VPN configuration. It is a filter on your iPhone, not a remote VPN server. Only DNS lookups — the names of the servers apps connect to — pass through it. All other traffic is untouched."),
        ("xmark.shield", "Blocked on your device",
         "Lookups for known ad, tracker and (if you turn it on) Focus Shield domains are answered “not found” right on your iPhone."),
        ("lock.shield", "Everything else: encrypted DNS",
         "Other lookups are resolved over encrypted DNS-over-HTTPS by Cloudflare (1.1.1.1). Like any DNS provider, Cloudflare receives the domain names being looked up."),
        ("hand.raised", "We collect nothing",
         "No account, no analytics, no ads. The Activity log and statistics stay on your iPhone and are never uploaded. We never sell or share any data."),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Caps("Before you turn it on", color: Theme.crimson)
                    Text("How system-wide blocking uses your data")
                        .font(.system(size: 28, weight: .light))
                    ForEach(Array(Self.points.enumerated()), id: \.offset) { index, point in
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: point.icon)
                                .font(.title3)
                                .foregroundStyle(Theme.crimson)
                                .frame(width: 30)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(point.title).font(.headline)
                                Text(point.text).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        .appear(0.05 + Double(index) * 0.06)
                    }
                    Link("Read the full Privacy Policy", destination: AppConfig.privacyURL)
                        .font(.subheadline.weight(.semibold))
                }
                .padding(24)
            }
            .background(AmbientBackground())
            .safeAreaInset(edge: .bottom) {
                if let onContinue {
                    VStack(spacing: 8) {
                        Button("Continue") { onContinue() }.buttonStyle(PrimaryButtonStyle())
                        Button("Not now") { dismiss() }.font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(.black.opacity(0.6))
                }
            }
            .toolbar {
                if onContinue == nil {
                    ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                }
            }
        }
    }
}

/// Version, links, and the attributions the bundled components' licenses require.
struct AboutView: View {
    private struct Component: Identifiable {
        let name: String
        let license: String
        let note: String
        let url: URL
        var id: String { name }
    }

    private let components: [Component] = [
        Component(name: "Spamurai", license: "GNU GPL v3",
                  note: "This app's source code is free software.",
                  url: AppConfig.sourceURL),
        Component(name: "sing-box", license: "GNU GPL v3 or later",
                  note: "© SagerNet. Network core used for system-wide DNS filtering.",
                  url: URL(string: "https://github.com/SagerNet/sing-box")!),
        Component(name: "EasyList & EasyPrivacy", license: "GNU GPL v3 / CC BY-SA 3.0",
                  note: "© The EasyList authors. Safari ad and tracker rules are built from these lists.",
                  url: URL(string: "https://easylist.to")!),
        Component(name: "AdGuard DNS filter", license: "GNU GPL v3",
                  note: "© AdGuard. System-wide domain list is built from this filter.",
                  url: URL(string: "https://github.com/AdguardTeam/AdGuardSDNSFilter")!),
    ]

    @State private var showDisclosure = false

    var body: some View {
        List {
            Section {
                VStack(spacing: 10) {
                    Image("AppIconPreview")
                        .resizable()
                        .frame(width: 84, height: 84)
                        .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
                    Text("Spamurai").font(.title2.weight(.light))
                    Caps("Version \(version)")
                    Caps("by RayCentral LLC")
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }
            Section {
                Button("How Spamurai uses data") { showDisclosure = true }
                Link("Privacy Policy", destination: AppConfig.privacyURL)
                Link("Terms of Use", destination: AppConfig.termsURL)
                Link("Source code", destination: AppConfig.sourceURL)
            }
            Section {
                ForEach(components) { c in
                    Link(destination: c.url) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(c.name).font(.headline).foregroundStyle(.white)
                                Spacer()
                                Text(c.license).font(.caption).foregroundStyle(Theme.crimson)
                            }
                            Text(c.note).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Open-source licenses")
            } footer: {
                Text("Filter lists are redistributed under their original licenses. Full license texts are linked above.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(AmbientBackground())
        .navigationTitle("About")
        .sheet(isPresented: $showDisclosure) { DataDisclosureView() }
    }

    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(v) (\(b))"
    }
}
