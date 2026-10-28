import Foundation
import PaperConfetti

/// Benchmark-only compromise: a few visually different pieces share a nearby flight.
/// Each original particle still supplies its own shape, color, size, phase and spin.
struct NativeFlightGroup {
    let members: [ConfettiParticle]
    var duration: Double { members.map(\.lifetime).max() ?? 0 }
    var delay: Double { members[0].delay }
    var anchors: [Double] {
        Array(Set([0, duration] + members.flatMap {
            [min(0.025, $0.launchDuration), $0.launchDuration,
             $0.launchDuration + $0.fallDuration * $0.fadeOutStart, $0.lifetime]
        })).sorted()
    }
    func position(at age: Double) -> CGPoint {
        let points = members.map { $0.position(at: age) }
        return CGPoint(x: points.reduce(0) { $0 + $1.x } / Double(points.count),
                       y: points.reduce(0) { $0 + $1.y } / Double(points.count))
    }
    func opacity(at age: Double) -> Double {
        members.reduce(0) { $0 + $1.opacity(at: age) } / Double(members.count)
    }
}

enum NativeParticlePlan {
    static let poseCount = 8
    static let maximumMembers = 3
    static let maximumSampledSeparation = 24.0
    static let probeTimes = [0.05, 0.1, 0.2, 0.35, 0.55, 0.8, 1.2, 1.8, 2.5, 3.3, 4.2]

    static func poseIndex(for particle: ConfettiParticle) -> Int {
        Int((particle.phase / (2 * .pi)) * Double(poseCount)) % poseCount
    }

    static func groups(_ particles: [ConfettiParticle]) -> [NativeFlightGroup] {
        // Cache probes once. Keep the grouping algorithm out of animation frames.
        let probes = particles.map { p in probeTimes.map { p.position(at: $0) } }
        var used = Set<Int>(), result: [NativeFlightGroup] = []
        func distance(_ a: Int, _ b: Int) -> Double? {
            let p = particles[a], q = particles[b]
            guard p.delay == q.delay, p.x == q.x, p.y == q.y,
                  p.shape != q.shape, p.color != q.color,
                  abs(p.launchDuration - q.launchDuration) < 0.16,
                  abs(p.fallDuration - q.fallDuration) < 0.16 else { return nil }
            var worst = 0.0
            for i in probeTimes.indices {
                let delta = hypot(probes[a][i].x - probes[b][i].x, probes[a][i].y - probes[b][i].y)
                if delta > maximumSampledSeparation { return nil }
                worst = max(worst, delta)
            }
            return worst
        }
        for first in particles.indices where !used.contains(first) {
            used.insert(first)
            var indices = [first]
            while indices.count < maximumMembers {
                var best: Int?, bestDistance = Double.infinity
                for candidate in particles.indices where !used.contains(candidate) {
                    var worst = 0.0, compatible = true
                    for member in indices {
                        guard let value = distance(member, candidate) else { compatible = false; break }
                        worst = max(worst, value)
                    }
                    if compatible && worst < bestDistance { best = candidate; bestDistance = worst }
                }
                guard let best else { break }
                indices.append(best); used.insert(best)
            }
            result.append(NativeFlightGroup(members: indices.map { particles[$0] }))
        }
        return result
    }
}
