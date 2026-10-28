# Changelog

## 0.2.0 — 2026-10-28

- Native `CAEmitterLayer` rendering is now the default, with `.threeDimensional`
  and `.flat` appearances on configurations and bursts. Existing pop calls still work.
- Individual parabolic rise/fall timing, a soft scattered blast edge, and shared
  raster starting poses preserve variety without per-frame app updates.
- Staged launch clocks prevent missed early cannons under heavy submission load;
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
