# Contributing

Maintainers develop on `dev`; open pull requests against `dev`. Integrate into
`main` when preparing a release. Keep package releases separate from any app's
App Store version/build number.

## Local checks

1. Open `Package.swift` or `Examples/PaperConfettiExample.xcodeproj`.
2. Run `swift test` for deterministic physics tests.
3. Run `python3 tools/validate.py` for iOS renderer/lifecycle tests, example UI
   tests, a Release simulator build, and DocC. Full Xcode and a compatible iOS
   simulator runtime must be installed. No generated project or signing account
   is required for simulator checks.
4. Run `python3 tools/capture-example.py` for still/seeded-pop screenshots, then
   inspect the example visually, including Reduce Motion, repeated pops,
   cancellation, shape proportions, custom colors and controls during flight.

The runner selects a runtime supported by the active Xcode SDK and uses only the
simulator named PaperConfetti Example. Logs, test results and build products stay
under `.artifacts/`. Do not commit generated data, personal Xcode settings,
credentials or an app signing team.

## Changes to protect

- Keep `confetti.pop()` an event. Repeated identical seeds intentionally repeat.
- Keep the controller free of per-frame published state. A new pop replaces the
  active burst; backgrounding/removal clears work rather than queuing surprises.
- Preserve transparent hit testing, accessibility hiding and Reduce Motion.
- Keep seeded physics deterministic and independent of frame rate. Shapes share
  a base descent speed; each piece has independent timing. Preserve soft blast edges
  and the staged native launch clock, including cancel-before-start safety.
- Keep the package independent of Wordie or any sibling repository. No account,
  Firebase, analytics, network or additional runtime dependency belongs here.
- Preserve attribution and both MIT notices. Add focused regressions for changed
  physics/lifecycle behavior; do not turn simulator metrics into FPS guarantees.

CI uses pinned GitHub Actions, read-only permissions and two Xcode versions. It
runs checks only; it never publishes tags or releases. Update the runner matrix
when GitHub retires an image/toolchain, with a documented validation result.
