# Standalone validation

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
CI remains configured for Xcode 16.4 and 26.6; neither hosted job has run yet
because this local repository has no remote.

Physical 60 Hz/120 Hz profiling and a minimum-iOS runtime run remain pre-release
checks in [PUBLISHING.md](PUBLISHING.md). The renderer targets iOS 16+, but simulator
tests do not establish device GPU/FPS, energy, or every supported OS behavior.
