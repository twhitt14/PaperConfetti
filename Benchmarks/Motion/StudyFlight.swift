import Foundation
import PaperConfetti

/// Benchmark candidate. Piecewise constant acceleration, continuous position and
/// zero vertical velocity only at the apex (no dwell/easing segment).
struct StudyFlight {
    let particle: ConfettiParticle
    let dx, dy, fallDuration, duration: Double
    init(_ p: ConfettiParticle, softenEdge: Bool = true) {
        particle = p
        fallDuration = Self.fallDuration(p)
        duration = p.launchDuration + fallDuration
        if softenEdge {
            // Convolve the original outward-weighted blast with a smooth, positive
            // reach distribution. No clamp at radius: progressively fewer outliers
            // travel beyond it. Separate angular jitter feathers the cone edges too.
            let pair = Self.normalPair(p)
            let spread = 0.24
            let reach = hypot(p.dx, p.dy) * exp(spread * pair.0 - spread * spread / 2)
            let angle = atan2(p.dy, p.dx) + pair.1 * 4 * .pi / 180
            dx = cos(angle) * reach; dy = sin(angle) * reach
        } else { dx = p.dx; dy = p.dy }
    }
    private static func unit(_ p: ConfettiParticle, salt: UInt64) -> Double {
        var bits = p.phase.bitPattern ^ p.spin.bitPattern ^ salt
        bits = (bits ^ (bits >> 30)) &* 0xbf58476d1ce4e5b9
        bits = (bits ^ (bits >> 27)) &* 0x94d049bb133111eb
        bits ^= bits >> 31
        return Double(bits >> 11) / Double(UInt64(1) << 53)
    }
    private static func normalPair(_ p: ConfettiParticle) -> (Double, Double) {
        let u = max(1 / Double(UInt64(1) << 53), unit(p, salt: 0x7265_6163_682d_7635))
        let angle = unit(p, salt: 0x616e_676c_652d_7635) * 2 * .pi
        let radius = sqrt(-2 * log(u))
        return (radius * cos(angle), radius * sin(angle))
    }
    static func fallDuration(_ p: ConfettiParticle) -> Double {
        p.fallDuration * (0.8 + 0.4 * unit(p, salt: 0x6661_6c6c_7469_6d65))
    }
    static func duration(_ p: ConfettiParticle) -> Double { p.launchDuration + fallDuration(p) }
    var apex: CGPoint { CGPoint(x: particle.x + dx, y: particle.y + dy) }
    var anchors: [Double] {
        [0, min(0.025, particle.launchDuration), particle.launchDuration,
         particle.launchDuration + fallDuration * particle.fadeOutStart, duration]
    }
    func opacity(at age: Double) -> Double {
        guard age >= 0, age < duration else { return 0 }
        let descent = max(0, (age - particle.launchDuration) / fallDuration)
        let fade = max(0, (descent - particle.fadeOutStart) / (1 - particle.fadeOutStart))
        return min(1, age / 0.025) * max(0, 1 - fade * fade)
    }
    func position(at age: Double) -> CGPoint {
        let p = particle, t = min(duration, max(0, age))
        let up = min(1, t / p.launchDuration), launch = 2 * up - up * up
        let down = max(0, (t - p.launchDuration) / fallDuration)
        let sway = sin(t * 7 + p.phase) * p.flutter * sin(t / duration * .pi)
        return CGPoint(x: p.x + dx * launch + sway, y: p.y + dy * launch + p.fall * down * down)
    }
    func verticalVelocity(at age: Double) -> Double {
        if age < particle.launchDuration {
            return 2 * dy / particle.launchDuration * (1 - max(0, age) / particle.launchDuration)
        }
        return 2 * particle.fall * min(fallDuration, age - particle.launchDuration) / (fallDuration * fallDuration)
    }
    static func anchors(_ p: ConfettiParticle) -> [Double] { StudyFlight(p).anchors }
    static func opacity(_ p: ConfettiParticle, at age: Double) -> Double { StudyFlight(p).opacity(at: age) }
    static func position(_ p: ConfettiParticle, at age: Double) -> CGPoint { StudyFlight(p).position(at: age) }
    static func verticalVelocity(_ p: ConfettiParticle, at age: Double) -> Double { StudyFlight(p).verticalVelocity(at: age) }
}

/// Stress-only batching leaves the released package's 2,000-piece safety cap intact.
/// Each <=2,000-piece seeded batch is an independent burst with shared shape speeds.
enum StudyPopulation {
    static let maximumCount = 5_760
    static func particles(_ burst: ConfettiBurst, paletteCount: Int) -> [ConfettiParticle] {
        let count = burst.cannons.reduce(0) { $0 + max(0, $1.count) }
        guard count <= maximumCount, burst.cannons.count <= 5 else { return [] }
        if count <= 2_000 { return burst.particles(paletteCount: paletteCount) }
        var remaining = burst.cannons.map { max(0, $0.count) }, result: [ConfettiParticle] = []
        var batchIndex: UInt64 = 0
        while remaining.contains(where: { $0 > 0 }) {
            var batch = burst
            batch.seed = burst.seed &+ (batchIndex &* 0x9E3779B97F4A7C15)
            batch.cannons = burst.cannons.enumerated().map { index, original in
                var cannon = original
                cannon.count = min(400, remaining[index]); remaining[index] -= cannon.count
                return cannon
            }
            result += batch.particles(paletteCount: paletteCount)
            batchIndex += 1
        }
        return result
    }
}
