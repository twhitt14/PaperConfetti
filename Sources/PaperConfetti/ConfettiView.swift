#if canImport(UIKit)
import UIKit

/// A touch-transparent UIKit host with the same lifecycle, accessibility and
/// completion behavior as the SwiftUI modifier. Add it to a stable container.
@MainActor public final class ConfettiView: UIView {
    private let renderer = ConfettiLayerView()
    private let controller = ConfettiController()
    public var isPlaying: Bool { controller.isPlaying }

    public override init(frame: CGRect) {
        super.init(frame: frame)
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
    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }
    public override func layoutSubviews() { super.layoutSubviews(); renderer.frame = bounds; refreshPolicy() }
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
    public func pop(at origin: CGPoint? = nil, configuration: ConfettiConfiguration = .init(),
                    completion: (@MainActor (ConfettiOutcome) -> Void)? = nil) {
        refreshPolicy(); controller.pop(at: origin, configuration: configuration, completion: completion)
    }
    public func pop(emitters: [ConfettiEmitter], configuration: ConfettiConfiguration = .init(), seed: UInt64? = nil,
                    completion: (@MainActor (ConfettiOutcome) -> Void)? = nil) {
        refreshPolicy(); controller.pop(emitters: emitters, configuration: configuration, seed: seed, completion: completion)
    }
    public func drop(configuration: ConfettiConfiguration = .init(), duration: TimeInterval = 2, seed: UInt64? = nil,
                     completion: (@MainActor (ConfettiOutcome) -> Void)? = nil) {
        refreshPolicy(); controller.drop(configuration: configuration, duration: duration, seed: seed, completion: completion)
    }
    public func cancel() { controller.cancel() }
    public override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
}
#endif
