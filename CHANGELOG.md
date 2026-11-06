# Changelog

## 1.0.0 — 2026-11-06

- Establish the stable public API and 1.x compatibility contract while retaining iOS 16 and the 0.4 method names. Configurations are now Sendable values.
- Fix color-space and pattern-color collisions in both image caches. Prepare only shape/color/pose combinations used by an event, sharing repeated images.
- Fix source anchors when SwiftUI replaces a controller without changing geometry, and support UIKit storyboard/archive decoding without restoring old flights.
- Harden extreme finite angle conversion and invalid shape-preview bounds. Stop shape selection after the first 32 distinct values.
- Document every authored public symbol, parameter limits, lifecycle outcomes, ownership, and privacy. Compile complete SwiftUI/UIKit examples and fail validation for missing public documentation or DocC warnings.
- Bundle explicit privacy declarations alongside the existing attribution. Add regression coverage for resources, palettes, custom holes, source movement/replacement/removal, deferred layout, UIKit foreground/background behavior, and input pass-through.
- Repair individual-shape profiling scenarios after the 0.4 value-type migration and validate all 16 named shapes. Make texture audits reflect used combinations and label their reconstruction scope. Existing physical-performance results retain their measured release labels; this release makes no new device-performance claim.

## 0.4.0 — 2026-11-05

- Modernize configuration labels and typed angles; share configuration across single and multiple cannons.
- Add launch-speed multiplier, observable lifecycle state, relative/source origins and a public UIKit host. Event calls return Void; outcomes report completion.
- Add full-width `drop()` showers and bounded, cached custom paths, keeping iOS 16 support.
- Move raw physics/texture/renderer diagnostics behind testing SPI. See the migration guide for pre-1.0 source changes.
- Extend examples and lifecycle, geometry, fading and touch-through regression coverage. Existing device measurements remain explicitly version-labeled.
- Select a standard iPhone runtime for simulator pixel probes when a device-specific runtime has the same version.

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
