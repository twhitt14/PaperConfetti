#if canImport(UIKit)
import SwiftUI
import UIKit

/// The same paper, palette and flight settings work with one cannon, many cannons,
/// or a full-width shower. Distances and particle size are in overlay-local points.
public struct ConfettiConfiguration: Sendable {
    /// The palette, resolved against the host’s traits when playback starts.
    ///
    /// Only the first 16 entries are used. An empty palette emits nothing.
    public var colors: [Color]
    /// The paper silhouettes, using the first 32 distinct values.
    ///
    /// Duplicate geometry is ignored. An empty collection emits nothing.
    public var shapes: [ConfettiShape]
    /// The number of pieces in a single cannon or shower.
    ///
    /// Negative counts act as zero; at most 6,000 pieces are emitted per event.
    /// Explicit emitters supply their own counts instead of this value.
    public var particleCount: Int
    /// The nominal reach in points, greater than zero and at most 5,000.
    ///
    /// The distribution includes a softly scattered outer tail, so this isn't a
    /// hard boundary. A shower ignores the launch but still validates this setting.
    public var launchDistance: Double
    /// The descent distance from the peak, greater than zero and at most 5,000 points.
    ///
    /// Showers descend at least the overlay height, even if this value is smaller.
    public var fallDistance: Double
    /// The nominal paper size in points, from 1 through 64.
    ///
    /// Built-in streamers may be wider than this value. Motion size variation
    /// and shape proportions determine each piece’s final size.
    public var particleSize: Double
    /// The single cannon’s direction; 90 degrees points up.
    ///
    /// Explicit emitters supply their own direction. Showers ignore this value.
    public var emissionAngle: ConfettiAngle
    /// The single cannon’s full fan width, normalized to 0–360 degrees.
    ///
    /// The absolute value is used. Explicit emitters supply their own spread;
    /// showers ignore this value.
    public var spread: ConfettiAngle
    /// Whether paper spins flat or also tumbles in depth.
    public var appearance: ConfettiAppearance
    /// The ascent, rotation, size variation, flutter, and fading settings.
    public var motion: ConfettiMotion
    /// The random base descent speed for each distinct shape, within 0.25–4.
    ///
    /// One multiplier is sampled per shape per event. Each particle also receives
    /// independent timing variation. Equal bounds give all shapes the same base speed.
    public var fallSpeedMultiplierRange: ClosedRange<Double>

    /// Creates a shared configuration for cannons and showers.
    ///
    /// Numeric values and range bounds must be finite. Invalid flight settings
    /// emit nothing and resolve a mounted request as ``ConfettiOutcome/notPresented``.
    /// See <doc:Configuration> for the complete limits and replacement behavior.
    ///
    /// - Parameters:
    ///   - colors: The palette. Defaults to cyan, pink, and yellow.
    ///   - shapes: The silhouettes. Defaults to the 13 festive shapes.
    ///   - particleCount: The single-cannon or shower count. Defaults to 80.
    ///   - launchDistance: The nominal reach in points. Defaults to 160.
    ///   - fallDistance: The descent distance in points. Defaults to 360.
    ///   - particleSize: The nominal paper size in points. Defaults to 10.
    ///   - emissionAngle: The single-cannon direction. Defaults to 90 degrees.
    ///   - spread: The full single-cannon fan width. Defaults to 70 degrees.
    ///   - fallSpeedMultiplierRange: The range of per-shape base fall speeds.
    ///   - motion: Advanced motion settings. Defaults to lifelike rise and tumble.
    ///   - appearance: Flat spin or three-dimensional tumble. Defaults to tumble.
    public init(colors: [Color] = [.cyan, .pink, .yellow], shapes: [ConfettiShape] = ConfettiShape.festive,
                particleCount: Int = 80, launchDistance: Double = 160, fallDistance: Double = 360,
                particleSize: Double = 10, emissionAngle: ConfettiAngle = .degrees(90),
                spread: ConfettiAngle = .degrees(70), fallSpeedMultiplierRange: ClosedRange<Double> = 0.75...1.35,
                motion: ConfettiMotion = .init(), appearance: ConfettiAppearance = .threeDimensional) {
        self.colors = colors; self.shapes = shapes; self.particleCount = particleCount
        self.launchDistance = launchDistance; self.fallDistance = fallDistance; self.particleSize = particleSize
        self.emissionAngle = emissionAngle; self.spread = spread
        self.fallSpeedMultiplierRange = fallSpeedMultiplierRange; self.motion = motion; self.appearance = appearance
    }

    /// An editable starting point for a restrained celebration.
    public static var subtle: Self { .init(particleCount: 40, launchDistance: 100, particleSize: 7) }
    /// An editable starting point using the default palette, 13 shapes, and 80 pieces.
    public static var festive: Self { .init() }

