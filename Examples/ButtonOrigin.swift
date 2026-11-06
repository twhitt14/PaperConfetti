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
