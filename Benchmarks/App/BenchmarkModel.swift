import SwiftUI
import PaperConfetti
import os.signpost

struct Scenario {
    let name: String
    let renderer: String
    let count: Int
    let cannons: Int
    var festive = false
    static let all: [Scenario] = [
        .init(name: "control", renderer: "none", count: 0, cannons: 1),
        .init(name: "paper-classic-180-single", renderer: "paper", count: 180, cannons: 1),
        .init(name: "legacy-classic-180-single", renderer: "legacy", count: 180, cannons: 1),
        .init(name: "paper-classic-180-five", renderer: "paper", count: 180, cannons: 5),
        .init(name: "legacy-classic-180-five", renderer: "legacy", count: 180, cannons: 5),
        .init(name: "paper-classic-720-five", renderer: "paper", count: 720, cannons: 5),
        .init(name: "legacy-classic-720-five", renderer: "legacy", count: 720, cannons: 5),
        .init(name: "paper-festive-180-five", renderer: "paper", count: 180, cannons: 5, festive: true),
        .init(name: "paper-festive-720-five", renderer: "paper", count: 720, cannons: 5, festive: true)
    ]
}

@MainActor final class BenchmarkModel: ObservableObject {
    @Published var status = "Waiting for the profiling runner…"
    @Published var scenario = Scenario.all[0]
    @Published var burst: ConfettiBurst?
    @Published var showKeyboard = true
    @Published var scrollToBottom = false
    @Published var trialID = 0
    @Published var complete = false
    let controller = ConfettiController()
    let palette: [Color] = [.cyan, .orange, .gray]
    var legacyEmissions = 0
    private var results: [[String: Any]] = []
    private var error: String?
    private let args = ProcessInfo.processInfo.arguments
    private let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    private var outputURL: URL { directory.appendingPathComponent("results-\(runID).json") }
    var runID: String { value("--run-id=") ?? "manual" }
    var pass: String { value("--pass=") ?? "timing" }
    var smoke: Bool { args.contains("--smoke") }
    private func value(_ key: String) -> String? { args.first { $0.hasPrefix(key) }.map { String($0.dropFirst(key.count)) } }
    private func pause(_ seconds: Double) async throws { try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }

