# Changelog

## 0.3.0 — 2026-11-04

- Make comparison-app coordinate conversions explicit for Xcode 16.4; the new
  release checks caught an older-compiler arithmetic ambiguity.

- Optional controller completion callbacks report `finished`, `reducedMotion`,
  `cancelled` or `notPresented` once on the main actor. Existing `pop()` calls and
  typed method references remain compatible. Completion includes delayed cannons
  and cleanup; it is not a last-visible-pixel measurement.
- Fix a pre-existing readiness-delegate capture error during full strict Swift 6
  compilation. The renderer's shared launch clock and particle physics are unchanged.
- Add a complete button-anchor origin recipe using the existing `pop(at:)` API.
  Validation compiles the library and examples in strict Swift 6 and checks that
  the standalone origin example matches its DocC source.
- Configure Swift Package Index documentation and compatibility badges, and add
  a launch-speed comparison to the example app.
- Improve local profiling/recording recovery and document the native renderer's
  measured device results. Performance measurements remain version/device-specific.

## 0.2.0 — 2026-10-28

- Native `CAEmitterLayer` rendering is now the default, with `.threeDimensional`
  and `.flat` appearances on configurations and bursts. Existing pop calls still work.
- Individual parabolic rise/fall timing, a soft scattered blast edge, and shared
  raster starting poses preserve variety without per-frame app updates.
- Staged, pre-rolled launch clocks avoid short birth windows under heavy submission load;
  cancellation also invalidates pending launches. Requested populations are bounded
  at 6,000, with visible 5,760-piece regression coverage.
- Example app gains a flat/3D picker and up to 5,760-piece stress control.
- Benchmarks exercise the shipping native renderer, retain a frozen 0.1 baseline,
  and remove SpriteKit/atlas experiments. Old CPU results remain version-labeled.
- Recover saved benchmark measurements after recording failures, allow slow device trace finalization with visible progress, and launch the app directly through Instruments. Clarify per-pass completion and keep the screen awake between recordings.
- One-command physical iPhone profiling suite with separate animation, CPU and memory recordings, a pinned historical ConfettiSwiftUI comparison, interaction checks, local reports and a simulator CI smoke test.

## 0.1.0 — 2026-10-26

- Method-based SwiftUI integration: `ConfettiController`, `pop()`, `cancel()` and
  `.confettiOverlay(...)`; no event counter needed.
- Thirteen original paper shapes, shape-specific random descent speeds, seeded
  physics, configurable palettes and independent multi-cannon timing.
- Core Animation rendering, bounded shared textures and explicit cancellation.
- Touch-transparent overlays, Reduce Motion and scene lifecycle handling.
- UIKit integration, DocC, MIT licensing and original ConfettiSwiftUI attribution.
- Standalone interactive iOS example, physics/renderer/UI tests and GitHub Actions.
