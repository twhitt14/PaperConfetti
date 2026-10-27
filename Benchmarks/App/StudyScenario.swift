import Foundation
import PaperConfetti

struct StudyScenario: Decodable, Identifiable {
    let id: String
    let suites: [String]
    let renderer: String
    let count: Int
    let size: Double
    let shapes: String
    let textureScale: Double
    let samples: Int
    let sampling: String
    let tumble: Bool
    let flutter: Bool
    let hostMotion: Bool
    let uniformSpeed: Bool
    let prewarm: Bool
    let opaqueProxy: Bool
    let atlas: Bool
    let paddedTexture: Bool
    let trilinear: Bool

    static let all: [Self] = {
        struct Manifest: Decodable { let schema: Int; let scenarios: [StudyScenario] }
        // This is a bundled, validated fixture; fail visibly rather than silently testing no particles.
        guard let url = Bundle.main.url(forResource: "Study", withExtension: "json"),
              let data = try? Data(contentsOf: url), let manifest = try? JSONDecoder().decode(Manifest.self, from: data),
              manifest.schema == 1 else { fatalError("Missing or invalid Study.json") }
        return manifest.scenarios
    }()
    var shapeSet: [ConfettiShape] {
        if shapes == "festive" { return ConfettiShape.festive }
        if shapes == "classic" { return ConfettiShape.classic }
        return ConfettiShape.allCases.filter { String(describing: $0) == shapes }
    }
    func burst(size canvas: CGSize, seed: UInt64) -> ConfettiBurst {
        var burst = ConfettiBurst(cannons: (0..<5).map {
            ConfettiEmitter(x: Double(canvas.width) * (Double($0) + 0.5) / 5,
                            y: Double(canvas.height) * 0.62, delay: Double($0) * 0.1,
                            count: count / 5, angle: 90, spread: 40)
        }, seed: seed, radius: 130, fall: 320, size: size, shapes: shapeSet,
        fallSpeedRange: uniformSpeed ? 1...1 : 0.75...1.35)
        if !tumble { burst.motion.tumble = 0...0 }
        if !flutter { burst.motion.flutter = 0 }
        return burst
    }
}
