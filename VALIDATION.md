# Validation and release review

## Native renderer 0.2.0 preflight — October 28, 2026

The package now uses native particles by default, with flat/3D appearances. Local
validation on Xcode 27.2 RC (27B48), Swift 6.4.2 and the dedicated iOS 27.2 simulator:

- Nine macOS physics tests; sixteen iOS package/renderer tests.
- Three example UI tests, including both appearances, real touch-through scrolling,
  navigation, Reduce Motion, cancellation and repeated pops.
- macOS/iOS Release builds and DocC passed. The example screenshot was recaptured
  from the running app and visually reviewed with its new 3D/Flat selector.
- Ten numerical benchmark tests and 33 Python runner/parser tests passed.
- The renderer-study simulator smoke suite completed its native/legacy cases and
  all interaction checks, including the three production pixel regressions.
- On the connected iPhone 18 Pro Max, iOS 27.0.1, all three production-native
  pixel regressions passed: six flat/3D cannon replays, all 5,760 occupied grid
  positions, and a negative control reproducing the old expired birth window.
  The grid edits diagnostic positions/size through public layer APIs; shipping
  cell creation, clock, and cancellation code are exercised directly.
- A later simulator repeat intermittently missed the last moving column. Five
  repeated runs then passed all 30 cannon replays. The diagnostic now holds
  position/opacity and lengthens visibility so slow screenshot transfers cannot
  miss falling particles; production birth timing is unchanged. Failure captures
  are retained. The revised original profiling smoke passed all 12 UI tests,
  including all 5,760 slots and the old-clock negative control. Evidence:
  `.artifacts/profile-20261028T193958Z-95c1d5/`. The optional physical repeat of
  this diagnostic-only adjustment stopped when the phone locked; the production
  renderer itself is unchanged from the successful physical run above.

This physical evidence establishes emission correctness on the tested device,
not a general FPS/energy or all-device capacity guarantee. The historical 0.1 CPU
comparison is labeled accordingly; no new performance percentage is claimed.
Source has no runtime dependencies, network, analytics, private behaviors, test
launch arguments or project signing identity. SpriteKit was removed from active
code and scenarios. The original MIT attribution remains bundled. UIKit API names
and existing `pop()` calls remain source-compatible; seeded trajectories intentionally
change to the approved parabolic/soft-edge model in this minor release.