    func burst(emitters: [ConfettiEmitter], seed: UInt64?) -> ConfettiBurst {
        ConfettiBurst(cannons: emitters, seed: seed ?? .random(in: 1...UInt64.max),
            radius: launchDistance, fall: fallDistance, size: particleSize, shapes: shapes,
            fallSpeedRange: fallSpeedMultiplierRange, motion: motion, appearance: appearance)
    }


}

/// Lifecycle state, rather than a frame-by-frame progress signal.
public enum ConfettiPlaybackState: Equatable, Sendable {
    /// No request is queued or playing.
    case idle
    /// A request is waiting for its first host or a nonzero layout.
    case pending
    /// A request is being prepared or its scheduled flight is active.
    case playing
}

/// Own with `@StateObject`, attach `.confettiOverlay(controller)`, then call `pop()`.
/// A new event replaces the previous event. Cancellation and completion resolve once.
@MainActor public final class ConfettiController: ObservableObject {
    private struct Request {
        let id = UUID()
        let makeBurst: (CGSize) -> ConfettiBurst
        let colors: [UIColor]
        let completion: ConfettiCompletion
    }
    private weak var renderer: ConfettiLayerView?
    private var pending: Request?
    private var hasMounted = false
    private var sceneIsActive = false
    private var reduceMotion = false
    private var currentRequest: UUID?
    private var currentState = ConfettiPlaybackState.idle
    private var sources: [AnyHashable: CGPoint] = [:]
    private var enabled: Bool { sceneIsActive && !reduceMotion }

    /// Lifecycle changes are published on the next main-actor turn to avoid publishing
    /// during a SwiftUI layout update. No particle frame causes an observable update.
    @Published public private(set) var playbackState = ConfettiPlaybackState.idle
    /// Includes scheduled flight and preparation, not a render-server pixel readback.
    public var isPlaying: Bool { (renderer?.particleLayerCount ?? 0) > 0 }
    /// Whether a request is waiting for its first host or a nonzero layout.
    public var isPending: Bool { currentState == .pending }
    /// Creates an idle controller for one SwiftUI overlay.
    public init() {}

    /// Emits from bottom-center by default. Completion describes the actual outcome.
    /// - Parameters:
    ///   - origin: A point in overlay coordinates, or `nil` for the bottom center.
    ///   - configuration: The paper and flight settings.
    ///   - completion: An optional once-only main-actor callback, delivered asynchronously.
    ///     A pre-mount request can remain pending until layout or cancellation.
    public func pop(at origin: CGPoint? = nil, configuration: ConfettiConfiguration = .init(),
                    completion: (@MainActor (ConfettiOutcome) -> Void)? = nil) {
        enqueue(configuration: configuration, completion: completion) { bounds in
            let p = origin ?? CGPoint(x: bounds.width / 2, y: bounds.height)
            return configuration.burst(emitters: [.init(origin: p, particleCount: configuration.particleCount,
                emissionAngle: configuration.emissionAngle, spread: configuration.spread)], seed: nil)
        }
    }

    /// Each emitter supplies its position, count, direction and delay. Shared paper
    /// and motion settings are exactly the same configuration used by an ordinary pop.
    /// - Parameters:
    ///   - emitters: Up to 32 cannons, considered in order, with a shared 6,000-piece budget.
    ///   - configuration: Shared paper and motion settings; emitter counts and angles take precedence.
    ///   - seed: A reproducible seed for this package version, or `nil` for a new random event.
    ///   - completion: An optional once-only callback, delivered asynchronously on the main actor.
    public func pop(emitters: [ConfettiEmitter], configuration: ConfettiConfiguration = .init(),
                    seed: UInt64? = nil, completion: (@MainActor (ConfettiOutcome) -> Void)? = nil) {
        enqueue(configuration: configuration, completion: completion) { _ in
            configuration.burst(emitters: emitters, seed: seed)
        }
    }

    /// Resolves a normalized position in the overlay when this event starts.
    /// - Parameters:
    ///   - anchor: A normalized location in the overlay, resolved when playback starts.
    ///     Values outside 0–1 are allowed for offscreen origins; coordinates must be finite.
    ///   - configuration: The paper and flight settings.
    ///   - completion: An optional once-only callback, delivered asynchronously on the main actor.
    public func pop(from anchor: UnitPoint, configuration: ConfettiConfiguration = .init(),
                    completion: (@MainActor (ConfettiOutcome) -> Void)? = nil) {
        enqueue(configuration: configuration, completion: completion) { bounds in
            configuration.burst(emitters: [.init(origin: CGPoint(x: bounds.width * anchor.x, y: bounds.height * anchor.y),
                particleCount: configuration.particleCount, emissionAngle: configuration.emissionAngle,
                spread: configuration.spread)], seed: nil)
        }
    }

