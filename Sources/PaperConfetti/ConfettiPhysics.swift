import Foundation

/// Immutable emission coordinates. Moving the source view never moves flying paper.
public struct ConfettiEmitter: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var delay: Double
    public var count: Int
    public var angle: Double
    public var spread: Double
    public init(
        x: Double, y: Double, delay: Double = 0, count: Int = 36,
        angle: Double = 90, spread: Double = 40
    ) {
        self.x = x
        self.y = y
        self.delay = delay
        self.count = count
        self.angle = angle
        self.spread = spread
    }
}

/// Paper orientation. Both appearances use the native particle renderer.
public enum ConfettiAppearance: String, CaseIterable, Sendable {
    case flat
    case threeDimensional
}

/// Advanced paper motion. Ordinary callers can keep the lifelike defaults.
public struct ConfettiMotion: Equatable, Sendable {
    public var launchDuration: ClosedRange<Double>?
    public var spin: ClosedRange<Double>
    public var tumble: ClosedRange<Double>
    public var sizeVariation: ClosedRange<Double>
    public var flutter: Double
    /// Fraction of the descent before fading begins (0...0.95).
    public var fadeOutStart: Double
    public init(
        launchDuration: ClosedRange<Double>? = nil,
        spin: ClosedRange<Double> = 2.8...7.8,
        tumble: ClosedRange<Double> = 3...10,
        sizeVariation: ClosedRange<Double> = 0.8...1.2,
        flutter: Double = 5, fadeOutStart: Double = 0.4
    ) {
        self.launchDuration = launchDuration
        self.spin = spin
        self.tumble = tumble
        self.sizeVariation = sizeVariation
        self.flutter = flutter
        self.fadeOutStart = fadeOutStart
    }
    var isValid: Bool {
        func valid(_ range: ClosedRange<Double>, within bounds: ClosedRange<Double>) -> Bool {
            range.lowerBound.isFinite && range.upperBound.isFinite && bounds.contains(range.lowerBound)
                && bounds.contains(range.upperBound)
        }
        return (launchDuration.map { valid($0, within: 0.05...4) } ?? true) && valid(spin, within: 0...100)
            && valid(tumble, within: 0...100) && valid(sizeVariation, within: 0.1...3) && flutter.isFinite
            && (0...100).contains(flutter) && fadeOutStart.isFinite && (0...0.95).contains(fadeOutStart)
    }
}

/// No UI, timers or frame-step integration. Identical seeds produce identical flights.
public struct ConfettiBurst: Equatable, Sendable {
    public var cannons: [ConfettiEmitter]
    public var seed: UInt64
    public var radius: Double
    public var fall: Double
    public var size: Double
    public var shapes: [ConfettiShape]
    /// A new multiplier is drawn once per distinct shape in each seeded burst.
    public var fallSpeedRange: ClosedRange<Double>
    public var motion: ConfettiMotion
    public var appearance: ConfettiAppearance
    public init(
        cannons: [ConfettiEmitter], seed: UInt64 = .random(in: 1...UInt64.max),
        radius: Double = 130, fall: Double = 320, size: Double = 10,
        shapes: [ConfettiShape] = ConfettiShape.festive,
        fallSpeedRange: ClosedRange<Double> = 0.75...1.35,
        motion: ConfettiMotion = .init(), appearance: ConfettiAppearance = .threeDimensional
    ) {
        self.cannons = cannons
        self.seed = seed
        self.radius = radius
        self.fall = fall
        self.size = size
        self.shapes = shapes
        self.fallSpeedRange = fallSpeedRange
        self.motion = motion
        self.appearance = appearance
    }