Generated local evidence: `.artifacts/validation-20261028T192425Z/`,
`.artifacts/release-0.2-core.log`, `.artifacts/release-0.2-motion.log`, and
`.artifacts/Release02DeviceEmission.xcresult`. Main/tag CI and an exact-tag consumer
are separately required by [PUBLISHING.md](PUBLISHING.md); their final receipts
belong in the [0.2.0 release](https://github.com/twhitt14/PaperConfetti/releases/tag/0.2.0).

## Hosted release preflight — October 26, 2026

[GitHub Actions run 40281541365](https://github.com/twhitt14/PaperConfetti/actions/runs/40281541365)
passed on the release source at `93f6ec0227cb4d8ec5d90e010e5fee9860ffb285`:

| Toolchain | macOS tests | iOS package tests | Example UI tests | Release builds / DocC |
| --- | --- | --- | --- | --- |
| Xcode 16.4 (16F6), Swift 6.1.2 | 8 passed | 14 passed | 2 passed | Passed |
| Xcode 26.6 (17F113), Swift 6.3.3 | 8 passed | 14 passed | 2 passed | Passed |

A fresh consumer also resolved the private GitHub `dev` branch, built the product
using identity `paperconfetti`, and imported `PaperConfetti` successfully. The
release workflow separately requires successful main/tag CI and an exact-version
consumer before publishing release notes. See the
[0.1.0 release](https://github.com/twhitt14/PaperConfetti/releases/tag/0.1.0)
for the final tag and CI evidence.

The release review covered all tracked source, the example, tooling, workflow,
licenses, and reachable Git history. No credentials, private service configuration,
signing material, personal Xcode state or generated build output were found.
The runtime has no network calls, analytics, persistence or third-party package
dependencies. Original vector silhouettes and the example screenshot are included;
no external reference artwork is redistributed. The original ConfettiSwiftUI MIT
notice is retained verbatim at the root and in the package resource bundle.

CI actions are pinned, checkout does not persist credentials, token permissions
are read-only, and logs/results are retained for seven days. CI cannot publish a
release. Repository visibility remains private; this release does not authorize
a visibility change.

## Local extraction validation — October 25, 2026

Validated October 25, 2026 on Apple silicon with Xcode 27.2 (27B48),
Swift 6.4.2, and the dedicated **PaperConfetti Example** iOS 27.2 simulator.

| Check | Result |
| --- | --- |
| macOS physics tests | 8 passed |
| macOS Release library build | Passed |
| iOS package tests | 14 passed: 8 physics + 6 UIKit/lifecycle |
| Example UI tests | 2 passed |
| Example Release simulator build | Passed for arm64 and x86_64 |
| iOS DocC build | Passed, no documentation warnings |
| Example Debug/Release version resolution | App and UI-test targets inherit 0.1.0 (1); no signing team |
| Workflow YAML | Parses; action references pinned to verified v6 commits |
| Clean staged-source export | Full validation passed without prior build products or Xcode workspace state |
| Example screenshots | Captured and visually reviewed; README includes the live burst |

The interaction test fires confetti, taps the underlying button and toggle,
scrolls to the last shape, cancels, and navigates while another burst is active.
The second test enables the example's Reduce Motion preview and confirms that
popping leaves no active particles. Renderer tests separately verify UIKit hit
routing, canceled/inactive hosts, window removal, initial pending events and
repeated seeded pops. These are behavioral checks, not FPS measurements.

The example UI tests use short, bounded scroll gestures to bring controls below
the navigation bar before tapping. A full swipe previously scrolled an expandable
control behind the translucent bar; the test now checks the visible viewport.
A subsequent CI repeat also caught a center-screen scroll drag being consumed
by a slider. Gestures now use the empty 24-point content gutter and stop without
momentum; the Reduce Motion test explicitly verifies the switch is enabled.
Both UI tests passed three consecutive local repetitions after this correction
(six executions, no failures), recorded in
`.artifacts/release-0.1.0/RepeatedUITests.xcresult`.

Local evidence is intentionally ignored:

- `.artifacts/validation-20261025T204553Z/core.log` and `core-release.log`.
- `.artifacts/validation-20261025T204802Z/`: successful iOS tests, Release build,
  DocC, xcresults, and machine-readable completion receipt.
- `.artifacts/fresh-source/.artifacts/validation-20261025T205102Z/`: full successful
  clean-export repeat (8 macOS tests, 14 iOS package tests, 2 example UI tests,
  Release builds and DocC).
- `.artifacts/capture-build.log` and `.artifacts/captures/`: final seeded capture
  route rebuild and screenshots.

The newest SDK warns that the example has no App Intents metadata to extract,
and its XCTest libraries have a newer deployment minimum than the app's iOS 16
setting. The app/package build and the installed-runtime tests succeed. Hosted
results for Xcode 16.4 and 26.6 are recorded above.

Physical 60 Hz/120 Hz profiling and a minimum-iOS runtime run remain follow-up
checks described in [PUBLISHING.md](PUBLISHING.md). The renderer targets iOS 16+, but simulator
tests do not establish device GPU/FPS, energy, or every supported OS behavior.

## Automated profiling suite — October 26, 2026

The independent benchmark app and `tools/profile.py` now provide the device
workflow documented in [PROFILING.md](Documentation/PROFILING.md). The public
library and its dependency-free package manifest are unchanged.

Local validation used Xcode 27.2 and the dedicated PaperConfetti Example iOS
27.2 simulator:

- Seven Python regression tests cover physical-device selection, certificate
  team selection, result identity/completeness, warm-up exclusion and reports.
- `swift test` and the full `tools/validate.py` suite passed, including the iOS
  renderer tests, real example gestures, Release build and DocC.
- The final `python3 tools/profile.py --simulator-smoke` command passed, including
  both renderers, checkpoint/report collection, the native protocol smoke test
  and the two real overlay interaction tests. Its evidence is in
  `.artifacts/profile-20261027T051610Z-d775f9/`.
- The benchmark app and UI-test target compiled in Release for a physical iPhone
  with signing disabled for this compile-only check.
- The full benchmark protocol completed all 36 timing trials and 24 memory
  cycles on the simulator. Natural completion and explicit cancellation left
  PaperConfetti inactive.
- Screenshots confirmed that both the new renderer and the pinned historical
  renderer emit particles. These visual checks are separate from performance
  claims; screenshots were never part of a reported physical-device session.
- The host notification handshake, a Time Profiler recording/export on a test
  process, and an Allocations recording/export on the simulator benchmark app
  were exercised successfully. CoreDevice launch JSON was also verified.

Evidence lives under ignored `.artifacts/validation-20261027T051442Z/`,
`.artifacts/full-protocol-validation/`,
`.artifacts/simulator-allocation-validation/`, and
`.artifacts/host-recorder-validation/cpu.trace`. Deliberate unsupported-platform
probes are retained alongside their error logs; they are not successful runs.

No physical phone was connected. Physical signing/install, CoreDevice container
file transfers, and Animation Hitches recording must still be confirmed on the
first iPhone run. Apple does not support Hitches on this simulator, and its
CoreDevice simulator surface does not support Transfer Files; the smoke command
uses `simctl` for those local operations. These checks establish working
benchmark automation and cleanup, not an iPhone speedup, hitch rate, energy
measurement, leak-proof certification, or Wordie integration performance.


## Physical profiling recovery — October 27, 2026

The first iPhone 18 Pro Max / iOS 27.0.1 run completed all 36 timing trials,
but the runner terminated Instruments after its old 90-second finalization
limit. Valid app samples were recovered into that run's report; the partial
recording remains explicitly incomplete. A short capture then proved that
30 seconds of playback could require about 149 seconds to record and save.

The runner now launches directly through Instruments (avoiding an observed
CoreDevice PID-attachment lookup failure), allows 15 minutes for finalization,
prints save progress, and retains independently validated samples on failure.
The app clearly distinguishes a saved pass from a finished suite. Only the
exact installed benchmark bundle is stopped; a waiting screen prevents
between-pass auto-lock without changing the phone's settings.

The full recovery session saved all three recordings and passed every device
interaction check. The phone was reconnected during timing finalization; the
CPU/memory passes and gesture tests subsequently completed normally:

| Check | Result |
| --- | --- |
| Animation timing trials | 36 completed; 3.2 GB trace saved after about 12 minutes of finalization |
| CPU trials | 18 completed; trace saved |
| Memory cycles | 24 completed; trace saved; PaperConfetti inactive after every settle/cancel |
| Physical iPhone protocol/gesture tests | 3 passed |
| Dedicated simulator protocol/gesture tests | 3 passed |
| Python runner regression tests | 12 passed |

The full run also revealed incomplete scenario labels with template defaults.
Afterward, explicit Points of Interest and a retention window covering the
entire recording limit were verified in separate 45-second simulator and
physical-phone captures: all three trial intervals remained available, including
the early intervals more than 30 seconds before capture end. Future exports
retain compact hitch/signpost tables; per-frame/GPU details stay in the trace.
Do not use the earlier full run for per-scenario hitch comparisons. Its complete
app measurements remain valid process-CPU/scheduling/memory diagnostics.

Ignored evidence:

- `.artifacts/profile-20261027T064016Z-c581c3/`: original partial recording and
  recovered samples; original reports backed up before recovery.
- `.artifacts/profile-20261027T071826Z-346a53/`: completed three-pass session,
  full raw measurements and physical `Interactions.xcresult`.
- `.artifacts/ProfileRecoveryInteractions.xcresult`: three simulator UI tests.
- `.artifacts/recording-recovery-20261027/direct-verified/`: successful short
  device launch/capture/export.
- `.artifacts/recording-recovery-20261027/device-full-window/` and
  `simulator-full-window/`: verified early-marker retention.
- `.artifacts/recording-recovery-20261027/completion-screen.png`: inspected
  completion messaging.

No production renderer or package API changed. These are one-phone diagnostics,
not a public FPS/energy benchmark or proof that the complete Wordie app has no
hitches. Repeat full sessions on cool 60 Hz and ProMotion devices before broader
performance claims.

## Controlled renderer study — October 27, 2026

The expanded [study](Documentation/RENDERER_STUDY.md) is implemented in the benchmark app only. Package source, dependencies, public API and version remain unchanged.

Local checks used Xcode 27.2 (27B48) and the dedicated PaperConfetti Example simulator:

- 22 Python tests passed, including matched-factor validation, fresh-process cold cases, missing/no-op result rejection, XML references, process filtering, overlap/clipping, duplicate/missing markers, and unknown hitch attribution.
- `swift test` and `python3 tools/validate.py` passed again: 8 macOS tests, 14 iOS package tests, 2 example UI tests, Release builds and DocC. Evidence: `.artifacts/validation-20261027T083904Z/`.
- The new runner completed the six-case renderer smoke matrix; separate runs exercised reduced/adaptive motion sampling, texture resolution, padded/trilinear filtering and three fresh-process cold trials.
- The memory smoke completed ten cycles across all five renderer configurations, exercising both explicit cancellation and natural completion. Evidence: `.artifacts/study-20261027T085613Z-b4f33c/`.
- Five benchmark UI tests passed, including the original protocol and accessibility/navigation tests, completion/cleanup of every new renderer, and actual taps counted while each overlay was active plus scrolling to visible content beneath it.
- The benchmark app compiled in Release for generic iOS with signing disabled (compile-only), in addition to simulator builds.
- A fresh 35-second Instruments Time Profiler + Points of Interest recording retained both new study intervals. The exported XML parser resolved real references and matched process IDs, labels and durations against the app results. Evidence: `.artifacts/study-trace-verification/verification.json`. This was a simulator marker/export test, not physical hitch evidence.
- Screenshots of shipping layers, adjustable layers, CAEmitterLayer, SpriteKit, atlas, padded textures, trilinear filtering and adaptive motion were captured and inspected under `.artifacts/study-visual-check/`.

The deterministic motion audit (720 particles, seed 1000) measured maximum sampled-trajectory error of 33.712 points with 49 uniform samples, 55.542 points with 25 uniform samples, and 0.534 points with 26–41 adaptive samples. This quantifies approximation of the underlying physics, **not frame delivery or a device speed improvement**. The adaptive candidate remains benchmark-only pending physical CPU/hitch and visual comparison. Evidence: `.artifacts/study-20261027T083201Z-50f20e/`.

The physical iPhone was disconnected during this work. No new physical renderer ranking, GPU result, or production optimization is claimed. Run `python3 tools/compare.py --suite all` on the connected phone to collect that evidence. The previous physical ConfettiSwiftUI comparison remains independently documented above.

## Device start-transfer recovery — October 28, 2026

The full comparison command exposed an intermittent CoreDevice startup failure:
`Failed to retrieve the file node for Documents/start-…`. Both benchmark modes
removed the start file as soon as it appeared, racing CoreDevice's final transfer
verification. They now wait for the complete matching run ID and leave the tiny,
unique receipt intact. Partial or stale contents do not start playback. No
package rendering code, API, dependency, or version changed.

- The optimized benchmark app built and installed on the physical iPhone.
- Five consecutive device launches completed their start transfers and control
  trials; each receipt was read back after playback and still matched its run ID.
  Evidence: `.artifacts/startup-regression-20261028T000743/verification.json`.
- All 22 existing Python runner/parser tests passed.
- The exact `python3 tools/compare.py --suite all` command was restarted with the
  fix under `.artifacts/study-20261028T061131Z-d9654e/`. Its first nine timing
  trials had complete process-attributed Instruments markers; consult that
  run's report for subsequent batch status, rather than treating app completion
  or saved measurements alone as proof that all trace evidence is available.
- The earlier investigative run retained independent samples, but its second
  trace omitted four early trial markers. Hitch attribution correctly remained
  unavailable for that batch; no zero-hitch or renderer-ranking claim is made.

## Interactive restart and native emitter motion — October 28, 2026

Visual Review now offers to stop the active repository-owned runner, waits for
its cleanup, and opens a fresh app session. `--restart` explicitly authorizes the
same handoff without a prompt; `--stop` stops without launching another run.
The original suite shares the ownership lock. PID/start-time/repository checks
and the existing lock inode prevent terminating unrelated processes or starting
two runners together. Opening the installed app without runner arguments now
enters Visual Review, starting with Native particles at 720.

The benchmark CAEmitterLayer implementation changed from constant-gravity
ballistic flight to shared PaperConfetti position/fade tracks. Cohorts contain at
most four particles, with independent native spin and small horizontal drift.
This preserves the launch, deceleration, shape-specific descent and late fade,
while retaining fewer layers/animations than the per-particle implementation.
It does not reproduce individual 3D tumble. This is **benchmark-only**; package
source, API, dependencies and versions remain unchanged. Old native-emitter
performance results do not establish the new implementation's performance.

Validation:

- 30 Python tests passed, including decline/accept/restart, stale receipts,
  reused PIDs, other repositories, changed owners and cleanup timeouts.
- A real simulator comparison was interrupted through the new interactive
  `--visual-review` prompt. The old run exited, its results remained saved,
  and the new session opened without sharing the lock/device with it.
- `swift test`: 8 tests passed. The required iOS package/example/Release/DocC
  checks passed under `.artifacts/validation-20261028T065314Z/`.
- Six renderer smoke trials and six benchmark UI tests passed under
  `.artifacts/study-20261028T065412Z-04e334/`, covering all renderer paths,
  cleanup, real taps during flight, scrolling, and stop/replay/switching.
- After adding direct app entry, two focused UI tests passed under
  `.artifacts/VisualReviewEntry-20261028.xcresult`, including normal launch
  into the native comparison and another stop/replay/switch check.
- The final benchmark compiled in Release for generic physical iOS with signing
  disabled; evidence: `.artifacts/emitter-review-device-compile.log`.
- The 720-particle fixture used 257 native cohorts and 8,836 shared position
  samples. Maximum shared-path interpolation error was 0.532 points; opacity
  error was 0.00391. These are numerical diagnostics, **not FPS or GPU results**.
- Launch, apex, descent and cleared-overlay screenshots were inspected under
  `.artifacts/emitter-motion-20261028/` and
  `.artifacts/emitter-motion-final-20261028/`.

The earlier full device study was stopped at the owner's request. Completed
batches remain under `.artifacts/study-20261028T061131Z-d9654e/`; incomplete
marker evidence remains unavailable. The iPhone disconnected before the new
visual build could be installed. Reconnect/unlock it and run
`python3 tools/compare.py --visual-review` to install and test the new motion.
No new physical performance improvement is claimed.
