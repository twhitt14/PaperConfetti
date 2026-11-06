import SwiftUI
import PaperConfetti

// Compile the complete configuration/shape/outcome surface without @testable or SPI.
// An accidental isolation or signature change must fail here, not in a consumer app.
@MainActor
func configurePublicAPI(_ controller: ConfettiController) throws {
    var style = ConfettiConfiguration.festive
    style.colors = [.cyan, .orange, .gray]
    style.particleCount = 120
    style.launchDistance = 180
    style.fallDistance = 450
    style.particleSize = 12
    style.emissionAngle = .radians(.pi / 2)
    style.spread = .degrees(90)
    style.motion = .init(launchDuration: 0.3...0.7, launchSpeedMultiplier: 1.1,
                        spin: 2...6, tumble: 3...8, sizeVariation: 0.8...1.2,
                        flutter: 5, fadeOutStart: 0.4)
    style.fallSpeedMultiplierRange = 0.7...1.4
    style.appearance = .flat
    let path = CGMutablePath()
    path.addEllipse(in: CGRect(x: 0, y: 0, width: 1, height: 1))
    style.shapes = [try ConfettiShape(path: path, name: "Disc"), .ring, .wave]
    requireSendable(style)
    requireSendable(style.shapes)
    let emitters = [ConfettiEmitter(origin: CGPoint(x: 40, y: 500), delay: 0.1,
        particleCount: 36, emissionAngle: .degrees(90), spread: .degrees(40))]
    requireSendable(emitters)
    controller.pop(emitters: emitters, configuration: style, seed: 42)
    controller.pop(from: .bottomLeading, configuration: style)
    controller.pop(fromSource: "celebrate", configuration: .subtle)
    controller.drop(configuration: style, duration: 2.8, seed: 42) { outcome in
        switch outcome {
        case .finished, .reducedMotion: break
        case .cancelled, .notPresented: break
        }
    }
    controller.cancel()
}

private func requireSendable<T: Sendable>(_ value: T) {}
