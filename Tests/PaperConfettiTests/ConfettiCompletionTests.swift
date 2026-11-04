#if canImport(UIKit)
    import SwiftUI
    import UIKit
    import XCTest
    @testable import PaperConfetti

    @MainActor
    final class ConfettiCompletionTests: XCTestCase {
        private func shortBurst(delay: Double = 0) -> ConfettiBurst {
            ConfettiBurst(
                cannons: [.init(x: 100, y: 300, delay: delay, count: 1)], seed: 42,
                radius: 1, fall: 1, motion: .init(launchDuration: 0.05...0.05))
        }

        private func eventually(
            timeout: TimeInterval = 3, file: StaticString = #filePath, line: UInt = #line,
            _ condition: () -> Bool
        ) async throws {
            let deadline = Date().addingTimeInterval(timeout)
            while !condition(), Date() < deadline {
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            XCTAssertTrue(condition(), "Timed out waiting for the lifecycle outcome", file: file, line: line)
        }

        func testOrdinaryPopFinishesAfterCleanupAndNeverCallsInline() async throws {
            let controller = ConfettiController()
            let host = CompletionHost(controller)
            defer { host.close() }
            try await eventually { host.renderer != nil }
            var outcomes: [ConfettiOutcome] = []
            var returned = false
            let accepted = controller.pop(configuration: .init(
                count: 1, radius: 1, fall: 1, motion: .init(launchDuration: 0.05...0.05)
            )) { outcome in
                XCTAssertTrue(returned)
                XCTAssertTrue(Thread.isMainThread)
                XCTAssertFalse(controller.isPlaying)
                XCTAssertEqual(host.renderer?.particleLayerCount, 0)
                XCTAssertTrue(host.renderer?.layer.sublayers?.isEmpty ?? true)
                outcomes.append(outcome)
            }
            returned = true
            XCTAssertTrue(accepted)
            XCTAssertTrue(outcomes.isEmpty)
            try await eventually { !outcomes.isEmpty }
            controller.cancel()
            controller.cancel()
            try await Task.sleep(nanoseconds: 100_000_000)
            XCTAssertEqual(outcomes, [.finished])
        }

        func testNaturalCompletionIncludesTheLastDelayedCannon() async throws {
            let controller = ConfettiController()
            let host = CompletionHost(controller)
            defer { host.close() }
            try await eventually { host.renderer != nil }
            let burst = ConfettiBurst(
                cannons: [.init(x: 40, y: 300, count: 1),
                          .init(x: 100, y: 300, delay: 0.4, count: 1)], seed: 42,
                radius: 1, fall: 1, motion: .init(launchDuration: 0.05...0.05))
            let end = try XCTUnwrap(burst.particles(paletteCount: 1).map(\.endTime).max())
            let started = CACurrentMediaTime()
            var outcomes: [ConfettiOutcome] = []
            controller.pop(burst, colors: [.blue]) { outcome in
                XCTAssertGreaterThanOrEqual(CACurrentMediaTime() - started, end)
                outcomes.append(outcome)
            }
            try await Task.sleep(nanoseconds: 200_000_000)
            XCTAssertTrue(outcomes.isEmpty, "The early cannon must not finish the whole request")
            try await eventually { !outcomes.isEmpty }
            XCTAssertEqual(outcomes, [.finished])
        }

        func testReduceMotionSettlesBothPremountAndMountedRequestsWithoutParticles() async throws {
            let controller = ConfettiController()
            var queued: [ConfettiOutcome] = []
            XCTAssertTrue(controller.pop { queued.append($0) })
            let host = CompletionHost(controller, reduceMotion: true)
            defer { host.close() }
            try await eventually { !queued.isEmpty }
            XCTAssertEqual(queued, [.reducedMotion])
            XCTAssertFalse(controller.isPlaying)
            var mounted: [ConfettiOutcome] = []
            XCTAssertFalse(controller.pop { mounted.append($0) })
            XCTAssertTrue(mounted.isEmpty, "Even a skipped request never calls user code inline")
            try await eventually { !mounted.isEmpty }
            XCTAssertEqual(mounted, [.reducedMotion])
            XCTAssertEqual(host.renderer?.particleLayerCount, 0)
        }

        func testInactiveHostIsNotMistakenForAnAccessibilityCompletion() async throws {
            let controller = ConfettiController()
            var queued: [ConfettiOutcome] = []
            XCTAssertTrue(controller.pop { queued.append($0) })
            let host = CompletionHost(controller, reduceMotion: true, scenePhase: .inactive)
            defer { host.close() }
            try await eventually { !queued.isEmpty }
            XCTAssertEqual(queued, [.notPresented])
            var rejected: [ConfettiOutcome] = []
            XCTAssertFalse(controller.pop { rejected.append($0) })
            try await eventually { !rejected.isEmpty }
            XCTAssertEqual(rejected, [.notPresented])
            XCTAssertFalse(controller.isPlaying)
        }

        func testReplacementSettlesTheOldRequestWithoutFinishingTheNewOne() async throws {
            let controller = ConfettiController()
            let host = CompletionHost(controller)
            defer { host.close() }
            try await eventually { host.renderer != nil }
            var first: [ConfettiOutcome] = []
            var second: [ConfettiOutcome] = []
            controller.pop(shortBurst(delay: 0.5)) { first.append($0) }
            controller.pop(shortBurst()) { second.append($0) }
            try await eventually { !first.isEmpty && !second.isEmpty }
            XCTAssertEqual(first, [.cancelled])
            XCTAssertEqual(second, [.finished])
            // Give the replaced request's old cleanup deadline a chance to arrive.
            try await Task.sleep(nanoseconds: 600_000_000)
            XCTAssertEqual(first, [.cancelled])
            XCTAssertEqual(second, [.finished])
        }

        func testAReplacementCallbackCanSafelyStartAnotherPop() async throws {
            let controller = ConfettiController()
            let host = CompletionHost(controller)
            defer { host.close() }
            try await eventually { host.renderer != nil }
            var first: [ConfettiOutcome] = []
            var second: [ConfettiOutcome] = []
            var third: [ConfettiOutcome] = []
            let burst = shortBurst()
            controller.pop(burst) { outcome in
                first.append(outcome)
                controller.pop(burst) { third.append($0) }
            }
            controller.pop(burst) { second.append($0) }
            try await eventually { !first.isEmpty && !second.isEmpty && !third.isEmpty }
            XCTAssertEqual(first, [.cancelled])
            XCTAssertEqual(second, [.cancelled])
            XCTAssertEqual(third, [.finished], "Reentrant caller code must not be overwritten by an older pop")
        }

        func testPendingReplacementAndExplicitCancellationEachResolveExactlyOnce() async throws {
            let controller = ConfettiController()
            var first: [ConfettiOutcome] = []
            var second: [ConfettiOutcome] = []
            XCTAssertTrue(controller.pop { first.append($0) })
            XCTAssertTrue(controller.pop { second.append($0) })
            controller.cancel()
            controller.cancel()
            try await eventually { !first.isEmpty && !second.isEmpty }
            XCTAssertEqual(first, [.cancelled])
            XCTAssertEqual(second, [.cancelled])
        }

        func testDroppingAnUnmountedControllerSettlesItsPendingCallback() async throws {
            var controller: ConfettiController? = ConfettiController()
            weak var releasedController = controller
            var outcomes: [ConfettiOutcome] = []
            controller?.pop { outcomes.append($0) }
            controller = nil
            XCTAssertNil(releasedController)
            try await eventually { !outcomes.isEmpty }
            XCTAssertEqual(outcomes, [.cancelled])
        }

        func testEmptyOrInvalidBurstsAreNotReportedAsFinished() async throws {
            let controller = ConfettiController()
            let host = CompletionHost(controller)
            defer { host.close() }
            try await eventually { host.renderer != nil }
            var outcomes: [ConfettiOutcome] = []
            let empty = ConfettiBurst(cannons: [])
            XCTAssertTrue(controller.pop(empty) { outcomes.append($0) })
            XCTAssertTrue(controller.pop(shortBurst(), colors: []) { outcomes.append($0) })
            XCTAssertTrue(controller.pop(configuration: .init(count: 0)) { outcomes.append($0) })
            try await eventually { outcomes.count == 3 }
            XCTAssertEqual(outcomes, [.notPresented, .notPresented, .notPresented])
            XCTAssertFalse(controller.isPlaying)
        }

        func testPolicyChangesCancelAFlightAndNeverReplayIt() async throws {
            for reduceMotion in [false, true] {
                let controller = ConfettiController()
                let host = CompletionHost(controller)
                defer { host.close() }
                try await eventually { host.renderer != nil }
                var outcomes: [ConfettiOutcome] = []
                controller.pop(shortBurst(delay: 0.4)) { outcomes.append($0) }
                XCTAssertTrue(controller.isPlaying)
                host.update(reduceMotion: reduceMotion, scenePhase: reduceMotion ? .active : .inactive)
                try await eventually { !outcomes.isEmpty }
                XCTAssertEqual(outcomes, [.cancelled])
                XCTAssertFalse(controller.isPlaying)
                host.update(reduceMotion: false, scenePhase: .active)
                try await Task.sleep(nanoseconds: 850_000_000)
                XCTAssertFalse(controller.isPlaying)
                XCTAssertEqual(outcomes, [.cancelled])
            }
        }

        func testRemovingTheHostCancelsRatherThanCompletesAndRejectsLaterRequests() async throws {
            let controller = ConfettiController()
            let host = CompletionHost(controller)
            defer { host.close() }
            try await eventually { host.renderer != nil }
            var active: [ConfettiOutcome] = []
            controller.pop(shortBurst()) { active.append($0) }
            host.close()
            try await eventually { !active.isEmpty }
            XCTAssertEqual(active, [.cancelled])
            var rejected: [ConfettiOutcome] = []
            XCTAssertFalse(controller.pop { rejected.append($0) })
            try await eventually { !rejected.isEmpty }
            XCTAssertEqual(rejected, [.notPresented])
        }

        func testCancellationBeforeReadinessNeverTurnsIntoNaturalCompletion() async throws {
            let controller = ConfettiController()
            let host = CompletionHost(controller)
            defer { host.close() }
            try await eventually { host.renderer != nil }
            var outcomes: [ConfettiOutcome] = []
            controller.pop(shortBurst()) { outcomes.append($0) }
            controller.cancel()
            try await eventually { !outcomes.isEmpty }
            try await Task.sleep(nanoseconds: 600_000_000)
            XCTAssertEqual(outcomes, [.cancelled])
            XCTAssertFalse(controller.isPlaying)
            XCTAssertTrue(host.renderer?.layer.sublayers?.isEmpty ?? true)
        }

        func testRendererThatNeverBecomesReadyReportsNotPresented() async throws {
            let view = ConfettiLayerView()
            var outcomes: [ConfettiOutcome] = []
            view.play(burst: shortBurst(), colors: [.blue], completion: ConfettiCompletion { outcomes.append($0) })
            try await eventually(timeout: 4) { !outcomes.isEmpty }
            XCTAssertEqual(outcomes, [.notPresented])
            XCTAssertNil(view.scheduledStartDelay)
            XCTAssertEqual(view.particleLayerCount, 0)
            view.cancel()
            try await Task.sleep(nanoseconds: 100_000_000)
            XCTAssertEqual(outcomes, [.notPresented])
        }

        func testDroppingAnUnreadyRendererSettlesTheCallback() async throws {
            var view: ConfettiLayerView? = ConfettiLayerView()
            weak var releasedView = view
            var outcomes: [ConfettiOutcome] = []
            view?.play(burst: shortBurst(), colors: [.blue], completion: ConfettiCompletion { outcomes.append($0) })
            view = nil
            XCTAssertNil(releasedView)
            try await eventually { !outcomes.isEmpty }
            XCTAssertEqual(outcomes, [.cancelled])
        }

        func testExistingMethodReferencesKeepTheirOriginalTypes() {
            let controller = ConfettiController()
            let ordinary: (CGPoint?, ConfettiConfiguration) -> Bool = controller.pop
            let advanced: (ConfettiBurst, [Color]) -> Bool = controller.pop
            XCTAssertTrue(ordinary(nil, .init()))
            XCTAssertTrue(advanced(shortBurst(), [.blue]))
            controller.cancel()
        }
    }

    // Exercise the controller's actual bridge inputs with a real UIKit renderer.
    // accessibilityReduceMotion is a read-only SwiftUI environment value; do not
    // change global Simulator settings just to test the two policy states.
    @MainActor
    private final class CompletionHost {
        let controller: ConfettiController
        let host = UIViewController()
        let window: UIWindow
        let renderer: ConfettiLayerView?

        init(_ controller: ConfettiController, reduceMotion: Bool = false, scenePhase: ScenePhase = .active) {
            self.controller = controller
            window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
            let renderer = ConfettiLayerView(frame: window.bounds)
            self.renderer = renderer
            window.rootViewController = host
            host.view.addSubview(renderer)
            controller.attach(renderer, sceneIsActive: scenePhase == .active, reduceMotion: reduceMotion)
            window.isHidden = false
            host.view.layoutIfNeeded()
        }

        func update(reduceMotion: Bool, scenePhase: ScenePhase) {
            guard let renderer else { return }
            controller.attach(renderer, sceneIsActive: scenePhase == .active, reduceMotion: reduceMotion)
        }

        func close() {
            if let renderer {
                controller.detach(renderer)
                renderer.removeFromSuperview()
            }
            window.isHidden = true
            window.rootViewController = nil
        }
    }
#endif