    func run(size: CGSize) async {
        UIApplication.shared.isIdleTimerDisabled = true
        defer {
            // Successful passes stay on screen while the Mac exports/cools down.
            // Re-enabling auto-lock here can lock a 30-second phone between passes.
            if !complete { UIApplication.shared.isIdleTimerDisabled = false }
            controller.cancel(); burst = nil
        }
        do {
            if args.contains("--runner-hold") {
                status = "The Mac is preparing the next check…"
                while !Task.isCancelled { try await pause(1) }
                return
            }
            guard !UIAccessibility.isReduceMotionEnabled else { throw Failure("Turn off Reduce Motion for the timing run; accessibility is tested separately.") }
            guard !ProcessInfo.processInfo.isLowPowerModeEnabled else { throw Failure("Turn off Low Power Mode, let the phone cool, then rerun.") }
            if !args.contains("--autostart") {
                let start = directory.appendingPathComponent("start-\(runID)")
                // No polling or cross-device traffic during an actual measurement.
                var waits = 0
                while (try? String(contentsOf: start, encoding: .utf8)) != runID {
                    try await pause(0.25); waits += 1
                    if waits > 480 { throw Failure("The recorder did not start within two minutes.") }
                }
                // CoreDevice may still be verifying its transfer after this read.
                // Keep the unique receipt: removing it here races `devicectl copy`
                // and reports a missing file even though playback already started.
                // Matching the complete run ID also rejects partial/stale transfers.
            }
            try await pause(1)
            if pass == "memory" { try await memoryRun(size: size) }
            else { try await timingRun(size: size) }
            complete = true; status = "This pass is saved"
        } catch {
            self.error = error.localizedDescription
            status = "Stopped: \(error.localizedDescription)"
        }
        write(finished: true)
    }
    private func environmentCheck() throws {
        guard UIApplication.shared.applicationState == .active else { throw Failure("App left the foreground; rerun without switching apps or locking the phone.") }
        guard ProcessInfo.processInfo.thermalState == .nominal || ProcessInfo.processInfo.thermalState == .fair else {
            throw Failure("Phone became too warm. Let it cool before comparing results.")
        }
        guard !UIAccessibility.isReduceMotionEnabled, !ProcessInfo.processInfo.isLowPowerModeEnabled else {
            throw Failure("Reduce Motion or Low Power Mode changed during the run.")
        }
    }
    private func prepare(_ next: Scenario) async throws {
        controller.cancel(); burst = nil; legacyEmissions = 0
        scenario = next; showKeyboard = true; scrollToBottom = false
        status = next.name
        try await pause(smoke ? 0.2 : 0.8)
        try environmentCheck()
    }
    private func makeBurst(_ s: Scenario, size: CGSize, seed: UInt64) -> ConfettiBurst {
        ConfettiBurst(cannons: (0..<s.cannons).map { index in
            ConfettiEmitter(x: Double(size.width) * (Double(index) + 0.5) / Double(s.cannons),
                            y: Double(size.height) * 0.62, delay: Double(index) * 0.1,
                            count: s.count / s.cannons, angle: 90, spread: 40)
        }, seed: seed, radius: 130, fall: 320, size: s.festive ? 10 : 7,
        shapes: s.festive ? ConfettiShape.festive : ConfettiShape.classic, fallSpeedRange: s.festive ? 0.75...1.35 : 1...1)
    }
    private func emit(_ next: ConfettiBurst) throws {
        trialID += 1
        if scenario.renderer == "paper" {
            guard controller.pop(next, colors: palette), controller.isPlaying else { throw Failure("PaperConfetti rejected the burst. No performance result was recorded.") }
        } else if scenario.renderer == "legacy" { burst = next }
    }
    private func timingRun(size: CGSize) async throws {
        let scenarios = smoke ? Array(Scenario.all.prefix(3)) : Scenario.all
        let rounds = smoke ? 1 : (pass == "cpu" ? 2 : 4)
        for round in 0..<rounds {
            // Rotate scenario order, keeping the first round separate from warm statistics.
            let offset = round % scenarios.count
            for s in Array(scenarios.dropFirst(offset)) + scenarios.prefix(offset) {
                try await prepare(s)
                let seed = UInt64(1000 + round)
                let next = makeBurst(s, size: size, seed: seed)
                let meter = Measurements()
                let signpost = OSSignpostID(log: benchmarkLog)
                os_signpost(.begin, log: benchmarkLog, name: "Confetti trial", signpostID: signpost, "%{public}@ round=%d", s.name as NSString, round)
                meter.start(memory: false)
                defer { _ = meter.stop() } // Also invalidate sampling if this trial throws or is cancelled.
                try emit(next)
                // Match the same underlying content motion for every renderer, including control.
                try await pause(0.25)
                withAnimation(.easeInOut(duration: 0.35)) { showKeyboard = false }
                try await pause(0.45)
                withAnimation(.easeInOut(duration: 0.5)) { scrollToBottom = true }
                try await pause(4.8)
                var row = meter.stop()
                os_signpost(.end, log: benchmarkLog, name: "Confetti trial", signpostID: signpost)
                try environmentCheck()
                if s.renderer == "legacy", legacyEmissions != s.count { throw Failure("Legacy renderer did not trigger all expected particles.") }
                if s.renderer == "paper", controller.isPlaying { throw Failure("PaperConfetti did not clean up its completed flight.") }
                row.merge(["scenario": s.name, "renderer": s.renderer, "round": round,
                           "warmup": round == 0, "first_renderer_use": round == 0 && (s.name.hasSuffix("single") || s.renderer == "none"),
                           "particles": s.count, "seed": seed, "thermal_state": ProcessInfo.processInfo.thermalState.rawValue,
                           "legacy_triggered_particles": legacyEmissions,
                           "paper_active_after_settle": controller.isPlaying]) { _, new in new }
                results.append(row); write(finished: false)
            }
        }
    }
    private func memoryRun(size: CGSize) async throws {
        // Alternating natural completion and explicit cancellation. Each renderer gets its own
        // retained overlay, as in an app; unmount legacy flights between cycles to release state.
        let scenarios = [Scenario.all[7], Scenario.all[4]]
        for round in 0..<12 {
            for s in round % 2 == 0 ? scenarios : scenarios.reversed() {
                try await prepare(s)
                let meter = Measurements(); meter.start(memory: true)
                defer { _ = meter.stop() }
                let id = OSSignpostID(log: benchmarkLog)
                os_signpost(.begin, log: benchmarkLog, name: "Memory cycle", signpostID: id, "%{public}@ cycle=%d", s.name as NSString, round)
                try emit(makeBurst(s, size: size, seed: UInt64(2000 + round)))
                try await pause(round % 2 == 0 ? 1 : 5.5)
                let naturallyIdle = !controller.isPlaying
                controller.cancel(); burst = nil
                try await pause(1)
                var row = meter.stop()
                os_signpost(.end, log: benchmarkLog, name: "Memory cycle", signpostID: id)
                try environmentCheck()
                guard !controller.isPlaying else { throw Failure("PaperConfetti remained active after cancellation.") }
                if s.renderer == "paper", round % 2 == 1, !naturallyIdle { throw Failure("Natural flight cleanup did not finish.") }
                row.merge(["scenario": s.name, "renderer": s.renderer, "round": round,
                           "warmup": round == 0, "particles": s.count, "cancelled": round % 2 == 0,
                           "paper_active_after_settle": controller.isPlaying,
                           "thermal_state": ProcessInfo.processInfo.thermalState.rawValue]) { _, new in new }
                results.append(row); write(finished: false)
            }
        }
    }
    private func write(finished: Bool) {
        let payload: [String: Any] = ["schema": 1, "run_id": runID, "pass": pass,
            "finished": finished, "success": finished && error == nil, "error": error as Any? ?? NSNull(),
            "simulator": isSimulator, "os": UIDevice.current.systemVersion,
            "screen_maximum_fps": UIScreen.main.maximumFramesPerSecond,
            "reduce_motion": UIAccessibility.isReduceMotionEnabled,
            "low_power_mode": ProcessInfo.processInfo.isLowPowerModeEnabled,
            "rows": results]
        do { try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]).write(to: outputURL, options: .atomic) }
        catch { status = "Could not save measurements: \(error.localizedDescription)"; complete = false }
    }
    private var isSimulator: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }
    struct Failure: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}
