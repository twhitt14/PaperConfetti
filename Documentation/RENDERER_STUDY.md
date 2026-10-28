# Renderer and shape study

October 27, 2026. This study extends the [original physical profiling protocol](PROFILING.md). It is a benchmark app experiment, **not a change to the released PaperConfetti renderer**, and makes no new physical-device performance claim until the recordings have been reviewed.

## Run it

Connect and unlock your iPhone by USB, keep Low Power Mode and Reduce Motion off, and let the phone cool. Keep it connected until the Mac prints the final report—not just until the phone says the pass was saved. Use the same device, brightness, refresh-rate settings and charging conditions for repeat comparisons. Stop screen recording, debugger sessions and unrelated profiling tools.

From the PaperConfetti repository:

```sh
python3 tools/compare.py --suite all
```

That one command builds and installs the Release benchmark app, records the renderer, factor and individual-shape matrices, performs a memory endurance run, checks interactions, and writes a local HTML/JSON report under `.artifacts/study-…/`. It uses the same remembered signing team and exact-device safeguards as `profile.py`. Nothing is uploaded. The first build may require Xcode's usual device trust/signing approval.

The full study is intentionally long: approximately 30 minutes of actual playback plus building, cooling and Instruments trace processing. Allow substantially longer on a slow device/Mac; trace finalization previously took many minutes. Recordings are now split into small chunks, normally no more than four scenarios and three rounds per trace, so one large trace does not hold the entire study hostage. Each chunk saves independent results. The app waits for the complete, unique start receipt and keeps it in its Documents folder; deleting it while CoreDevice finishes the transfer can intermittently fail with “Failed to retrieve the file node.” These tiny receipts are intentional and do not trigger another run. If playback exceeds the generous collection budget, the study fails rather than accepting timing contaminated by early result collection; rerun the affected cases with `--trial-budget 15`. Do not run both profiling commands simultaneously.

For a shorter first comparison or a targeted follow-up:

```sh
python3 tools/compare.py                         # renderer comparison + CPU/memory/interactions
python3 tools/compare.py --suite factors --phase timing
python3 tools/compare.py --suite shapes --phase timing
python3 tools/compare.py --only layers-720,adaptive-keyframes --phase timing
python3 tools/compare.py --only layers-720,texture-1x,texture-2x --phase cpu
python3 tools/compare.py --list --suite all
```

`--rounds 3` is the default: one warm-up and two measured rounds, rotating order within each chunk. Repeat a session before choosing a winner; two warm samples are screening evidence, not a population-level conclusion. `--rounds 5` increases repetitions. Cold-texture cases are each launched alone in a fresh process, repeated separately, and never included in warm medians. The memory pass uses at least six cycles per renderer, alternating cancellation and natural completion. Fixed chunk order remains a possible thermal/order bias; for confirmation use `--only` in reversed order as well.

The original apples-to-apples classic-shape comparison with **ConfettiSwiftUI 1.1.0** remains available unchanged:

```sh
python3 tools/profile.py
```

Its numeric baseline and the new study are different protocols. Don't compare their CPU totals directly: the new study uses more complex shapes at a matched 10-point size, a direct UIKit host, and additional diagnostics outside each trial. ConfettiSwiftUI does not provide the same thirteen shapes, so it is not mislabeled as an equivalent fancy-shape implementation.

## Watch the alternatives yourself

```sh
python3 tools/compare.py --visual-review
```

If a comparison is already running, this command asks **“Stop it and open Visual Review? [y/N]”**. Type `y` and press Return. The runner stops its own recording, keeps completed results, waits for cleanup, rebuilds, and opens a fresh interactive session. Declining leaves the existing run alone. The interrupted recording may be incomplete; it is never silently treated as a finished measurement.

For an explicit restart without the question, use `python3 tools/compare.py --visual-review --restart`. To stop without opening another session, use `python3 tools/compare.py --stop`. These controls also recognize the original `profile.py` runner. They verify the process, repository and start time before signaling it; an unrelated process or reused PID is not killed. Old runner versions without an ownership receipt must be stopped with Control-C in their original terminal.

After installing once, you can also open **Confetti Benchmarks** directly on the phone to enter Visual Review—no Mac command needed. Automated measurement mode is entered only by the runner's launch arguments.

Visual Review defaults to the five 720-particle renderers, starting with **Native particles**. To include other experiments, use `--suite all` or `--only emitter-720,paper-720,adaptive-keyframes`. Use **Replay**, **Next**, or the experiment picker. Changing the selection immediately replays it, and **Stop animation** cancels the current burst. Replay uses the same seed for PaperConfetti's particle population and trajectories. The native emitters have their own internal randomization. The three observation buttons save **Smooth**, **Launch hitch**, or **Flight hitch** with the scenario, seed and timestamp. They are subjective observations, kept separate from Instruments metrics. A tap counter also confirms touches reach the content beneath the overlay.

