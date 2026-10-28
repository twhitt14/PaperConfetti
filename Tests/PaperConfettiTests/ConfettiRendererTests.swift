#if canImport(UIKit)
    import XCTest
    import SwiftUI
    import UIKit
    @testable import PaperConfetti

    @MainActor
    final class ConfettiRendererTests: XCTestCase {
        func testActiveUIKitOverlayPassesHitTestsThroughToTheButton() throws {
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
            let host = UIViewController()
            window.rootViewController = host
            window.isHidden = false
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }
            let button = UIButton(frame: CGRect(x: 20, y: 300, width: 300, height: 100))
            host.view.addSubview(button)
            let overlay = ConfettiLayerView(frame: host.view.bounds)
            host.view.addSubview(overlay)
            overlay.play(burst: .init(cannons: [.init(x: 150, y: 400)]), colors: [.blue])
            XCTAssertEqual(overlay.particleLayerCount, 36)
            let point = button.convert(CGPoint(x: 20, y: 20), to: window)
            XCTAssertTrue(window.hitTest(point, with: nil) === button)
            overlay.isUserInteractionEnabled = true
            XCTAssertTrue(
                window.hitTest(point, with: nil) === button,
                "Even accidental host changes cannot intercept taps")
            XCTAssertTrue(overlay.accessibilityElementsHidden)
        }

        func testMethodAPIHandlesFirstMountRepeatedSeedCancellationAndDetach() async throws {
            try XCTSkipIf(UIAccessibility.isReduceMotionEnabled)
            let controller = ConfettiController()
            let burst = ConfettiBurst(cannons: [.init(x: 100, y: 500)], seed: 42)
            XCTAssertTrue(controller.pop(burst), "A first onAppear event may precede renderer attachment")
            let host = UIHostingController(
                rootView: Color.clear.confettiOverlay(controller).environment(\.scenePhase, .active))
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
            window.rootViewController = host
            window.isHidden = false
            host.view.layoutIfNeeded()
            for _ in 0..<100 {
                if controller.isPlaying { break }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            XCTAssertTrue(controller.isPlaying)
            controller.cancel()
            XCTAssertFalse(controller.isPlaying)
            XCTAssertTrue(controller.pop(burst))
            XCTAssertTrue(controller.isPlaying, "Same seed is a new explicit pop")
            host.rootView = Color.clear.confettiOverlay(controller).environment(\.scenePhase, .inactive)
            host.view.layoutIfNeeded()
            for _ in 0..<100 {
                if !controller.isPlaying { break }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            XCTAssertFalse(controller.isPlaying)
            XCTAssertFalse(
                controller.pop(burst), "Inactive hosts drop events instead of replaying them on return")
            host.rootView = Color.clear.confettiOverlay(controller).environment(\.scenePhase, .active)
            host.view.layoutIfNeeded()
            try await Task.sleep(nanoseconds: 50_000_000)
            XCTAssertFalse(controller.isPlaying)
            window.isHidden = true
            window.rootViewController = nil
            XCTAssertFalse(controller.pop(burst), "Detached overlays cannot queue a surprise on return")
            controller.cancel()
        }

        func testParentUpdatesAndResizeDoNotRestartOrMoveFlyingParticles() throws {
            let view = ConfettiLayerView()
            let burst = ConfettiBurst(cannons: [.init(x: 40, y: 500)], seed: 42)
            view.show(burst: burst, colors: [.blue, .orange, .gray])
            let clock = try XCTUnwrap(view.layer.sublayers?.first)
            let paper = try XCTUnwrap(clock.sublayers?.first)
            let animation = try XCTUnwrap(paper.animation(forKey: "flight"))
            view.frame.size = CGSize(width: 390, height: 500)
            view.show(burst: burst, colors: [.blue, .orange, .gray])
            XCTAssertTrue(view.layer.sublayers?.first === clock)
            XCTAssertTrue(clock.sublayers?.first === paper)
            XCTAssertEqual(paper.animation(forKey: "flight")?.beginTime, animation.beginTime)
            let group = try XCTUnwrap(paper.animation(forKey: "flight") as? CAAnimationGroup)
            let positions = try XCTUnwrap(group.animations?.first as? CAKeyframeAnimation)
            XCTAssertEqual((positions.values?.first as? NSValue)?.cgPointValue, CGPoint(x: 40, y: 500))
            view.cancel()
        }
        func testCancellationRemovesAllWorkAndCannotReplayTheSameBurst() {
            let view = ConfettiLayerView()
            let burst = ConfettiBurst(cannons: [.init(x: 40, y: 500)], seed: 42)
            view.show(burst: burst, colors: [.blue])
            XCTAssertEqual(view.particleLayerCount, 36)
            view.cancel()
            XCTAssertEqual(view.particleLayerCount, 0)
            XCTAssertTrue(view.layer.sublayers?.isEmpty ?? true)
            view.show(burst: burst, colors: [.blue])
            XCTAssertEqual(view.particleLayerCount, 0)
            view.show(burst: burst, colors: [.red])
            XCTAssertEqual(view.particleLayerCount, 0, "Palette changes must not replay a completed win")
            var newBurst = burst
            newBurst.seed = 43
            view.show(burst: newBurst, colors: [.blue])
            XCTAssertEqual(view.particleLayerCount, 36)
            view.cancel()
        }
        func testReduceMotionAndInactiveSceneCreateNoParticles() {
            let view = ConfettiLayerView()
            let burst = ConfettiBurst(cannons: [.init(x: 0, y: 0)], seed: 42)
            view.show(burst: burst, colors: [.blue], enabled: false)
            XCTAssertEqual(view.particleLayerCount, 0)
            view.show(burst: burst, colors: [.blue], enabled: true)
            XCTAssertEqual(view.particleLayerCount, 0, "Do not replay a celebration on return to the app")
        }
        func testNativeRendererSupportsFlatAnd3DAndCancellationBeforeArming() async throws {
            let view = ConfettiLayerView()
            for appearance in ConfettiAppearance.allCases {
                let burst = ConfettiBurst(cannons: [.init(x: 40, y: 500)], seed: 42, appearance: appearance)
                view.play(burst: burst, colors: [.cyan, .orange])
                let clock = try XCTUnwrap(view.layer.sublayers?.first)
                let emitter = try XCTUnwrap(clock.sublayers?.first as? CAEmitterLayer)
                let group = try XCTUnwrap(emitter.animation(forKey: "flight") as? CAAnimationGroup)
                XCTAssertEqual(emitter.emitterCells?.count, 1)
                let tilt = group.animations?.compactMap { $0 as? CAPropertyAnimation }.contains { $0.keyPath == "transform.rotation.x" }
                XCTAssertEqual(tilt, appearance == .threeDimensional)
                view.cancel()
                try await Task.sleep(nanoseconds: 250_000_000)
                XCTAssertEqual(view.particleLayerCount, 0)
                XCTAssertTrue(view.layer.sublayers?.isEmpty ?? true, "A delayed readiness callback cannot resurrect a cancelled burst")
            }
        }
        func testDelayedCannonsSharePrerolledEmissionButKeepTheirFlightDelay() throws {
            let view = ConfettiLayerView()
            let burst = ConfettiBurst(cannons: [
                .init(x: 20, y: 200, count: 1), .init(x: 80, y: 200, delay: 5, count: 1)
            ], seed: 42)
            view.play(burst: burst, colors: [.cyan])
            defer { view.cancel() }
            let clock = try XCTUnwrap(view.layer.sublayers?.first)
            let emitters = try XCTUnwrap(clock.sublayers?.compactMap { $0 as? CAEmitterLayer })
            let particles = burst.particles(paletteCount: 1)
            XCTAssertEqual(clock.timeOffset, ConfettiLayerView.emissionPeriod)
            XCTAssertEqual(emitters.count, 2)
            for (emitter, particle) in zip(emitters, particles) {
                XCTAssertEqual(emitter.beginTime, 0.000001)
                XCTAssertEqual(emitter.opacity, 0, "Hide cells until their flight animation starts")
                let flight = try XCTUnwrap(emitter.animation(forKey: "flight") as? CAAnimationGroup)
                XCTAssertEqual(flight.beginTime, ConfettiLayerView.emissionPeriod + max(0.000001, particle.delay))
                let cell = try XCTUnwrap(emitter.emitterCells?.first)
                XCTAssertEqual(cell.birthRate, Float(1 / ConfettiLayerView.emissionPeriod))
                XCTAssertEqual(cell.duration, .infinity, "Do not expire emission before the render server starts")
                XCTAssertGreaterThan(Double(cell.lifetime), particle.endTime)
                XCTAssertEqual(cell.velocity, 0, "A delayed cell must not drift before launch")
            }
        }
        func testNextNativeBirthIsBeyondEvenTheLongestAllowedBurst() {
            let burst = ConfettiBurst(cannons: [.init(x: 0, y: 0, delay: 60, count: 6_000)],
                                      seed: 42, radius: 5_000, fall: 5_000,
                                      fallSpeedRange: 0.25...0.25)
            let end = burst.particles(paletteCount: 1).map(\.endTime).max()!
            XCTAssertGreaterThan(end, 300, "Exercise the maximum delay, range and slowest descent")
            XCTAssertLessThan(end + 2, ConfettiLayerView.emissionPeriod,
                              "Cleanup, including the detached-host watchdog, precedes another birth")
        }
        func testCompletedBurstReleasesItsLayers() async throws {
            let view = ConfettiLayerView()
            let burst = ConfettiBurst(cannons: [.init(x: 0, y: 0, count: 1)], seed: 42, radius: 1, fall: 1)
            view.show(burst: burst, colors: [.blue])
            let end = try XCTUnwrap(burst.particles(paletteCount: 1).map(\.endTime).max())
            try await Task.sleep(nanoseconds: UInt64((end + 2.4) * 1_000_000_000))
            XCTAssertEqual(view.particleLayerCount, 0)
        }
    }

#endif
