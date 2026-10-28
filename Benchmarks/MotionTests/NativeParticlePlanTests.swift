import XCTest
import PaperConfetti
@testable import StudyMotion

final class NativeParticlePlanTests: XCTestCase {
    private func particles(seed: UInt64 = 1001) -> [ConfettiParticle] {
        ConfettiBurst(cannons: (0..<5).map {
            ConfettiEmitter(x: Double($0) * 80 + 40, y: 500, delay: Double($0) * 0.1,
                            count: 144, angle: 90, spread: 40)
        }, seed: seed, radius: 130, fall: 320, size: 10, shapes: ConfettiShape.festive).particles(paletteCount: 3)
    }
    private func identity(_ p: ConfettiParticle) -> String { "\(p.delay):\(p.phase):\(p.dx):\(p.dy)" }

    func testGroupingPreservesEverySeededParticleExactlyOnce() {
        let original = particles(), groups = NativeParticlePlan.groups(original, shared: true)
        XCTAssertEqual(groups.flatMap(\.members).map(identity).sorted(), original.map(identity).sorted())
        XCTAssertLessThan(groups.count, original.count)
        XCTAssertTrue(groups.allSatisfy { (1...3).contains($0.members.count) })
        // Reusing originals preserves the shape-specific fall speeds and seeded palette.
        XCTAssertEqual(groups.flatMap(\.members).map(\.fallSpeed).sorted(), original.map(\.fallSpeed).sorted())
        print("Native mixed groups: \(groups.count) for \(original.count) pieces")
    }
    func testNoMatchingShapeOrColorWithinSharedFlight() {
        for group in NativeParticlePlan.groups(particles(), shared: true) {
            XCTAssertEqual(Set(group.members.map(\.shape)).count, group.members.count)
            XCTAssertEqual(Set(group.members.map(\.color)).count, group.members.count)
            XCTAssertEqual(Set(group.members.map(\.delay)).count, 1)
            for p in group.members {
                XCTAssertLessThanOrEqual(abs(StudyFlight.fallDuration(p) - StudyFlight.fallDuration(group.members[0])), 0.16)
            }
        }
    }
    func testGroupingAndPosesAreDeterministicButChangeWithSeed() {
        func signature(_ seed: UInt64) -> [[String]] { NativeParticlePlan.groups(particles(seed: seed), shared: true).map { $0.members.map(identity) } }
        XCTAssertEqual(signature(1001), signature(1001))
        XCTAssertNotEqual(signature(1001), signature(1002))
        XCTAssertEqual(Set(particles().map(NativeParticlePlan.poseIndex)), Set(0..<NativeParticlePlan.poseCount))
        XCTAssertTrue(particles().contains { $0.spin < 0 })
        XCTAssertTrue(particles().contains { $0.spin > 0 })
    }
    func testMeanFlightStaysNearOriginalPathsAndHasFiniteBoundedOpacity() {
        var worst = 0.0
        for group in NativeParticlePlan.groups(particles(), shared: true) {
            XCTAssertEqual(group.anchors.first, 0)
            XCTAssertEqual(group.anchors.last, group.duration)
            XCTAssertEqual(group.opacity(at: group.duration), 0, accuracy: 0.000001)
            for step in 0...300 {
                let age = group.duration * Double(step) / 300
                let center = group.position(at: age)
                XCTAssertTrue(center.x.isFinite && center.y.isFinite)
                XCTAssertTrue((0...1).contains(group.opacity(at: age)))
                for p in group.members {
                    let point = StudyFlight.position(p, at: age)
                    worst = max(worst, hypot(center.x - point.x, center.y - point.y))
                }
            }
        }
        // Dense samples catch errors between the planner's cheaper probes.
        XCTAssertLessThan(worst, 24)
        print("Maximum mixed-flight deviation from candidate: \(worst) pt")
    }
    func testDefaultKeepsEveryParticlesOwnTiming() {
        let original = particles(), flights = NativeParticlePlan.groups(original)
        XCTAssertEqual(flights.count, original.count)
        XCTAssertTrue(flights.allSatisfy { $0.members.count == 1 })
        XCTAssertEqual(flights.map(\.duration), original.map(StudyFlight.duration))
        XCTAssertGreaterThan(Set(original.map(StudyFlight.fallDuration)).count, 700)
        XCTAssertGreaterThan(Set(original.map(\.launchDuration)).count, 700)
        for sameShape in Dictionary(grouping: original, by: \.shape).values {
            XCTAssertEqual(Set(sameShape.map(StudyFlight.fallDuration)).count, sameShape.count)
            XCTAssertTrue(sameShape.contains { StudyFlight.fallDuration($0) < $0.fallDuration })
            XCTAssertTrue(sameShape.contains { StudyFlight.fallDuration($0) > $0.fallDuration })
        }
        XCTAssertTrue(original.allSatisfy {
            (0.8...1.2).contains(StudyFlight.fallDuration($0) / $0.fallDuration)
        })
    }
    func testEmptyAndSingleInputs() {
        XCTAssertTrue(NativeParticlePlan.groups([]).isEmpty)
        let p = particles()[0], group = NativeParticlePlan.groups([p])[0]
        for age in NativeParticlePlan.probeTimes {
            let exact = StudyFlight.position(p, at: age)
            XCTAssertEqual(group.position(at: age).x, exact.x)
            XCTAssertEqual(group.position(at: age).y, exact.y)
            XCTAssertEqual(group.opacity(at: age), StudyFlight.opacity(p, at: age))
        }
    }
}
