#if canImport(UIKit)
    /// The terminal outcome of one controller request, delivered on the main actor.
    public enum ConfettiOutcome: Equatable, Sendable {
        /// The scheduled flight and cleanup finished. This is not a render-server
        /// readback of the last visible particle.
        case finished
        /// An active host intentionally omitted motion for accessibility.
        case reducedMotion
        /// An accepted request was replaced, explicitly cancelled, or interrupted
        /// by a host/lifecycle change. Do not treat this as successful completion.
        case cancelled
        /// The request could not be presented: an unavailable host, an empty or
        /// invalid burst, or a renderer that never became ready.
        case notPresented
    }

    /// Own the callback independently of the controller/renderer so pending requests
    /// and teardown use the same once-only delivery. Never call user code inline
    /// while SwiftUI is updating its representable or a new burst is being installed.
    @MainActor
    final class ConfettiCompletion {
        private var callback: (@MainActor (ConfettiOutcome) -> Void)?

        init(_ callback: (@MainActor (ConfettiOutcome) -> Void)?) {
            self.callback = callback
        }

        func resolve(_ outcome: ConfettiOutcome) {
            guard let callback else { return }
            self.callback = nil
            Task { @MainActor in callback(outcome) }
        }

        deinit {
            // Dropping the last owner must not silently lose an unresolved callback.
            // Capture the closure, never the object being destroyed.
            if let callback {
                Task { @MainActor in callback(.cancelled) }
            }
        }
    }
#endif
