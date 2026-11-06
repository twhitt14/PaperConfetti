# ``PaperConfetti``

Add a playful, touch-transparent celebration to SwiftUI or UIKit.

## Overview

PaperConfetti draws 13 paper silhouettes with native Core Animation particles.
3D tumble is the default; use `ConfettiConfiguration(appearance: .flat)` for flat
spinning paper. Each shape has a base fall speed, with independent timing per piece.
No per-frame SwiftUI state updates or third-party runtime dependencies are needed.

```swift
import SwiftUI
import PaperConfetti

@MainActor
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

## Following a celebration

The controller also accepts a completion closure. Switch on ``ConfettiOutcome``
to continue after `.finished` or `.reducedMotion`, and avoid treating `.cancelled`
or `.notPresented` as a successful animation. The same callback form is available
for configured single-cannon and explicit multi-cannon requests.

Callbacks run once per resolved request, asynchronously on the main actor after
cleanup. Event methods return `Void`; the outcome is the result. A request
queued before the first mount waits for attachment/layout, replacement or
cancellation. Keep the controller owned by the screen, and cancel a pending
request if you abandon that presentation. Avoid strong owner/callback cycles.

Natural completion follows the renderer's scheduled lifetime, including all
cannon delays and a quarter-second cleanup margin. It does not inspect the last
visible Core Animation particle. An already resolved outcome is not changed by
a later cancellation; the caller still decides whether its follow-up is current.

Use ``ConfettiView`` for UIKit with automatic scene and Reduce Motion policy.
Use `drop()` for a full-width shower; it has the same outcome contract.
Custom ``ConfettiShape`` paths share the built-in raster cache.

## Topics

### Triggering a celebration
- ``ConfettiController``
- ``ConfettiOutcome``
- ``ConfettiConfiguration``
- ``ConfettiPlaybackState``
- <doc:ButtonOrigin>

### Customizing the paper and flight
- <doc:Configuration>
- ``ConfettiAppearance``
- ``ConfettiShape``
- ``ConfettiAngle``
- ``ConfettiEmitter``
- ``ConfettiMotion``

### Integration contract
- <doc:Compatibility>

### UIKit integration
- <doc:UIKitIntegration>
- ``ConfettiView``
