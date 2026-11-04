# Launch confetti from a button

Start a celebration at the tapped control while the paper flies across its containing view.

`ConfettiController.pop(at:configuration:)` accepts a `CGPoint` in the overlay's
local coordinate space. An ordinary `pop()` uses the bottom-center of that space.
Both forms have been available since 0.2.0; this recipe does not require completion callbacks.

## Measure the button in the overlay's coordinates

Attach the overlay to a stable, full-size container. The button publishes its
bounds as an anchor; a background on that same container resolves the anchor.
This avoids mixing a button's local bounds, screen coordinates and safe-area
insets. The following complete example supports iOS 16 and later.

```swift
import SwiftUI
import PaperConfetti

@MainActor
struct ButtonOriginExample: View {
    @StateObject private var confetti = ConfettiController()
    @State private var buttonBounds: CGRect?

    var body: some View {
        VStack(spacing: 24) {
            Text("A small victory").font(.title)
            Spacer()
            Button("Celebrate here") {
                guard let buttonBounds else { return }
                let origin = CGPoint(x: buttonBounds.midX, y: buttonBounds.midY)
                confetti.pop(at: origin)
            }
            .buttonStyle(.borderedProminent)
            .anchorPreference(key: CelebrationButtonBounds.self, value: .bounds) { $0 }
            .padding(.bottom, 48)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .backgroundPreferenceValue(CelebrationButtonBounds.self) { anchor in
            GeometryReader { geometry in
                let bounds = anchor.map { geometry[$0] }
                Color.clear
                    .onAppear { buttonBounds = bounds }
                    .onChange(of: bounds) { buttonBounds = $0 }
            }
        }
        .confettiOverlay(confetti)
    }
}

private struct CelebrationButtonBounds: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? { nil }

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}
```

The preference reader and `confettiOverlay` are on the same container, with no
padding or frame modifier between them. `geometry[anchor]` therefore measures the
button where the renderer expects its origin. The background does not determine
the container's size or cover its controls.

The measurement updates after layout changes. The tap captures a point for that
burst; later changes to the button do not redirect flying particles. Before the
first measurement there is no origin yet, so the action waits for a later tap
instead of guessing a position. The single-value preference key is for one
button; use identifiable anchors if several controls share a host.

## Scrolling and changing layouts

If the button lives inside a scroll view, keep the preference reader and confetti
overlay on the stable container **outside** that scroll view. Anchors resolve
through the view hierarchy, including the scroll offset. Keep any clipping or
scrolling on the content, not on the full-size confetti host. Moving the host
itself still moves the entire effect.

To launch from a relative place in the container, a `UnitPoint` is also useful:
multiply its `x` and `y` by the container's width and height, then pass the result
to `pop(at:)`. A unit point locates a fraction of its own view; it does not by
itself locate a child button in a different view.

The SwiftUI modifier still supplies Reduce Motion, scene cancellation and touch
pass-through. Keep the app's normal success state or feedback independent of
whether decorative motion is displayed.

For the underlying geometry contracts, see Apple's
[Anchor documentation](https://developer.apple.com/documentation/swiftui/anchor),
[GeometryProxy](https://developer.apple.com/documentation/swiftui/geometryproxy),
and [UnitPoint](https://developer.apple.com/documentation/swiftui/unitpoint).