    /// Launches at a view registered by `.confettiSource(id:controller:)`. Missing
    /// sources report `.notPresented`; no stale position or guessed fallback is used.
    /// - Parameters:
    ///   - id: A unique source ID registered under this controller's overlay.
    ///     Its center is captured at the time of the call. A missing source leaves any active event alone.
    ///   - configuration: The paper and flight settings.
    ///   - completion: An optional once-only callback, delivered asynchronously on the main actor.
    public func pop(fromSource id: some Hashable, configuration: ConfettiConfiguration = .init(),
                    completion: (@MainActor (ConfettiOutcome) -> Void)? = nil) {
        guard let origin = sources[AnyHashable(id)] else {
            ConfettiCompletion(completion).resolve(.notPresented)
            return
        }
        pop(at: origin, configuration: configuration, completion: completion)
    }

    /// Drops `particleCount` pieces across the full overlay width. `duration` is the
    /// emission window (0...10 seconds), not the total flight time. Paper starts just
    /// above the overlay, descends at least its height, and fades before cleanup.
    /// Like pop, this replaces the previous event on this controller.
    /// - Parameters:
    ///   - configuration: Shared paper, count, and descent settings. Direction and ascent don't affect a shower.
    ///   - duration: The finite emission window in seconds, from zero through 10.
    ///     An invalid duration leaves any active event alone and reports `notPresented`.
    ///   - seed: A reproducible seed for this package version, or `nil` for a new random event.
    ///   - completion: An optional once-only callback, delivered asynchronously on the main actor.
    public func drop(configuration: ConfettiConfiguration = .init(), duration: TimeInterval = 2,
                     seed: UInt64? = nil, completion: (@MainActor (ConfettiOutcome) -> Void)? = nil) {
        guard duration.isFinite, (0...10).contains(duration) else {
            ConfettiCompletion(completion).resolve(.notPresented)
            return
        }
        enqueue(configuration: configuration, completion: completion) { bounds in
            var burst = configuration.burst(emitters: [.init(origin: .zero, particleCount: configuration.particleCount)], seed: seed)
            burst.dropRegion = CGRect(origin: .zero, size: bounds)
            burst.dropDuration = duration
            return burst
        }
    }

    /// Cancels the queued or active request and removes all flying paper.
    ///
    /// Repeated calls are safe. A pending completion receives
    /// ``ConfettiOutcome/cancelled`` once, asynchronously on the main actor.
    public func cancel() {
        currentRequest = nil
        pending?.completion.resolve(.cancelled)
        pending = nil
        renderer?.cancel()
        publish(.idle)
    }

    // Historical benchmark adapter, intentionally outside the supported public API.
    @_spi(Testing) @discardableResult
    public func pop(_ burst: ConfettiBurst, colors: [Color] = [.cyan, .pink, .yellow],
                    completion: (@MainActor (ConfettiOutcome) -> Void)? = nil) -> Bool {
        submit(Request(makeBurst: { _ in burst }, colors: colors.prefix(16).map(UIColor.init),
                       completion: ConfettiCompletion(completion)))
    }

    private func enqueue(configuration: ConfettiConfiguration,
                         completion: (@MainActor (ConfettiOutcome) -> Void)?,
                         makeBurst: @escaping (CGSize) -> ConfettiBurst) {
        _ = submit(Request(makeBurst: makeBurst, colors: configuration.colors.prefix(16).map(UIColor.init),
                           completion: ConfettiCompletion(completion)))
    }
    private func publish(_ state: ConfettiPlaybackState) {
        currentState = state
        Task { @MainActor [weak self] in
            guard let self, self.playbackState != self.currentState else { return }
            self.playbackState = self.currentState
        }
    }
    private func submit(_ request: Request) -> Bool {
        guard !hasMounted || (renderer != nil && sceneIsActive) else {
            request.completion.resolve(.notPresented); return false
        }
        if let renderer, renderer.hasEnteredWindow,
            renderer.window == nil || renderer.window?.isHidden == true {
            request.completion.resolve(.notPresented); return false
        }
        guard !hasMounted || !reduceMotion else {
            request.completion.resolve(.reducedMotion); return false
        }
        cancel()
        currentRequest = request.id
        pending = request
        publish(.pending)
        flush()
        return true
    }
    func attach(_ view: ConfettiLayerView, sceneIsActive: Bool, reduceMotion: Bool) {
        if renderer !== view {
            renderer?.layoutReady = nil
            renderer?.cancel()
            renderer = view
            view.layoutReady = { [weak self] in self?.flush() }
        }
        hasMounted = true
        self.sceneIsActive = sceneIsActive
        self.reduceMotion = reduceMotion
        if enabled { flush() }
        else {
            pending?.completion.resolve(sceneIsActive ? .reducedMotion : .notPresented)
            pending = nil
            renderer?.cancel()
            currentRequest = nil
            publish(.idle)
        }
    }
    func detach(_ view: ConfettiLayerView) {
        guard renderer === view else { return }
        cancel(); view.layoutReady = nil; renderer = nil; sceneIsActive = false; sources = [:]
    }
    private func flush() {
        guard enabled, let view = renderer, view.window?.isHidden == false,
            view.bounds.width > 0, view.bounds.height > 0, let request = pending else { return }
        pending = nil
        publish(.playing)
        view.play(burst: request.makeBurst(view.bounds.size), colors: request.colors,
                  completion: ConfettiCompletion { [weak self] outcome in
            if self?.currentRequest == request.id {
                self?.currentRequest = nil
                self?.publish(.idle)
            }
            request.completion.resolve(outcome)
        })
    }
    fileprivate func updateSources(_ sources: [AnyHashable: CGPoint]) { self.sources = sources }
}

