import Foundation
import PaperConfetti

/// Adapter around the production 0.2 flight; no second physics implementation.
struct StudyFlight {
    let particle: ConfettiParticle
    init(_ p: ConfettiParticle) { particle = p }
    var dx: Double { particle.dx }
    var dy: Double { particle.dy }
    var fallDuration: Double { particle.fallDuration }
    var duration: Double { particle.lifetime }
    var apex: CGPoint { CGPoint(x: particle.x + dx, y: particle.y + dy) }
    var anchors: [Double] {
        [0, min(0.025, particle.launchDuration), particle.launchDuration,
         particle.launchDuration + fallDuration * particle.fadeOutStart, duration]
    }
    func opacity(at age: Double) -> Double { particle.opacity(at: age) }
    func position(at age: Double) -> CGPoint {
        let p = particle.position(at: age); return CGPoint(x: p.x, y: p.y)
    }
    func verticalVelocity(at age: Double) -> Double {
        if age < particle.launchDuration { return 2 * dy / particle.launchDuration * (1 - max(0, age) / particle.launchDuration) }
        return 2 * particle.fall * min(fallDuration, age - particle.launchDuration) / (fallDuration * fallDuration)
    }
    static func fallDuration(_ p: ConfettiParticle) -> Double { p.fallDuration }
    static func duration(_ p: ConfettiParticle) -> Double { p.lifetime }
    static func anchors(_ p: ConfettiParticle) -> [Double] { StudyFlight(p).anchors }
    static func opacity(_ p: ConfettiParticle, at age: Double) -> Double { p.opacity(at: age) }
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
