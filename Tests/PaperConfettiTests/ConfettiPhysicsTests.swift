import XCTest

@testable import PaperConfetti

final class ConfettiPhysicsTests: XCTestCase {
    func testDeterministicBoundedParticlesAndPalette() {
        let burst = ConfettiBurst(
            cannons: (0..<5).map { .init(x: Double($0) * 70, y: 500, delay: Double($0) * 0.1) }, seed: 42)
        let particles = burst.particles(paletteCount: 3)
        XCTAssertEqual(particles.count, 180)
        XCTAssertEqual(particles, burst.particles(paletteCount: 3))
        XCTAssertTrue(
            particles.allSatisfy { (0..<3).contains($0.color) && ConfettiShape.festive.contains($0.shape) })
        XCTAssertEqual(particles[144].delay, 0.4)
    }
    func testFlightsStartAtSourceRiseThenFallAndDisappear() {
        let particles = ConfettiBurst(cannons: [.init(x: 100, y: 500)], seed: 99).particles(paletteCount: 3)
        for p in particles {
            XCTAssertEqual(p.position(at: 0).x, 100, accuracy: 0.01)
            XCTAssertEqual(p.position(at: 0).y, 500, accuracy: 0.02)
            XCTAssertLessThan(p.position(at: 0.35).y, 500)
            XCTAssertGreaterThan(p.position(at: p.lifetime).y, 500)
            XCTAssertEqual(p.opacity(at: -1), 0)
            XCTAssertEqual(p.opacity(at: p.lifetime), 0)
            for step in 0...100 {
                let time = Double(step) / 100 * p.lifetime
                XCTAssertTrue(p.position(at: time).x.isFinite)
                XCTAssertTrue((0...1).contains(p.opacity(at: time)))
            }
        }
    }
    func testPathIsIndependentOfFrameRateAndSourceMutation() {
        var burst = ConfettiBurst(cannons: [.init(x: 100, y: 500)], seed: 42)
        let particle = burst.particles(paletteCount: 3)[0]
        let expected = particle.position(at: 0.5)
        for i in 0..<120 { _ = particle.position(at: Double(i) / 120) }
        burst.cannons[0].y = 200
        XCTAssertEqual(particle.position(at: 0.5).y, expected.y)
        XCTAssertEqual(particle.y, 500)
    }
    func testParabolicPathHasNoApexHoldAndContinuousPosition() {
        let particles = ConfettiBurst(cannons: [.init(x: 100, y: 500)], seed: 42).particles(paletteCount: 3)
        for p in particles {
            let apex = p.position(at: p.launchDuration).y
            XCTAssertEqual(apex, p.y + p.dy, accuracy: 1e-9)
            XCTAssertGreaterThan(p.position(at: p.launchDuration - 0.01).y, apex)
            XCTAssertGreaterThan(p.position(at: p.launchDuration + 0.01).y, apex)
            XCTAssertEqual(p.position(at: p.launchDuration - 0.0001).y,
                           p.position(at: p.launchDuration + 0.0001).y, accuracy: 0.0001)
            let t = p.launchDuration * 0.5
            XCTAssertEqual(p.position(at: t).y, p.y + p.dy * 0.75, accuracy: 1e-9)
            XCTAssertEqual(p.position(at: p.launchDuration + p.fallDuration * 0.5).y,
                           apex + p.fall * 0.25, accuracy: 1e-9)
        }
    }
    func testSoftBlastTailTapersAndAppearanceDefaultsTo3D() {
        var distances = [Double]()
        for seed in 1...20 {
            let b = ConfettiBurst(cannons: [.init(x: 0, y: 0, count: 5760)], seed: UInt64(seed))
            XCTAssertEqual(b.appearance, .threeDimensional)
            distances += b.particles(paletteCount: 3).map { hypot($0.dx, $0.dy) / b.radius }
        }
        XCTAssertEqual(distances.reduce(0,+) / Double(distances.count), 0.783, accuracy: 0.015)
        let beyond = Double(distances.filter { $0 > 1 }.count) / Double(distances.count)
        XCTAssertTrue((0.1...0.3).contains(beyond))
        var previous = Int.max
        for start in stride(from: 1.0, to: 1.6, by: 0.1) {
            let n = distances.filter { $0 >= start && $0 < start + 0.1 }.count
            XCTAssertLessThan(n, previous); previous = n
        }
    }
    func testEveryRequestedSilhouetteIsPresentAndShapeSpeedsMatchAcrossCannons() {
        let burst = ConfettiBurst(
            cannons: [
                .init(x: 0, y: 400, count: 300),
                .init(x: 100, y: 400, delay: 0.4, count: 300),
            ], seed: 42)
        let particles = burst.particles(paletteCount: 3)
        XCTAssertEqual(Set(particles.map(\.shape)), Set(ConfettiShape.festive))
        XCTAssertEqual(ConfettiShape.festive.count, 13)
        for shape in ConfettiShape.festive {
            let matching = particles.filter { $0.shape == shape }
            XCTAssertEqual(Set(matching.map(\.fallSpeed)).count, 1)
            XCTAssertGreaterThan(Set(matching.map(\.fallDuration)).count, 1)
            let base = (burst.fall + burst.radius) / (200 * matching[0].fallSpeed)
            XCTAssertTrue(matching.allSatisfy { (0.8...1.2).contains($0.fallDuration / base) })
        }
        XCTAssertGreaterThan(Set(particles.map(\.fallSpeed)).count, 10)
        var next = burst
        next.seed = 43
        let nextSpeeds = Dictionary(grouping: next.particles(paletteCount: 3), by: \.shape)
        XCTAssertTrue(
            ConfettiShape.festive.allSatisfy { shape in
                particles.first { $0.shape == shape }!.fallSpeed != nextSpeeds[shape]!.first!.fallSpeed
            })
    }

