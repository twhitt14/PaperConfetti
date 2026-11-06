#if canImport(UIKit)
import SwiftUI
import UIKit
import XCTest
@_spi(Testing) @testable import PaperConfetti

@MainActor
private final class SourceModel: ObservableObject {
    @Published var controller = ConfettiController()
    @Published var x = 100.0
    @Published var visible = true
}
private struct SourceFixture: View {
    @ObservedObject var model: SourceModel
    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            if model.visible {
                Color.blue.frame(width: 40, height: 40)
                    .confettiSource(id: "button", controller: model.controller)
                    .position(x: model.x, y: 160)
            }
        }
        .confettiOverlay(model.controller)
        .environment(\.scenePhase, .active)
    }
}

@MainActor
final class ConfettiSourceTests: XCTestCase {
    private func eventually(file: StaticString = #filePath, line: UInt = #line, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(4)
        while !condition() && Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertTrue(condition(), file: file, line: line)
    }
    private func renderer(in view: UIView) -> ConfettiLayerView? {
        if let view = view as? ConfettiLayerView { return view }
        return view.subviews.lazy.compactMap { self.renderer(in: $0) }.first
    }
    private func origin(_ renderer: ConfettiLayerView) -> CGPoint? {
        let group = renderer.layer.sublayers?.first?.sublayers?.first?.animation(forKey: "flight") as? CAAnimationGroup
        let positions = group?.animations?.first as? CAKeyframeAnimation
        return (positions?.values?.first as? NSValue)?.cgPointValue
    }

    func testSourceTracksMovementRemovalAndReplacementController() async throws {
        try XCTSkipIf(UIAccessibility.isReduceMotionEnabled)
        let model = SourceModel()
        let host = UIHostingController(rootView: SourceFixture(model: model))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = host; window.isHidden = false
        defer { model.controller.cancel(); window.isHidden = true; window.rootViewController = nil }
        host.view.layoutIfNeeded()
        try await eventually { self.renderer(in: host.view) != nil }
        let renderer = try XCTUnwrap(renderer(in: host.view))
        // Wait for the source's layout preference, without assuming one run-loop turn.
        try await eventually {
            model.controller.pop(fromSource: "button", configuration: .init(particleCount: 1))
            return self.origin(renderer)?.x == 100
        }
        model.x = 250
        try await eventually {
            model.controller.pop(fromSource: "button", configuration: .init(particleCount: 1))
            return self.origin(renderer)?.x == 250
        }
        let old = model.controller
        model.controller = ConfettiController()
        try await eventually {
            model.controller.pop(fromSource: "button", configuration: .init(particleCount: 1))
            return model.controller.isPlaying
        }
        XCTAssertFalse(old.isPlaying)
        XCTAssertEqual(origin(try XCTUnwrap(self.renderer(in: host.view)))?.x, 250, "Unchanged geometry still belongs to the replacement controller")
        model.visible = false
        var outcomes: [ConfettiOutcome] = []
        try await eventually {
            model.controller.pop(fromSource: "button", configuration: .init(particleCount: 1)) { outcomes.append($0) }
            return outcomes.contains(.notPresented)
        }
        model.controller.cancel()
        XCTAssertFalse(model.controller.isPlaying)
    }

    func testZeroSizedHostWaitsForLayoutThenPlaysExactlyOnce() async throws {
        let controller = ConfettiController()
        let host = UIViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = host; window.isHidden = false
        let renderer = ConfettiLayerView(frame: .zero)
        host.view.addSubview(renderer)
        controller.attach(renderer, sceneIsActive: true, reduceMotion: false)
        defer { controller.detach(renderer); window.isHidden = true; window.rootViewController = nil }
        var outcomes: [ConfettiOutcome] = []
        controller.pop(configuration: .init(particleCount: 1)) { outcomes.append($0) }
        XCTAssertTrue(controller.isPending)
        XCTAssertEqual(renderer.particleLayerCount, 0)
        renderer.frame = host.view.bounds; renderer.layoutIfNeeded()
        try await eventually { controller.isPlaying }
        XCTAssertFalse(controller.isPending)
        controller.cancel()
        try await eventually { !outcomes.isEmpty }
        XCTAssertEqual(outcomes, [.cancelled])
        renderer.setNeedsLayout(); renderer.layoutIfNeeded()
        XCTAssertFalse(controller.isPlaying)
    }
}
#endif
