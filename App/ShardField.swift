import SwiftUI

/// The hero: glass shards orbiting in 3D that assemble into the split shield when protection is on.
/// Drawn with Canvas — ~180 shards at 60 fps, no SceneKit.
struct ShardField: View {
    enum Phase: Equatable { case scattered, gathering, assembled, paused }

    let phase: Phase
    /// Increments on every block — sends a blade of light across the shield.
    var pulse: Int = 0

    @State private var from: Double = 0
    @State private var to: Double = 0
    @State private var changedAt = Date.distantPast
    @State private var pulseAt = Date.distantPast

    private static let shards: [Shard] = Shard.make(count: 300)

    var body: some View {
        TimelineView(.animation) { context in
            let now = context.date
            let t = now.timeIntervalSinceReferenceDate
            let assembly = progress(at: now)
            let sweep = now.timeIntervalSince(pulseAt)
            Canvas { gc, size in
                drawDotWaves(&gc, size: size, t: t, energy: assembly)
                drawShards(&gc, size: size, t: t, assembly: assembly, sweep: sweep)
                drawBlade(&gc, size: size, assembly: assembly, sweep: sweep)
            }
        }
        .onAppear { retarget(animated: false) }
        .onChange(of: phase) { retarget(animated: true) }
        .onChange(of: pulse) { pulseAt = Date() }
        .accessibilityHidden(true)
    }

    // MARK: - Assembly progress

    private var target: Double {
        switch phase {
        case .scattered: 0
        case .gathering: 0.45
        case .paused: 0.7
        case .assembled: 1
        }
    }

    private func progress(at date: Date) -> Double {
        let raw = min(1, max(0, date.timeIntervalSince(changedAt) / 1.8))
        // easeInOutCubic
        let eased = raw < 0.5 ? 4 * raw * raw * raw : 1 - pow(-2 * raw + 2, 3) / 2
        return from + (to - from) * eased
    }

    private func retarget(animated: Bool) {
        let now = Date()
        from = animated ? progress(at: now) : target
        to = target
        changedAt = animated ? now : .distantPast
    }

    // MARK: - Drawing

    private func drawShards(_ gc: inout GraphicsContext, size: CGSize, t: Double, assembly: Double, sweep: Double) {
        let unit = min(size.width, size.height) * 0.82
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let paused = phase == .paused

        // Back-to-front so nearer shards cover farther ones.
        let placed = Self.shards.map { shard -> (Shard, CGPoint, Double, Double, Double) in
            // Each shard starts moving at its own moment for a cascading assembly.
            let p = smooth(min(1, max(0, (assembly - shard.delay) / (1 - shard.delay * 0.9))))
            let angle = shard.theta + t * shard.speed
            let depth = sin(angle) // -1 far … 1 near
            let scatter = CGPoint(x: cos(angle) * shard.radius,
                                  y: shard.height + sin(t * 0.7 + shard.theta) * 0.02)
            let breathe = sin(t * 1.4 + shard.theta) * 0.004
            let x = scatter.x + (shard.target.x - scatter.x) * p
            let y = scatter.y + (shard.target.y + breathe - scatter.y) * p
            let z = depth * (1 - p)
            return (shard, CGPoint(x: center.x + x * unit, y: center.y + y * unit), z, p, angle)
        }
        .sorted { $0.2 < $1.2 }

        for (shard, point, z, p, angle) in placed {
            let perspective = 1 / (1.55 - 0.55 * z) // 0.48 … 1
            let scale = shard.size * perspective * (0.8 + 0.45 * p)
            let rotation = Angle.radians((angle * 2 + shard.spin) * (1 - p) + shard.rest * p)

            var path = Path()
            path.addLines(shard.outline.map { CGPoint(x: $0.x * scale, y: $0.y * scale) })
            path.closeSubpath()
            let placedPath = path
                .applying(CGAffineTransform(rotationAngle: rotation.radians))
                .applying(CGAffineTransform(translationX: point.x, y: point.y))

            // Scattered shards are silvery glass lit by depth; assembled ones take the blade gradient.
            let light = 0.25 + 0.55 * (z + 1) / 2
            let warm = shard.target.y + 0.5 // 0 top … 1 bottom
            let assembledColor = paused
                ? Color(red: 1, green: 0.78 - warm * 0.25, blue: 0.25)
                : Color(red: 1, green: 0.48 - warm * 0.34, blue: 0.27 - warm * 0.12)
            let glint = max(0, 1 - abs(sweepPosition(sweep) - (shard.target.x - shard.target.y)) * 7) * p
            let fill = Color.white.opacity(light * (1 - p) * 0.55)
            gc.fill(placedPath, with: .color(fill))
            gc.fill(placedPath, with: .color(assembledColor.opacity(p * (0.75 + 0.25 * shard.shade))))
            gc.fill(placedPath, with: .color(.white.opacity(glint * 0.9)))
            gc.stroke(placedPath, with: .color(.white.opacity(0.18 + 0.4 * light * (1 - p) + 0.12 * p)), lineWidth: 0.6)
        }
    }

