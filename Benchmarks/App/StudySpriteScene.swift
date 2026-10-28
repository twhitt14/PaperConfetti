import SpriteKit
import PaperConfetti

/// One persistent transparent scene. Native particles stay local to their flight
/// node; a central update applies the same flight equations used by CAEmitterLayer.
@MainActor final class StudySpriteScene: SKScene {
    struct Flight {
        let plan: NativeFlightGroup
        let node: SKTransformNode
        let emitters: [SKEmitterNode]
        var started = false
    }
    private var flights: [Flight] = []
    private var startTime: TimeInterval?
    private var canvasHeight: CGFloat = 0
    private var tilt = false
    private var warmFrames = 0
    private var warmGeneration = 0
    private var warmed: (() -> Void)?
    private(set) var sceneUpdates = 0
    private(set) var activatedParticles = 0

    func clearParticles() {
        flights = []; startTime = nil
        removeAllActions(); removeAllChildren()
    }
    func prepareClearFrame() async {
        await withCheckedContinuation { continuation in
            warmFrames = 0; warmGeneration += 1
            let generation = warmGeneration
            warmed?()
            warmed = { continuation.resume() }
            // Bounded if the view leaves its window while an async preload completes.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard self?.warmGeneration == generation else { return }
                self?.finishWarmup()
            }
        }
    }
    private func finishWarmup() {
        let done = warmed; warmed = nil; done?()
    }
    override func didFinishUpdate() {
        warmFrames += 1
        if warmFrames >= 2 { finishWarmup() }
    }
    func play(_ plans: [NativeFlightGroup], textures: [SKTexture], spec: StudyScenario, canvasHeight: CGFloat) {
        clearParticles(); sceneUpdates = 0; activatedParticles = 0
        self.canvasHeight = canvasHeight; tilt = spec.native3D == true
        flights = plans.map { plan in
            let node = SKTransformNode(); node.isHidden = true
            let emitters = plan.members.map { p -> SKEmitterNode in
                let emitter = SKEmitterNode()
                emitter.particleTexture = textures[p.color * spec.shapeSet.count + spec.shapeSet.firstIndex(of: p.shape)!]
                emitter.particleSize = CGSize(width: p.size * p.shape.width, height: p.size * p.shape.height)
                emitter.particleColorBlendFactor = 0
                emitter.particleBirthRate = 100; emitter.numParticlesToEmit = 1
                emitter.particleLifetime = plan.duration + 0.1
                emitter.particlePositionRange = CGVector(dx: 12, dy: 8)
                emitter.emissionAngle = 0; emitter.emissionAngleRange = 0
                emitter.particleSpeed = CGFloat(cos(p.phase) * p.flutter * 0.5)
                emitter.xAcceleration = 0; emitter.yAcceleration = 0
                emitter.particleScale = 1; emitter.particleScaleRange = 0
                emitter.particleRotation = -p.phase; emitter.particleRotationSpeed = -p.spin
                emitter.particleRotationRange = 0
                emitter.particleAlpha = 1; emitter.particleAlphaSpeed = 0
                // nil is essential: already-born particles must follow the parent flight.
                emitter.targetNode = nil; emitter.isPaused = true
                node.addChild(emitter)
                return emitter
            }
            addChild(node)
            return Flight(plan: plan, node: node, emitters: emitters)
        }
    }
    override func update(_ currentTime: TimeInterval) {
        guard !flights.isEmpty else { return }
        if startTime == nil { startTime = currentTime }
        let elapsed = currentTime - startTime!
        sceneUpdates += 1
        for i in flights.indices {
            let flight = flights[i], age = elapsed - flight.plan.delay
            guard age >= 0 else { continue }
            if age >= flight.plan.duration {
                flight.node.removeFromParent(); continue
            }
            let point = flight.plan.position(at: age)
            flight.node.position = CGPoint(x: point.x, y: canvasHeight - point.y)
            flight.node.alpha = flight.plan.opacity(at: age)
            if tilt {
                let p = flight.plan.members[0]
                flight.node.xRotation = -p.phase - p.tumble * age
            }
            if !flight.started {
                flights[i].started = true; flight.node.isHidden = false
                for emitter in flight.emitters {
                    emitter.isPaused = false
                    emitter.advanceSimulationTime(0.02)
                    activatedParticles += 1
                }
            }
        }
    }
}
