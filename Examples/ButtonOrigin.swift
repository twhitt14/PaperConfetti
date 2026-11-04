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
