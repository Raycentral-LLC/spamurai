import SwiftUI

/// The hero control: a glowing ring that spins while protected, ripples outward, and flashes
/// every time something gets blocked. Tap toggles; long-press offers pause.
struct ProtectionOrb: View {
    enum Mode: Equatable { case safariOnly, off, connecting, on, paused(until: Date) }

    let mode: Mode
    let blockedToday: Int
    let pulse: Int
    let action: () -> Void

    @State private var taps = 0

    var body: some View {
        Button {
            taps += 1
            action()
        } label: {
            ZStack {
                Circle()
                    .fill(glow.opacity(isOn ? 0.45 : 0.15))
                    .frame(width: 250, height: 250)
                    .blur(radius: 50)
                    .animation(.easeInOut(duration: 0.8), value: isOn)

                if isOn { Ripples(color: Theme.crimson).frame(width: 220, height: 220) }
                BlockFlash(trigger: pulse).frame(width: 214, height: 214)

                Circle()
                    .stroke(.white.opacity(0.07), lineWidth: 14)
                    .frame(width: 214, height: 214)

                TimelineView(.animation(minimumInterval: nil, paused: !spins)) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    let speed = mode == .connecting ? 1.2 : 6.0
                    Circle()
                        .trim(from: 0, to: arcLength)
                        .stroke(AngularGradient(colors: ringColors, center: .center),
                                style: StrokeStyle(lineWidth: 14, lineCap: .round))
                        .rotationEffect(.degrees(t.truncatingRemainder(dividingBy: speed) / speed * 360))
                        .opacity(arcLength > 0 ? 1 : 0)
                }
                .frame(width: 214, height: 214)
                .animation(.spring(response: 0.9, dampingFraction: 0.8), value: arcLength)

                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(Circle().strokeBorder(.white.opacity(0.1)))
                    .frame(width: 172, height: 172)
                    .shadow(color: .black.opacity(0.35), radius: 18, y: 10)

                VStack(spacing: 6) {
                    Image(systemName: symbol)
                        .font(.system(size: 52, weight: .semibold))
                        .foregroundStyle(isOn ? AnyShapeStyle(Theme.blade) : AnyShapeStyle(Color.secondary))
                        .contentTransition(.symbolEffect(.replace))
                        .symbolEffect(.bounce, value: pulse)
                    Text(title)
                        .font(.system(.headline, design: .rounded))
                    subtitle
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(width: 150)
            }
            .frame(height: 280)
            .contentShape(Circle())
        }
        .buttonStyle(PressableStyle(scale: 0.95))
        .sensoryFeedback(.impact(weight: .medium), trigger: taps)
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.5), trigger: pulse)
        .accessibilityLabel(title)
    }

    private var isOn: Bool { mode == .on }
    private var spins: Bool { mode == .on || mode == .connecting }
    private var glow: Color { isOn ? Theme.crimson : .gray }

    private var arcLength: CGFloat {
        switch mode {
        case .on: 0.78
        case .connecting: 0.25
        case .paused: 0.4
        default: 0
        }
    }

    private var ringColors: [Color] {
        switch mode {
        case .paused: [.yellow.opacity(0.2), .yellow]
        default: [Theme.crimson.opacity(0.05), Theme.crimson, Theme.ember]
        }
    }

    private var symbol: String {
        switch mode {
        case .on: "checkmark.shield.fill"
        case .connecting: "shield.lefthalf.filled"
        case .paused: "pause.circle.fill"
        case .off, .safariOnly: "shield.slash"
        }
    }

    private var title: String {
        switch mode {
        case .on: "Protected"
        case .connecting: "Connecting…"
        case .paused: "Paused"
        case .off: "Protection off"
        case .safariOnly: "Safari only"
        }
    }

    @ViewBuilder private var subtitle: some View {
        switch mode {
        case .on:
            HStack(spacing: 4) {
                Text(blockedToday.formatted())
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(blockedToday)))
                Text("blocked today")
            }
        case .paused(let until):
            Text("Resumes \(until, style: .relative)")
        case .connecting:
            Text("Arming the filter")
        case .off, .safariOnly:
            Text("Tap to protect every app")
        }
    }
}

/// Soft rings drifting outward while protection is on.
private struct Ripples: View {
    let color: Color

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(0..<3) { i in
                    let phase = (t / 3 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                    Circle()
                        .stroke(color.opacity(0.35 * (1 - phase)), lineWidth: 1.5)
                        .scaleEffect(1 + phase * 0.45)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// A red shockwave each time the tunnel blocks something.
private struct BlockFlash: View {
    let trigger: Int
    @State private var scale: CGFloat = 1
    @State private var opacity: Double = 0

    var body: some View {
        Circle()
            .stroke(Theme.ember, lineWidth: 4)
            .scaleEffect(scale)
            .opacity(opacity)
            .allowsHitTesting(false)
            .onChange(of: trigger) {
                scale = 1
                opacity = 0.9
                withAnimation(.easeOut(duration: 0.9)) {
                    scale = 1.35
                    opacity = 0
                }
            }
    }
}

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

/// Dark ink backdrop with two slow-drifting crimson/ember glows.
struct AmbientBackground: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            ZStack {
                Theme.ink
                Circle()
                    .fill(Theme.crimson.opacity(0.28))
                    .frame(width: 420)
                    .blur(radius: 110)
                    .offset(x: -120 + sin(t / 7) * 60, y: -300 + cos(t / 9) * 40)
                Circle()
                    .fill(Theme.ember.opacity(0.16))
                    .frame(width: 360)
                    .blur(radius: 120)
                    .offset(x: 150 + cos(t / 8) * 50, y: 260 + sin(t / 6) * 50)
            }
        }
        .ignoresSafeArea()
    }
}
