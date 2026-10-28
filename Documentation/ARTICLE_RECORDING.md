# Record the PaperConfetti article comparison

This is a visual demonstration, separate from timing/CPU/memory measurements.
It uses the shipping native PaperConfetti renderer and pinned ConfettiSwiftUI
1.1.0 (`f45961f97bbae6fff6e2e64546fea0189425ad92`) in the same optimized host.
The old renderer is a historical baseline, not an assertion about latest upstream.

## On an iPhone

Connect by USB, unlock it and run from this checkout:

```sh
python3 tools/article-demo.py
```

The existing profiling setup supplies device selection and locally remembered
signing; first-time setup may need the same `--team` option as `tools/profile.py`.
Start iOS Screen Recording from Control Center, return to the app and tap
**Start comparison**. The sequence runs itself (about 75 seconds). **Stop**
cancels the sequence; **Start** replays it. The app prevents auto-lock only during
playback and restores normal behavior afterward. No Instruments is attached.

The eight segments are:

1. ConfettiSwiftUI 1.1.0, 180 pieces.
2. Native PaperConfetti, 180 pieces.
3. ConfettiSwiftUI 1.1.0, 720 pieces.
4. Native PaperConfetti, 720 pieces.
5. ConfettiSwiftUI 1.1.0, 1,800 pieces.
6. Native PaperConfetti, 1,800 pieces.
7. Native PaperConfetti, 1,800 festive pieces.
8. Native PaperConfetti, 5,760 festive pieces.

The first six match three classic shapes, colors, nominal size, cannon count,
spacing and host keyboard animation. Their random trajectories and physics differ;
legacy randomness is not seed-controlled. Festive clips are explicitly separate
showcases: thirteen shapes and a larger nominal size. 5,760 is 32 times Wordie's
180-piece budget, not evidence of a 32× speedup or a universal capacity guarantee.

Use a cool phone, the same orientation throughout, Low Power Mode/Reduce Motion
off, and a Focus that hides personal notifications. Screen recording itself adds
work and may conceal or introduce stutter; keep it out of benchmark runs. Don't
retime footage, interpolate frames or select a deliberately bad baseline take.
If the old small burst looks smooth, report that honestly.

## Automatic simulator footage

```sh
python3 tools/article-demo.py --simulator
# A single segment, useful for reviewing framing:
python3 tools/article-demo.py --simulator --case festive-5760
```

Output is under ignored `.artifacts/article-*/`: `comparison.mp4`, `after.png`,
and `receipt.json` with the source revision, dirty flag, source library pin,
completed segment IDs/counts and request timestamps. The recorder waits for a
fresh run ID's completion receipt, not a guessed total duration. A failure retains
partial footage instead of labeling it complete. `--skip-build` is only for a
binary rebuilt after the most recent source change. Simulator video demonstrates
appearance and automation, not physical-device performance.

Both modes share the existing run lock with profiling/comparison tools. Stop a
running recorder with Control-C before starting another. Do not run multiple
recording/measurement flows concurrently.

The package runtime itself does not contain this screen, recording code, file
receipts or the historical dependency. Do not mix the article's output with
`tools/profile.py` / `tools/compare.py` measurement evidence.
