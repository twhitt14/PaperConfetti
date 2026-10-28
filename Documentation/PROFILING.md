# Physical-device profiling

Run from the PaperConfetti repository on a Mac with Xcode 16 or later (new enough for your iPhone’s iOS version) and Python 3. No App Store Connect key, TestFlight upload, Cloud credits, paid service, or change to the library is involved. The benchmark app is separate from the example and from Wordie.

## First run

1. Connect your iPhone by USB, unlock it, and accept **Trust This Computer** if asked. In **Settings → Privacy & Security → Developer Mode**, enable Developer Mode and complete the required restart if it is not already enabled.
2. Sign into your Apple account in **Xcode → Settings → Accounts**. Xcode needs an **Apple Development** signing identity for your team. The script automatically selects it when only one development team is available. Otherwise pass `--team ABCDE12345` once; find the team ID in your Apple Developer membership details. The choice is remembered in ignored `.artifacts/profile-settings.json` after successful build/install. No password is read or saved by the script.
3. Turn off Low Power Mode and Reduce Motion for the timing run. Let the phone cool. Use a quiet foreground session without screen recording, mirroring, a debugger, or competing profiling tools. Keep the same brightness, power connection and display settings for repeat comparisons. The benchmark screen prevents auto-lock during playback and the export/cooldown gaps; normal auto-lock resumes when that screen closes.
4. Run:

   ```sh
   python3 tools/profile.py
   ```

5. Approve macOS developer-tools access if Apple asks. If recording times out while a first-time permission dialog is pending, complete that dialog and rerun. Device trust/signing/Developer Mode cannot safely be bypassed by the runner.
6. Leave the phone alone for roughly **15–30 minutes** plus the first build/download (large device traces can take longer to finalize). It plays every scenario, changes its simulated game keyboard and scroll position, records three Instruments traces, then runs real gesture tests. The phone reports completion of each pass, not completion of the entire suite. Keep it connected while the terminal finalizes recordings; it prints progress every 20 seconds and the final report path when finished. Open `report.html` in that folder.

If multiple phones are connected, choose one:

```sh
python3 tools/profile.py --list-devices
python3 tools/profile.py --device 'My iPhone' --team ABCDE12345
```

`--team` is only necessary when automatic selection is ambiguous or there is no remembered choice. The team also gives the benchmark app a unique bundle ID; the runner never installs over a personal app. Apple automatic signing may register this development bundle ID and your connected test device with the selected team. It never submits a release or changes marketing/build versions.

## What the command does

- Selects exactly one connected **physical iPhone**; unavailable devices and simulators are excluded. Rejects ambiguous selection.
- Builds the standalone `Benchmarks/PaperConfettiBenchmarks.xcodeproj` in **Release**, installs it, and runs without LLDB, coverage, sanitizers, or the example's extended-flight UI-testing mode.
- Lets Instruments launch the benchmark directly, avoiding unreliable lookup of a separately launched device process by PID. Only the exact installed benchmark bundle is stopped between passes; other apps are untouched. A host Darwin notification confirms the recorder is ready; only then does the runner place a unique start marker in the app's private Documents directory. Playback waits for that marker, so first-use work is inside the recording. Result IDs prevent old files being mistaken for a new run.
- Records **Animation Hitches**, **Time Profiler**, and **Allocations** in separate launches, explicitly including **Points of Interest** to identify each scenario and a retention window covering the entire recording limit. This avoids inheriting a template’s short rolling window. There are short cooldown gaps. The app rejects Low Power Mode/Reduce Motion, stops on serious/critical thermal state or lost foreground, and records thermal state per trial. It does not change your accessibility settings.
- Saves checkpoint results between trials, outside the measured intervals. It avoids device result polling during the expected measurement window. Missing/duplicate trials, no-op timing samples and incomplete flights stop the run with an incomplete report, not a misleading success.
- Tests actual taps, a toggle, scrolling, navigation, cancellation and the Reduce Motion preview through the production SwiftUI overlay using XCUITest. These separate functional tests deliberately use longer-lived particles so gestures reliably happen during flight; those timings are never included in performance statistics.
- Allows up to 15 minutes for each recording to finalize; a physical-device capture can take longer to save than it took to record. Preserves validated app measurements in the report even when a recorder fails, continues independent remaining checks, and still returns a failure status if any recording is incomplete. Preserves local artifacts and partial evidence on failure. A local lock prevents simultaneous runners from colliding. It does not publish anything or contact an analytics service.

## Scenarios and fair comparisons

The matched cases use the same host UI, cyan/orange/gray palette, nominal 7-point size, 130-point launch radius, 320-point fall distance, 40-degree spread, particle totals and 0.1-second five-cannon spacing:

| Scenario | PaperConfetti | ConfettiSwiftUI 1.1.0 |
| --- | --- | --- |
| No-confetti host control | One common control | One common control |
| 180 classic particles, one cannon | Yes | Yes |
| 180 classic particles, five cannons | Yes | Yes |
| 720 classic particles, five cannons | Yes | Yes |
| 180 / 720 festive particles, five cannons | 13 shapes, 10-point size, varied fall speeds | No equivalent; do not compare as identical work |

