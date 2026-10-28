// Frozen PaperConfetti 0.1.0 physics; MIT. Benchmark only.
import PaperConfetti
import Foundation

/// Immutable emission coordinates. Moving the source view never moves flying paper.
public struct LegacyConfettiEmitter: Equatable, Sendable {
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

/// Advanced paper motion. Ordinary callers can keep the lifelike defaults.
public struct LegacyConfettiMotion: Equatable, Sendable {
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
public struct LegacyConfettiBurst: Equatable, Sendable {
    public var cannons: [LegacyConfettiEmitter]
    public var seed: UInt64
    public var radius: Double
    public var fall: Double
    public var size: Double
    public var shapes: [ConfettiShape]
    /// A new multiplier is drawn once per distinct shape in each seeded burst.
    public var fallSpeedRange: ClosedRange<Double>
    public var motion: LegacyConfettiMotion
    public init(
        cannons: [LegacyConfettiEmitter], seed: UInt64 = .random(in: 1...UInt64.max),
        radius: Double = 130, fall: Double = 320, size: Double = 10,
        shapes: [ConfettiShape] = ConfettiShape.festive,
        fallSpeedRange: ClosedRange<Double> = 0.75...1.35,
        motion: LegacyConfettiMotion = .init()
    ) {
        self.cannons = cannons
        self.seed = seed
        self.radius = radius
        self.fall = fall
        self.size = size
        self.shapes = shapes
        self.fallSpeedRange = fallSpeedRange
        self.motion = motion
    }

    public func particles(paletteCount: Int) -> [LegacyConfettiParticle] {
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
        var speedRandom = LegacyConfettiRandom(seed: seed ^ 0x7368_6170_6573)
        let speeds = Dictionary(
            uniqueKeysWithValues: shapes.map { shape in
                (
                    shape,
                    fallSpeedRange.lowerBound + speedRandom.unit()
                        * (fallSpeedRange.upperBound - fallSpeedRange.lowerBound)
                )
            })
        var random = LegacyConfettiRandom(seed: seed)
        var result = [LegacyConfettiParticle]()
        // Bound accidental caller mistakes without a runaway animation allocation.
        for cannon in cannons.prefix(32)
        where cannon.x.isFinite && cannon.y.isFinite && cannon.delay.isFinite && cannon.angle.isFinite
            && cannon.spread.isFinite
        {
            for _ in 0..<min(max(0, cannon.count), max(0, 2_000 - result.count)) {
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
                    LegacyConfettiParticle(
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
                        shape: shape, color: Int(random.unit() * Double(paletteCount))))
            }
        }
        return result
    }
}

public struct LegacyConfettiParticle: Equatable, Sendable {
    public let x, y, delay, dx, dy, fall, launchDuration, fallDuration, fallSpeed, size, phase, spin, tumble,
        flutter, fadeOutStart: Double
    public let shape: ConfettiShape
    public let color: Int
    public var lifetime: Double { launchDuration + fallDuration }
    public var endTime: Double { delay + lifetime }

    public func position(at age: Double) -> (x: Double, y: Double) {
        let launch = Self.lookup(Self.launchCurve, at: age / launchDuration)
        let rain = Self.lookup(Self.rainCurve, at: (age - launchDuration) / fallDuration)
        // Fall starts after launch: matching silhouettes share the same descent
        // curve and duration, regardless of their individual launch or spin.
        let flutter = sin(age * 7 + phase) * self.flutter * sin(min(1, max(0, age / lifetime)) * .pi)
        return (x + dx * launch + flutter, y + dy * launch + fall * rain)
    }
    public func opacity(at age: Double) -> Double {
        guard age >= 0, age < lifetime else { return 0 }
        let descent = max(0, (age - launchDuration) / fallDuration)
        let fade = max(0, (descent - fadeOutStart) / (1 - fadeOutStart))
        return min(1, age / 0.025) * max(0, 1 - fade * fade)
    }
    // Every particle uses these same normalized timing curves. Invert them once,
    // rather than thousands of times on the main thread when a burst is attached.
    private static let launchCurve = (0...1024).map {
        bezier(Double($0) / 1024, x1: 0.1, y1: 0.8, x2: 0, y2: 1)
    }
    private static let rainCurve = (0...1024).map {
        bezier(Double($0) / 1024, x1: 0.12, y1: 0, x2: 0.39, y2: 0)
    }
    private static func lookup(_ values: [Double], at fraction: Double) -> Double {
        guard fraction > 0 else { return 0 }
        guard fraction < 1 else { return 1 }
        let sample = fraction * Double(values.count - 1)
        let index = Int(sample)
        return values[index] + (values[index + 1] - values[index]) * (sample - Double(index))
    }
    // Invert the cubic's x, rather than assuming its parameter is elapsed time.
    static func bezier(_ fraction: Double, x1: Double, y1: Double, x2: Double, y2: Double) -> Double {
        let x = min(1, max(0, fraction))
        var low = 0.0
        var high = 1.0
        func cubic(_ t: Double, _ a: Double, _ b: Double) -> Double {
            3 * (1 - t) * (1 - t) * t * a + 3 * (1 - t) * t * t * b + t * t * t
        }
        for _ in 0..<20 {
            let mid = (low + high) / 2
            if cubic(mid, x1, x2) < x { low = mid } else { high = mid }
        }
        return cubic((low + high) / 2, y1, y2)
    }
}

struct LegacyConfettiRandom {
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

extension LegacyConfettiBurst {
    init(_ b: ConfettiBurst) {
        self.init(cannons: b.cannons.map { LegacyConfettiEmitter(x: $0.x, y: $0.y, delay: $0.delay,
            count: $0.count, angle: $0.angle, spread: $0.spread) }, seed: b.seed, radius: b.radius,
            fall: b.fall, size: b.size, shapes: b.shapes, fallSpeedRange: b.fallSpeedRange,
            motion: LegacyConfettiMotion(launchDuration: b.motion.launchDuration, spin: b.motion.spin,
                tumble: b.motion.tumble, sizeVariation: b.motion.sizeVariation,
                flutter: b.motion.flutter, fadeOutStart: b.motion.fadeOutStart))
    }
}
