import PaperConfetti
import SwiftUI
import UIKit

struct ShowcaseView: View {
    @StateObject private var confetti = ConfettiController()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var palette = Palette.party
    @State private var selected = Set(ConfettiShape.festive)
    @State private var count = 180.0
    @State private var size = 12.0
    @State private var spread = 80.0
    @State private var variedSpeeds = true
    @State private var taps = 0
    @State private var toggled = false
    @State private var proof = "Try a button while the paper is falling."
    @State private var showDetails = false
    @State private var reduceMotionDemo = false
    @State private var pops = 0
    private let ink = Color(red: 0.055, green: 0.075, blue: 0.14)
    private let accent = Color(red: 0.38, green: 0.91, blue: 0.83)
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
                                "Core Animation handles the flight. Matching shapes share a fall speed; each new pop feels a little different."
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
            Toggle("Try a toggle", isOn: $toggled).tint(accent)
                .onChange(of: toggled) { _ in recordInteraction() }.accessibilityIdentifier("toggle-through")
            Text(proof).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("input-proof")
        }
        .padding(20).background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 22))
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Make it yours").font(.title2.bold())
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
                    slider("Pieces", value: $count, range: 40...400, step: 20)
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
                            let image = ConfettiTextures.make(
                                colors: [UIColor(accent)], size: 25, scale: 3, shapes: [shape])[0]
                            Image(decorative: image, scale: 3).frame(height: 34)
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
                    .accessibilityIdentifier("shape-\(shape.rawValue)")
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
        let burst = ConfettiBurst(
            cannons: (0..<cannons).map { index in
                .init(
                    x: Double(bounds.width) * (Double(index) + 0.5) / Double(cannons),
                    y: Double(bounds.height) - 110, delay: Double(index) * 0.1,
                    count: total / cannons + (index < total % cannons ? 1 : 0), spread: spread)
            },
            seed: ProcessInfo.processInfo.arguments.contains("--capture-pop")
                ? 42 : .random(in: 1...UInt64.max),
            radius: min(320, Double(bounds.height) * 0.42), fall: fall, size: size,
            shapes: shapes, fallSpeedRange: speeds)
        if reduceMotion || reduceMotionDemo {
            confetti.cancel()
        } else {
            confetti.pop(burst, colors: palette.colors)
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
    fileprivate var label: String {
        switch self {
        case .star: return "Star"
        case .outlinedStar: return "Star outline"
        case .sparkle: return "Sparkle"
        case .asterisk: return "Asterisk"
        case .wave: return "Wave"
        case .squiggle: return "Squiggle"
        case .loop: return "Loop"
        case .doubleLoop: return "Double loop"
        case .ring: return "Ring"
        case .longTriangle: return "Long triangle"
        case .curvedTriangle: return "Curved cut"
        case .diamond: return "Diamond"
        case .parallelogram: return "Paper cut"
        case .circle: return "Circle"
        case .triangle: return "Triangle"
        case .strip: return "Strip"
        }
    }
}
