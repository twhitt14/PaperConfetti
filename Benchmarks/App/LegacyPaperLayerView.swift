import UIKit
import PaperConfetti
// Frozen PaperConfetti 0.1.0 renderer; MIT. Benchmark only.
    /// Public for UIKit hosts and the comparison harness. One bounded animation group per particle.
    @MainActor public final class LegacyPaperLayerView: UIView {
        private(set) var hasEnteredWindow = false
        var layoutReady: (() -> Void)?
        private var lastBurst: LegacyConfettiBurst?
        private var cleanup: DispatchWorkItem?
        public private(set) var particleLayerCount = 0
        public override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            backgroundColor = .clear
            isOpaque = false
            accessibilityElementsHidden = true
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        public func show(burst: LegacyConfettiBurst, colors: [UIColor], enabled: Bool = true) {
            // Do not replay a completed/canceled burst on scene activation or a parent update.
            guard burst != lastBurst else {
                if !enabled { cancel() }
                return
            }
            lastBurst = burst
            guard enabled else {
                cancel()
                return
            }
            play(burst: burst, colors: colors)
        }

        /// An explicit event: identical seeded bursts may be played again intentionally.
        public func play(burst: LegacyConfettiBurst, colors: [UIColor]) {
            cancel()
            guard !colors.isEmpty else { return }
            let particles = burst.particles(paletteCount: colors.count)
            guard !particles.isEmpty else { return }
            let scale = window?.screen.scale ?? traitCollection.displayScale
            let textures = ConfettiTextures.make(
                colors: Array(colors.prefix(16)).map { $0.resolvedColor(with: traitCollection) },
                size: burst.size, scale: max(1, scale), shapes: ConfettiShape.allCases)
            let start = layer.convertTime(CACurrentMediaTime(), from: nil)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for particle in particles {
                let paper = CALayer()
                paper.bounds = CGRect(
                    x: 0, y: 0, width: particle.size * particle.shape.width,
                    height: particle.size * particle.shape.height)
                paper.position = CGPoint(x: particle.x, y: particle.y)
                paper.contents =
                    textures[particle.color * ConfettiShape.allCases.count + particle.shape.rawValue]
                paper.contentsScale = max(1, scale)
                paper.opacity = 0
                // Small textures are shared by all particles. No per-frame path rasterization.
                let motion = CAKeyframeAnimation(keyPath: "position")
                let samples = 48
                motion.values = (0...samples).map { step -> NSValue in
                    let p = particle.position(at: Double(step) / Double(samples) * particle.lifetime)
                    return NSValue(cgPoint: CGPoint(x: p.x, y: p.y))
                }
                motion.calculationMode = .linear
                let opacity = CAKeyframeAnimation(keyPath: "opacity")
                opacity.values = (0...samples).map {
                    particle.opacity(at: Double($0) / Double(samples) * particle.lifetime)
                }
                let spin = CABasicAnimation(keyPath: "transform.rotation.z")
                spin.fromValue = particle.phase
                spin.toValue = particle.phase + particle.spin * particle.lifetime
                let tumble = CABasicAnimation(keyPath: "transform.rotation.x")
                tumble.fromValue = particle.phase
                tumble.toValue = particle.phase + particle.tumble * particle.lifetime
                let group = CAAnimationGroup()
                group.animations = [motion, opacity, spin, tumble]
                group.duration = particle.lifetime
                group.beginTime = start + particle.delay
                group.timingFunction = CAMediaTimingFunction(name: .linear)
                for animation in group.animations! { animation.duration = particle.lifetime }
                layer.addSublayer(paper)
                paper.add(group, forKey: "flight")
            }
            particleLayerCount = particles.count
            CATransaction.commit()
            let removal = DispatchWorkItem { [weak self] in self?.cancel() }
            cleanup = removal
            DispatchQueue.main.asyncAfter(
                deadline: .now() + (particles.map(\.endTime).max() ?? 0) + 0.15, execute: removal)
        }

        public func cancel() {
            cleanup?.cancel()
            cleanup = nil
            layer.sublayers?.forEach {
                $0.removeAllAnimations()
                $0.removeFromSuperlayer()
            }
            particleLayerCount = 0
        }
        /// Always decorative, even if a host accidentally re-enables interaction.
        public override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }

        public override func layoutSubviews() {
            super.layoutSubviews()
            layoutReady?()
        }

        public override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil {
                cancel()
            } else {
                hasEnteredWindow = true
                layoutReady?()
            }
        }
    }

