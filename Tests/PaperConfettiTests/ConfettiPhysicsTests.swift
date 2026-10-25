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
    func testCachedTimingCurvesMatchDirectEvaluationWithinASmallFractionOfAPoint() {
        let particles = ConfettiBurst(cannons: [.init(x: 100, y: 500)], seed: 42).particles(paletteCount: 3)
        for particle in particles {
            for step in 0...300 {
                let age = Double(step) / 300 * particle.lifetime
                let launch = ConfettiParticle.bezier(
                    age / particle.launchDuration, x1: 0.1, y1: 0.8, x2: 0, y2: 1)
                let rain = ConfettiParticle.bezier(
                    (age - particle.launchDuration) / particle.fallDuration, x1: 0.12, y1: 0, x2: 0.39, y2: 0)
                let flutter =
                    sin(age * 7 + particle.phase) * 5 * sin(min(1, max(0, age / particle.lifetime)) * .pi)
                let actual = particle.position(at: age)
                XCTAssertEqual(actual.x, particle.x + particle.dx * launch + flutter, accuracy: 0.05)
                XCTAssertEqual(
                    actual.y, particle.y + particle.dy * launch + particle.fall * rain, accuracy: 0.05)
            }
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
            XCTAssertEqual(Set(matching.map(\.fallDuration)).count, 1)
            let first = matching[0]
            // The descent displacement matches at the same age after launch,
            // even though origins, launch distances and delays differ.
            let descent = first.position(at: first.launchDuration + 0.9).y - first.y - first.dy
            for particle in matching {
                XCTAssertEqual(
                    particle.position(at: particle.launchDuration + 0.9).y - particle.y - particle.dy,
                    descent, accuracy: 0.001)
            }
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
        XCTAssertEqual(huge.particles(paletteCount: 3).count, 2_000)
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
