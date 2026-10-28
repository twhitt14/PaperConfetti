import UIKit
import SpriteKit
import SwiftUI
import PaperConfetti

/// Benchmarks only. The released renderer and public package API stay unchanged.
@MainActor final class StudyRenderer: UIView {
    let production = ConfettiLayerView()
    private let particlesView = UIView()
    private let sprite = SKView()
    private var removal: DispatchWorkItem?
    private(set) var activeCount = 0
    private(set) var lastStats: [String: Any] = [:]
    private var scene: SKScene?
    private var preparedImages: [CGImage] = []
    private var preparedSpriteTextures: [SKTexture] = []
    private var retainedAtlas: SKTextureAtlas?
    private var submittedSampleCount = 0
    static let colors: [UIColor] = [.systemCyan, .systemOrange, .systemGray]

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear; isOpaque = false; isUserInteractionEnabled = false
        accessibilityElementsHidden = true
        particlesView.backgroundColor = .clear; particlesView.isUserInteractionEnabled = false
        sprite.backgroundColor = .clear; sprite.allowsTransparency = true
        sprite.isUserInteractionEnabled = false; sprite.ignoresSiblingOrder = true
        sprite.isPaused = true; sprite.isHidden = true
        [production, particlesView, sprite].forEach(addSubview)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
    override func layoutSubviews() {
        super.layoutSubviews()
        [production, particlesView, sprite].forEach { $0.frame = bounds }
        scene?.size = bounds.size
    }
    override func didMoveToWindow() { super.didMoveToWindow(); if window == nil { cancel() } }
    var isIdle: Bool { activeCount == 0 && production.particleLayerCount == 0 && (scene?.children.isEmpty ?? true) }
    func cancel() {
        removal?.cancel(); removal = nil
        production.cancel()
        particlesView.layer.sublayers?.forEach { $0.removeAllAnimations(); $0.removeFromSuperlayer() }
        scene?.removeAllActions(); scene?.removeAllChildren()
        sprite.isPaused = true; activeCount = 0
    }
    func reset() {
        cancel(); preparedImages = []; preparedSpriteTextures = []; retainedAtlas = nil
        sprite.presentScene(nil); scene = nil; sprite.isHidden = true
    }
    private func scale(_ spec: StudyScenario) -> CGFloat {
        spec.textureScale == 0 ? (window?.screen.scale ?? max(1, traitCollection.displayScale)) : spec.textureScale
    }
    private func images(_ spec: StudyScenario) -> [CGImage] {
        let shapes = spec.renderer == "paper" ? ConfettiShape.allCases : spec.shapeSet
        if spec.opaqueProxy {
            return Self.colors.flatMap { color in shapes.map { shape in
                let format = UIGraphicsImageRendererFormat(); format.scale = scale(spec); format.opaque = true
                return UIGraphicsImageRenderer(size: CGSize(width: spec.size * shape.width, height: spec.size * shape.height), format: format).image { c in
                    color.setFill(); c.fill(CGRect(x: 0, y: 0, width: spec.size * shape.width, height: spec.size * shape.height))
                }.cgImage!
            } }
        }
        let originals = ConfettiTextures.make(colors: Self.colors, size: spec.size, scale: scale(spec), shapes: shapes)
        guard spec.paddedTexture else { return originals }
        // Separate padded-linear control: test the filter independently of extra bitmap area.
        return originals.map { image in
            func powerOfTwo(_ n: Int) -> Int { var p = 1; while p < n { p *= 2 }; return p }
            let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = false
            return UIGraphicsImageRenderer(size: CGSize(width: powerOfTwo(image.width), height: powerOfTwo(image.height)), format: format).image { context in
                context.cgContext.interpolationQuality = .none
                UIImage(cgImage: image).draw(in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            }.cgImage!
        }
    }
    private func spriteTextures(_ images: [CGImage], atlas: Bool) -> [SKTexture] {
        if atlas {
            let packed = SKTextureAtlas(dictionary: Dictionary(uniqueKeysWithValues: images.enumerated().map { ("piece\($0.offset)", UIImage(cgImage: $0.element)) }))
            retainedAtlas = packed
            return images.indices.map { packed.textureNamed("piece\($0)") }
        }
        return images.map { SKTexture(cgImage: $0) }
    }
    /// Cache priming is outside the measured trial. A cold-textures case is launched alone in a fresh process.
    func prepare(_ spec: StudyScenario) async {
        reset()
        if spec.renderer == "sprite" {
            let scene = SKScene(size: bounds.size); scene.backgroundColor = .clear; scene.scaleMode = .resizeFill
            self.scene = scene; sprite.preferredFramesPerSecond = window?.screen.maximumFramesPerSecond ?? 60
            sprite.presentScene(scene); sprite.isPaused = true; sprite.isHidden = false
        }
        guard spec.prewarm, spec.renderer != "none" else { return }
        preparedImages = images(spec)
        if spec.renderer == "sprite" {
            preparedSpriteTextures = spriteTextures(preparedImages, atlas: spec.atlas)
            await withCheckedContinuation { continuation in
                SKTexture.preload(preparedSpriteTextures) { continuation.resume() }
            }
        }
    }
    @discardableResult func play(_ spec: StudyScenario, burst: ConfettiBurst) -> [String: Any] {
        cancel()
        guard !UIAccessibility.isReduceMotionEnabled, spec.renderer != "none" else { lastStats = ["requested_particles": 0]; return lastStats }
        let start = CACurrentMediaTime()
        if spec.renderer == "paper" {
            production.play(burst: burst, colors: Self.colors)
            lastStats = ["setup_ms": (CACurrentMediaTime() - start) * 1000, "requested_particles": production.particleLayerCount,
                         "particle_layers": production.particleLayerCount, "position_samples": 49, "native_count_is_estimate": false]
            return lastStats
        }
        let particles = burst.particles(paletteCount: Self.colors.count)
        let physicsEnd = CACurrentMediaTime()
        let textures = preparedImages.isEmpty ? images(spec) : preparedImages
        let textureEnd = CACurrentMediaTime()
        activeCount = particles.count
        submittedSampleCount = 0
        switch spec.renderer {
        case "layers": layers(particles, textures: textures, spec: spec)
        case "emitter": emitters(particles, textures: textures, spec: spec)
        case "sprite": spriteEmitters(particles, textures: textures, spec: spec)
        default: preconditionFailure("Unknown renderer")
        }
        let work = DispatchWorkItem { [weak self] in self?.cancel() }
        removal = work
        // Include the brief native birth window; cancellation still removes every layer/node.
        let lifetime = (particles.map(\.endTime).max() ?? 0) + 0.25
        DispatchQueue.main.asyncAfter(deadline: .now() + lifetime, execute: work)
        lastStats = ["setup_ms": (CACurrentMediaTime() - start) * 1000,
                     "physics_ms": (physicsEnd - start) * 1000, "texture_lookup_ms": (textureEnd - physicsEnd) * 1000,
                     "requested_particles": particles.count, "particle_layers": spec.renderer == "layers" ? particles.count : 0,
                     "submitted_position_samples": submittedSampleCount,
                     "native_count_is_estimate": spec.renderer == "emitter",
                     "native_motion_model": spec.renderer == "emitter" ? "shared-flight-v2" : spec.renderer == "sprite" ? "ballistic-v1" : "paper-physics",
                     "emitter_cohorts": spec.renderer == "emitter" ? (particlesView.layer.sublayers?.count ?? 0) : 0]
        return lastStats
    }
    private func index(_ p: ConfettiParticle, _ s: StudyScenario) -> Int { p.color * s.shapeSet.count + s.shapeSet.firstIndex(of: p.shape)! }
    private func layers(_ particles: [ConfettiParticle], textures: [CGImage], spec: StudyScenario) {
        let start = particlesView.layer.convertTime(CACurrentMediaTime(), from: nil)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for p in particles {
            let layer = CALayer()
            layer.bounds = CGRect(x: 0, y: 0, width: p.size * p.shape.width, height: p.size * p.shape.height)
            layer.contents = textures[index(p, spec)]; layer.contentsScale = scale(spec); layer.opacity = 0
            layer.isOpaque = spec.opaqueProxy
            if spec.paddedTexture {
                let image = textures[index(p, spec)]
                // Keep the original point-size silhouette after padding the backing image.
                layer.contentsRect = CGRect(x: 0, y: 0,
                    width: ceil(spec.size * p.shape.width * scale(spec)) / Double(image.width),
                    height: ceil(spec.size * p.shape.height * scale(spec)) / Double(image.height))
            }
            layer.minificationFilter = spec.trilinear ? .trilinear : .linear
            let track = StudyTrack(particle: p, spec: spec)
            submittedSampleCount += track.times.count
            let position = CAKeyframeAnimation(keyPath: "position")
            position.values = track.positions.map { NSValue(cgPoint: $0) }
            position.keyTimes = track.times.map { NSNumber(value: $0 / p.lifetime) }
            position.calculationMode = .linear
            let alpha = CAKeyframeAnimation(keyPath: "opacity")
            alpha.values = track.opacities
            alpha.keyTimes = position.keyTimes
            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.fromValue = p.phase; spin.toValue = p.phase + p.spin * p.lifetime
            let tumble = CABasicAnimation(keyPath: "transform.rotation.x")
            tumble.fromValue = p.phase; tumble.toValue = p.phase + p.tumble * p.lifetime
            let group = CAAnimationGroup()
            group.animations = spec.tumble ? [position, alpha, spin, tumble] : [position, alpha, spin]
            group.duration = p.lifetime; group.beginTime = start + p.delay
            group.timingFunction = CAMediaTimingFunction(name: .linear)
            group.animations?.forEach { $0.duration = p.lifetime }
            particlesView.layer.addSublayer(layer); layer.add(group, forKey: "flight")
        }
        CATransaction.commit()
        // Accuracy is audited after measurement; no extra per-particle validation in the timed setup.
    }
    private func groups(_ particles: [ConfettiParticle]) -> [[ConfettiParticle]] {
        // Stable groups preserve the requested per-cannon shape/color population and one speed per shape.
        let groups = Dictionary(grouping: particles) { "\($0.delay)|\($0.shape.rawValue)|\($0.color)" }
        return groups.keys.sorted().map { groups[$0]! }
    }
    private func nativeCohorts(_ particles: [ConfettiParticle]) -> [[ConfettiParticle]] {
        groups(particles).flatMap { group in
            stride(from: 0, to: group.count, by: 4).map { Array(group[$0..<min($0 + 4, group.count)]) }
        }
    }
    private func emitters(_ particles: [ConfettiParticle], textures: [CGImage], spec: StudyScenario) {
        let start = particlesView.layer.convertTime(CACurrentMediaTime(), from: nil)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for group in nativeCohorts(particles) {
            let p = group[0]
            // A small cohort shares one flight, rather than creating a layer and four
            // animations for every particle. Native cells still render/spin independently.
            // Moving the entire layer moves its live particles; emitterPosition alone
            // would only move the birthplace of particles emitted later.
            let emitter = CAEmitterLayer()
            emitter.emitterPosition = .zero
            emitter.emitterShape = .rectangle; emitter.emitterSize = CGSize(width: 10, height: 4)
            emitter.renderMode = .unordered
            emitter.seed = UInt32(truncatingIfNeeded: p.phase.bitPattern ^ p.delay.bitPattern)
            emitter.beginTime = start + p.delay
            emitter.opacity = 0
            let cell = CAEmitterCell()
            cell.contents = textures[index(p, spec)]; cell.contentsScale = scale(spec)
            cell.birthRate = Float(group.count) / 0.06; cell.duration = 0.06
            cell.lifetime = Float(p.lifetime + 0.06)
            // The shared path supplies launch, deceleration and shape-specific rain.
            // Small native drift separates the cohort without the old runaway gravity
            // or continued sideways spray. No private CAEmitterBehavior APIs are used.
            cell.velocity = 0
            cell.velocityRange = CGFloat(p.flutter * 1.2)
            cell.emissionLongitude = 0; cell.emissionRange = 0
            cell.xAcceleration = 0; cell.yAcceleration = 0
            cell.scale = 1; cell.scaleRange = 0.2
            cell.spin = CGFloat(p.spin); cell.spinRange = 1.5
            emitter.emitterCells = [cell]

            let track = StudyTrack(particle: p, spec: spec, forceAdaptive: true)
            submittedSampleCount += track.times.count
            let flight = CAKeyframeAnimation(keyPath: "position")
            flight.values = track.positions.map { NSValue(cgPoint: $0) }
            flight.keyTimes = track.times.map { NSNumber(value: $0 / p.lifetime) }
            flight.calculationMode = .linear
            let alpha = CAKeyframeAnimation(keyPath: "opacity")
            alpha.values = track.opacities; alpha.keyTimes = flight.keyTimes
            let animation = CAAnimationGroup()
            animation.animations = [flight, alpha]
            animation.duration = p.lifetime
            animation.animations?.forEach { $0.duration = p.lifetime }
            // Explicit local zero: a literal zero is Core Animation's "start now" default.
            animation.beginTime = 0.000001
            animation.timingFunction = CAMediaTimingFunction(name: .linear)
            particlesView.layer.addSublayer(emitter)
            emitter.add(animation, forKey: "shared-flight")
        }
        CATransaction.commit()
    }
    private func spriteEmitters(_ particles: [ConfettiParticle], textures: [CGImage], spec: StudyScenario) {
        guard let scene else { preconditionFailure("SpriteKit scene was not prepared") }
        let atlas = preparedSpriteTextures.isEmpty ? spriteTextures(textures, atlas: spec.atlas) : preparedSpriteTextures
        sprite.isPaused = false
        for group in groups(particles) {
            let p = group[0], emitter = SKEmitterNode()
            emitter.particleTexture = atlas[index(p, spec)]
            emitter.particleSize = CGSize(width: spec.size * p.shape.width, height: spec.size * p.shape.height)
            emitter.particleBirthRate = CGFloat(group.count) / 0.06; emitter.numParticlesToEmit = group.count
            emitter.particleLifetime = p.lifetime
            emitter.position = CGPoint(x: p.x, y: bounds.height - p.y)
            emitter.emissionAngle = .pi / 2; emitter.emissionAngleRange = .pi * 40 / 180
            emitter.particleSpeed = 430; emitter.particleSpeedRange = 30
            emitter.yAcceleration = -710 * CGFloat(p.fallSpeed)
            emitter.particleScale = 1; emitter.particleScaleRange = 0.4
            emitter.particleRotationSpeed = 5; emitter.particleRotationRange = .pi * 2
            emitter.particleAlphaSpeed = -1 / CGFloat(p.lifetime)
            emitter.targetNode = scene
            scene.run(.sequence([.wait(forDuration: p.delay), .run { [weak scene] in scene?.addChild(emitter) }]))
        }
    }
    /// These diagnostics run after the measurement interval, never in animation frames.
    func audit(_ spec: StudyScenario, burst: ConfettiBurst) -> [String: Any] {
        guard spec.renderer != "none" else { return ["textures": [], "texture_bytes": 0] }
        let textures = images(spec)
        let shapes = spec.renderer == "paper" ? ConfettiShape.allCases : spec.shapeSet
        let details: [[String: Any]] = textures.enumerated().map { offset, image in
            let width = image.width, height = image.height
            var rgba = [UInt8](repeating: 0, count: width * height * 4)
            rgba.withUnsafeMutableBytes { data in
                let c = CGContext(data: data.baseAddress, width: width, height: height, bitsPerComponent: 8,
                    bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                c.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            }
            let nonzero = stride(from: 3, to: rgba.count, by: 4).filter { rgba[$0] > 0 }.count
            return ["shape": String(describing: shapes[offset % shapes.count]), "color": offset / shapes.count,
                    "width_px": width, "height_px": height, "bytes": image.bytesPerRow * height,
                    "nontransparent_fraction": Double(nonzero) / Double(width * height)]
        }
        var maxPositionError = 0.0, maxOpacityError = 0.0
        var sampleCounts: [Int] = []
        if ["layers", "paper", "emitter"].contains(spec.renderer) {
            let all = burst.particles(paletteCount: 3)
            let audited = spec.renderer == "emitter" ? nativeCohorts(all).map { $0[0] } : all
            for p in audited {
                let track = StudyTrack(particle: p, spec: spec, forceAdaptive: spec.renderer == "emitter")
                sampleCounts.append(track.times.count)
                var lo = 0
                for step in 0...960 {
                    let t = Double(step) / 960 * p.lifetime
                    while lo < track.times.count - 2 && track.times[lo + 1] < t { lo += 1 }
                    let mix = (t - track.times[lo]) / (track.times[lo + 1] - track.times[lo])
                    let a = track.positions[lo], b = track.positions[lo + 1], exact = p.position(at: t)
                    maxPositionError = max(maxPositionError, hypot(exact.x - (a.x + (b.x - a.x) * mix), exact.y - (a.y + (b.y - a.y) * mix)))
                    let alpha = track.opacities[lo], beta = track.opacities[lo + 1]
                    maxOpacityError = max(maxOpacityError, abs(p.opacity(at: t) - (alpha + (beta - alpha) * mix)))
                }
            }
        }
        return ["trajectory_audit_scope": spec.renderer == "emitter" ? "shared-cohort-path-excludes-native-drift" : "individual-particles",
                "textures": details, "texture_bytes": textures.reduce(0) { $0 + $1.bytesPerRow * $1.height },
                "minimum_track_samples": sampleCounts.min() as Any? ?? NSNull(), "maximum_track_samples": sampleCounts.max() as Any? ?? NSNull(),
                "position_interpolation_max_error_points": sampleCounts.isEmpty ? NSNull() : maxPositionError as Any,
                "opacity_interpolation_max_error": sampleCounts.isEmpty ? NSNull() : maxOpacityError as Any]
    }
}

struct StudyRendererHost: UIViewRepresentable {
    let view: StudyRenderer
    func makeUIView(context: Context) -> StudyRenderer { view }
    func updateUIView(_ uiView: StudyRenderer, context: Context) {}
    static func dismantleUIView(_ uiView: StudyRenderer, coordinator: ()) { uiView.reset() }
}

/// Compare approximation quality independently of display delivery. This is deliberately
/// benchmark-only until device CPU/commit costs and visual results justify a library change.
private struct StudyTrack {
    let times: [Double]
    let positions: [CGPoint]
    let opacities: [Double]
    init(particle p: ConfettiParticle, spec: StudyScenario, forceAdaptive: Bool = false) {
        if forceAdaptive || spec.sampling == "adaptive" {
            var times: [Double] = [0]
            func split(_ a: Double, _ b: Double, depth: Int) {
                let start = p.position(at: a), end = p.position(at: b)
                let alpha = p.opacity(at: a), beta = p.opacity(at: b)
                var needsSplit = false
                for fraction in [0.25, 0.5, 0.75] {
                    let t = a + (b - a) * fraction, exact = p.position(at: t)
                    let error = hypot(exact.x - (start.x + (end.x - start.x) * fraction), exact.y - (start.y + (end.y - start.y) * fraction))
                    if error > 0.5 || abs(p.opacity(at: t) - (alpha + (beta - alpha) * fraction)) > 0.015 { needsSplit = true }
                }
                if needsSplit && depth < 7 {
                    let mid = (a + b) / 2
                    split(a, mid, depth: depth + 1); split(mid, b, depth: depth + 1)
                } else { times.append(b) }
            }
            let anchors = [0, min(0.025, p.launchDuration), p.launchDuration,
                           p.launchDuration + p.fallDuration * p.fadeOutStart, p.lifetime]
            for (a,b) in zip(anchors, anchors.dropFirst()) where b > a { split(a,b,depth:0) }
            self.times = times
        } else {
            times = (0...spec.samples).map { Double($0) / Double(spec.samples) * p.lifetime }
        }
        positions = times.map { let point = p.position(at: $0); return CGPoint(x: point.x, y: point.y) }
        opacities = times.map { p.opacity(at: $0) }
    }
}
