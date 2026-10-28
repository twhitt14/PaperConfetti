#if canImport(UIKit)
    import SwiftUI
    import UIKit

    /// All ordinary single-cannon choices in one value. Advanced multi-cannon bursts
    /// use `ConfettiBurst` with the same shapes, seeded physics and finite bounds.
    public struct ConfettiConfiguration {
        public var colors: [Color]
        public var shapes: [ConfettiShape]
        public var count: Int
        public var radius, fall, size, angle, spread: Double
        public var appearance: ConfettiAppearance
        public var motion: ConfettiMotion
        public var fallSpeedRange: ClosedRange<Double>

        public init(
            colors: [Color] = [.cyan, .pink, .yellow],
            shapes: [ConfettiShape] = ConfettiShape.festive,
            count: Int = 80, radius: Double = 160, fall: Double = 360,
            size: Double = 10, angle: Double = 90, spread: Double = 70,
            fallSpeedRange: ClosedRange<Double> = 0.75...1.35, motion: ConfettiMotion = .init(),
            appearance: ConfettiAppearance = .threeDimensional
        ) {
            self.colors = colors
            self.shapes = shapes
            self.count = count
            self.radius = radius
            self.fall = fall
            self.size = size
            self.angle = angle
            self.spread = spread
            self.fallSpeedRange = fallSpeedRange
            self.appearance = appearance
            self.motion = motion
        }
    }

    /// Own one controller with @StateObject and attach `.confettiOverlay(controller)`.
    /// Calling `pop()` is an event; callers never maintain counters or change seeds
    /// just to trigger a render. A new pop replaces the old one, keeping work bounded.
    @MainActor public final class ConfettiController: ObservableObject {
        private struct Request {
            let makeBurst: (CGSize) -> ConfettiBurst
            let colors: [UIColor]
        }
        private weak var renderer: ConfettiLayerView?
        private var pending: Request?
        private var hasMounted = false
        private var enabled = false
        public init() {}

        public var isPlaying: Bool { (renderer?.particleLayerCount ?? 0) > 0 }

        /// Default origin is bottom-center in the overlay's local coordinate space.
        /// Returns false when the mounted host is absent/inactive or motion is reduced.
        /// Before the first mount, at most one request is retained for initial onAppear.
        @discardableResult
        public func pop(at origin: CGPoint? = nil, configuration: ConfettiConfiguration = .init()) -> Bool {
            submit(
                Request(
                    makeBurst: { bounds in
                        let point = origin ?? CGPoint(x: bounds.width / 2, y: bounds.height)
                        return ConfettiBurst(
                            cannons: [
                                .init(
                                    x: point.x, y: point.y, count: configuration.count,
                                    angle: configuration.angle, spread: configuration.spread)
                            ], radius: configuration.radius,
                            fall: configuration.fall, size: configuration.size, shapes: configuration.shapes,
                            fallSpeedRange: configuration.fallSpeedRange, motion: configuration.motion,
                            appearance: configuration.appearance)
                    }, colors: configuration.colors.prefix(16).map(UIColor.init)))
        }

        /// Full control: independently placed/delayed cannons, requested budget, palette,
        /// shape selection, dimensions, flight distances, speed range and optional seed.
        @discardableResult
        public func pop(_ burst: ConfettiBurst, colors: [Color] = [.cyan, .pink, .yellow]) -> Bool {
            submit(Request(makeBurst: { _ in burst }, colors: colors.prefix(16).map(UIColor.init)))
        }

        public func cancel() {
            pending = nil
            renderer?.cancel()
        }

        private func submit(_ request: Request) -> Bool {
            guard !hasMounted || (renderer != nil && enabled) else { return false }
            if let renderer, renderer.hasEnteredWindow,
                renderer.window == nil || renderer.window?.isHidden == true
            {
                return false
            }
            pending = request
            flush()
            return true
        }

        fileprivate func attach(_ view: ConfettiLayerView, enabled: Bool) {
            if renderer !== view {
                renderer?.layoutReady = nil
                renderer?.cancel()
                renderer = view
                view.layoutReady = { [weak self] in self?.flush() }
            }
            hasMounted = true
            self.enabled = enabled
            if enabled { flush() } else { cancel() }
        }

        fileprivate func detach(_ view: ConfettiLayerView) {
            guard renderer === view else { return }
            cancel()
            view.layoutReady = nil
            renderer = nil
            enabled = false
        }

        private func flush() {
            guard enabled, let view = renderer, view.window?.isHidden == false,
                view.bounds.width > 0, view.bounds.height > 0, let request = pending
            else { return }
            pending = nil
            view.play(burst: request.makeBurst(view.bounds.size), colors: request.colors)
        }
    }

    private struct ControlledConfettiOverlay: UIViewRepresentable {
        let controller: ConfettiController
        let enabled: Bool
        func makeUIView(context: Context) -> ConfettiLayerView { ConfettiLayerView() }
        func makeCoordinator() -> Coordinator { Coordinator(controller) }
        func updateUIView(_ view: ConfettiLayerView, context: Context) {
            if context.coordinator.controller !== controller {
                context.coordinator.controller.detach(view)
                context.coordinator.controller = controller
            }
            controller.attach(view, enabled: enabled)
        }
        static func dismantleUIView(_ view: ConfettiLayerView, coordinator: Coordinator) {
            coordinator.controller.detach(view)
        }
        final class Coordinator {
            var controller: ConfettiController
            init(_ controller: ConfettiController) { self.controller = controller }
        }
    }

    private struct ConfettiOverlayModifier: ViewModifier {
        let controller: ConfettiController
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.scenePhase) private var scenePhase
        func body(content: Content) -> some View {
            content.overlay {
                ControlledConfettiOverlay(
                    controller: controller, enabled: !reduceMotion && scenePhase == .active
                )
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
    }

    extension View {
        /// Mount on a stable, full-size container; emitters use that container's coordinates.
        public func confettiOverlay(_ controller: ConfettiController) -> some View {
            modifier(ConfettiOverlayModifier(controller: controller))
        }
    }
#endif
