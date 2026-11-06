import SwiftUI
@_spi(Testing) import PaperConfetti
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
            openingAngle: .degrees(cannon.angle - cannon.spread.degrees / 2),
            closingAngle: .degrees(cannon.angle + cannon.spread.degrees / 2), radius: 130)
        .frame(width: 0, height: 0)
        .task {
            // Allow SwiftUI to mount the legacy counter observer before its first event.
            try? await Task.sleep(nanoseconds: UInt64((0.02 + cannon.delay) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            trigger += 1; emitted()
        }
    }
}

/// Editorial footage only. No timing measurements run while recording the screen.
struct ArticleDemoView: View {
    private struct Clip: Identifiable {
        let id: String
        let legacy: Bool
        let count: Int
        var festive = false
        var title: String { legacy ? "ConfettiSwiftUI 1.1.0" : "PaperConfetti · native 3D" }
        var detail: String { "\(count.formatted()) pieces · five cannons · \(festive ? "13 festive shapes" : "3 classic shapes")" }
    }
    private static let clips: [Clip] = [
        .init(id: "legacy-180", legacy: true, count: 180),
        .init(id: "native-180", legacy: false, count: 180),
        .init(id: "legacy-720", legacy: true, count: 720),
        .init(id: "native-720", legacy: false, count: 720),
        .init(id: "legacy-1800", legacy: true, count: 1800),
        .init(id: "native-1800", legacy: false, count: 1800),
        .init(id: "festive-1800", legacy: false, count: 1800, festive: true),
        .init(id: "festive-5760", legacy: false, count: 5760, festive: true)
    ]
    @StateObject private var controller = ConfettiController()
    @State private var legacyBurst: ConfettiBurst?
    @State private var index = 0
    @State private var task: Task<Void, Never>?
    @State private var running = false
    @State private var status = "Start screen recording, then tap Start comparison"
    @State private var showKeyboard = true
    @State private var taps = 0
    @State private var generation = 0
    @State private var recordedClips: [[String: Any]] = []
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let palette: [Color] = [.cyan, .orange, .gray]
    private var clips: [Clip] {
        let prefix = "--article-case="
        guard let arg = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix(prefix) }) else { return Self.clips }
        let selected = Self.clips.filter { $0.id == String(arg.dropFirst(prefix.count)) }
        return selected.isEmpty ? Self.clips : selected
    }
    private var clip: Clip { clips[min(index, max(0, clips.count - 1))] }
    private var simulatorLabel: String {
#if targetEnvironment(simulator)
        "Simulator recording · appearance only, not device performance"
#else
        "On-device screen recording · visual comparison, not an FPS test"
#endif
    }
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 16) {
                Text("PaperConfetti comparison").font(.headline)
                Text(clip.title).font(.title2.bold())
                Text(clip.detail).font(.subheadline.monospacedDigit())
                Text(status).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("article-status")
                Spacer()
                ForEach(0..<3) { row in
                    HStack(spacing: 8) {
                        ForEach(Array("WORDS").indices, id: \.self) { column in
                            Circle().fill(row == 2 ? Color.cyan : Color.gray.opacity(0.3))
                                .overlay(Text(String(Array("WORDS")[column])).font(.title.bold()))
                                .frame(maxHeight: 64)
                        }
                    }
                }
                Spacer()
                if showKeyboard {
                    Text("Q W E R T Y U I O P\nA S D F G H J K L\nZ X C V B N M")
                        .font(.body.monospaced().bold()).multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity).frame(height: 115)
                        .background(.gray.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                } else {
                    Text("Solved in 3 turns!").font(.title2.bold()).frame(height: 115)
                }
                HStack {
                    Button(running ? "Stop" : "Start comparison") {
                        if running { stop() } else { start(in: geometry.size) }
                    }.accessibilityIdentifier("article-start")
                    Button("Tap test: \(taps)") { taps += 1 }.accessibilityIdentifier("article-tap")
                }.buttonStyle(.borderedProminent)
                Text(simulatorLabel).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .padding(20).frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(uiColor: .systemGroupedBackground))
            .overlay(alignment: .topLeading) {
                if let burst = legacyBurst {
                    ZStack(alignment: .topLeading) {
                        ForEach(Array(burst.cannons.enumerated()), id: \.offset) { _, cannon in
                            LegacyCannon(cannon: cannon, palette: palette) { }
                                .position(x: cannon.x, y: cannon.y)
                        }
                    }.id(index).allowsHitTesting(false).accessibilityHidden(true)
                }
            }
            .confettiOverlay(controller)
            .task {
                if ProcessInfo.processInfo.arguments.contains("--article-autostart") {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    guard !Task.isCancelled else { return }
                    start(in: geometry.size)
                }
            }
        }
        .onDisappear { stop() }
        .onChange(of: scenePhase) { phase in if phase != .active { stop() } }
    }
    private func start(in size: CGSize) {
        guard !running, !clips.isEmpty else { return }
        guard !reduceMotion else { status = "Turn off Reduce Motion to record animations"; save(finished: true, success: false); return }
        UIApplication.shared.isIdleTimerDisabled = true
        generation += 1
        let token = generation
        recordedClips = []; running = true
        save(finished: false, success: false)
        task = Task { @MainActor in
            defer {
                if token == generation {
                    controller.cancel(); legacyBurst = nil; running = false
                    UIApplication.shared.isIdleTimerDisabled = false
                }
            }
            do {
                for i in clips.indices {
                    controller.cancel(); legacyBurst = nil; index = i; showKeyboard = true
                    status = "\(i + 1) of \(clips.count) · ready"
                    recordedClips.append(["id": clips[i].id, "count": clips[i].count,
                                          "ready_epoch": Date().timeIntervalSince1970])
                    save(finished: false, success: false)
                    try await Task.sleep(nanoseconds: 2_000_000_000)
                    let c = clips[i]
                    let burst = ConfettiBurst(cannons: (0..<5).map { column in
                        ConfettiEmitter(x: Double(size.width) * (Double(column) + 0.5) / 5,
                                        y: Double(size.height) * 0.62, delay: Double(column) * 0.1,
                                        count: c.count / 5, angle: 90, spread: 40)
                    }, seed: 2026, radius: 130, fall: 320, size: c.festive ? 10 : 7,
                       shapes: c.festive ? ConfettiShape.festive : ConfettiShape.classic)
                    if c.legacy { legacyBurst = burst } else { controller.pop(burst, colors: palette) }
                    status = "\(i + 1) of \(clips.count) · \(c.id)"
                    recordedClips[i]["pop_epoch"] = Date().timeIntervalSince1970
                    save(finished: false, success: false)
                    try await Task.sleep(nanoseconds: 220_000_000)
                    withAnimation(.easeInOut(duration: 0.35)) { showKeyboard = false }
                    try await Task.sleep(nanoseconds: 6_780_000_000)
                }
                status = "Done · \(clips.count) clips · tap Start to replay"
                save(finished: true, success: true)
            } catch {
                if token == generation {
                    status = "Stopped · tap Start to replay"
                    save(finished: true, success: false)
                }
            }
        }
    }
    private func stop() {
        generation += 1
        task?.cancel(); task = nil; controller.cancel(); legacyBurst = nil
        if running { status = "Stopped · tap Start to replay"; save(finished: true, success: false) }
        running = false; UIApplication.shared.isIdleTimerDisabled = false
    }
    private func save(finished: Bool, success: Bool) {
        let prefix = "--article-run-id="
        let runID = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix(prefix) })
            .map { String($0.dropFirst(prefix.count)) } ?? "manual"
        let payload: [String: Any] = ["run_id": runID, "finished": finished, "success": success,
                                     "status": status, "clips": recordedClips]
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("article-session.json")
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys, .prettyPrinted]) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