Copy those observations back to the Mac afterward:

```sh
python3 tools/compare.py --collect-visual
```

Visual review deliberately has no Instruments attached. Do not judge the precise motion from simulator screenshots alone; view the animation on the phone. If making a video, do it in a separate visual-review session so recording overhead cannot contaminate the timing trial.

## What is actually being drawn?

PaperConfetti does **not** ship SVGs or load PNG files for particles. [`ConfettiTextures.swift`](../Sources/PaperConfetti/ConfettiTextures.swift) draws small Core Graphics paths into in-memory `CGImage` textures once, then shares them through a bounded cache. The image type is raster, but there is no image-file decoding per burst and no vector tessellation on every frame.

The paths are already compact: a star has ten corners; squiggles/loops use two or three cubic Bézier segments; the sparkle uses four. Blindly simplifying those paths is unlikely to improve steady-state playback. It could reduce an initial rasterization cost, but may damage the silhouette; the cold-versus-prewarmed experiment isolates that phase first.

At 10 points and a 3× screen, square shapes are 30×30 pixels; wide ribbons reach 66 pixels across. The thirteen-shape, three-color texture set measured **198,432 bytes** of CPU image backing in the simulator texture audit. The shipping renderer requests all sixteen shape types, totaling **232,992 bytes** with this palette/size. These are image byte counts, **not total GPU memory**. Per-particle size varies from 8–12 points, so the textures are not grossly oversized and can actually be enlarged slightly. Every result includes actual dimensions, bytes per row × height, and the fraction of pixels with nonzero alpha.

The old classic/fancy comparison changed several variables at once: three versus thirteen shapes, 7 versus 10 points, different aspect ratios, and uniform versus shape-dependent falling speeds. A 10-point, 2.2-wide ribbon covers a larger rectangular area than a 7-point piece even when much of that rectangle is transparent. Transparent holes do not automatically mean fewer fragment/blending operations. Texture downsampling changes texture storage/sampling cost; it does **not** reduce the on-screen area being composited.

The shipping renderer creates one layer and one group of four animations per particle. At 720 particles that is 720 layers, 3,600 animation objects including the groups, and 70,560 position/opacity sample values. CPU setup, the later render-server preparation, GPU blending, and motion approximation are distinct possible causes. Low process CPU by itself does not rule out a hitch elsewhere in the render loop.

## Comparison matrix

The versioned source of truth is [`Benchmarks/Study.json`](../Benchmarks/Study.json), bundled into the app and read by the Mac runner. The test suite verifies the intended factor pairs.

| Suite | Comparison | What it isolates |
| --- | --- | --- |
| renderers | Shipping PaperConfetti, adjustable CALayers, CAEmitterLayer, SpriteKit, SpriteKit atlas; 180 and 720 requested particles | Renderer architecture and atlas tradeoffs |
| factors | 10pt vs 7pt, same shapes/motion/count | Visible particle footprint |
| factors | Device-resolution vs 4× vs 2× vs 1× images, same point dimensions | Texture resolution/storage; inspect edge quality |
| factors | Festive vs classic at 10pt with uniform speed in both | Shape population, with the old size/speed confounds removed |
| factors | Padded linear vs padded trilinear textures | Minification filtering / thin-edge shimmer; same source silhouette and point bounds |
| factors | Uniform speed vs per-shape speed | Residence time / simultaneous visible population |
| factors | 48 vs 24 vs 12 uniform motion intervals | Setup/commit size versus trajectory fidelity |
| factors | Adaptive motion sampling | Extra samples near fast curvature/fades instead of uniform spacing |
| factors | Tumble off; flutter off; static host | Rotation/trajectory and keyboard/scroll interactions, independently |
| factors | Prewarmed versus fresh-process cold textures | First-use texture rasterization/cache effects |
| factors | Opaque rectangles with each shape's original bounds | Alpha silhouette diagnostic; deliberately different appearance |
| shapes | Each of the sixteen silhouettes alone, 720 particles | Per-shape footprint and transparency; same count/nominal size |

All five-cannon trials use 0.1-second launch spacing, the same palette, screen positions, nominal radius/fall and seed per round. Scoring a renderer requires looking at both its hitch measurements and its appearance.

