import Foundation

/// An explicit angle. Zero points right and 90 degrees points up in overlay coordinates.
public struct ConfettiAngle: Equatable, Sendable {
    /// The angle in degrees; finite values are normalized when emitting particles.
    public var degrees: Double
    /// The equivalent angle in radians.
    public var radians: Double { degrees / 180 * .pi }
    /// Creates an angle measured in degrees.
    ///
    /// - Parameter value: The number of degrees.
    /// - Returns: The corresponding angle.
    public static func degrees(_ value: Double) -> Self { Self(degrees: value) }
    /// Creates an angle measured in radians.
    ///
    /// - Parameter value: The number of radians.
    /// - Returns: The corresponding angle.
    public static func radians(_ value: Double) -> Self { Self(degrees: value / .pi * 180) }
}

/// Captured emission coordinates. Moving the source view never moves flying paper.
public struct ConfettiEmitter: Equatable, Sendable {
    @_spi(Testing) public var x: Double
    @_spi(Testing) public var y: Double
    /// The emission delay in seconds, clamped to 0–60. Non-finite values skip this emitter.
    public var delay: Double
    @_spi(Testing) public var count: Int
    @_spi(Testing) public var angle: Double
    private var spreadDegrees: Double
    /// The finite emission point in overlay coordinates, captured for this event.
    public var origin: CGPoint {
        get { CGPoint(x: x, y: y) }
        set { x = newValue.x; y = newValue.y }
    }
    /// The requested count; negative counts act as zero. The event shares a 6,000-piece budget.
    public var particleCount: Int { get { count } set { count = newValue } }
    /// The direction, normalized to a full rotation; zero points right and 90 degrees points up.
    public var emissionAngle: ConfettiAngle { get { .degrees(angle) } set { angle = newValue.degrees } }
    /// The full fan width, using the absolute value clamped to 360 degrees.
    public var spread: ConfettiAngle { get { .degrees(spreadDegrees) } set { spreadDegrees = newValue.degrees } }
    /// Creates a cannon with captured coordinates and independent timing.
    ///
    /// - Parameters:
    ///   - origin: The emission point in overlay-local points.
    ///   - delay: Seconds before this cannon's visible flight. Defaults to zero.
    ///   - particleCount: The requested count. Defaults to 80.
    ///   - emissionAngle: The direction. Defaults to 90 degrees, pointing up.
    ///   - spread: The full fan width. Defaults to 70 degrees.
    public init(origin: CGPoint, delay: TimeInterval = 0, particleCount: Int = 80,
                emissionAngle: ConfettiAngle = .degrees(90), spread: ConfettiAngle = .degrees(70)) {
        self.init(x: origin.x, y: origin.y, delay: delay, count: particleCount,
                  angle: emissionAngle.degrees, spread: spread.degrees)
    }
    @_spi(Testing) public init(
        x: Double, y: Double, delay: Double = 0, count: Int = 36,
        angle: Double = 90, spread: Double = 40
    ) {
        self.x = x
        self.y = y
        self.delay = delay
        self.count = count
        self.angle = angle
        self.spreadDegrees = spread
    }
}

/// Paper orientation. Both appearances use the native particle renderer.
public enum ConfettiAppearance: String, CaseIterable, Sendable {
    /// Paper spins in the screen plane without depth tilt.
    case flat
    /// Paper spins and tumbles in depth using the same flight paths as flat paper.
    case threeDimensional
}

