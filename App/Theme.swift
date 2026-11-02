import SwiftUI

/// Visual language: deep ink background, crimson "blade" accent, soft glass cards.
enum Theme {
    static let crimson = Color(red: 0.90, green: 0.16, blue: 0.24)
    static let ember = Color(red: 1.00, green: 0.45, blue: 0.25)
    static let jade = Color(red: 0.20, green: 0.80, blue: 0.55)
    static let ink = Color(red: 0.05, green: 0.05, blue: 0.08)

    static let blade = LinearGradient(colors: [crimson, ember], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let calm = LinearGradient(colors: [jade, Color(red: 0.15, green: 0.65, blue: 0.85)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing)
}

/// Rounded glass card used across the app.
struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(.white.opacity(0.08))
            )
    }
}

/// Fades and lifts a view in once, after `delay` — used to stagger screen sections.
struct AppearModifier: ViewModifier {
    let delay: Double
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 18)
            .scaleEffect(shown ? 1 : 0.98)
            .onAppear {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.85).delay(delay)) { shown = true }
            }
    }
}

extension View {
    func appear(_ delay: Double = 0) -> some View { modifier(AppearModifier(delay: delay)) }
}

/// Section title with an optional trailing accessory.
struct SectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack {
            Text(title).font(.title3.weight(.bold))
            Spacer()
            trailing
        }
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(_ title: String) { self.init(title: title) { EmptyView() } }
}

/// Colored monogram for a domain — a stable, favicon-like marker without network fetches.
struct DomainBadge: View {
    let domain: String
    var blocked = false

    var body: some View {
        let name = Insights.company(for: domain) ?? Insights.registrable(domain)
        let hue = Double(abs(name.hashValueStable) % 360) / 360
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color(hue: hue, saturation: 0.55, brightness: 0.85).gradient)
            Text(String(name.prefix(1)).uppercased())
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: 32, height: 32)
        .overlay(alignment: .bottomTrailing) {
            if blocked {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white, Theme.crimson)
                    .offset(x: 4, y: 4)
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }
}

extension String {
    /// `hashValue` is randomized per launch; this one is stable so colors don't change.
    var hashValueStable: Int {
        unicodeScalars.reduce(5381) { ($0 &* 33) &+ Int($1.value) }
    }
}
