# ``PaperConfetti``

Add a playful, touch-transparent celebration to SwiftUI or UIKit.

## Overview

PaperConfetti draws 13 paper silhouettes with Core Animation. Each shape receives
one random descent speed per burst, while pieces rotate and tumble independently.
No per-frame SwiftUI state updates or third-party runtime dependencies are needed.

```swift
import SwiftUI
import PaperConfetti

struct CelebrationView: View {
    @StateObject private var confetti = ConfettiController()

    var body: some View {
        VStack {
            Button("Celebrate") { confetti.pop() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .confettiOverlay(confetti)
    }
}
```

Attach the modifier to a stable, full-size container. Emitter positions use its
local coordinate system. A new pop replaces the previous one. Reduced Motion,
scene deactivation and view removal stop the effect without replaying it later.
The overlay does not consume touches or become an accessibility element.

## Topics

### Triggering a celebration
- ``ConfettiController``
- ``ConfettiConfiguration``
- ``ConfettiOverlay``

### Customizing the paper and flight
- ``ConfettiShape``
- ``ConfettiBurst``
- ``ConfettiEmitter``
- ``ConfettiMotion``

### UIKit integration
- <doc:UIKitIntegration>
- ``ConfettiLayerView``

### Deterministic physics
- ``ConfettiParticle``
