# Using UIKit directly

Mount a decorative view and trigger the same renderer from a UIKit event.

```swift
let overlay = ConfettiLayerView(frame: container.bounds)
overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
container.addSubview(overlay)

// In your success/button handler:
guard !UIAccessibility.isReduceMotionEnabled else { return }
overlay.play(
    burst: ConfettiBurst(cannons: [
        ConfettiEmitter(x: container.bounds.midX, y: container.bounds.height)
    ]),
    colors: [.systemTeal, .systemPink, .systemYellow]
)
```

The UIKit host owns scene and accessibility policy: call `cancel()` when its scene
becomes inactive or its view disappears, and observe Reduce Motion changes to
cancel an active effect. Keep this view outside containers that move during the
celebration. The SwiftUI modifier handles those policies automatically.

`play` is an explicit event and can repeat an identical seeded burst. The older
`show` method only consumes changed values; do not mix event and state triggers
on one renderer. Both methods pass touches through to views beneath the overlay.
