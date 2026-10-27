import UIKit
import Darwin
import os.signpost

let benchmarkLog = OSLog(subsystem: "org.paperconfetti.benchmarks", category: .pointsOfInterest)

/// Scheduling diagnostics, not a count of frames actually presented by the GPU.
@MainActor final class Measurements: NSObject {
    private var link: CADisplayLink?
    private var intervals: [Double] = []
    private var last: Double?
    private var startTime = 0.0
    private var startCPU = 0.0
    private var firstCallback: Double?
    private var baselineMemory: UInt64 = 0
    private var peakMemory: UInt64 = 0
    private var memoryTimer: Timer?

    static func footprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : 0
    }
    private func cpuTime() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
            + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
    }
    func start(memory: Bool) {
        intervals = []; last = nil; firstCallback = nil
        baselineMemory = Self.footprint(); peakMemory = baselineMemory
        startCPU = cpuTime(); startTime = CACurrentMediaTime()
        if memory {
            // Only the memory pass samples allocations/footprint while flying.
            memoryTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.sampleMemory() }
            }
        } else {
            link = CADisplayLink(target: self, selector: #selector(tick))
            let maximum = Float(UIScreen.main.maximumFramesPerSecond)
            link?.preferredFrameRateRange = CAFrameRateRange(minimum: min(60, maximum), maximum: maximum, preferred: maximum)
            link?.add(to: .main, forMode: .common)
        }
    }
    private func sampleMemory() { peakMemory = max(peakMemory, Self.footprint()) }
    @objc private func tick() {
        let now = CACurrentMediaTime()
        if let last { intervals.append((now - last) * 1000) }
        else { firstCallback = (now - startTime) * 1000 }
        last = now
    }
    func stop() -> [String: Any] {
        link?.invalidate(); link = nil
        memoryTimer?.invalidate(); memoryTimer = nil
        let endMemory = Self.footprint()
        let sorted = intervals.sorted()
        func percentile(_ p: Double) -> Any {
            guard !sorted.isEmpty else { return NSNull() }
            return sorted[Int(Double(sorted.count - 1) * p)]
        }
        return ["duration_s": CACurrentMediaTime() - startTime,
                "cpu_ms": (cpuTime() - startCPU) * 1000,
                "callback_count": intervals.count,
                "first_callback_ms": firstCallback as Any? ?? NSNull(),
                "callback_p95_ms": percentile(0.95), "callback_p99_ms": percentile(0.99),
                "footprint_start_bytes": baselineMemory, "footprint_end_bytes": endMemory,
                "footprint_peak_sampled_bytes": max(peakMemory, endMemory)]
    }
}
