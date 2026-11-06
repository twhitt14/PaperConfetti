import PaperConfetti
import UIKit

@MainActor
final class UIKitCelebrationViewController: UIViewController {
    var configuration = ConfettiConfiguration()
    private let confetti = ConfettiView()
    private let status = UILabel()
    private var taps = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        status.text = "Ready"
        status.textAlignment = .center
        status.accessibilityIdentifier = "uikit-status"
        let stack = UIStackView(arrangedSubviews: [
            status,
            button("Pop") { [weak self] in self?.pop() },
            button("Shower") { [weak self] in self?.shower() },
            button("Tap through") { [weak self] in
                guard let self else { return }
                self.taps += 1
                self.status.text = "Tap \(self.taps) · \(self.confetti.isPlaying ? "playing" : "idle")"
            },
            button("Stop") { [weak self] in self?.confetti.cancel() }
        ])
        stack.axis = .vertical; stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.8)
        ])
        confetti.frame = view.bounds
        confetti.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(confetti)
    }

    private func button(_ title: String, action: @escaping () -> Void) -> UIButton {
        let button = UIButton(configuration: .filled())
        button.setTitle(title, for: .normal)
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        return button
    }

    private func pop() {
        confetti.pop(configuration: configuration) { [weak self] outcome in self?.show(outcome) }
        status.text = confetti.isPlaying ? "Playing" : "Waiting"
    }
    private func shower() {
        confetti.drop(configuration: configuration) { [weak self] outcome in self?.show(outcome) }
        status.text = confetti.isPlaying ? "Playing" : "Waiting"
    }
    private func show(_ outcome: ConfettiOutcome) {
        status.text = String(describing: outcome)
    }
}