/// Advanced paper motion. Ordinary callers can keep the lifelike defaults.
public struct ConfettiMotion: Equatable, Sendable {
    /// Multiplies ascent velocity while preserving reach and descent timing, within 0.25–4.
    public var launchSpeedMultiplier: Double
    /// The ascent duration range in seconds before the speed multiplier, within 0.05–4.
    ///
    /// `nil` derives the range from launch distance. Showers have no ascent.
    public var launchDuration: ClosedRange<Double>?
    /// The screen-plane spin magnitude in radians per second, within 0–100. Direction is randomized.
    public var spin: ClosedRange<Double>
    /// The depth-tumble magnitude in radians per second, within 0–100. Flat appearance ignores it.
    public var tumble: ClosedRange<Double>
    /// The per-particle size multipliers, within 0.1–3.
    public var sizeVariation: ClosedRange<Double>
    /// The horizontal flutter amplitude in points, from zero through 100.
    public var flutter: Double
    /// Fraction of the descent before fading begins (0...0.95).
    public var fadeOutStart: Double
    /// Creates advanced motion settings.
    ///
    /// All values and range bounds must be finite and within their documented limits.
    /// An invalid setting emits nothing. Showers ignore ascent settings but still
    /// validate the complete configuration.
    ///
    /// - Parameters:
    ///   - launchDuration: Optional ascent duration range before applying the speed multiplier.
    ///   - launchSpeedMultiplier: Ascent speed multiplier, within 0.25–4. Defaults to 1.
    ///   - spin: Screen-plane rotation magnitudes. Defaults to 2.8–7.8 radians per second.
    ///   - tumble: Depth rotation magnitudes. Defaults to 3–10 radians per second.
    ///   - sizeVariation: Size multipliers. Defaults to 0.8–1.2.
    ///   - flutter: Horizontal flutter in points. Defaults to 5.
    ///   - fadeOutStart: Fraction of descent before fading begins. Defaults to 0.4.
    public init(
        launchDuration: ClosedRange<Double>? = nil, launchSpeedMultiplier: Double = 1,
        spin: ClosedRange<Double> = 2.8...7.8,
        tumble: ClosedRange<Double> = 3...10,
        sizeVariation: ClosedRange<Double> = 0.8...1.2,
        flutter: Double = 5, fadeOutStart: Double = 0.4
    ) {
        self.launchSpeedMultiplier = launchSpeedMultiplier
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
        return launchSpeedMultiplier.isFinite && (0.25...4).contains(launchSpeedMultiplier)
            && (launchDuration.map { valid($0, within: 0.05...4) } ?? true) && valid(spin, within: 0...100)
            && valid(tumble, within: 0...100) && valid(sizeVariation, within: 0.1...3) && flutter.isFinite
            && (0...100).contains(flutter) && fadeOutStart.isFinite && (0...0.95).contains(fadeOutStart)
    }
}

/// No UI, timers or frame-step integration. Identical seeds produce identical flights.
@_spi(Testing) public struct ConfettiBurst: Equatable, Sendable {
    var dropRegion: CGRect?
    var dropDuration: TimeInterval = 0
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
        var selectedShapes: [ConfettiShape] = []
        for shape in shapes where seen.insert(shape).inserted {
            selectedShapes.append(shape)
            if selectedShapes.count == 32 { break }
        }
        let shapes = selectedShapes
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
            && cannon.spread.degrees.isFinite
        {
            for _ in 0..<min(max(0, cannon.count), max(0, 6_000 - result.count)) {
                let angle =
                    (cannon.angle.truncatingRemainder(dividingBy: 360) + (random.unit() - 0.5)
                        * min(abs(cannon.spread.degrees), 360))
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
                        fall: fall, launchDuration: launchDuration / motion.launchSpeedMultiplier,
                        fallDuration: (fall + radius) / (200 * speed), fallSpeed: speed,
                        size: size * random.value(in: motion.sizeVariation),
                        phase: random.unit() * .pi * 2,
                        spin: (random.unit() < 0.5 ? -1 : 1) * random.value(in: motion.spin),
                        tumble: random.value(in: motion.tumble), flutter: motion.flutter,
                        fadeOutStart: motion.fadeOutStart,
                        shape: shape, color: Int(random.unit() * Double(paletteCount))).softened)
            }
        }
        if let region = dropRegion {
            // Stratify x positions, then jitter within each stratum for even coverage
            // without a visible wall or synchronized rows. Each piece gets its own delay.
            let width = Double(region.width), height = Double(region.height)
            var drops = ConfettiRandom(seed: seed ^ 0x64726f7073)
            return result.enumerated().map { index, p in
                ConfettiParticle(x: Double(region.minX) + (Double(index) + drops.unit()) / Double(result.count) * width,
                    y: Double(region.minY) - p.size * 2, delay: drops.unit() * dropDuration,
                    dx: (drops.unit() - 0.5) * min(80, width * 0.2), dy: 0,
                    fall: max(fall, height + p.size * 4), launchDuration: 0,
                    fallDuration: max(0.4, (max(fall, height) / (200 * p.fallSpeed)) * (0.8 + drops.unit() * 0.4)),
                    fallSpeed: p.fallSpeed, size: p.size, phase: p.phase, spin: p.spin, tumble: p.tumble,
                    flutter: p.flutter, fadeOutStart: p.fadeOutStart, shape: p.shape, color: p.color)
            }
        }
        return result
    }
}

@_spi(Testing) public struct ConfettiParticle: Equatable, Sendable {
    public let x, y, delay, dx, dy, fall, launchDuration, fallDuration, fallSpeed, size, phase, spin, tumble,
        flutter, fadeOutStart: Double
    public let shape: ConfettiShape
    public let color: Int
    public var lifetime: Double { launchDuration + fallDuration }
    public var endTime: Double { delay + lifetime }

    public func position(at age: Double) -> (x: Double, y: Double) {
        let age = min(lifetime, max(0, age))
        let up = launchDuration > 0 ? min(1, age / launchDuration) : min(1, age / fallDuration)
        let launch = launchDuration > 0 ? 2 * up - up * up : up
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