**Native-emitter motion update, October 28:** CAEmitterLayer now moves small cohorts (at most four same-shape/color particles per cannon) along adaptively sampled PaperConfetti position and opacity curves. That preserves the upward launch, deceleration, shape-specific descent and late fade, instead of the old constant-gravity arc that accelerated offscreen and kept spreading sideways. Native particles add small horizontal drift and independent 2D spin; their vertical movement follows the shared path. Each cohort uses one native emitter and two shared animations, rather than a layer and four animations per individual particle. Only public Core Animation APIs are used.

This is still an approximation: particles in a cohort share launch timing/path; there is no individual 3D tumble. CAEmitterLayer's rate × duration remains a requested-count estimate. The path audit now includes cohort paths, excluding native drift/spin. Rows identify the new implementation as `native_motion_model: shared-flight-v2`. Earlier emitter results measured `ballistic-v1` motion and **must not be used as performance evidence for the new path**. Remeasure on the phone after choosing the appearance.

SpriteKit intentionally retains its ballistic baseline; it can leave the viewport sooner and does not reproduce the same flight, hover, fade or 3D tumble. It specifies finite `numParticlesToEmit`, but its internal particle randomization is not publicly seedable. These comparisons test plausible alternative appearances, not mathematically identical workloads. The adjustable CALayer variants retain individual original physics.

## A second source of apparent stutter: motion sampling

The shipping implementation samples the entire flight at 49 uniformly spaced times. Its launch accelerates/settles much faster than the later descent. The simulator's deterministic audit found about **34 points maximum position approximation error** for the 720-particle fixture when comparing the interpolated path with the underlying physics. This is a numerical trajectory diagnostic, not evidence of a dropped frame or proof of the user's reported cause.

Each trial's audit now evaluates position and opacity approximation at 961 times per particle, after the timed interval. Reduced sampling can lower setup cost but worsen this error. `adaptive-keyframes` anchors the launch, initial fade-in, start of fade-out and end; it recursively adds samples where curvature or opacity changes warrant them. Recursion is bounded. This candidate may cost more to prepare, and is not promoted to the package without device and visual comparison. The report retains sample counts and measured errors rather than assuming the tolerance was achieved.

## Measurements and reliability

- **Animation Hitches pass:** actual process-attributed hitch count, unioned hitch duration, longest clipped hitch, and first-500ms versus subsequent-flight hitch duration. Exported `hitches` rows are joined to complete `Renderer study` signpost intervals for the recorded PID. Missing/changing schemas, missing endpoints, duplicate or mismatched intervals produce **unavailable**, never an invented zero. Overlapping hitch durations are unioned and clipped to the trial window. This is not Apple's animation-active hitch time ratio: the 5.5-second trial includes settling time.
- **Time Profiler pass:** whole-process CPU time, synchronous setup time and the call stacks needed to explain expensive work. Setup ends after animation submission; it does not include Core Animation's later commit or render-server work. Native/adjustable renderers additionally split physics preparation and texture lookup. A preloaded SpriteKit atlas is prepared outside the trial; its memory cost still contributes to process footprint.
- **Allocations pass:** baseline/peak sampled/settled footprint across repeated natural completions and cancellations. Bounded framework caches are expected; inspect live allocations and the trend before calling an increase a leak.
- **Scheduling:** first callback and p95/p99 main-thread `CADisplayLink` intervals remain available. They are not rendered FPS and do not replace the hitch trace.
- **Correctness:** requested populations and cleanup are checked in the app; UI tests tap through each active overlay and scroll the content beneath it. Natural cleanup and explicit cancellation both run. All benchmark-only overlays return no hit-test target. The shipping library's existing Reduce Motion, cancellation and navigation tests still run.

No screenshot capture, texture audit, per-frame console logging, or host/device polling runs inside the measured interval. Texture and interpolation audits run afterward. The runner validates run identity, complete expected trial sets, foreground/thermal conditions and matching start receipts. Each report retains source hashes, the manifest, exact Xcode/revision and worktree state. Partial files are retained on failure. No automatic speed ranking is produced from simulator runs or missing trace data.

Open a `.trace` from the report in Instruments. Select a `Renderer study` interval in Points of Interest, then examine the Animation Hitches track and whether the expensive work is in app commit, render prepare or render execute. That distinction determines whether to reduce main-thread preparation, layer/animation count, or GPU work. If the report's hitch field is unavailable, inspect the trace and exporter logs; do not infer smoothness from CPU alone.

## Research findings and optimization order

