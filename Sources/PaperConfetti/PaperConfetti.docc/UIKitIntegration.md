# Using UIKit directly

Mount a touch-transparent view and trigger the same renderer from a UIKit event.

```swift
import PaperConfetti

let confetti = ConfettiView(frame: container.bounds)
confetti.autoresizingMask = [.flexibleWidth, .flexibleHeight]
container.addSubview(confetti)

// In your success/button handler:
confetti.pop(configuration: .init(colors: [.cyan, .pink, .yellow]))
// Or let paper fall across the top:
confetti.drop(configuration: .init(particleCount: 220), duration: 2.8)
```

Keep the view in a stable container outside keyboard-driven animations. The view
handles Reduce Motion, scene deactivation and detachment; cancelled events never
replay when returning. Call `cancel()` when abandoning a pending presentation.
A new request replaces the previous one. Separate views support intentional overlap.

`pop(emitters:configuration:seed:completion:)` supports multiple origins. Optional
callbacks use the same ``ConfettiOutcome`` contract as SwiftUI. They run once,
asynchronously on the main actor; interruption is not successful completion.
The view returns nil from hit testing even if interaction is accidentally enabled.
`isPlaying` is immediate lifecycle status, not a frame-delivery measurement.
