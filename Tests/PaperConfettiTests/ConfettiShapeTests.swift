import CoreGraphics
import XCTest
@_spi(Testing) @testable import PaperConfetti

final class ConfettiShapeTests: XCTestCase {
    func testCustomPathSnapshotsGeometryAndUsesGeometryForIdentity() throws {
        let path = CGMutablePath()
        path.addRect(CGRect(x: 10, y: 20, width: 40, height: 20))
        let first = try ConfettiShape(path: path, name: "One")
        let same = try ConfettiShape(path: path, name: "Different label")
        XCTAssertEqual(first, same)
        XCTAssertEqual(first.width, 1)
        XCTAssertEqual(first.height, 0.5)
        path.addEllipse(in: CGRect(x: 0, y: 0, width: 20, height: 20))
        let changed = try ConfettiShape(path: path, name: "One")
        XCTAssertNotEqual(first, changed)
        XCTAssertEqual(first, same, "Mutating the source path cannot mutate a cached shape")
    }

    func testRejectsEmptyDegenerateAndExcessivelyComplexPaths() {
        XCTAssertThrowsError(try ConfettiShape(path: CGMutablePath()))
        let line = CGMutablePath(); line.move(to: .zero); line.addLine(to: CGPoint(x: 10, y: 0))
        XCTAssertThrowsError(try ConfettiShape(path: line))
        let huge = CGMutablePath(); huge.move(to: .zero)
        for i in 0..<513 { huge.addLine(to: CGPoint(x: i % 2, y: i)) }
        XCTAssertThrowsError(try ConfettiShape(path: huge)) { XCTAssertEqual($0 as? ConfettiShape.PathError, .tooComplex) }
    }

    func testCustomShapesUseDeterministicBoundedPhysics() throws {
        let path = CGPath(ellipseIn: CGRect(x: 0, y: 0, width: 1, height: 1), transform: nil)
        let shape = try ConfettiShape(path: path)
        let burst = ConfettiBurst(cannons: [.init(x: 100, y: 300, count: 100)], seed: 123, shapes: [shape, .star])
        let pieces = burst.particles(paletteCount: 3)
        XCTAssertEqual(pieces, burst.particles(paletteCount: 3))
        XCTAssertEqual(Set(pieces.map(\.shape)), Set([shape, .star]))
        XCTAssertTrue(pieces.allSatisfy { $0.position(at: $0.lifetime / 2).y.isFinite })
    }

    func testLaunchSpeedChangesOnlyTheAscent() {
        let normal = ConfettiBurst(cannons: [.init(x: 100, y: 300)], seed: 5)
        var faster = normal; faster.motion.launchSpeedMultiplier = 1.1
        for (a,b) in zip(normal.particles(paletteCount: 3), faster.particles(paletteCount: 3)) {
            XCTAssertEqual(b.launchDuration, a.launchDuration / 1.1, accuracy: 0.000001)
            XCTAssertEqual(a.dx, b.dx); XCTAssertEqual(a.dy, b.dy)
            XCTAssertEqual(a.fallDuration, b.fallDuration); XCTAssertEqual(a.delay, b.delay)
        }
    }

    func testDropCoversWidthAndFallsContinuouslyWithACompleteFade() {
        var drop = ConfettiBurst(cannons: [.init(x: 0, y: 0, count: 220)], seed: 42, fall: 300)
        drop.dropRegion = CGRect(x: 0, y: 0, width: 390, height: 800); drop.dropDuration = 2.8
        let particles = drop.particles(paletteCount: 3)
        XCTAssertEqual(particles.count, 220)
        XCTAssertEqual(particles, drop.particles(paletteCount: 3))
        XCTAssertEqual(Set(particles.map { Int($0.x / 39) }).count, 10, "Every tenth of the width receives paper")
        XCTAssertGreaterThan(Set(particles.map(\.delay)).count, 200)
        for p in particles {
            XCTAssertTrue((0...2.8).contains(p.delay))
            XCTAssertEqual(p.launchDuration, 0)
            let start = p.position(at: 0), middle = p.position(at: p.lifetime / 2), end = p.position(at: p.lifetime)
            XCTAssertLessThan(start.y, 0); XCTAssertGreaterThan(middle.y, start.y); XCTAssertGreaterThan(end.y, middle.y)
            XCTAssertLessThan(p.opacity(at: p.lifetime * 0.99), 0.04)
            XCTAssertEqual(p.opacity(at: p.lifetime), 0)
        }
    }
}
