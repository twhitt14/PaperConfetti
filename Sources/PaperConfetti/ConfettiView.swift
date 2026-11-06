#if canImport(UIKit)
import UIKit

/// A touch-transparent UIKit host with the same lifecycle, accessibility and
/// completion behavior as the SwiftUI modifier. Add it to a stable container.
@MainActor public final class ConfettiView: UIView {
    private let renderer = ConfettiLayerView()
    private let controller = ConfettiController()
    /// Whether a flight is being prepared or is active; this is not a visible-pixel measurement.
    public var isPlaying: Bool { controller.isPlaying }

    /// Creates a transparent decorative host.
    ///
    /// - Parameter frame: The frame in its parent’s coordinates.
    public override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    /// Creates a touch-transparent host from a storyboard or archived view.
    /// - Parameter coder: An unarchiver containing the view. Active flights are not restored.
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        // UIView decoding may restore the old decorative child. Flights aren't
        // restorable state; keep exactly one fresh renderer and no old callbacks.
        subviews.filter { $0 is ConfettiLayerView }.forEach { $0.removeFromSuperview() }
        configure()
    }

    private func configure() {
        isOpaque = false; backgroundColor = .clear
        isUserInteractionEnabled = false; accessibilityElementsHidden = true
        addSubview(renderer)
        NotificationCenter.default.addObserver(self, selector: #selector(deactivate), name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(sceneDeactivated(_:)), name: UIScene.willDeactivateNotification, object: nil)
        for name in [UIApplication.didBecomeActiveNotification, UIScene.didActivateNotification,
                     UIAccessibility.reduceMotionStatusDidChangeNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(refreshPolicy), name: name, object: nil)
        }
    }
    /// Updates the host bounds without repositioning paper already in flight.
    public override func layoutSubviews() { super.layoutSubviews(); renderer.frame = bounds; refreshPolicy() }
    /// Attaches to the current window or cancels requests when removed.
    public override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { controller.detach(renderer) } else { refreshPolicy() }
    }
    @objc private func deactivate() {
        controller.attach(renderer, sceneIsActive: false, reduceMotion: UIAccessibility.isReduceMotionEnabled)
    }
    @objc private func sceneDeactivated(_ notification: Notification) {
        guard let scene = notification.object as? UIScene, scene === window?.windowScene else { return }
        deactivate()
    }
    @objc private func refreshPolicy() {
        guard window != nil else { return }
        controller.attach(renderer,
            sceneIsActive: window?.windowScene?.activationState == .foregroundActive && UIApplication.shared.applicationState == .active,
            reduceMotion: UIAccessibility.isReduceMotionEnabled)
    }
    /// Emits a single cannon, replacing the previous request.
    ///
    /// - Parameters:
    ///   - origin: A point in this view's bounds, or `nil` for bottom center.
    ///   - configuration: Shared paper and flight settings.
    ///   - completion: An optional once-only callback, delivered asynchronously on the main actor.
    public func pop(at origin: CGPoint? = nil, configuration: ConfettiConfiguration = .init(),
                    completion: (@MainActor (ConfettiOutcome) -> Void)? = nil) {
        refreshPolicy(); controller.pop(at: origin, configuration: configuration, completion: completion)
    }
    /// Emits multiple cannons as one event, replacing the previous request.
    ///
    /// - Parameters:
    ///   - emitters: Up to 32 cannons in this view's coordinates, sharing a 6,000-piece budget.
    ///   - configuration: Shared paper and motion settings; emitter counts and angles take precedence.
    ///   - seed: A reproducible seed for this package version, or `nil` for new random motion.
    ///   - completion: An optional once-only callback, delivered asynchronously on the main actor.
    public func pop(emitters: [ConfettiEmitter], configuration: ConfettiConfiguration = .init(), seed: UInt64? = nil,
                    completion: (@MainActor (ConfettiOutcome) -> Void)? = nil) {
        refreshPolicy(); controller.pop(emitters: emitters, configuration: configuration, seed: seed, completion: completion)
    }
    /// Drops paper across the top of this view, replacing the previous request.
    ///
    /// - Parameters:
    ///   - configuration: Shared paper, count, and descent settings.
    ///   - duration: The emission window, from zero through 10 seconds. An invalid
    ///     duration reports `notPresented` without interrupting an active event.
    ///   - seed: A reproducible seed for this package version, or `nil` for new random motion.
    ///   - completion: An optional once-only callback, delivered asynchronously on the main actor.
    public func drop(configuration: ConfettiConfiguration = .init(), duration: TimeInterval = 2, seed: UInt64? = nil,
                     completion: (@MainActor (ConfettiOutcome) -> Void)? = nil) {
        refreshPolicy(); controller.drop(configuration: configuration, duration: duration, seed: seed, completion: completion)
    }
    /// Cancels pending and active flights. Repeated calls are safe.
    public func cancel() { controller.cancel() }
    /// Passes all touches through to content behind this decorative view.
    ///
    /// - Parameters:
    ///   - point: The point UIKit is testing.
    ///   - event: The event associated with the hit test, if any.
    /// - Returns: Always `nil`, even if user interaction is accidentally enabled.
    public override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
}
#endif