The benchmark-only dependency is **ConfettiSwiftUI 1.1.0**, revision `f45961f97bbae6fff6e2e64546fea0189425ad92`, matching Wordie's former renderer. It is fetched by SwiftPM from its public repository and pinned by revision in both the project and lockfile. It is **not** added to PaperConfetti's `Package.swift` or the normal example. Its MIT license and attribution remain in `THIRD_PARTY_NOTICES.txt` and the original dependency checkout. This is a historical-baseline comparison, not a claim about current ConfettiSwiftUI releases.

The libraries' implementation, shape geometry and randomized trajectories differ. PaperConfetti uses recorded seeds; the old library has no public seed input. Treat this as matched product workloads rather than pixel-identical animation. New rich shapes are measured separately. Every timing case includes simulated game-keyboard removal and scrolling under a stationary overlay.

Animation Hitches runs one first-use/warm-up round plus three warm rounds; Time Profiler runs one warm-up plus one diagnostic round. Scenario order rotates each round. Round zero is retained in raw results and excluded from warm medians. Only the first single-cannon case for each renderer is its first renderer use in that process; later round-zero cases are warm-up, not cold-start claims. App-launch latency is outside this protocol.

The memory pass alternates 24 total cycles across both renderers, switching order each round, with natural completion and cancellation. PaperConfetti uses its full festive palette there; compare trends within each renderer, not these unequal workloads against one another. It samples process physical footprint every 200 ms in the memory pass only, and verifies PaperConfetti is inactive after settling/cancellation. A bounded cache can keep the final footprint above the starting footprint; rising retained allocations across successive settled cycles are more informative.

## Read the results

Everything is under `.artifacts/profile-<timestamp>-<id>/` (ignored by Git). Reports and logs contain local paths, device names/identifiers and source status; review and redact those before publishing results:


- `report.html` / `report.json`: run status, source revision and dirty-file inventory, device/Xcode metadata, warm medians, links to traces and interaction status.
- `timing-measurements.json`, `cpu-measurements.json`, `memory-measurements.json`: every trial, including first-use/warm-up, process CPU milliseconds, physical footprint, thermal state, callbacks and cleanup checks.
- `timing.trace`: open with Instruments, select **Animation Hitches**, and inspect each **Confetti trial** signpost. This is the authority for actual frame delivery/hitches. The report deliberately does not invent a hitch count when Xcode's export schema changes.
- `cpu.trace`: inspect **Time Profiler** call stacks and first-pop setup work.
- `memory.trace`: inspect **Allocations** and **Memory cycle** signposts for retained objects after natural completion/cancellation. This is not an automatic leak-proof certification.
- `*-toc.xml` lists the schemas offered by your Xcode version. Compact hitch and signpost tables are exported; the much larger per-frame/GPU tables remain available in the original traces.
- `Interactions.xcresult`: actual overlay interaction and Reduce Motion-preview test evidence.
- Logs for build/install/record/export/test failures. Failed or interrupted runs keep an **incomplete** report.

**CADisplayLink callback timing is main-thread scheduling, not GPU presentation, FPS, or hitch rate.** CPU totals are for the whole benchmark process during each interval. Tools add overhead: compare within the same instrument pass on the same phone. Simulator values and memory-instrumented timing must not be used to claim faster device rendering.

Run at least three complete sessions on the same cool phone before conclusions. Check first-pop latency separately from warm medians. Then repeat on an older 60 Hz iPhone and a ProMotion iPhone. The suite requests the display's available refresh range rather than pretending every device is 60 Hz. Verify the complete Wordie win/keyboard sequence on-device separately before claiming the app's hitch is fixed.

## Development checks

```sh
python3 -m unittest discover -s tools/tests -v
python3 tools/profile.py --simulator-smoke
```

The smoke command uses only the dedicated **PaperConfetti Example** simulator, builds Release, verifies the control and both renderers complete, and runs the same real gesture tests. It produces a clearly labeled simulator-only report and skips Instruments; CI must not mistake simulator metrics for device benchmarks. The native benchmark smoke test also runs from the shared benchmark scheme.

The first physical run verified development signing, installation, file transfers and all 36 timing trials on an iPhone 18 Pro Max. Its recorder exceeded the original 90-second finalization limit, so that report is incomplete. A short Animation Hitches capture subsequently saved and exported successfully after more than two minutes. The runner now allows longer finalization and recovers validated samples when a trace fails. Consult `VALIDATION.md` for complete-session evidence; a successful playback alone is not a complete profiling session.

References: [Apple: improving responsiveness](https://developer.apple.com/documentation/xcode/improving-app-responsiveness), [Apple: command-line tools](https://developer.apple.com/documentation/xcode/xcode-command-line-tool-reference), [ConfettiSwiftUI 1.1.0](https://github.com/simibac/ConfettiSwiftUI/releases/tag/1.1.0).

## Renderer alternatives and shape-cost investigation

Use [the renderer study](RENDERER_STUDY.md) for the expanded matrix and per-trial Instruments hitch attribution. `tools/profile.py` preserves this original ConfettiSwiftUI comparison. `tools/compare.py` adds controlled fancy-shape comparisons and a hands-on visual mode; it reuses the same signing, recording, cleanup and device-selection machinery. Do not compare totals from different protocols as if their visual workloads were identical.

To stop the original suite and switch to the interactive renderer comparison, run
`python3 tools/compare.py --visual-review` and answer `y` to the restart question.
Use `python3 tools/compare.py --stop` to stop without starting another session.
Completed recordings remain saved; the interrupted recording is marked incomplete.
