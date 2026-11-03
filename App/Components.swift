import SwiftUI

struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// Gradient capsule with a slow shimmer — the app's primary call to action.
struct PrimaryButtonStyle: ButtonStyle {
    var gradient = Theme.blade

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(gradient, in: Capsule())
            .overlay(Shimmer().clipShape(Capsule()))
            .shadow(color: Theme.crimson.opacity(0.45), radius: 16, y: 8)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

private struct Shimmer: View {
    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3.2) / 3.2
            GeometryReader { geo in
                LinearGradient(colors: [.clear, .white.opacity(0.35), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: geo.size.width * 0.35)
                    .rotationEffect(.degrees(20))
                    .offset(x: -geo.size.width * 0.4 + geo.size.width * 1.8 * t)
            }
        }
        .allowsHitTesting(false)
        .blendMode(.plusLighter)
    }
}

/// Near-black backdrop with a faint crimson haze at the top.
struct AmbientBackground: View {
    var body: some View {
        ZStack {
            Color.black
            RadialGradient(colors: [Theme.crimson.opacity(0.16), .clear], center: .top, startRadius: 0, endRadius: 520)
        }
        .ignoresSafeArea()
    }
}
