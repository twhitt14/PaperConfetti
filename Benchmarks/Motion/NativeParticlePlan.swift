import Foundation
import PaperConfetti

/// Benchmark flight plan. One piece per plan by default; optional diagnostic
/// grouping lets a few visually different pieces share a nearby flight.
struct NativeFlightGroup {
    let members: [ConfettiParticle]
    private let flights: [StudyFlight]
    let duration: Double
    let delay: Double
    let anchors: [Double]
    init(members: [ConfettiParticle]) {
        precondition(!members.isEmpty)
        self.members = members
        let flights = members.map { StudyFlight($0) }
        self.flights = flights
        duration = flights.map(\.duration).max()!
        delay = members[0].delay
        anchors = Array(Set([0, duration] + flights.flatMap(\.anchors))).sorted()
    }
    func position(at age: Double) -> CGPoint {
        var x = 0.0, y = 0.0
        for flight in flights {
            let point = flight.position(at: age); x += point.x; y += point.y
        }
        return CGPoint(x: x / Double(members.count), y: y / Double(members.count))
    }
    func opacity(at age: Double) -> Double {
        flights.reduce(0) { $0 + $1.opacity(at: age) } / Double(members.count)
    }
}

enum NativeParticlePlan {
    static let poseCount = 8
    static let maximumMembers = 3
    static let maximumSampledSeparation = 20.0
    static let probeTimes = [0.05, 0.1, 0.2, 0.35, 0.55, 0.8, 1.2, 1.8, 2.5, 3.3, 4.2]

    static func poseIndex(for particle: ConfettiParticle) -> Int {
        Int((particle.phase / (2 * .pi)) * Double(poseCount)) % poseCount
    }

    static func groups(_ particles: [ConfettiParticle], shared: Bool = false) -> [NativeFlightGroup] {
        // Default: each piece owns its complete timing/path, including independent descent.
        // The old shared-flight compromise remains a separately labeled diagnostic only.
        if !shared { return particles.map { NativeFlightGroup(members: [$0]) } }
        // Cache probes once. Keep the grouping algorithm out of animation frames.
        let probes = particles.map { p in probeTimes.map { StudyFlight.position(p, at: $0) } }
        // Nearby duration buckets avoid an all-pairs scan in the large stress cases.
        struct Bucket: Hashable {
            let x, y, delay: Double
            let launch, fall: Int
        }
        func key(_ p: ConfettiParticle, launch: Int = 0, fall: Int = 0) -> Bucket {
            Bucket(x: p.x, y: p.y, delay: p.delay,
                   launch: Int(p.launchDuration / 0.16) + launch, fall: Int(StudyFlight.fallDuration(p) / 0.16) + fall)
        }
        var buckets: [Bucket: [Int]] = [:]
        for i in particles.indices { buckets[key(particles[i]), default: []].append(i) }
        var used = [Bool](repeating: false, count: particles.count), result: [NativeFlightGroup] = []
        func distance(_ a: Int, _ b: Int) -> Double? {
            let p = particles[a], q = particles[b]
            guard p.delay == q.delay, p.x == q.x, p.y == q.y,
                  p.shape != q.shape, p.color != q.color,
                  abs(p.launchDuration - q.launchDuration) < 0.16,
                  abs(StudyFlight.fallDuration(p) - StudyFlight.fallDuration(q)) < 0.16 else { return nil }
            var worst = 0.0
            for i in probeTimes.indices {
                let delta = hypot(probes[a][i].x - probes[b][i].x, probes[a][i].y - probes[b][i].y)
                if delta > maximumSampledSeparation { return nil }
                worst = max(worst, delta)
            }
            return worst
        }
        for first in particles.indices where !used[first] {
            used[first] = true
            var candidates: [Int] = []
            for launch in -1...1 { for fall in -1...1 {
                candidates += buckets[key(particles[first], launch: launch, fall: fall)] ?? []
            } }
            candidates.sort()
            var indices = [first]
            while indices.count < maximumMembers {
                var best: Int?, bestDistance = Double.infinity
                for candidate in candidates where !used[candidate] {
                    var worst = 0.0, compatible = true
                    for member in indices {
                        guard let value = distance(member, candidate) else { compatible = false; break }
                        worst = max(worst, value)
                    }
                    if compatible && worst < bestDistance { best = candidate; bestDistance = worst }
                }
                guard let best else { break }
                indices.append(best); used[best] = true
            }
            result.append(NativeFlightGroup(members: indices.map { particles[$0] }))
        }
        return result
    }
}