    public func particles(paletteCount: Int) -> [ConfettiParticle] {
        guard paletteCount > 0, motion.isValid, radius.isFinite, fall.isFinite, size.isFinite,
            (0...5_000).contains(radius), radius > 0, (0...5_000).contains(fall), fall > 0,
            (1...64).contains(size)
        else { return [] }
        guard fallSpeedRange.lowerBound.isFinite, fallSpeedRange.upperBound.isFinite,
            fallSpeedRange.lowerBound >= 0.25, fallSpeedRange.upperBound <= 4
        else { return [] }
        var seen = Set<ConfettiShape>()
        let shapes = shapes.filter { seen.insert($0).inserted }
        guard !shapes.isEmpty else { return [] }
        let paletteCount = min(paletteCount, 16)
        // Separate stream: changes to cannon counts/positions do not reroll shape speeds.
        var speedRandom = ConfettiRandom(seed: seed ^ 0x7368_6170_6573)
        let speeds = Dictionary(
            uniqueKeysWithValues: shapes.map { shape in
                (
                    shape,
                    fallSpeedRange.lowerBound + speedRandom.unit()
                        * (fallSpeedRange.upperBound - fallSpeedRange.lowerBound)
                )
            })
        var random = ConfettiRandom(seed: seed)
        var result = [ConfettiParticle]()
        // Bound accidental caller mistakes without a runaway animation allocation.
        for cannon in cannons.prefix(32)
        where cannon.x.isFinite && cannon.y.isFinite && cannon.delay.isFinite && cannon.angle.isFinite
            && cannon.spread.isFinite
        {
            for _ in 0..<min(max(0, cannon.count), max(0, 6_000 - result.count)) {
                let angle =
                    (cannon.angle.truncatingRemainder(dividingBy: 360) + (random.unit() - 0.5)
                        * min(abs(cannon.spread), 360))
                    * .pi / 180
                // Retain the original ConfettiSwiftUI outer-weighted distance distribution.
                let distance = pow(0.01 + random.unit() * 0.99, 2.0 / 7.0) * radius
                let shape = shapes[Int(random.unit() * Double(shapes.count))]
                let speed = speeds[shape]!
                let launchDuration = random.value(
                    in: motion.launchDuration ?? ((0.2 + radius / 1300)...(0.675 + radius / 1300)))
                result.append(
                    ConfettiParticle(
                        x: cannon.x, y: cannon.y,
                        delay: min(60, max(0, cannon.delay)), dx: cos(angle) * distance,
                        dy: -sin(angle) * distance,
                        fall: fall, launchDuration: launchDuration,
                        fallDuration: (fall + radius) / (200 * speed), fallSpeed: speed,
                        size: size * random.value(in: motion.sizeVariation),
                        phase: random.unit() * .pi * 2,
                        spin: (random.unit() < 0.5 ? -1 : 1) * random.value(in: motion.spin),
                        tumble: random.value(in: motion.tumble), flutter: motion.flutter,
                        fadeOutStart: motion.fadeOutStart,
                        shape: shape, color: Int(random.unit() * Double(paletteCount))).softened)
            }
        }
        return result
    }
}

public struct ConfettiParticle: Equatable, Sendable {
    public let x, y, delay, dx, dy, fall, launchDuration, fallDuration, fallSpeed, size, phase, spin, tumble,
        flutter, fadeOutStart: Double
    public let shape: ConfettiShape
    public let color: Int
    public var lifetime: Double { launchDuration + fallDuration }
    public var endTime: Double { delay + lifetime }

    public func position(at age: Double) -> (x: Double, y: Double) {
        let age = min(lifetime, max(0, age))
        let up = min(1, age / launchDuration)
        let launch = 2 * up - up * up
        let down = max(0, (age - launchDuration) / fallDuration)
        let sway = sin(age * 7 + phase) * flutter * sin(age / lifetime * .pi)
        return (x + dx * launch + sway, y + dy * launch + fall * down * down)
    }
    public func opacity(at age: Double) -> Double {
        guard age >= 0, age < lifetime else { return 0 }
        let descent = max(0, (age - launchDuration) / fallDuration)
        let fade = max(0, (descent - fadeOutStart) / (1 - fadeOutStart))
        return min(1, age / 0.025) * max(0, 1 - fade * fade)
    }
    // Independent seeded streams retain the energetic outer-weighted population
    // while feathering its radius/cone boundary and individual descent times.
    private func unit(_ salt: UInt64) -> Double {
        var bits = phase.bitPattern ^ spin.bitPattern ^ salt
        bits = (bits ^ (bits >> 30)) &* 0xbf58476d1ce4e5b9
        bits = (bits ^ (bits >> 27)) &* 0x94d049bb133111eb
        bits ^= bits >> 31
        return Double(bits >> 11) / Double(UInt64(1) << 53)
    }
    fileprivate var softened: Self {
        let u = max(1 / Double(UInt64(1) << 53), unit(0x7265_6163_682d_7635))
        let normalRadius = sqrt(-2 * log(u))
        let normalAngle = unit(0x616e_676c_652d_7635) * 2 * .pi
        let spread = 0.24
        let reach = hypot(dx, dy) * exp(spread * normalRadius * cos(normalAngle) - spread * spread / 2)
        let angle = atan2(dy, dx) + normalRadius * sin(normalAngle) * 4 * .pi / 180
        return Self(x: x, y: y, delay: delay, dx: cos(angle) * reach, dy: sin(angle) * reach,
                    fall: fall, launchDuration: launchDuration,
                    fallDuration: fallDuration * (0.8 + 0.4 * unit(0x6661_6c6c_7469_6d65)),
                    fallSpeed: fallSpeed, size: size, phase: phase, spin: spin, tumble: tumble,
                    flutter: flutter, fadeOutStart: fadeOutStart, shape: shape, color: color)
    }

}

struct ConfettiRandom {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func value(in range: ClosedRange<Double>) -> Double {
        range.lowerBound + unit() * (range.upperBound - range.lowerBound)
    }
    mutating func unit() -> Double {
        state &+= 0x9e37_79b9_7f4a_7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58_476d_1ce4_e5b9
        z = (z ^ (z >> 27)) &* 0x94d0_49bb_1331_11eb
        return Double((z ^ (z >> 31)) >> 11) / Double(UInt64(1) << 53)
    }
}
