import Foundation
import PaperConfetti

struct StudyScenario: Decodable, Identifiable {
    var id: String
    let suites: [String]
    let renderer: String
    var count: Int
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
    let paddedTexture: Bool
    let trilinear: Bool
    let native3D: Bool?
    let sharedFlight: Bool?

    static let all: [Self] = {
        struct Manifest: Decodable { let schema: Int; let scenarios: [StudyScenario] }
        // This is a bundled, validated fixture; fail visibly rather than silently testing no particles.
        guard let url = Bundle.main.url(forResource: "Study", withExtension: "json"),
              let data = try? Data(contentsOf: url), let manifest = try? JSONDecoder().decode(Manifest.self, from: data),
              manifest.schema == 1 else { fatalError("Missing or invalid Study.json") }
        return manifest.scenarios
    }()
    var displayName: String {
        let names = ["paper": "PaperConfetti 0.1 baseline", "layers": "Adjustable layers",
                     "emitter": native3D == true ? "Native particles · 3D tilt" : "Native particles · flat",
                     "none": "No confetti"]
        if id == "adaptive-keyframes" { return "Adjustable layers · adaptive · \(count)" }
        let simple = suites.contains("renderers")
        return simple ? "\(names[renderer] ?? renderer) · \(count)" : id
    }
    var availableCounts: [Int] { renderer == "paper" ? [180, 720, 1440] : [180, 720, 1440, 2880, 5760] }
    func resized(to count: Int) -> Self {
        var copy = self
        if count != self.count { copy.id += "@\(count)"; copy.count = count }
        return copy
    }
    var shapeSet: [ConfettiShape] {
        if ProcessInfo.processInfo.arguments.contains("--emission-probe") { return [.circle] }
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
        if ProcessInfo.processInfo.arguments.contains("--study-interaction-test") {
            // UI automation can spend several seconds locating a single control.
            // Keep real particles alive through those gestures; never use this
            // interaction-only fixture in a measured performance trial.
            burst.fall = 2_000; burst.fallSpeedRange = 0.25...0.25
        }
        if ProcessInfo.processInfo.arguments.contains("--emission-probe") {
            // Keep the diagnostic population alive long enough for screenshot RPCs.
            // The probe host holds position/opacity; actual cell birth timing stays unchanged.
            burst.radius = 2; burst.fall = 800; burst.fallSpeedRange = 1...1
            burst.motion.flutter = 0; burst.motion.tumble = 0...0; burst.motion.spin = 0...0
            burst.motion.launchDuration = 0.3...0.3
            for i in burst.cannons.indices { burst.cannons[i].spread = 0 }
            if ProcessInfo.processInfo.arguments.contains("--native-legacy-clock") {
                // The negative control tests an expired window, not throughput.
                // Keep its repeated live reference small; high-load coverage is
                // supplied separately by the real 5,760-piece production probes.
                for i in burst.cannons.indices { burst.cannons[i].count = 8 }
            }
        }
        return burst
    }
}
