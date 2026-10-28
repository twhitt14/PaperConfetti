#if canImport(UIKit)
import UIKit

/// Native-particle renderer for UIKit and the SwiftUI overlays. A pop replaces the
/// previous burst. Particle positions stay in the view's captured local coordinates.
@MainActor public final class ConfettiLayerView: UIView {
    private(set) var hasEnteredWindow = false
    var layoutReady: (() -> Void)?
    private var lastBurst: ConfettiBurst?
    private var cleanup: DispatchWorkItem?
    private var generation = 0
    private var gate: ConfettiLaunchGate?
    // Exactly representable reciprocal; longer than every bounded burst (under 305s).
    // Start one emission period into local time instead of closing a tiny birth window.
    static let emissionPeriod: TimeInterval = 1_024
    /// Requested active population, not a readback of Core Animation's live particles.
    public private(set) var particleLayerCount = 0
    /// Preparation plus asynchronous start headroom, in seconds. Not first-frame latency.
    /// Nil until the current launch is armed; retained after natural completion/cancel.
    public private(set) var scheduledStartDelay: TimeInterval?

    public override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false; backgroundColor = .clear; isOpaque = false
        accessibilityElementsHidden = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public func show(burst: ConfettiBurst, colors: [UIColor], enabled: Bool = true) {
        guard burst != lastBurst else { if !enabled { cancel() }; return }
        lastBurst = burst
        guard enabled else { cancel(); return }
        play(burst: burst, colors: colors)
    }

    /// Play an explicit event, including repeated identical seeds. UIKit hosts own
    /// Reduce Motion/scene policy; the SwiftUI modifier supplies it automatically.
    public func play(burst: ConfettiBurst, colors: [UIColor]) {
        cancel(); scheduledStartDelay = nil
        let started = CACurrentMediaTime()
        let particles = burst.particles(paletteCount: colors.count)
        guard !particles.isEmpty else { return }
        let colors = colors.prefix(16).map { $0.resolvedColor(with: traitCollection) }
        let scale = max(1, window?.screen.scale ?? traitCollection.displayScale)
        let shapes = Array(Set(particles.map(\.shape))).sorted { $0.rawValue < $1.rawValue }
        let textures = ConfettiNativeTextures.make(colors: colors, size: burst.size, scale: scale, shapes: shapes)
        let clock = CALayer(); clock.name = "PaperConfetti.Clock"
        clock.speed = 0; clock.timeOffset = Self.emissionPeriod
        let token = generation
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for p in particles {
            let emitter = CAEmitterLayer()
            emitter.emitterPosition = .zero; emitter.emitterShape = .rectangle
            emitter.emitterSize = CGSize(width: 12, height: 8)
            emitter.renderMode = .unordered; emitter.preservesDepth = false
            emitter.seed = UInt32(truncatingIfNeeded: p.phase.bitPattern ^ p.delay.bitPattern ^ p.dx.bitPattern)
            emitter.opacity = 0
            // All cells share a clock. Cannon delays apply to visible flight only.
            emitter.beginTime = 0.000001
            let cell = CAEmitterCell()
            let shape = shapes.firstIndex(of: p.shape)!
            let pose = Int(p.phase / (2 * .pi) * 8) % 8
            cell.contents = textures[(p.color * shapes.count + shape) * 8 + pose]
            cell.contentsScale = scale
            // Leave emission enabled: a short cell.duration can expire before the
            // render server first visits a large layer tree. The pre-rolled clock
            // crosses the first birth immediately, with the next safely beyond cleanup.
            // CAEmitterCell exposes a rate, not an exact-count emission operation.
            cell.birthRate = Float(1 / Self.emissionPeriod)
            cell.lifetime = Float(p.endTime + 0.06)
            cell.velocity = 0 // The sampled flight owns translation, including while waiting.
            cell.velocityRange = 0; cell.emissionLongitude = 0; cell.emissionRange = 0
            cell.xAcceleration = 0; cell.yAcceleration = 0
            cell.scale = CGFloat(p.size / burst.size); cell.scaleRange = 0
            cell.spin = CGFloat(p.spin); cell.spinRange = 0
            emitter.emitterCells = [cell]
            let track = ConfettiTrack(p)
            let motion = CAKeyframeAnimation(keyPath: "position")
            motion.values = track.positions.map { NSValue(cgPoint: $0) }
            motion.keyTimes = track.times.map { NSNumber(value: $0 / p.lifetime) }
            motion.calculationMode = .linear
            let opacity = CAKeyframeAnimation(keyPath: "opacity")
            opacity.values = track.opacities; opacity.keyTimes = motion.keyTimes
            let group = CAAnimationGroup(); group.animations = [motion, opacity]
            if burst.appearance == .threeDimensional {
                let tilt = CABasicAnimation(keyPath: "transform.rotation.x")
                tilt.fromValue = p.phase; tilt.toValue = p.phase + p.tumble * p.lifetime
                group.animations?.append(tilt)
            }
            group.duration = p.lifetime; group.beginTime = Self.emissionPeriod + max(0.000001, p.delay)
            group.timingFunction = CAMediaTimingFunction(name: .linear)
            group.animations?.forEach { $0.duration = p.lifetime }
            clock.addSublayer(emitter); emitter.add(group, forKey: "flight")
        }
        // Freeze the expensive tree while submitting it, then arm ONE parent clock.
        // Keep a measured nonblocking margin for render-server activation at high loads.
        let lead = max(1.0 / 30, min(0.2, Double(particles.count) / 40_000))
        let lifetime = (particles.map(\.endTime).max() ?? 0) + 0.25
        layer.addSublayer(clock)
        let marker = CALayer(); marker.name = "PaperConfetti.Readiness"; layer.addSublayer(marker)
        let gate = ConfettiLaunchGate { [weak self, weak clock, weak marker] in
            guard let self, let clock, self.generation == token, clock.superlayer != nil else { return }
            CATransaction.begin(); CATransaction.setDisableActions(true)
            marker?.removeFromSuperlayer()
            clock.beginTime = self.layer.convertTime(CACurrentMediaTime(), from: nil) + lead
            clock.speed = 1
            CATransaction.commit()
            self.scheduledStartDelay = CACurrentMediaTime() - started + lead
            self.gate = nil
            self.scheduleCleanup(after: lifetime + lead)
        }
        self.gate = gate
        let ready = CABasicAnimation(keyPath: "opacity")
        ready.fromValue = 0; ready.toValue = 0; ready.duration = 1.0 / 60; ready.delegate = gate
        marker.add(ready, forKey: "ready")
        particleLayerCount = particles.count
        CATransaction.commit()
        // Also bound detached/offscreen UIKit calls whose marker cannot run.
        scheduleCleanup(after: lifetime + 2)
    }