    func testDuplicateShapeChoicesDoNotSplitTheirSpeedAndFixedSpeedIsSupported() {
        let particles = ConfettiBurst(
            cannons: [.init(x: 0, y: 0, count: 100)], seed: 42,
            shapes: [.ring, .ring, .star], fallSpeedRange: 1...1
        ).particles(paletteCount: 3)
        XCTAssertEqual(Set(particles.map(\.shape)), [.ring, .star])
        XCTAssertTrue(particles.allSatisfy { $0.fallSpeed == 1 })
        XCTAssertTrue(
            ConfettiBurst(cannons: [.init(x: 0, y: 0)], shapes: []).particles(paletteCount: 3).isEmpty)
    }

    func testInvalidInputAndHugeBudgetsAreSafe() {
        XCTAssertTrue(ConfettiBurst(cannons: [.init(x: 0, y: 0)]).particles(paletteCount: 0).isEmpty)
        XCTAssertTrue(ConfettiBurst(cannons: [.init(x: .nan, y: 0)]).particles(paletteCount: 3).isEmpty)
        XCTAssertTrue(
            ConfettiBurst(cannons: [.init(x: 0, y: 0)], radius: .infinity).particles(paletteCount: 3).isEmpty)
        XCTAssertTrue(
            ConfettiBurst(cannons: [.init(x: 0, y: 0, count: -1)]).particles(paletteCount: 3).isEmpty)
        let huge = ConfettiBurst(cannons: Array(repeating: .init(x: 0, y: 0, count: 10_000), count: 100))
        XCTAssertEqual(huge.particles(paletteCount: 3).count, 6_000)
    }
    func testExtremeFiniteAnglesCannotOverflowAndInvalidMotionEmitsNothing() {
        let particles = ConfettiBurst(cannons: [
            .init(
                x: 100, y: 100,
                angle: Double.greatestFiniteMagnitude)
        ]).particles(paletteCount: 1_000)
        XCTAssertEqual(particles.count, 36)
        XCTAssertTrue(
            particles.allSatisfy { $0.position(at: 0.2).x.isFinite && $0.position(at: 0.2).y.isFinite })
        XCTAssertTrue(particles.allSatisfy { (0..<16).contains($0.color) })
        let invalid: [ConfettiMotion] = [
            .init(launchDuration: 0...1), .init(spin: 0...Double.infinity),
            .init(flutter: .nan), .init(fadeOutStart: 1), .init(sizeVariation: 0...1),
        ]
        for motion in invalid {
            XCTAssertTrue(
                ConfettiBurst(cannons: [.init(x: 0, y: 0)], motion: motion).particles(paletteCount: 3).isEmpty
            )
        }
    }

}
