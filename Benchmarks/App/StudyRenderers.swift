import UIKit
import SwiftUI
import PaperConfetti

/// Benchmarks only. The released renderer and public package API stay unchanged.
@MainActor final class StudyRenderer: UIView {
    let production = LegacyPaperLayerView()
    private let native = ConfettiLayerView()
    private var usingProductionNative = false
    private let particlesView = UIView()
    private var removal: DispatchWorkItem?
    private(set) var activeCount = 0
    private(set) var lastStats: [String: Any] = [:]
    private var preparationID = 0
    private var preparedImages: [CGImage] = []
    private var preparedNativeImages: [CGImage] = []
    private var nativePoseCache: (key: String, images: [CGImage])?
    private var submittedSampleCount = 0
    private var nativeGate: NativeLaunchGate?
    private var nativeGeneration = 0
    private var nativeEmitterCount = 0
    private var nativeArmDelay: Double?
    private var nativeSetupStart = 0.0
    static let colors: [UIColor] = [.systemCyan, .systemOrange, .systemGray]

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear; isOpaque = false; isUserInteractionEnabled = false
        accessibilityElementsHidden = true
        particlesView.backgroundColor = .clear; particlesView.isUserInteractionEnabled = false
        [production, particlesView, native].forEach(addSubview)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
    override func layoutSubviews() {
        super.layoutSubviews()
        [production, particlesView, native].forEach { $0.frame = bounds }
    }
    override func didMoveToWindow() { super.didMoveToWindow(); if window == nil { cancel() } }
    var isIdle: Bool { activeCount == 0 && production.particleLayerCount == 0 && native.particleLayerCount == 0 }
    func cancel() {
        nativeGeneration += 1; nativeGate = nil
        removal?.cancel(); removal = nil
        production.cancel(); native.cancel()
        particlesView.layer.sublayers?.forEach { $0.removeAllAnimations(); $0.removeFromSuperlayer() }
        activeCount = 0
    }
    func reset() {
        preparationID += 1
        cancel(); preparedImages = []; preparedNativeImages = []
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
    /// Public CAEmitterCell has spin speed but no starting rotation. Bake eight small
    /// bitmap orientations; retain just the most recent set, not an unbounded cache.
    private func nativeImages(_ images: [CGImage], spec: StudyScenario) -> [CGImage] {
        let key = "\(spec.size)|\(scale(spec))|\(spec.shapes)|\(spec.opaqueProxy)|\(spec.paddedTexture)|\(traitCollection.userInterfaceStyle.rawValue)"
        if let cached = nativePoseCache, cached.key == key { return cached.images }
        let poses = images.flatMap { image in
            (0..<NativeParticlePlan.poseCount).map { pose in
                let side = ceil(hypot(Double(image.width), Double(image.height))) + 2
                let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = false
                return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { c in
                    c.cgContext.translateBy(x: side / 2, y: side / 2)
                    c.cgContext.rotate(by: Double(pose) * 2 * .pi / Double(NativeParticlePlan.poseCount))
                    let width = CGFloat(image.width), height = CGFloat(image.height)
                    let rect = CGRect(x: -width / 2, y: -height / 2, width: width, height: height)
                    UIImage(cgImage: image).draw(in: rect)
                }.cgImage!
            }
        }
        nativePoseCache = (key, poses)
        return poses
    }
    /// Warm the same package textures outside the timed trial.
    func prepare(_ spec: StudyScenario) async {
        reset()
        if spec.prewarm && spec.renderer != "none" {
            preparedImages = images(spec)
            if spec.renderer == "emitter" {
                if spec.sharedFlight == true || ProcessInfo.processInfo.arguments.contains("--native-legacy-clock") { preparedNativeImages = nativeImages(preparedImages, spec: spec) }
                var b = spec.burst(size: bounds.size, seed: 1000)
                b.appearance = spec.native3D == true ? .threeDimensional : .flat
                native.play(burst: b, colors: Self.colors); native.cancel()
            }
        }
    }

    @discardableResult func play(_ spec: StudyScenario, burst: ConfettiBurst) -> [String: Any] {
        cancel()
        guard !UIAccessibility.isReduceMotionEnabled, spec.renderer != "none" else { lastStats = ["requested_particles": 0]; return lastStats }
        let start = CACurrentMediaTime()
        if spec.renderer == "paper" {
            production.play(burst: LegacyConfettiBurst(burst), colors: Self.colors)
            lastStats = ["setup_ms": (CACurrentMediaTime() - start) * 1000, "requested_particles": production.particleLayerCount,
                         "particle_layers": production.particleLayerCount, "position_samples": 49, "native_count_is_estimate": false]
            return lastStats
        }
        usingProductionNative = spec.renderer == "emitter" && spec.sharedFlight != true && !ProcessInfo.processInfo.arguments.contains("--native-legacy-clock")
        if usingProductionNative {
            var b = burst; b.appearance = spec.native3D == true ? .threeDimensional : .flat
            CATransaction.begin(); CATransaction.setDisableActions(true)
            native.play(burst: b, colors: Self.colors)
            configureProductionProbe(spec)
            if let arg = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--native-stall-ms=") }),
               let ms = Double(arg.dropFirst("--native-stall-ms=".count)), ms.isFinite {
                Thread.sleep(forTimeInterval: max(0, min(1, ms / 1000)))
            }
            CATransaction.commit()
            lastStats = ["setup_ms": (CACurrentMediaTime() - start) * 1000,
                         "requested_particles": native.particleLayerCount, "native_count_is_estimate": true,
                         "native_motion_model": "PaperConfetti-0.2-native", "tilt_enabled": b.appearance == .threeDimensional]
            return lastStats
        }
        let particles = StudyPopulation.particles(burst, paletteCount: Self.colors.count)
        let physicsEnd = CACurrentMediaTime()
        let textures = preparedImages.isEmpty ? images(spec) : preparedImages
        let nativeTextures = spec.renderer == "emitter"
            ? (preparedNativeImages.isEmpty ? nativeImages(textures, spec: spec) : preparedNativeImages) : []
        let textureEnd = CACurrentMediaTime()
        activeCount = particles.count
        submittedSampleCount = 0
        nativeEmitterCount = 0; nativeArmDelay = nil; nativeSetupStart = start
        switch spec.renderer {
        case "layers": layers(particles, textures: textures, spec: spec)
        case "emitter": emitters(particles, textures: nativeTextures, spec: spec)
        default: preconditionFailure("Unknown renderer")
        }
        // Native cleanup is scheduled when its staged clock actually starts.
        if spec.renderer != "emitter" { scheduleCleanup(after: (particles.map { $0.delay + StudyFlight.duration($0) }.max() ?? 0) + 0.25) }
        lastStats = ["setup_ms": (CACurrentMediaTime() - start) * 1000,
                     "physics_ms": (physicsEnd - start) * 1000, "texture_lookup_ms": (textureEnd - physicsEnd) * 1000,
                     "requested_particles": particles.count, "particle_layers": spec.renderer == "layers" ? particles.count : 0,
                     "submitted_position_samples": submittedSampleCount,
                     "native_count_is_estimate": spec.renderer == "emitter",
                     "population_batches": Int(ceil(Double(particles.count) / 2_000)),
                     "shared_flight": spec.sharedFlight == true,
                     "tilt_enabled": spec.native3D == true,
                     "native_motion_model": spec.sharedFlight == true ? "parabolic-v5-soft-edge-shared-diagnostic" : "parabolic-v5-soft-edge-individual-timing",
                     "native_pose_texture_count": nativeTextures.count,
                     "native_pose_texture_bytes": nativeTextures.reduce(0) { $0 + $1.bytesPerRow * $1.height },
                     "emitter_cohorts": nativeEmitterCount]
        return lastStats
    }
    private func index(_ p: ConfettiParticle, _ s: StudyScenario) -> Int { p.color * s.shapeSet.count + s.shapeSet.firstIndex(of: p.shape)! }
    private func layers(_ particles: [ConfettiParticle], textures: [CGImage], spec: StudyScenario) {
        var scheduled: [(CALayer, CAAnimationGroup, Double)] = []
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for p in particles {
            let duration = StudyFlight.duration(p)
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
            position.keyTimes = track.times.map { NSNumber(value: $0 / duration) }
            position.calculationMode = .linear
            let alpha = CAKeyframeAnimation(keyPath: "opacity")
            alpha.values = track.opacities
            alpha.keyTimes = position.keyTimes
            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.fromValue = p.phase; spin.toValue = p.phase + p.spin * duration
            let tumble = CABasicAnimation(keyPath: "transform.rotation.x")
            tumble.fromValue = p.phase; tumble.toValue = p.phase + p.tumble * duration
            let group = CAAnimationGroup()
            group.animations = spec.tumble ? [position, alpha, spin, tumble] : [position, alpha, spin]
            group.duration = duration
            group.timingFunction = CAMediaTimingFunction(name: .linear)
            group.animations?.forEach { $0.duration = duration }
            particlesView.layer.addSublayer(layer); scheduled.append((layer, group, p.delay))
        }
        let start = particlesView.layer.convertTime(CACurrentMediaTime(), from: nil) + 1.0 / 60
        for (layer, animation, delay) in scheduled {
            animation.beginTime = start + delay; layer.add(animation, forKey: "flight")
        }
        CATransaction.commit()
        // Accuracy is audited after measurement; no extra per-particle validation in the timed setup.
    }
    private func emitters(_ particles: [ConfettiParticle], textures: [CGImage], spec: StudyScenario) {
        let cohorts = NativeParticlePlan.groups(particles, shared: spec.sharedFlight == true)
        let args = ProcessInfo.processInfo.arguments
        func optionSeconds(_ prefix: String) -> Double? {
            guard let argument = args.first(where: { $0.hasPrefix(prefix) }),
                  let ms = Double(argument.dropFirst(prefix.count)), ms.isFinite else { return nil }
            return max(0, min(1, ms / 1000))
        }
        let legacy = args.contains("--native-legacy-clock")
        let gridProbe = args.contains("--emission-grid")
        let emissionProbe = args.contains("--emission-probe")
        let preroll = optionSeconds("--native-preroll-ms=") ?? 0
        let clock = CALayer()
        clock.speed = 0; clock.timeOffset = 0
        let generation = nativeGeneration
        nativeEmitterCount = cohorts.count
        var scheduled: [(layer: CAEmitterLayer, delay: Double)] = []
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for (flightIndex, cohort) in cohorts.enumerated() {
            let p = cohort.members[0]
            let emitter = CAEmitterLayer()
            emitter.emitterPosition = .zero
            emitter.emitterShape = gridProbe ? .point : .rectangle; emitter.emitterSize = gridProbe ? .zero : CGSize(width: 12, height: 8)
            emitter.renderMode = .unordered
            // Each default plan is one piece. Flatten it before tilting its plane;
            // preservesDepth does not supply an independent particle X/Y spin.
            emitter.preservesDepth = false
            emitter.seed = UInt32(truncatingIfNeeded: p.phase.bitPattern ^ p.delay.bitPattern ^ p.dx.bitPattern)
            scheduled.append((emitter, cohort.delay))
            emitter.opacity = 0
            emitter.emitterCells = cohort.members.map { piece in
                let cell = CAEmitterCell()
                let pose = NativeParticlePlan.poseIndex(for: piece)
                cell.contents = textures[index(piece, spec) * NativeParticlePlan.poseCount + pose]
                cell.contentsScale = scale(spec)
                // Place the first birth safely INSIDE the window, not on its end:
                // 25/s births at 40ms; the next (80ms) is beyond the 60ms window.
                // A rate of 1/duration can produce zero pieces at the boundary.
                // Native birth counts remain estimates; there is no exact-count API.
                cell.birthRate = 25; cell.duration = 0.06
                cell.lifetime = Float(cohort.duration + 0.06)
                cell.velocity = CGFloat(cos(piece.phase) * piece.flutter * 0.5)
                cell.velocityRange = 0; cell.emissionLongitude = 0; cell.emissionRange = 0
                cell.xAcceleration = 0; cell.yAcceleration = 0
                cell.scale = CGFloat((gridProbe ? 1.4 : piece.size) / spec.size); cell.scaleRange = 0
                cell.spin = CGFloat(piece.spin); cell.spinRange = 0
                return cell
            }
            // Submit the cached individual flight once; only the explicit shared
            // diagnostic averages nearby trajectories. No per-frame app callbacks.
            let track = StudyTrack(cohort: cohort)
            submittedSampleCount += track.times.count
            let flight = CAKeyframeAnimation(keyPath: "position")
            let columns = 60, rows = max(1, Int(ceil(Double(cohorts.count) / 60)))
            let gridPoint = CGPoint(x: (Double(flightIndex % columns) + 0.5) * bounds.width / Double(columns),
                                    y: bounds.height * 0.2 + (Double(flightIndex / columns) + 0.5) * bounds.height * 0.6 / Double(rows))
            flight.values = track.positions.map { NSValue(cgPoint: gridProbe ? gridPoint : emissionProbe ? CGPoint(x: p.x, y: p.y) : $0) }
            flight.keyTimes = track.times.map { NSNumber(value: $0 / cohort.duration) }
            flight.calculationMode = .linear
            let alpha = CAKeyframeAnimation(keyPath: "opacity")
            alpha.values = emissionProbe ? track.opacities.map { _ in 1.0 } : track.opacities; alpha.keyTimes = flight.keyTimes
            let animation = CAAnimationGroup()
            animation.animations = [flight, alpha]
            if spec.native3D == true {
                // Each piece owns a layer/timing by default. The explicitly selected
                // shared-flight diagnostic alone groups up to three nearby pieces.
                let tumble = CABasicAnimation(keyPath: "transform.rotation.x")
                tumble.fromValue = p.phase; tumble.toValue = p.phase + p.tumble * cohort.duration
                animation.animations?.append(tumble)
            }
            animation.duration = cohort.duration
            animation.animations?.forEach { $0.duration = cohort.duration }
            animation.beginTime = 0.000001 // explicit layer-local zero, not CA's "now" sentinel
            animation.timingFunction = CAMediaTimingFunction(name: .linear)
            if !legacy { emitter.beginTime = max(0.000001, cohort.delay + preroll) }
            (legacy ? particlesView.layer : clock).addSublayer(emitter)
            emitter.add(animation, forKey: "flight")
        }
        // Staging alone is insufficient: the render server still needs time to
        // activate thousands of native emitters after the clock update. Scale the
        // future start with tree size; this is nonblocking and part of arm latency.
        let defaultLead: Double = legacy ? (1.0 / 60) : max(1.0 / 30, min(0.2, Double(cohorts.count) / 40_000))
        let lead = optionSeconds("--native-lead-ms=") ?? defaultLead
        let stall = optionSeconds("--native-stall-ms=") ?? 0
        let lifetime = (cohorts.map { $0.delay + $0.duration }.max() ?? 0) + 0.25
        if legacy {
            // Retained solely to reproduce the expired birth window in the pixel regression.
            let start = particlesView.layer.convertTime(CACurrentMediaTime(), from: nil) + lead
            for item in scheduled { item.layer.beginTime = start + item.delay }
            if stall > 0 { Thread.sleep(forTimeInterval: stall) }
            CATransaction.commit()
            scheduleCleanup(after: lifetime + lead)
            return
        }
        // Submit the expensive tree with ONE frozen parent clock. Child delays are
        // relative to that clock, so encoding thousands of layers consumes no births.
        particlesView.layer.addSublayer(clock)
        let marker = CALayer()
        particlesView.layer.addSublayer(marker)
        let gate = NativeLaunchGate { [weak self, weak clock, weak marker] in
            guard let self, let clock, generation == self.nativeGeneration, clock.superlayer != nil else { return }
            CATransaction.begin(); CATransaction.setDisableActions(true)
            marker?.removeFromSuperlayer()
            clock.beginTime = self.particlesView.layer.convertTime(CACurrentMediaTime(), from: nil) + lead
            clock.speed = 1
            CATransaction.commit()
            self.nativeArmDelay = (CACurrentMediaTime() - self.nativeSetupStart + lead) * 1000
            self.nativeGate = nil
            self.scheduleCleanup(after: lifetime + lead + preroll)
        }
        nativeGate = gate
        // A completion notification for a real CA animation gates the second, tiny
        // clock update. This is not a claim of GPU frame delivery or a fixed sleep.
        let ready = CABasicAnimation(keyPath: "opacity")
        ready.fromValue = 0; ready.toValue = 0; ready.duration = 1.0 / 60; ready.delegate = gate
        marker.add(ready, forKey: "native-ready")
        if stall > 0 { Thread.sleep(forTimeInterval: stall) }
        CATransaction.commit()
        // Bound cleanup even if the window disappears before the completion arrives.
        scheduleCleanup(after: lifetime + 2)
    }
    private func scheduleCleanup(after seconds: Double) {
        removal?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.cancel() }
        removal = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }
    /// Diagnostic-only layer edits use public CALayer APIs, leaving shipping code
    /// free of command-line switches. The actual production cell/clock/birth path is tested.
    private func configureProductionProbe(_ spec: StudyScenario) {
        guard ProcessInfo.processInfo.arguments.contains("--emission-probe"),
              let clock = native.layer.sublayers?.first(where: { $0.name == "PaperConfetti.Clock" }) else { return }
        let grid = ProcessInfo.processInfo.arguments.contains("--emission-grid")
        let emitters = clock.sublayers ?? [], rows = max(1, Int(ceil(Double(emitters.count) / 60)))
        for (index, layer) in emitters.enumerated() {
            guard let emitter = layer as? CAEmitterLayer,
                  let group = emitter.animation(forKey: "flight") as? CAAnimationGroup else { continue }
            if grid {
                emitter.emitterShape = .point; emitter.emitterSize = .zero
                let cells = emitter.emitterCells
                cells?.forEach { $0.scale = CGFloat(1.4 / spec.size) }
                emitter.emitterCells = cells
            }
            let point = CGPoint(x: (Double(index % 60) + 0.5) * bounds.width / 60,
                                y: bounds.height * 0.2 + (Double(index / 60) + 0.5) * bounds.height * 0.6 / Double(rows))
            for case let track as CAKeyframeAnimation in group.animations ?? [] {
                if track.keyPath == "position", let first = track.values?.first as? NSValue {
                    // Keep emitted pieces visible in their own column while XCTest copies pixels.
                    let fixed = grid ? NSValue(cgPoint: point) : first
                    track.values = track.values?.map { _ in fixed }
                }
                if track.keyPath == "opacity" { track.values = track.values?.map { _ in 1.0 } }
            }
            emitter.add(group, forKey: "flight")
        }
    }
    func completionStats(_ spec: StudyScenario) -> [String: Any] {
        if spec.renderer == "emitter" {
            let delay = usingProductionNative ? native.scheduledStartDelay.map { $0 * 1000 } : nativeArmDelay
            return ["native_arm_delay_ms": delay as Any? ?? NSNull(),
                    "native_staged_clock": !ProcessInfo.processInfo.arguments.contains("--native-legacy-clock")]
        }
        return [:]
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
        var maxPositionError = 0.0, maxOpacityError = 0.0, maxGroupingError = 0.0
        var sampleCounts: [Int] = []
        let all = usingProductionNative ? burst.particles(paletteCount: 3) : StudyPopulation.particles(burst, paletteCount: 3)
        func inspect(track: StudyTrack, duration: Double,
                     position: (Double) -> CGPoint, opacity: (Double) -> Double) {
            sampleCounts.append(track.times.count)
            var lo = 0
            for step in 0...960 {
                let t = Double(step) / 960 * duration
                while lo < track.times.count - 2 && track.times[lo + 1] < t { lo += 1 }
                let mix = (t - track.times[lo]) / (track.times[lo + 1] - track.times[lo])
                let a = track.positions[lo], b = track.positions[lo + 1], exact = position(t)
                maxPositionError = max(maxPositionError, hypot(exact.x - (a.x + (b.x - a.x) * mix), exact.y - (a.y + (b.y - a.y) * mix)))
                let alpha = track.opacities[lo], beta = track.opacities[lo + 1]
                maxOpacityError = max(maxOpacityError, abs(opacity(t) - (alpha + (beta - alpha) * mix)))
            }
        }
        if spec.renderer == "emitter" {
            for cohort in NativeParticlePlan.groups(all, shared: spec.sharedFlight == true) {
                inspect(track: StudyTrack(cohort: cohort), duration: cohort.duration,
                        position: cohort.position, opacity: cohort.opacity)
                for step in 0...300 {
                    let age = Double(step) / 300 * cohort.duration, center = cohort.position(at: age)
                    for p in cohort.members {
                        let point = StudyFlight.position(p, at: age)
                        maxGroupingError = max(maxGroupingError, hypot(point.x - center.x, point.y - center.y))
                    }
                }
            }
        } else if spec.renderer == "paper" {
            for p in LegacyConfettiBurst(burst).particles(paletteCount: 3) {
                inspect(track: StudyTrack(legacy: p), duration: p.lifetime,
                        position: { let point = p.position(at: $0); return CGPoint(x: point.x, y: point.y) },
                        opacity: { p.opacity(at: $0) })
            }
        } else if spec.renderer == "layers" {
            for p in all {
                inspect(track: StudyTrack(particle: p, spec: spec), duration: p.lifetime,
                        position: { StudyFlight.position(p, at: $0) }, opacity: { p.opacity(at: $0) })
            }
        }
        let poses = spec.renderer == "emitter" ? nativeImages(textures, spec: spec) : []
        defer { if usingProductionNative { nativePoseCache = nil } }
        return ["trajectory_audit_scope": spec.renderer == "emitter" ? "parabolic-v5-soft-edge-excludes-native-birth-drift-and-tilt" : "individual-particles",
                "textures": details, "texture_bytes": textures.reduce(0) { $0 + $1.bytesPerRow * $1.height },
                "native_pose_texture_count": poses.count,
                "native_pose_texture_bytes": poses.reduce(0) { $0 + $1.bytesPerRow * $1.height },
                "grouping_max_error_points": spec.renderer == "emitter" ? maxGroupingError as Any : NSNull(),
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
    init(legacy p: LegacyConfettiParticle) {
        self.init(duration: p.lifetime, samples: 48, adaptive: false, anchors: [],
                  position: { let xy = p.position(at: $0); return CGPoint(x: xy.x, y: xy.y) }, opacity: { p.opacity(at: $0) })
    }
    init(particle p: ConfettiParticle, spec: StudyScenario) {
        self.init(duration: p.lifetime, samples: spec.samples, adaptive: spec.sampling == "adaptive",
                  anchors: StudyFlight.anchors(p), position: { StudyFlight.position(p, at: $0) }, opacity: { p.opacity(at: $0) })
    }
    init(cohort: NativeFlightGroup) {
        self.init(duration: cohort.duration, samples: 48, adaptive: true, anchors: cohort.anchors,
                  position: cohort.position, opacity: cohort.opacity)
    }
    private init(duration: Double, samples: Int, adaptive: Bool, anchors: [Double],
                 position: (Double) -> CGPoint, opacity: (Double) -> Double) {
        if adaptive {
            var times: [Double] = [0]
            func split(_ a: Double, _ b: Double, depth: Int) {
                let start = position(a), end = position(b)
                let alpha = opacity(a), beta = opacity(b)
                var needsSplit = false
                for fraction in [0.25, 0.5, 0.75] {
                    let t = a + (b - a) * fraction, exact = position(t)
                    let error = hypot(exact.x - (start.x + (end.x - start.x) * fraction), exact.y - (start.y + (end.y - start.y) * fraction))
                    if error > 0.5 || abs(opacity(t) - (alpha + (beta - alpha) * fraction)) > 0.015 { needsSplit = true }
                }
                if needsSplit && depth < 7 {
                    let mid = (a + b) / 2
                    split(a, mid, depth: depth + 1); split(mid, b, depth: depth + 1)
                } else { times.append(b) }
            }
            for (a,b) in zip(anchors, anchors.dropFirst()) where b > a { split(a,b,depth:0) }
            self.times = times
        } else {
            times = (0...samples).map { Double($0) / Double(samples) * duration }
        }
        positions = times.map(position)
        opacities = times.map(opacity)
    }
}

/// Retained by the renderer until it starts or cancels; stale completions cannot
/// restart a stopped/replaced burst. UIKit mutations always return to the main actor.
private final class NativeLaunchGate: NSObject, CAAnimationDelegate {
    let ready: @MainActor () -> Void
    init(ready: @escaping @MainActor () -> Void) { self.ready = ready }
    func animationDidStop(_ anim: CAAnimation, finished flag: Bool) {
        guard flag else { return }
        Task { @MainActor in ready() }
    }
}