    private func scheduleCleanup(after duration: TimeInterval) {
        cleanup?.cancel()
        let token = generation
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.generation == token else { return }; self.cancel()
        }
        cleanup = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }
    public func cancel() {
        generation += 1; gate = nil
        cleanup?.cancel(); cleanup = nil
        layer.sublayers?.forEach { $0.removeAllAnimations(); $0.removeFromSuperlayer() }
        particleLayerCount = 0
    }
    public override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
    public override func layoutSubviews() { super.layoutSubviews(); layoutReady?() }
    public override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { cancel() } else { hasEnteredWindow = true; layoutReady?() }
    }
}

private final class ConfettiLaunchGate: NSObject, CAAnimationDelegate {
    let ready: @MainActor () -> Void
    init(_ ready: @escaping @MainActor () -> Void) { self.ready = ready }
    func animationDidStop(_ animation: CAAnimation, finished: Bool) {
        guard finished else { return }
        Task { @MainActor in ready() }
    }
}

/// Adaptive samples preserve fast rise curvature without expensive uniform oversampling.
struct ConfettiTrack {
    let times: [Double]
    let positions: [CGPoint]
    let opacities: [Double]
    init(_ p: ConfettiParticle) {
        var times = [0.0]
        func split(_ a: Double, _ b: Double, depth: Int) {
            let start = p.position(at: a), end = p.position(at: b)
            let alpha = p.opacity(at: a), beta = p.opacity(at: b)
            var refine = false
            for fraction in [0.25, 0.5, 0.75] {
                let t = a + (b - a) * fraction, exact = p.position(at: t)
                if hypot(exact.x - (start.x + (end.x - start.x) * fraction),
                         exact.y - (start.y + (end.y - start.y) * fraction)) > 0.5 ||
                    abs(p.opacity(at: t) - (alpha + (beta - alpha) * fraction)) > 0.015 { refine = true }
            }
            if refine && depth < 7 { let mid = (a + b) / 2; split(a, mid, depth: depth + 1); split(mid, b, depth: depth + 1) }
            else { times.append(b) }
        }
        let anchors = Array(Set([0, min(0.025, p.launchDuration), p.launchDuration,
                                 p.launchDuration + p.fallDuration * p.fadeOutStart, p.lifetime])).sorted()
        for (a,b) in zip(anchors, anchors.dropFirst()) where b > a { split(a,b,depth:0) }
        self.times = times
        positions = times.map { let value = p.position(at: $0); return CGPoint(x: value.x, y: value.y) }
        opacities = times.map { p.opacity(at: $0) }
    }
}
#endif
