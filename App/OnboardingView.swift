import SwiftUI

/// First launch: what Spamurai does → turn on Safari → offer system-wide Pro.
struct OnboardingView: View {
    @EnvironmentObject private var store: Store
    @Binding var done: Bool
    @State private var page = 0
    @State private var showPaywall = false
    @State private var showSafariHelp = false

    var body: some View {
        ZStack {
            AmbientBackground()
            VStack(spacing: 0) {
                TabView(selection: $page.animation(.snappy)) {
                    welcome.tag(0)
                    safari.tag(1)
                    everywhere.tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                HStack(spacing: 8) {
                    ForEach(0..<3) { i in
                        Capsule()
                            .fill(i == page ? AnyShapeStyle(Theme.blade) : AnyShapeStyle(Color.white.opacity(0.2)))
                            .frame(width: i == page ? 26 : 8, height: 8)
                    }
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.7), value: page)
                .padding(.bottom, 20)

                Group {
                    switch page {
                    case 0: Button("Get started") { page = 1 }
                    case 1: Button("I turned it on") { page = 2 }
                    default: Button("Try Pro free for a week") { showPaywall = true }
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 24)

                Button(page == 2 ? "Maybe later" : "Skip") { finish() }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 14)
            }
        }
        .sensoryFeedback(.selection, trigger: page)
        .sheet(isPresented: $showPaywall, onDismiss: { if store.isPro { finish() } }) { PaywallView() }
        .sheet(isPresented: $showSafariHelp) { SafariHelpView().presentationDetents([.medium]) }
    }

    private func finish() {
        withAnimation(.snappy) { done = true }
    }

    private var welcome: some View {
        Page(title: "Spamurai", subtitle: "One clean cut through ads and trackers — in Safari and every app.") {
            ZStack {
                Circle().fill(Theme.crimson.opacity(0.4)).frame(width: 200).blur(radius: 60)
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 110, weight: .semibold))
                    .foregroundStyle(Theme.blade)
                    .symbolEffect(.bounce, value: page)
            }
        }
    }

    private var safari: some View {
        Page(title: "Turn on Safari blocking", subtitle: "Settings → Apps → Safari → Extensions → turn on Spamurai Ads and Spamurai Privacy.") {
            VStack(spacing: 14) {
                ForEach(Array(["Spamurai Ads", "Spamurai Privacy"].enumerated()), id: \.offset) { index, name in
                    HStack {
                        Image(systemName: "puzzlepiece.extension.fill").foregroundStyle(Theme.blade)
                        Text(name).font(.headline)
                        Spacer()
                        Toggle("", isOn: .constant(true)).labelsHidden().tint(Theme.jade).allowsHitTesting(false)
                    }
                    .padding(16)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .appear(0.1 + Double(index) * 0.1)
                }
                Button("Show me how") { showSafariHelp = true }.font(.subheadline.weight(.semibold))
            }
            .padding(.horizontal, 30)
        }
    }

    private var everywhere: some View {
        Page(title: "Now, every app", subtitle: "Games, social and news apps load ads outside Safari. Pro blocks them system-wide — on your iPhone, no servers.") {
            HStack(spacing: -18) {
                ForEach(Array(["gamecontroller.fill", "bubble.left.and.bubble.right.fill", "newspaper.fill", "play.rectangle.fill"].enumerated()), id: \.offset) { index, icon in
                    Image(systemName: icon)
                        .font(.system(size: 30))
                        .foregroundStyle(.white)
                        .frame(width: 72, height: 72)
                        .background(Theme.blade.opacity(0.9 - Double(index) * 0.15), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.ink, lineWidth: 3))
                        .rotationEffect(.degrees(Double(index - 1) * 6))
                        .appear(0.1 + Double(index) * 0.08)
                }
            }
        }
    }
}

private struct Page<Art: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var art: Art

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            art.frame(height: 240)
            VStack(spacing: 12) {
                Text(title)
                    .font(.system(size: 32, weight: .heavy, design: .rounded))
                    .multilineTextAlignment(.center)
                Text(subtitle)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 28)
            Spacer()
        }
    }
}
