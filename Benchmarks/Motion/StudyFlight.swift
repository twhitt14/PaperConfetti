import Foundation
import PaperConfetti

/// Benchmark candidate. Piecewise constant acceleration, continuous position and
/// zero vertical velocity only at the apex (no dwell/easing segment).
enum StudyFlight {
    static func fallDuration(_ p: ConfettiParticle) -> Double {
        // Independent deterministic jitter, layered over the silhouette's base speed.
        // Hash instead of reusing the rotation angle directly, avoiding visible correlation.
        var bits = p.phase.bitPattern ^ p.spin.bitPattern ^ 0x6661_6c6c_7469_6d65
        bits = (bits ^ (bits >> 30)) &* 0xbf58476d1ce4e5b9
        bits = (bits ^ (bits >> 27)) &* 0x94d049bb133111eb
        bits ^= bits >> 31
        let unit = Double(bits >> 11) / Double(UInt64(1) << 53)
        return p.fallDuration * (0.8 + 0.4 * unit)
    }
    static func duration(_ p: ConfettiParticle) -> Double { p.launchDuration + fallDuration(p) }
    static func anchors(_ p: ConfettiParticle) -> [Double] {
        [0, min(0.025, p.launchDuration), p.launchDuration,
         p.launchDuration + fallDuration(p) * p.fadeOutStart, duration(p)]
    }
    static func opacity(_ p: ConfettiParticle, at age: Double) -> Double {
        guard age >= 0, age < duration(p) else { return 0 }
        let descent = max(0, (age - p.launchDuration) / fallDuration(p))
        let fade = max(0, (descent - p.fadeOutStart) / (1 - p.fadeOutStart))
        return min(1, age / 0.025) * max(0, 1 - fade * fade)
    }
    static func position(_ p: ConfettiParticle, at age: Double) -> CGPoint {
        let t = min(duration(p), max(0, age))
        let up = min(1, t / p.launchDuration)
        let launch = 2 * up - up * up
        let down = max(0, (t - p.launchDuration) / fallDuration(p))
        let sway = sin(t * 7 + p.phase) * p.flutter * sin(t / duration(p) * .pi)
        return CGPoint(x: p.x + p.dx * launch + sway,
                       y: p.y + p.dy * launch + p.fall * down * down)
    }
    static func verticalVelocity(_ p: ConfettiParticle, at age: Double) -> Double {
        if age < p.launchDuration {
            return 2 * p.dy / p.launchDuration * (1 - max(0, age) / p.launchDuration)
        }
        return 2 * p.fall * min(fallDuration(p), age - p.launchDuration) / pow(fallDuration(p), 2)
    }
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