1. **Keep cached, shared raster images.** Apple recommends assigning a shared image directly to layer contents. PaperConfetti already does this. Avoid switching to per-frame `CAShapeLayer` path drawing or enabling `shouldRasterize` on a constantly changing particle subtree without evidence; rasterization introduces a bitmap/cache tradeoff. Merely setting `isOpaque` does not remove the alpha channel of an assigned image. The opaque-proxy test uses genuinely opaque images. [Core Animation performance guidance](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/CoreAnimation_guide/ImprovingAnimationPerformance/ImprovingAnimationPerformance.html), [shouldRasterize](https://developer.apple.com/documentation/quartzcore/calayer/shouldrasterize).
2. **Measure outside the app process too.** Apple separates commit, render preparation and GPU execution. Hundreds of layers can cost render-server time even when application CPU is low. Masks, dynamic shadows and effects can add offscreen work; the study's particle views avoid them. This motivates real hitch attribution, not an FPS label on a display-link callback. [Render-phase hitches](https://developer.apple.com/videos/play/tech-talks/10857/), [render loop and hitch measurement](https://developer.apple.com/videos/play/tech-talks/10855/).
3. **Native emitter experiments:** keep lifetimes and emissions bounded, remove completed emitters, avoid per-particle SpriteKit actions, and avoid reconfiguring properties every frame. The SpriteKit prototype uses one finite emitter per population group and only launch scheduling actions. The revised CAEmitterLayer prototype adds two shared keyframe animations per small cohort; its cost must be remeasured. CAEmitterLayer uses its default unordered source-over mode; additive mode would change our paper colors and appearance. [SpriteKit emitter optimization](https://developer.apple.com/documentation/spritekit/optimizing-emitter-node-performance), [CAEmitterLayer unordered mode](https://developer.apple.com/documentation/quartzcore/caemitterlayerrendermode/unordered?language=objc).
4. **Atlas test, not an assumption:** SpriteKit can combine compatible textures into fewer draw calls; common z positions and `ignoresSiblingOrder` help batching. Preloading and reusing textures avoids first-use stalls. The atlas variant keeps the same particle population and dimensions; the plain version is its direct comparison. Exact batching of emitters must still be verified in Instruments. [Node drawing performance](https://developer.apple.com/documentation/spritekit/maximizing-node-drawing-performance), [texture performance](https://developer.apple.com/documentation/spritekit/maximizing-texture-performance).
5. **Canvas remains a valid alternative, not a guaranteed upgrade.** Apple's particle example resolves an image once and shares it inside a Canvas; that reduces SwiftUI view overhead. A TimelineView/Canvas solution still updates and draws the population each frame. Our previous simulator-only Canvas prototype used more process CPU, which does not prove it would hitch more on this phone. [Apple Canvas particle example](https://developer.apple.com/videos/play/wwdc2021/10021/). [Vortex](https://github.com/twostraws/Vortex) is a relevant open-source particle library to inspect, but is not a measured competitor in this study.
6. **Separate aliasing from missed frames.** Thin squiggles/rings can shimmer as rotation makes their strokes smaller than a pixel, even with timely frames. This is a hypothesis to check visually, not a diagnosed cause. The 4× texture and no-tumble trials help investigate it. `padded-textures` and `trilinear-textures` use identical power-of-two backing images and preserve the original visible point bounds; only minification filtering changes. Apple notes some renderers may ignore trilinear filtering or impose power-of-two restrictions, so selecting it is not proof that mipmaps were used. Inspect appearance and device traces. [Core Animation scaling filters](https://developer.apple.com/documentation/quartzcore/scaling-filters). SpriteKit mipmaps are another future test; its documented memory cost is usually about one-third extra and its dimensions must be powers of two. [SpriteKit mipmaps](https://developer.apple.com/documentation/spritekit/sktexture/usesmipmaps).
7. **Metal is the next escalation if native systems cannot preserve the look smoothly.** Instanced quads with shared textures/atlas and per-particle data could retain our exact physics while avoiding hundreds of Core Animation layers. Apple's instancing discussion explains the draw-call reduction opportunity. It adds shader, lifecycle, accessibility and GPU resource-management work; we should justify it with render-server/GPU evidence first. No custom Metal renderer or performance claim is included here. [Metal instanced rendering](https://developer.apple.com/videos/play/wwdc2021/10286/).

Choose an optimization only if it improves repeated **physical** hitch measurements and keeps the visual quality/input behavior. First investigate launch setup versus later flight. Then compare samples, texture sizes and shape cases against their matched baseline. A lower-resolution texture is acceptable only if rings/stars/squiggles stay crisp on the phone; removing shapes, shortening visible flight, or lowering refresh rate is not a free performance win.

## Local validation

```sh
python3 -m unittest discover -s tools/tests -v
python3 tools/compare.py --simulator-smoke
python3 tools/validate.py
```

These checks validate automation, renderer presence/cleanup, parser safety and UI behavior. Simulator results do not establish physical GPU performance. CI runs the original and new smoke protocols on its existing Xcode matrix. Runtime package dependencies and public APIs are unchanged.
