# Launch from a button or tile

Register the source on a child view and mount the overlay on its stable ancestor.
The controller resolves the current center, including scrolling, when you tap.
Flying particles keep that captured position. A missing source reports
`ConfettiOutcome.notPresented` rather than reusing an old position.

```swift
import SwiftUI
import PaperConfetti

@MainActor
struct ButtonOriginExample: View {
    @StateObject private var confetti = ConfettiController()

    var body: some View {
        VStack(spacing: 24) {
            Text("A small victory").font(.title)
            Spacer()
            Button("Celebrate here") {
                confetti.pop(fromSource: "reward")
            }
            .buttonStyle(.borderedProminent)
            .confettiSource(id: "reward", controller: confetti)
            .padding(.bottom, 48)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .confettiOverlay(confetti)
    }
}
```

`pop(at:)` accepts a point in the overlay's coordinates. `pop(from: .center)`
accepts a normalized `UnitPoint`. Source identifiers are scoped to their controller;
use unique identifiers for views sharing one controller.

Keep the overlay outside moving keyboard/scroll containers. Reduce Motion,
scene cancellation, completion outcomes and touch pass-through apply to all forms.
