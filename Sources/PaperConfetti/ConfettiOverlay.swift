#if canImport(UIKit)
    import SwiftUI
    import UIKit

    /// Decorative SwiftUI overlay. Give each new celebration a new burst seed or `.id`.
    /// Core Animation owns the flight: no per-frame SwiftUI updates or particle timers.
    public struct ConfettiOverlay: View {
        public let burst: ConfettiBurst
        public let colors: [Color]
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.scenePhase) private var scenePhase
        public init(burst: ConfettiBurst, colors: [Color]) {
            self.burst = burst
            self.colors = colors
        }
        public var body: some View {
            ConfettiLayerRepresentable(
                burst: burst, colors: colors.prefix(16).map(UIColor.init),
                enabled: !reduceMotion && scenePhase == .active
            )
            .allowsHitTesting(false).accessibilityHidden(true)
        }
    }

    private struct ConfettiLayerRepresentable: UIViewRepresentable {
        let burst: ConfettiBurst
        let colors: [UIColor]
        let enabled: Bool
        func makeUIView(context: Context) -> ConfettiLayerView { ConfettiLayerView() }
        func updateUIView(_ view: ConfettiLayerView, context: Context) {
            view.show(burst: burst, colors: colors, enabled: enabled)
        }
        static func dismantleUIView(_ view: ConfettiLayerView, coordinator: ()) { view.cancel() }
    }

#endif
