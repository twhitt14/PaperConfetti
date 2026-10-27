# Validation and release review

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
