import SwiftUI
import PaperConfetti
import os.signpost

@MainActor final class StudyModel: ObservableObject {
    @Published var status = "Waiting for the comparison runner…"
    @Published var scenario: StudyScenario
    @Published var showKeyboard = true
    @Published var scrollToBottom = false
    @Published var complete = false
    @Published var busy = false
    @Published var taps = 0
    @Published var activeTaps = 0
    @Published var visualIndex = 0
    @Published var visualNote = ""
    let renderer = StudyRenderer()
    let scenarios: [StudyScenario]
    let visual: Bool
    private let args = ProcessInfo.processInfo.arguments
    private var results: [[String: Any]] = []
    private var error: String?
    private var interrupted = false
    private var visualTask: Task<Void, Never>?
    private let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    private var runID: String { value("--run-id=") ?? "manual-study" }
    private var pass: String { value("--pass=") ?? "timing" }
    private var rounds: Int { min(12, max(1, Int(value("--study-rounds=") ?? "3") ?? 3)) }
    private func value(_ prefix: String) -> String? { args.first { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) } }
    init() {
        let arguments = ProcessInfo.processInfo.arguments
        visual = arguments.contains("--visual-review")
        let selection = arguments.first { $0.hasPrefix("--study=") }.map { String($0.dropFirst(8)).split(separator: ",").map(String.init) }
        scenarios = selection.map { ids in ids.compactMap { id in StudyScenario.all.first { $0.id == id } } }
            ?? StudyScenario.all.filter { $0.suites.contains("renderers") && $0.count == 720 }
        precondition(!scenarios.isEmpty && (selection == nil || scenarios.count == selection!.count), "Invalid study selection")
        scenario = scenarios[0]
    }
    private func pause(_ seconds: Double) async throws { try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }
    private func check() throws {
        guard !interrupted, UIApplication.shared.applicationState == .active,
              !UIAccessibility.isReduceMotionEnabled, !ProcessInfo.processInfo.isLowPowerModeEnabled,
              ProcessInfo.processInfo.thermalState == .nominal || ProcessInfo.processInfo.thermalState == .fair else {
            throw BenchmarkModel.Failure("Keep the app visible, turn off Low Power Mode/Reduce Motion, and let the phone cool before measuring.")
        }
    }
    func run(size: CGSize) async {
        UIApplication.shared.isIdleTimerDisabled = true
        if visual {
            status = "Visual review • same seed on every replay"
            if args.contains("--visual-autoplay") { replay(size: size) }
            return
        }
        do {
            if !args.contains("--autostart") {
                let marker = directory.appendingPathComponent("start-\(runID)")
                var waits = 0
                while !FileManager.default.fileExists(atPath: marker.path) {
                    try await pause(0.25); waits += 1
                    if waits > 480 { throw BenchmarkModel.Failure("Instruments did not start.") }
                }
                try FileManager.default.removeItem(at: marker)
            }
            try await pause(1)
            for round in 0..<rounds {
                let offset = round % scenarios.count
                for spec in Array(scenarios.dropFirst(offset)) + scenarios.prefix(offset) {
                    scenario = spec; status = "\(spec.id) · round \(round + 1)/\(rounds)"
                    showKeyboard = true; scrollToBottom = false
                    await renderer.prepare(spec)
                    try await pause(0.8); try check()
                    let burst = spec.burst(size: size, seed: UInt64(1000 + round))
                    let signpost = OSSignpostID(log: benchmarkLog)
                    os_signpost(.begin, log: benchmarkLog, name: "Renderer study", signpostID: signpost, "%{public}@ round=%d", spec.id as NSString, round)
                    let meter = Measurements(); meter.start(memory: pass == "memory")
                    let setup = renderer.play(spec, burst: burst)
                    var row: [String: Any]
                    do {
                        if spec.count > 0 && (setup["requested_particles"] as? Int) != spec.count {
                            throw BenchmarkModel.Failure("Renderer did not submit the requested particle population.")
                        }
                        if pass == "memory" {
                            try await pause(round % 2 == 0 ? 1 : 5.5)
                            if round % 2 == 1 && !renderer.isIdle { throw BenchmarkModel.Failure("Natural cleanup failed.") }
                            renderer.cancel(); try await pause(1)
                        } else {
                            try await pause(0.25)
                            if spec.hostMotion { withAnimation(.easeInOut(duration: 0.35)) { showKeyboard = false } }
                            try await pause(0.45)
                            if spec.hostMotion { withAnimation(.easeInOut(duration: 0.5)) { scrollToBottom = true } }
                            try await pause(4.8)
                        }
                        row = meter.stop()
                    } catch {
                        _ = meter.stop()
                        os_signpost(.end, log: benchmarkLog, name: "Renderer study", signpostID: signpost)
                        throw error
                    }
                    os_signpost(.end, log: benchmarkLog, name: "Renderer study", signpostID: signpost)
                    try check()
                    guard renderer.isIdle else { throw BenchmarkModel.Failure("Particles remained active after settling.") }
                    row.merge(setup) { _, new in new }
                    row.merge(["scenario": spec.id, "renderer": spec.renderer, "round": round, "warmup": round == 0,
                               "particles": spec.count, "seed": 1000 + round, "idle_after_settle": renderer.isIdle,
                               "thermal_state": ProcessInfo.processInfo.thermalState.rawValue,
                               "texture_prewarmed": spec.prewarm, "cancelled": pass == "memory" && round % 2 == 0,
                               "audit": renderer.audit(spec, burst: burst)]) { _, new in new }
                    results.append(row); try write(finished: false)
                }
            }
            complete = true; status = "Comparison saved"
        } catch {
            self.error = error.localizedDescription; status = "Stopped: \(error.localizedDescription)"
        }
        renderer.cancel()
        do { try write(finished: true) } catch { complete = false; status = "Could not save comparison: \(error.localizedDescription)" }
    }
    private func write(finished: Bool) throws {
        #if targetEnvironment(simulator)
        let simulator = true
        #else
        let simulator = false
        #endif
        let payload: [String: Any] = ["schema": 2, "run_id": runID, "pass": pass, "finished": finished,
            "success": finished && error == nil, "error": error as Any? ?? NSNull(), "simulator": simulator,
            "process_id": ProcessInfo.processInfo.processIdentifier, "rounds": rounds,
            "os": UIDevice.current.systemVersion, "screen_maximum_fps": UIScreen.main.maximumFramesPerSecond,
            "screen_scale": UIScreen.main.scale, "rows": results]
        try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent("results-\(runID).json"), options: .atomic)
    }
    func replay(size: CGSize) {
        visualTask?.cancel(); renderer.reset()
        let spec = scenarios[visualIndex]; scenario = spec
        visualNote = ""; busy = true; showKeyboard = true; scrollToBottom = false
        visualTask = Task {
            await renderer.prepare(spec)
            guard !Task.isCancelled else { return }
            try? await pause(0.2)
            guard !Task.isCancelled else { return }
            let stats = renderer.play(spec, burst: spec.burst(size: size, seed: 1001))
            status = "\(spec.id) • \(stats["requested_particles"] ?? 0) particles"
            try? await pause(0.25)
            guard !Task.isCancelled else { return }
            if spec.hostMotion { withAnimation(.easeInOut(duration: 0.35)) { showKeyboard = false } }
            try? await pause(0.45)
            guard !Task.isCancelled else { return }
            if spec.hostMotion { withAnimation(.easeInOut(duration: 0.5)) { scrollToBottom = true } }
            try? await pause(4.8)
            guard !Task.isCancelled else { return }
            busy = false
        }
    }
    func tap() {
        taps += 1
        if !renderer.isIdle { activeTaps += 1 }
    }
    func note(_ value: String) {
        visualNote = value
        let url = directory.appendingPathComponent("visual-observations.jsonl")
        let record: [String: Any] = ["scenario": scenario.id, "seed": 1001, "observation": value, "timestamp": Date().timeIntervalSince1970]
        do {
            var data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]); data.append(10)
            if !FileManager.default.fileExists(atPath: url.path) { try Data().write(to: url) }
            let file = try FileHandle(forWritingTo: url); defer { try? file.close() }
            try file.seekToEnd(); try file.write(contentsOf: data)
        } catch { visualNote = "Could not save note" }
    }
    func stop() {
        interrupted = true
        visualTask?.cancel(); renderer.reset(); busy = false
        UIApplication.shared.isIdleTimerDisabled = false
    }
}
