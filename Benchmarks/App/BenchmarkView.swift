import SwiftUI
import PaperConfetti
import ConfettiSwiftUI

struct BenchmarkView: View {
    @StateObject private var model = BenchmarkModel()
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 12) {
                Text("PaperConfetti • Device Lab").font(.headline)
                Text(model.status).font(.caption.monospaced()).accessibilityIdentifier("benchmark-status")
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(0..<12) { row in
                                HStack(spacing: 6) {
                                    ForEach(0..<5) { col in
                                        Circle().fill(row == 6 ? .cyan : .gray.opacity(0.25))
                                            .overlay(Text(String(Array("WORDS")[col])).font(.title2.bold()))
                                            .frame(height: 54)
                                    }
                                }.id(row)
                            }
                        }
                    }
                    .onChange(of: model.scrollToBottom) { bottom in proxy.scrollTo(bottom ? 7 : 0, anchor: .top) }
                }
                if model.showKeyboard {
                    VStack(spacing: 5) {
                        ForEach(["QWERTYUIOP", "ASDFGHJKL", "ZXCVBNM"], id: \.self) { row in
                            HStack(spacing: 4) {
                                ForEach(Array(row).map(String.init), id: \.self) { key in
                                    Text(key).font(.caption.bold()).frame(maxWidth: .infinity).frame(height: 30)
                                        .background(.gray.opacity(0.25), in: RoundedRectangle(cornerRadius: 4))
                                }
                            }
                        }
                    }.transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    Text("Solved in 7 turns!").font(.title2.bold()).frame(height: 100)
                }
                Text(model.complete ? "The Mac is finishing this recording. Keep your iPhone connected." : "Automated run — please leave this screen open")
                    .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("benchmark-complete")
            }
            .padding(20).frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(uiColor: .systemGroupedBackground))
            .overlay(alignment: .topLeading) {
                if let burst = model.burst {
                    ZStack(alignment: .topLeading) {
                        ForEach(Array(burst.cannons.enumerated()), id: \.offset) { _, cannon in
                            LegacyCannon(cannon: cannon, palette: model.palette) { model.legacyEmissions += cannon.count }
                                .position(x: cannon.x, y: cannon.y)
                        }
                    }.id(model.trialID).allowsHitTesting(false).accessibilityHidden(true)
                }
            }
            .confettiOverlay(model.controller)
            .task { await model.run(size: geometry.size) }
            .onDisappear {
                model.controller.cancel()
                UIApplication.shared.isIdleTimerDisabled = false
            }
        }
    }
}

private struct LegacyCannon: View {
    let cannon: ConfettiEmitter
    let palette: [Color]
    let emitted: () -> Void
    @State private var trigger = 0
    var body: some View {
        ConfettiCannon(counter: $trigger, num: cannon.count,
            confettis: [.shape(.circle), .shape(.triangle), .shape(.slimRectangle)],
            colors: palette, confettiSize: 7, rainHeight: 320,
            openingAngle: .degrees(cannon.angle - cannon.spread / 2),
            closingAngle: .degrees(cannon.angle + cannon.spread / 2), radius: 130)
        .frame(width: 0, height: 0)
        .task {
            // Allow SwiftUI to mount the legacy counter observer before its first event.
            try? await Task.sleep(nanoseconds: UInt64((0.02 + cannon.delay) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            trigger += 1; emitted()
        }
    }
}
