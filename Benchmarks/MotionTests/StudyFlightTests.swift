import XCTest
import PaperConfetti
@testable import StudyMotion

final class StudyFlightTests: XCTestCase {
    private func burst(count: Int = 720, seed: UInt64 = 1001) -> ConfettiBurst {
        ConfettiBurst(cannons: (0..<5).map {
            ConfettiEmitter(x: Double($0) * 80 + 40, y: 500, delay: Double($0) * 0.1,
                            count: count / 5, angle: 90, spread: 40)
        }, seed: seed, radius: 130, fall: 320, size: 10, shapes: ConfettiShape.festive)
    }
    func testApexHasContinuousPositionAndVelocityWithoutDwell() {
        for p in burst().particles(paletteCount: 3) {
            let apex = p.launchDuration
            XCTAssertEqual(StudyFlight.position(p, at: apex).y, StudyFlight(p).apex.y, accuracy: 1e-9)
            XCTAssertEqual(StudyFlight.verticalVelocity(p, at: apex), 0, accuracy: 1e-9)
            XCTAssertLessThan(StudyFlight.verticalVelocity(p, at: apex - 0.001), 0)
            XCTAssertGreaterThan(StudyFlight.verticalVelocity(p, at: apex + 0.001), 0)
            XCTAssertLessThan(abs(StudyFlight.position(p, at: apex - 0.0001).y - StudyFlight.position(p, at: apex + 0.0001).y), 0.0001)
            XCTAssertEqual(StudyFlight.position(p, at: StudyFlight.duration(p)).y, StudyFlight(p).apex.y + p.fall, accuracy: 1e-9)
        }
    }
    func testConstantAccelerationInEachPhaseAndLessTimeNearTheTop() {
        var oldDwell = 0.0, newDwell = 0.0
        for (p, old) in zip(burst().particles(paletteCount: 3), LegacyConfettiBurst(burst()).particles(paletteCount: 3)) {
            func acceleration(_ t: Double) -> Double {
                (StudyFlight.verticalVelocity(p, at: t + 0.001) - StudyFlight.verticalVelocity(p, at: t)) / 0.001
            }
            XCTAssertEqual(acceleration(p.launchDuration * 0.25), acceleration(p.launchDuration * 0.75), accuracy: 1e-7)
            XCTAssertEqual(acceleration(p.launchDuration + StudyFlight.fallDuration(p) * 0.25), acceleration(p.launchDuration + StudyFlight.fallDuration(p) * 0.75), accuracy: 1e-7)
            for step in 0..<1000 {
                let t = max(p.lifetime, StudyFlight.duration(p)) * Double(step) / 1000, top = p.y + p.dy
                if abs(old.position(at: t).y - old.y - old.dy) <= 5 { oldDwell += max(p.lifetime, StudyFlight.duration(p)) / 1000 }
                if abs(StudyFlight(p).position(at: t).y - top) <= 5 { newDwell += max(p.lifetime, StudyFlight.duration(p)) / 1000 }
            }
        }
        XCTAssertLessThan(newDwell, oldDwell * 0.75)
        print("Mean within 5pt of apex: original \(oldDwell / 720)s, candidate \(newDwell / 720)s")
    }
    func testSoftEdgeTapersBeyondNominalReachWithoutMovingTheAverage() {
        var original: [Double] = [], softened: [Double] = []
        for seed in 1...20 {
            let b = burst(count: 5760, seed: UInt64(seed))
            original += LegacyConfettiBurst(b).particles(paletteCount: 3).map { hypot($0.dx, $0.dy) / 130 }
            for p in StudyPopulation.particles(b, paletteCount: 3) {
                let f = StudyFlight(p)
                softened.append(hypot(f.dx, f.dy) / 130)
                XCTAssertTrue(f.dx.isFinite && f.dy.isFinite)
                XCTAssertEqual(f.dx, StudyFlight(p).dx)
            }
        }
        let count = Double(softened.count)
        let mean = softened.reduce(0,+)/count, oldMean = original.reduce(0,+)/Double(original.count)
        XCTAssertEqual(mean, oldMean, accuracy: 0.015)
        XCTAssertTrue(original.allSatisfy { $0 <= 1 })
        let beyond = Double(softened.filter { $0 > 1 }.count)/count
        XCTAssertTrue((0.1...0.3).contains(beyond))
        var previous = Int.max
        for lower in stride(from: 1.0, to: 1.6, by: 0.1) {
            let n = softened.filter { $0 >= lower && $0 < lower + 0.1 }.count
            XCTAssertLessThan(n, previous); previous = n
        }
        print("Soft reach mean \(mean), original \(oldMean), beyond radius \(beyond)")
    }
    func testStressPopulationIsCompleteBoundedAndReproducible() {
        for count in [180, 720, 1440, 2880, 5760] {
            let b = burst(count: count)
            let first = StudyPopulation.particles(b, paletteCount: 3)
            XCTAssertEqual(first.count, count)
            XCTAssertEqual(first, StudyPopulation.particles(b, paletteCount: 3))
            XCTAssertEqual(Set(first.map(\.delay)).count, 5)
            XCTAssertTrue(first.allSatisfy { StudyFlight.position($0, at: 1).y.isFinite })
        }
        XCTAssertTrue(StudyPopulation.particles(burst(count: 10_000), paletteCount: 3).isEmpty)
        XCTAssertEqual(burst(count: 5760).particles(paletteCount: 3).count, 5760, "The native package supports this stress population")
    }
}