private struct ControlledConfettiOverlay: UIViewRepresentable {
    let controller: ConfettiController
    let sources: [AnyHashable: CGPoint]
    let sceneIsActive: Bool
    let reduceMotion: Bool
    func makeUIView(context: Context) -> ConfettiLayerView { ConfettiLayerView() }
    func makeCoordinator() -> Coordinator { Coordinator(controller) }
    func updateUIView(_ view: ConfettiLayerView, context: Context) {
        if context.coordinator.controller !== controller {
            context.coordinator.controller.detach(view)
            context.coordinator.controller = controller
        }
        controller.updateSources(sources)
        controller.attach(view, sceneIsActive: sceneIsActive, reduceMotion: reduceMotion)
    }
    static func dismantleUIView(_ view: ConfettiLayerView, coordinator: Coordinator) { coordinator.controller.detach(view) }
    final class Coordinator {
        var controller: ConfettiController
        init(_ controller: ConfettiController) { self.controller = controller }
    }
}

private struct ConfettiSourceID: Hashable {
    let controller: ObjectIdentifier
    let id: AnyHashable
}
private struct ConfettiSourcePreferences: PreferenceKey {
    static var defaultValue: [ConfettiSourceID: Anchor<CGRect>] { [:] }
    static func reduce(value: inout [ConfettiSourceID: Anchor<CGRect>], nextValue: () -> [ConfettiSourceID: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, last in last })
    }
}
private struct ConfettiOverlayModifier: ViewModifier {
    let controller: ConfettiController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    func body(content: Content) -> some View {
        content.overlayPreferenceValue(ConfettiSourcePreferences.self) { sources in
            GeometryReader { geometry in
                let centers = Dictionary(uniqueKeysWithValues: sources.compactMap { key, anchor -> (AnyHashable, CGPoint)? in
                    guard key.controller == ObjectIdentifier(controller) else { return nil }
                    let rect = geometry[anchor]
                    return (key.id, CGPoint(x: rect.midX, y: rect.midY))
                })
                ControlledConfettiOverlay(controller: controller, sources: centers,
                                          sceneIsActive: scenePhase == .active, reduceMotion: reduceMotion)
            }
            .allowsHitTesting(false).accessibilityHidden(true)
        }
    }
}
extension View {
    /// Mount on a stable full-size container, outside scrolling/keyboard-driven layouts.
    /// The overlay passes touches through, hides decorative paper from accessibility,
    /// and handles Reduce Motion and scene changes. Use a different controller for
    /// each overlay; attaching one controller to multiple hosts isn't supported.
    ///
    /// - Parameter controller: The screen-owned controller, usually stored with `@StateObject`.
    /// - Returns: The view with a decorative confetti host in its local coordinate system.
    public func confettiOverlay(_ controller: ConfettiController) -> some View {
        modifier(ConfettiOverlayModifier(controller: controller))
    }
    /// Registers this view's center with a controller attached to an ancestor container.
    /// - Parameters:
    ///   - id: An ID unique among this controller's source views.
    ///   - controller: The controller mounted on an ancestor with `confettiOverlay(_:)`.
    /// - Returns: The view with a source anchor that follows layout and scrolling.
    public func confettiSource(id: some Hashable, controller: ConfettiController) -> some View {
        anchorPreference(key: ConfettiSourcePreferences.self, value: .bounds) {
            [ConfettiSourceID(controller: ObjectIdentifier(controller), id: AnyHashable(id)): $0]
        }
    }
}
#endif
