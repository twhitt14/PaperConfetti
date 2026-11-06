import PaperConfetti
import SwiftUI
import UIKit

struct ShowcaseView: View {
    @StateObject private var confetti = ConfettiController()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appearance = ConfettiAppearance.threeDimensional
    @State private var palette = Palette.party
    @State private var selected = Set(ConfettiShape.festive)
    @State private var count = 180.0
    @State private var size = 12.0
    @State private var spread = 80.0
    @State private var launchSpeed = 1.1
    @State private var variedSpeeds = true
    @State private var taps = 0
    @State private var toggled = false
    @State private var proof = "Try a button while the paper is falling."
    @State private var showDetails = false
    @State private var reduceMotionDemo = false
    @State private var pops = 0
    private let ink = Color(red: 0.055, green: 0.075, blue: 0.14)
    private let accent = Color(red: 0.38, green: 0.91, blue: 0.83)
    private static let heart: ConfettiShape = {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0.5, y: 1))
        path.addCurve(to: CGPoint(x: 0.5, y: 0.2), control1: CGPoint(x: -0.6, y: 0.3), control2: CGPoint(x: 0.1, y: -0.3))
        path.addCurve(to: CGPoint(x: 0.5, y: 1), control1: CGPoint(x: 0.9, y: -0.3), control2: CGPoint(x: 1.6, y: 0.3))
        path.closeSubpath()
        // This fixed, normalized recipe is validated by the custom-shape tests.
        return try! ConfettiShape(path: path, name: "Heart")
    }()
    private var testing: Bool { ProcessInfo.processInfo.arguments.contains("--ui-testing") }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            hero
                            playground
                            controls
                            shapeGallery
                            Text("No timers. No counters. Just pop.")
                                .font(.headline).foregroundStyle(accent).padding(.top, 8)
                            Text(
                                "Native particles handle the flight. Every piece has its own rhythm, with softer edges and a playful tumble."
                            )
                            .font(.subheadline).foregroundStyle(.secondary)
                        }
                        .padding(24)
                        .frame(maxWidth: 700)
                        .frame(maxWidth: .infinity)
                    }
                    .accessibilityIdentifier("showcase-scroll")
                    HStack(spacing: 12) {
                        Button {
                            emit(in: geometry.size, cannons: 1)
                        } label: {
                            Label("Pop", systemImage: "sparkles").font(.headline).frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.borderedProminent).tint(accent).foregroundStyle(ink)
                        .accessibilityIdentifier("pop")
                        Button {
                            emit(in: geometry.size, cannons: 5)
                        } label: {
                            Text("5 cannons").font(.headline).padding(.vertical, 10)
                        }
                        .buttonStyle(.bordered).tint(accent).accessibilityIdentifier("cannons")
                        Button {
                            confetti.cancel()
                            proof = "Stopped"
                        } label: {
                            Image(systemName: "stop.fill").padding(.vertical, 10)
                        }
                        .buttonStyle(.bordered).tint(.white).accessibilityLabel("Stop confetti")
                        .accessibilityIdentifier("stop")
                    }
                    .padding(20).background(ink.opacity(0.98))
                }
                .background(ink)
                .confettiOverlay(confetti)
                .onChange(of: reduceMotionDemo) { value in if value { confetti.cancel() } }
                .onDisappear { confetti.cancel() }
                .task {
                    // Capture-only convenience; normal use is always an explicit button event.
                    if ProcessInfo.processInfo.arguments.contains("--capture-pop") {
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                        emit(in: geometry.size, cannons: 5)
                    } else if ProcessInfo.processInfo.arguments.contains("--capture-hearts") {
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                        confetti.pop(emitters: [.init(origin: CGPoint(x: geometry.size.width / 2, y: geometry.size.height - 130), particleCount: 180)],
                            configuration: .init(colors: palette.colors, shapes: [Self.heart, .ring, .star], launchDistance: 350,
                                                  fallDistance: 600, particleSize: 16), seed: 42)
                    } else if ProcessInfo.processInfo.arguments.contains("--capture-shower") {
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                        confetti.drop(configuration: .init(colors: palette.colors, particleCount: 220), duration: 2.8, seed: 42)
                    }
                }
            }
            .navigationTitle("PaperConfetti")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $showDetails) {
                VStack(spacing: 20) {
                    Image(systemName: "hand.tap.fill").font(.system(size: 54)).foregroundStyle(accent)
                    Text("Every tap gets through.").font(.title.bold())
                    Text(
                        "The confetti overlay stays decorative. Your app keeps responding to buttons, gestures, scrolling and navigation."
                    )
                    .foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.padding(28).accessibilityIdentifier("detail")
            }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 15) {
            Label("A LITTLE MOMENT OF JOY", systemImage: "sparkle")
                .font(.caption.weight(.bold)).tracking(2).foregroundStyle(accent)
            Text("Make it\nfeel like a win.")
                .font(.system(size: 43, weight: .bold, design: .rounded)).fixedSize(
                    horizontal: false, vertical: true)
            Text("Thirteen paper shapes. A playful tumble.\nOne method call.")
                .font(.body).foregroundStyle(.white.opacity(0.72))
            HStack {
                Text("confetti.pop()").font(.system(.callout, design: .monospaced).weight(.semibold))
                Spacer()
                Image(systemName: "arrow.up.right").font(.callout.bold())
            }
            .foregroundStyle(accent).padding(16)
            .background(accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private var playground: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Keep playing").font(.title3.bold())
                Spacer()
                Label("LIVE", systemImage: "circle.fill").font(.caption2.bold()).foregroundStyle(accent)
            }
            HStack {
                Button("Tap me · \(taps)") {
                    taps += 1
                    recordInteraction()
                }
                .buttonStyle(.bordered).tint(accent).accessibilityIdentifier("tap-through")
                Spacer()
                Button {
                    recordInteraction()
                    showDetails = true
                } label: {
                    Label("Details", systemImage: "arrow.right")
                }.accessibilityIdentifier("details")
            }
            HStack {
                Button("Shower") {
                    guard !reduceMotionDemo else { return }
                    confetti.drop(configuration: .init(colors: palette.colors, particleCount: Int(count), appearance: appearance))
                }.accessibilityIdentifier("drop")
                Button("Custom hearts") {
                    guard !reduceMotionDemo else { return }
                    confetti.pop(fromSource: "custom-hearts", configuration: .init(colors: palette.colors,
                        shapes: [Self.heart, .ring, .star], particleCount: 120, particleSize: 14, appearance: appearance))
                }
                .confettiSource(id: "custom-hearts", controller: confetti)
                .accessibilityIdentifier("custom-hearts")
            }.buttonStyle(.bordered).tint(accent)
            Text("Playback: \(String(describing: confetti.playbackState))")
                .font(.caption).accessibilityIdentifier("playback-state")
            Toggle("Try a toggle", isOn: $toggled).tint(accent)
                .onChange(of: toggled) { _ in recordInteraction() }.accessibilityIdentifier("toggle-through")
            Text(proof).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("input-proof")
        }
        .padding(20).background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 22))
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Make it yours").font(.title2.bold())
            Picker("Appearance", selection: $appearance) {
                Text("3D tumble").tag(ConfettiAppearance.threeDimensional)
                Text("Flat").tag(ConfettiAppearance.flat)
            }.pickerStyle(.segmented).accessibilityIdentifier("appearance")
            VStack(alignment: .leading, spacing: 8) {
                Text("Launch speed").font(.subheadline.weight(.semibold))
                Picker("Launch speed", selection: $launchSpeed) {
                    Text("Normal").tag(1.0)
                    Text("10% faster").tag(1.1)
                }.pickerStyle(.segmented).accessibilityIdentifier("launch-speed")
                Text("A quicker rise, with the same height and fall.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Picker("Palette", selection: $palette) {
                ForEach(Palette.allCases) { value in Text(value.rawValue).tag(value) }
            }.pickerStyle(.segmented).accessibilityIdentifier("palette")
            HStack(spacing: 8) {
                ForEach(palette.colors.indices, id: \.self) { index in
                    Capsule().fill(palette.colors[index]).frame(height: 8)
                }
            }.accessibilityHidden(true)
            DisclosureGroup("Tune the pop") {
                VStack(spacing: 16) {
                    slider("Pieces", value: $count, range: 40...5760, step: 20)
                    slider("Size", value: $size, range: 5...18, step: 1)
                    slider("Spread", value: $spread, range: 30...140, step: 5)
                    Toggle("Vary speed by shape", isOn: $variedSpeeds)
                    Toggle("Preview Reduce Motion", isOn: $reduceMotionDemo).accessibilityIdentifier(
                        "reduce-motion")
                }.padding(.top, 16).tint(accent)
            }
            if reduceMotion || reduceMotionDemo {
                Label(
                    "Motion is reduced. Pops are announced without flying paper.",
                    systemImage: "accessibility"
                )
                .font(.caption).foregroundStyle(accent).accessibilityIdentifier("reduced-motion-message")
            }
        }
    }

    private var shapeGallery: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Pick your paper").font(.title2.bold())
                Spacer()
                Button("All") { selected = Set(ConfettiShape.festive) }.tint(accent)
            }
            Text("Tap shapes to mix your own celebration.").font(.subheadline).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 94), spacing: 10)], spacing: 10) {
                ForEach(ConfettiShape.festive, id: \.self) { shape in
                    Button {
                        if selected.contains(shape) { selected.remove(shape) } else { selected.insert(shape) }
                    } label: {
                        VStack(spacing: 10) {
                            shape.fill(accent, style: FillStyle(eoFill: true)).frame(width: 52, height: 34)
                            Text(shape.label).font(.caption).foregroundStyle(.white)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(
                            selected.contains(shape) ? accent.opacity(0.10) : .white.opacity(0.025),
                            in: RoundedRectangle(cornerRadius: 16)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16).strokeBorder(
                                selected.contains(shape) ? accent.opacity(0.7) : .clear))
                    }
                    .buttonStyle(.plain).accessibilityLabel(shape.label)
                    .accessibilityValue(selected.contains(shape) ? "Selected" : "Not selected")
                    .accessibilityIdentifier("shape-\(ConfettiShape.allCases.firstIndex(of: shape) ?? -1)")
                }
            }
            if selected.isEmpty {
                Text("Choose at least one shape to pop.").font(.caption).foregroundStyle(accent)
            }
        }.accessibilityIdentifier("shape-gallery")
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double)
        -> some View
    {
        VStack {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(value.wrappedValue))").monospacedDigit().foregroundStyle(accent)
            }
            Slider(value: value, in: range, step: step).tint(accent).accessibilityLabel(title)
        }
    }

    private func emit(in bounds: CGSize, cannons: Int) {
        guard !selected.isEmpty else {
            proof = "Choose a shape first."
            return
        }
        let shapes = ConfettiShape.festive.filter { selected.contains($0) }
        // UI automation keeps particles around long enough to verify gestures under load.
        let fall = testing ? 2_000.0 : 500.0
        let speeds = testing ? 0.5...0.6 : (variedSpeeds ? 0.75...1.35 : 1...1)
        let total = Int(count)
        let radius = min(320, Double(bounds.height) * 0.42)
        let configuration = ConfettiConfiguration(colors: palette.colors, shapes: shapes,
            particleCount: total, launchDistance: radius, fallDistance: fall, particleSize: size,
            spread: .degrees(spread), fallSpeedMultiplierRange: speeds,
            motion: .init(launchSpeedMultiplier: launchSpeed), appearance: appearance)
        if reduceMotion || reduceMotionDemo {
            confetti.cancel()
        } else {
            confetti.pop(emitters: (0..<cannons).map { index in
                .init(origin: CGPoint(x: Double(bounds.width) * (Double(index) + 0.5) / Double(cannons),
                                      y: bounds.height - 110), delay: Double(index) * 0.1,
                      particleCount: total / cannons + (index < total % cannons ? 1 : 0), spread: .degrees(spread))
            }, configuration: configuration, seed: ProcessInfo.processInfo.arguments.contains("--capture-pop") ? 42 : nil)
        }
        pops += 1
        proof =
            reduceMotion || reduceMotionDemo
            ? "Celebration \(pops) · Reduced Motion" : "Pop \(pops) · \(total) pieces"
        UIAccessibility.post(notification: .announcement, argument: "Celebration")
    }

    private func recordInteraction() {
        proof =
            confetti.isPlaying ? "Tap received while confetti is active" : "Tap received · overlay is idle"
    }
}

private enum Palette: String, CaseIterable, Identifiable {
    case party = "Party"
    case ocean = "Ocean"
    case sunset = "Sunset"
    var id: Self { self }
    var colors: [Color] {
        switch self {
        case .party: return [.cyan, .pink, .orange, .mint, .purple]
        case .ocean: return [.cyan, .mint, .blue, .white]
        case .sunset: return [.orange, .yellow, .pink, .red]
        }
    }
}

extension ConfettiShape {
    var label: String { name }
}