    /// A diagonal light streak along the shield's cut, brightest right after a block.
    private func drawBlade(_ gc: inout GraphicsContext, size: CGSize, assembly: Double, sweep: Double) {
        guard assembly > 0.85 else { return }
        let unit = min(size.width, size.height) * 0.82
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        let a = CGPoint(x: c.x + 0.32 * unit, y: c.y - 0.31 * unit)
        let b = CGPoint(x: c.x - 0.32 * unit, y: c.y + 0.31 * unit)
        let flash = max(0, 1 - sweep / 0.8)
        let alpha = (assembly - 0.85) / 0.15 * (0.55 + 0.45 * flash)
        var line = Path()
        line.move(to: a)
        line.addLine(to: b)
        var glow = gc
        glow.addFilter(.blur(radius: 10))
        glow.stroke(line, with: .color(Color(red: 1, green: 0.6, blue: 0.45).opacity(alpha)), lineWidth: 10)
        gc.stroke(line, with: .color(.white.opacity(alpha)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
    }

    /// Perspective rings of dots on a floor plane — the "sonar" under the shield.
    private func drawDotWaves(_ gc: inout GraphicsContext, size: CGSize, t: Double, energy: Double) {
        let c = CGPoint(x: size.width / 2, y: size.height * 0.5)
        let maxR = size.width * 0.75
        let tint = phase == .paused ? Color.yellow : Color(red: 0.95, green: 0.2, blue: 0.28)
        for ring in 0..<9 {
            let travel = (Double(ring) / 9 + t * 0.04).truncatingRemainder(dividingBy: 1)
            let r = maxR * (0.25 + travel * 0.75)
            let dots = 40 + ring * 6
            for i in 0..<dots {
                let a = Double(i) / Double(dots) * .pi * 2 + t * 0.05
                let p = CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r * 0.32 + size.height * 0.18)
                let fade = (1 - travel) * (0.25 + 0.75 * (sin(a) + 1) / 2)
                let dot = Path(ellipseIn: CGRect(x: p.x - 0.9, y: p.y - 0.9, width: 1.8, height: 1.8))
                gc.fill(dot, with: .color((energy > 0.5 ? tint : .white).opacity(fade * (0.18 + 0.3 * energy))))
            }
        }
    }

    private func sweepPosition(_ sweep: Double) -> Double {
        // Travels from upper-left to lower-right across the shield in 0.6 s after a pulse.
        sweep < 0.6 ? -0.9 + sweep / 0.6 * 1.8 : 5
    }

    private func smooth(_ x: Double) -> Double { x * x * (3 - 2 * x) }
}

/// One glass fragment: where it orbits when scattered and where it sits in the shield.
private struct Shard {
    var target: CGPoint     // in unit shield space, centered on 0
    var radius: Double      // orbit radius when scattered
    var theta: Double       // orbit phase
    var speed: Double       // orbit angular speed
    var height: Double      // vertical position when scattered
    var size: Double
    var spin: Double
    var rest: Double        // resting rotation when assembled
    var delay: Double       // 0 … 0.4, staggers the assembly
    var shade: Double
    var outline: [CGPoint]  // unit polygon

    static func make(count: Int) -> [Shard] {
        var rng = SeededRandom(seed: 0x5A3_1EAF)
        var shards: [Shard] = []
        while shards.count < count {
            let p = CGPoint(x: rng.next(-0.33, 0.33), y: rng.next(-0.36, 0.36))
            guard ShieldShape.contains(p), !ShieldShape.inCut(p) else { continue }
            let vertices = Int(rng.next(3, 5.99))
            let outline = (0..<vertices).map { i -> CGPoint in
                let a = Double(i) / Double(vertices) * .pi * 2 + rng.next(-0.4, 0.4)
                let r = rng.next(0.55, 1)
                return CGPoint(x: cos(a) * r, y: sin(a) * r)
            }
            shards.append(Shard(
                target: p,
                radius: rng.next(0.22, 0.62),
                theta: rng.next(0, .pi * 2),
                speed: rng.next(0.12, 0.32) * (rng.next(0, 1) > 0.15 ? 1 : -1),
                height: rng.next(-0.42, 0.42),
                size: rng.next(6, 13),
                spin: rng.next(0, .pi * 2),
                rest: rng.next(-0.5, 0.5),
                delay: rng.next(0, 0.4),
                shade: rng.next(0, 1),
                outline: outline
            ))
        }
        return shards
    }
}

/// The icon's shield in unit space (x, y ∈ about -0.35 … 0.35), and the diagonal cut through it.
enum ShieldShape {
    static func contains(_ p: CGPoint) -> Bool {
        // Top edge dips toward the middle; sides taper to a point at the bottom.
        // Like the icon: peak at the top center, shoulders lower, flanks curving to a point.
        let y = p.y
        guard y > -0.34, y < 0.35 else { return false }
        let topEdge = -0.34 + 0.09 * pow(min(1, abs(p.x) / 0.27), 1.4)
        guard y > topEdge else { return false }
        let halfWidth = y < -0.05 ? 0.27 : 0.27 * (1 - pow((y + 0.05) / 0.40, 1.8))
        return abs(p.x) < halfWidth
    }

    /// Keep a clean gap along the blade's path (upper-right → lower-left).
    static func inCut(_ p: CGPoint) -> Bool {
        abs(p.x + p.y * 1.03) < 0.022
    }
}

private struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next(_ low: Double, _ high: Double) -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        let unit = Double(state >> 11) / Double(1 << 53)
        return low + (high - low) * unit
    }
}
