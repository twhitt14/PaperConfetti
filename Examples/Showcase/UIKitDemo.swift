import SwiftUI

struct UIKitDemo: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIKitCelebrationViewController {
        let viewController = UIKitCelebrationViewController()
        // Keep this test-only flight alive while automation sends real input.
        viewController.configuration = .init(particleCount: 80, fallDistance: 2_000, fallSpeedMultiplierRange: 0.25...0.25)
        return viewController
    }
    func updateUIViewController(_ viewController: UIKitCelebrationViewController, context: Context) {}
}
