import SwiftUI
import PaperConfetti

@MainActor
struct ConfettiQuickStart: View {
    @StateObject private var confetti = ConfettiController()

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
            VStack(spacing: 24) {
                Button("Celebrate") { confetti.pop() }
                Button("Stop") { confetti.cancel() }
                Button("Stars and streamers") {
                    confetti.pop(configuration: .init(
                        colors: [.mint, .pink, .orange],
                        shapes: [.star, .ring, .doubleLoop, .curvedTriangle],
                        count: 100, size: 12, spread: 100))
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .confettiOverlay(confetti)
    }
}
