import CoreGraphics
import XCTest
@_spi(Testing) @testable import PaperConfetti

final class ConfettiContractTests: XCTestCase {
    func testDistributionResourcesContainPrivacyManifestAndAttribution() throws {
        let privacy = try XCTUnwrap(Bundle.module.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(contentsOf: privacy), format: nil) as? [String: Any])
        XCTAssertEqual(plist["NSPrivacyTracking"] as? Bool, false)
        for key in ["NSPrivacyTrackingDomains", "NSPrivacyCollectedDataTypes", "NSPrivacyAccessedAPITypes"] {
            XCTAssertEqual((plist[key] as? [Any])?.count, 0, key)
        }
        let notice = try XCTUnwrap(Bundle.module.url(forResource: "ThirdPartyNotices", withExtension: "txt"))
        let attribution = try String(contentsOf: notice, encoding: .utf8)
        XCTAssertTrue(attribution.contains("Simon Bachmann"))
        XCTAssertTrue(attribution.contains("MIT License"))
    }

    func testAngleConversionsAvoidIntermediateOverflow() {
        XCTAssertTrue(ConfettiAngle.degrees(.greatestFiniteMagnitude).radians.isFinite)
        let radians = Double.greatestFiniteMagnitude / 100
        XCTAssertTrue(ConfettiAngle.radians(radians).degrees.isFinite)
        XCTAssertEqual(ConfettiAngle.degrees(180).radians, .pi, accuracy: 1e-12)
        XCTAssertEqual(ConfettiAngle.radians(.pi / 2).degrees, 90, accuracy: 1e-12)
    }

    func testDistinctShapeLimitPreservesInputOrderAndIgnoresDuplicates() throws {
        let shapes = try (1...40).map { height in
            try ConfettiShape(path: CGPath(rect: CGRect(x: 0, y: 0, width: 64, height: height), transform: nil))
        }
        let duplicated = shapes.flatMap { [$0, $0] }
        let a = ConfettiBurst(cannons: [.init(origin: .zero, particleCount: 600)], seed: 42, shapes: duplicated)
        let b = ConfettiBurst(cannons: a.cannons, seed: 42, shapes: Array(shapes.prefix(32)))
        XCTAssertEqual(a.particles(paletteCount: 16), b.particles(paletteCount: 16))
        XCTAssertEqual(Set(a.particles(paletteCount: 16).map(\.shape)), Set(shapes.prefix(32)))
    }

    func testEveryMotionLimitRejectsInvalidValuesAndAcceptsBoundaries() {
        let base = ConfettiBurst(cannons: [.init(origin: .zero, particleCount: 2)], seed: 4)
        let edits: [(inout ConfettiMotion) -> Void] = [
            { $0.launchSpeedMultiplier = 0 }, { $0.launchSpeedMultiplier = .infinity },
            { $0.launchDuration = 0...1 }, { $0.launchDuration = 0.05...4.01 },
            { $0.spin = -1...1 }, { $0.tumble = 0...101 }, { $0.sizeVariation = 0...1 },
            { $0.flutter = .nan }, { $0.fadeOutStart = 1 }
        ]
        for edit in edits {
            var burst = base; edit(&burst.motion)
            XCTAssertTrue(burst.particles(paletteCount: 1).isEmpty)
        }
        for speed in [0.25, 4] {
            var burst = base
            burst.motion = .init(launchDuration: 0.05...4, launchSpeedMultiplier: speed,
                                 spin: 0...100, tumble: 0...100, sizeVariation: 0.1...3,
                                 flutter: 100, fadeOutStart: 0.95)
            let particles = burst.particles(paletteCount: 1)
            XCTAssertEqual(particles.count, 2)
            XCTAssertTrue(particles.allSatisfy { $0.endTime.isFinite && $0.endTime > 0 })
        }
    }

    func testEmitterLimitsSkipNonfiniteValuesAndClampFiniteValues() {
        let emitters: [ConfettiEmitter] = [
            .init(origin: CGPoint(x: Double.nan, y: 0)),
            .init(origin: .zero, delay: .infinity),
            .init(origin: .zero, particleCount: -1),
            .init(origin: .zero, emissionAngle: .degrees(.infinity)),
            .init(origin: .zero, spread: .degrees(.nan)),
            .init(origin: .zero, delay: -5, particleCount: 1, spread: .degrees(-400)),
            .init(origin: .zero, delay: 100, particleCount: 1)
        ]
        let particles = ConfettiBurst(cannons: emitters, seed: 42).particles(paletteCount: 20)
        XCTAssertEqual(particles.count, 2)
        XCTAssertEqual(particles.map(\.delay), [0, 60])
        XCTAssertTrue(particles.allSatisfy { (0..<16).contains($0.color) })
        let oversized = Array(repeating: ConfettiEmitter(origin: .zero, particleCount: 1), count: 40)
        XCTAssertEqual(ConfettiBurst(cannons: oversized).particles(paletteCount: 1).count, 32)
    }
}
