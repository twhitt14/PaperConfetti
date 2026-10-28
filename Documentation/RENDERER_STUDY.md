# Renderer and shape study

Updated for 0.2.0, October 28, 2026. Native particles are now the package default,
with flat and 3D appearances. Ordinary native cases call the actual public renderer;
the old clock remains only as a regression control. SpriteKit/atlas code and active
cases were removed after visual/performance review. The frozen `paper` case is the
0.1 renderer/physics, and `layers` remains a diagnostic. The current stress suite has
eight cases (two native appearances × four loads); Visual Review has five variants.
The production renderer also shares one protected initial birth window across
cannons, with delays applied to visible flight. This addresses later-cannon misses
observed on hosted simulator runs after the v5 first-cannon fix.
The original app-only and Instruments records below remain historical evidence,
with their tested revision and limitations. They are not measurements of every
subsequent package build.

This study extends the [physical profiling protocol](PROFILING.md).

## Run it

Connect and unlock your iPhone by USB, keep Low Power Mode and Reduce Motion off, and let the phone cool. Keep it connected until the Mac prints the final report—not just until the phone says the pass was saved. Use the same device, brightness, refresh-rate settings and charging conditions for repeat comparisons. Stop screen recording, debugger sessions and unrelated profiling tools.

From the PaperConfetti repository:

```sh
python3 tools/compare.py --suite all
```

That one command builds and installs the Release benchmark app, records the renderer, factor and individual-shape matrices, performs a memory endurance run, checks interactions, and writes a local HTML/JSON report under `.artifacts/study-…/`. It uses the same remembered signing team and exact-device safeguards as `profile.py`. Nothing is uploaded. The first build may require Xcode's usual device trust/signing approval.

The standard study is intentionally long: approximately 30 minutes of actual playback plus building, cooling and Instruments trace processing. The separate stress matrix adds eight cases. Historical SpriteKit traces could take several minutes to finalize and lose trial markers under capture load; those variants are no longer run. Allow substantially longer on a slow device/Mac; trace finalization previously took many minutes. Recordings are now split into small chunks, normally no more than four scenarios and three rounds per trace, so one large trace does not hold the entire study hostage. Each chunk saves independent results. The app waits for the complete, unique start receipt and keeps it in its Documents folder; deleting it while CoreDevice finishes the transfer can intermittently fail with “Failed to retrieve the file node.” These tiny receipts are intentional and do not trigger another run. If playback exceeds the generous collection budget, the study fails rather than accepting timing contaminated by early result collection; rerun the affected cases with `--trial-budget 15`. Do not run both profiling commands simultaneously.

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

The classic-shape protocol against **ConfettiSwiftUI 1.1.0** remains available. It now exercises the current native package; keep new measurements separate from archived 0.1 results:

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

Visual Review defaults to five alternatives, starting with **Native particles · 3D tilt**: native flat, adjustable/adaptive layers, and the frozen PaperConfetti 0.1 baseline. The **Particles** menu offers 180, 720, 1,440, 2,880 and 5,760 pieces for candidates; the original library baseline stops at 1,440 to respect its safety cap. To include other experiments, use `--suite all` or `--only emitter-3d-720,paper-720,adaptive-keyframes,emitter-720`. Use **Replay**, **Shuffle**, **Next**, or the experiment picker. Changing the selection immediately replays it; **Stop animation** cancels the burst. Replay and Next preserve the numbered mix for comparison. Shuffle advances to a fresh seeded mix, including different shape-specific base speeds, individual rise/fall timing, spins, paths and starting orientations. Automated measurements still use their fixed per-round seeds. Native emission counts/positions also use Core Animation's seeded randomization.

The three observation buttons save **Smooth**, **Launch hitch**, or **Flight hitch** with the actual scenario, mix and timestamp. They are subjective observations, kept separate from Instruments metrics. A tap counter confirms touches reach the content beneath the overlay.

Copy those observations back to the Mac afterward:

```sh
python3 tools/compare.py --collect-visual
```

Visual review deliberately has no Instruments attached. Do not judge the precise motion from simulator screenshots alone; view the animation on the phone. If making a video, do it in a separate visual-review session so recording overhead cannot contaminate the timing trial.

## What is actually being drawn?

PaperConfetti does **not** ship SVGs or load PNG files for particles. [`ConfettiTextures.swift`](../Sources/PaperConfetti/ConfettiTextures.swift) draws small Core Graphics paths into in-memory `CGImage` textures once, then shares them through a bounded cache. The image type is raster, but there is no image-file decoding per burst and no vector tessellation on every frame.

The paths are already compact: a star has ten corners; squiggles/loops use two or three cubic Bézier segments; the sparkle uses four. Blindly simplifying those paths is unlikely to improve steady-state playback. It could reduce an initial rasterization cost, but may damage the silhouette; the cold-versus-prewarmed experiment isolates that phase first.

At 10 points and a 3× screen, square shapes are 30×30 pixels; wide ribbons reach 66 pixels across. The thirteen-shape, three-color texture set measured **198,432 bytes** of CPU image backing in the simulator texture audit. The archived 0.1 renderer requested all sixteen shape types, totaling **232,992 bytes** with this palette/size. The native renderer only requests the selected silhouettes and caches eight padded starting orientations per shape/color; its backing cost is different. These are image byte counts, **not total GPU memory**. Per-particle size varies from 8–12 points, so the textures are not grossly oversized and can actually be enlarged slightly. Every result includes actual dimensions, bytes per row × height, and the fraction of pixels with nonzero alpha.

The old classic/fancy comparison changed several variables at once: three versus thirteen shapes, 7 versus 10 points, different aspect ratios, and uniform versus shape-dependent falling speeds. A 10-point, 2.2-wide ribbon covers a larger rectangular area than a 7-point piece even when much of that rectangle is transparent. Transparent holes do not automatically mean fewer fragment/blending operations. Texture downsampling changes texture storage/sampling cost; it does **not** reduce the on-screen area being composited.

The archived 0.1 renderer created one layer and one group of four animations per particle. At 720 particles that is 720 layers, 3,600 animation objects including the groups, and 70,560 position/opacity sample values. The native default instead submits one emitter/cell per requested piece, adaptive position/opacity tracks and optional X-axis tilt, under one frozen launch clock. CPU setup, the later render-server preparation, GPU blending, and motion approximation are distinct possible costs. Low process CPU by itself does not rule out a hitch elsewhere in the render loop.

## Comparison matrix

The versioned source of truth is [`Benchmarks/Study.json`](../Benchmarks/Study.json), bundled into the app and read by the Mac runner. The test suite verifies the intended factor pairs.

| Suite | Comparison | What it isolates |
| --- | --- | --- |
| renderers | Frozen PaperConfetti 0.1, adjustable CALayers, current native flat and 3D; 180 and 720 requested particles | Legacy layers versus the current native renderer |
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
| stress | Current native flat/3D at 720 / 1,440 / 2,880 / 5,760 pieces | Capacity, launch versus flight hitches; explicit opt-in |
| shapes | Each of the sixteen silhouettes alone, 720 particles | Per-shape footprint and transparency; same count/nominal size |

All five-cannon trials use 0.1-second launch spacing, the same palette, screen positions, nominal radius/fall and seed per round. Scoring a renderer requires looking at both its hitch measurements and its appearance.

## Promoted native model: parabolic flight with a soft edge

October 28, `parabolic-v5-soft-edge-individual-timing` retains v4's individual timing, feathers the blast boundary, and stages native emission before starting its clock. The released `paper` baseline still uses the original physics. Keep v5 measurements separate from v4 and earlier ballistic/shared/mixed-flight results.

Every piece keeps its independently seeded rise duration (roughly 0.30–0.775 seconds) and receives an independent ±20% descent-duration variation over its silhouette's base speed. The independent hash avoids tying fall speed directly to spin. Replay preserves the whole mix; Shuffle changes it. Shapes still influence the base descent, but exact copies no longer have to arrive/fall together, as requested in the latest review.

For normalized rise time `u`, height follows `2u - u²`; after the apex, normalized descent `v` follows `v²`. Position and vertical velocity meet continuously at the peak. There is no hold segment: vertical speed reaches zero at a single instant. The acceleration changes between phases, deliberately giving the pop a steeper arc than the fall. This is stylized piecewise ballistics, not a full air-drag simulation. In the seeded 720-piece numerical fixture, average time within five points of the apex fell from 0.592 to 0.404 seconds (32% less). That measures the motion model, not rendering performance.

The original outward-weighted reach distribution is preserved, then multiplied by a deterministic mean-one lognormal factor (`sigma = 0.24`). Independent Gaussian angular variation (4° standard deviation) feathers the cone's sides too. There is no new clamp at the old radius. In 115,200 seeded pieces, mean reach was 0.78291 × radius versus 0.78268 previously; 18.93% extended beyond the old boundary, with monotonically fewer pieces in successive 0.1-radius bins from 1.0 to 1.6. This removes the dense outer rim without simply enlarging the whole blast. Per-piece flight geometry is cached once, not recalculated in SpriteKit's frame loop. These are distribution checks, not frame-performance measurements.

**Native particles:** the default now uses one emitter layer and one finite cell per piece, retaining its exact individual timing, flat spin, appearance, and (optionally) X-axis tilt. This costs more layers than the earlier 521-group fixture and must earn its performance in new phone recordings. `emitter-shared-720` remains a separate diagnostic: at most three different shapes/colors share a nearby mean trajectory/tilt. It is not the default and does not satisfy fully independent timing.

Eight cached rotated bitmap poses per shape/color provide starting-angle variety. Their larger transparent canvases prevent clipping; the report separately lists backing bytes (not total GPU memory). Emission remains rate-based: 25 births/second over a 60ms window places the first birth inside it at 40ms and the next outside at 80ms. There is no public exact live count for CAEmitterLayer. Its public `spin` is scalar; independent tilt comes from the enclosing layer, with `preservesDepth=false`. No private behaviors or KVC keys are used.

### Missing native cannons: launch-window regression

The old native launch set an absolute start only 1/60 second ahead, then submitted thousands of emitters. Its 60ms birth window could already have elapsed when the render server activated the first cannon. Controlled simulator captures reproduced missing early cannons at 5,760 pieces; injecting a 150ms submission stall also reproduced it at 720. Keeping the same population and adding start headroom restored the missing cannons. This identifies a timing failure, not evidence of a fixed particle-count cap.

V5 submits the tree beneath one frozen parent clock. A real Core Animation marker completion gates the small clock-start transaction. The start includes nonblocking, count-scaled headroom: 33ms at 720, 144ms at 5,760, capped at 200ms. Staging alone with only 17ms lead still missed a cannon in the simulator, which is why the headroom remains. This is an empirically verified margin, not a public render-server readiness guarantee. Cleanup follows the actual scheduled start; cancellation invalidates the pending generation so a late callback cannot resurrect a stopped burst.

The report includes `native_arm_delay_ms` from `play` through the scheduled clock start, including setup, readiness and headroom. This is not first-visible-frame latency. `setup_ms` alone excludes the asynchronous portion. A trial whose clock never arms is rejected; native rate-based counts still require independent visual verification.

`NativeEmissionTests` includes actual screenshot checks: all five separated cannon columns over repeated flat/3D runs (including a 350ms injected stall), an old-clock negative control, and a 60 × 96 grid that checks all 5,760 separate particle positions. The pixel probes hold position/opacity and extend visibility so screenshot transfer delays cannot miss a short falling trail; the grid also fixes size and separate positions. These diagnostic edits leave the production birth timing intact; it does not measure fancy-shape FPS, and it is not an exact-count promise across every iOS/device. Diagnostic arguments (`--emission-probe`, `--emission-grid`, `--native-legacy-clock`, `--native-stall-ms=…`, `--native-lead-ms=…`, `--native-preroll-ms=…`) belong only to the benchmark and must not contaminate performance runs.

**Removed SpriteKit experiments:** plain/atlas and flat/tilted candidates shared an analytic scene-update model. They did not provide a compelling improvement in the physical review, so their code, dependencies and active scenarios were removed. Prior measurements remain in the historical result documents and Git history; SpriteKit is not a public renderer option.

## Mega stress test

```sh
python3 tools/compare.py --suite stress
```

This explicitly opts into eight cases: native flat and 3D variants at four loads from 720 to 5,760 pieces, always five cannons. It records timing/hitches, CPU and memory, then checks interactions. For a shorter first screen use `--suite stress --phase timing`. `--suite all` deliberately excludes stress. The stress trial budget is at least 15 seconds including untimed diagnostics; the measured window remains 5.5 seconds. Three rounds include warm-up and two measured repeats; repeat promising cases in reversed order before making a final capacity claim.

Current native stress cases generate the entire requested population through the public package. Some older layer diagnostics still assemble deterministic <=2,000-piece batches with separate seeds; those are not exact particle-for-particle high-load comparisons with native. The standard 180/720 cases use the matched seed and population. The package now caps native requests at 6,000; its old 0.1 benchmark fixture retains a 2,000-piece cap. Higher loads increase CPU setup, layer/node counts, transparent overdraw and memory; do not interpret lower frame-callback counts alone as a measured GPU limit.

For side-by-side visual review, use the normal `--visual-review` command and the **Particles** menu. Replay, Shuffle, Stop and the hitch-observation buttons remain available at every load. The original PaperConfetti baseline retains its existing smaller budget.

## A second source of apparent stutter: motion sampling

The archived 0.1 implementation sampled the entire flight at 49 uniformly spaced times. Its launch accelerates/settles much faster than the later descent. The simulator's deterministic audit found about **34 points maximum position approximation error** for the 720-particle fixture when comparing the interpolated path with the underlying physics. This is a numerical trajectory diagnostic, not evidence of a dropped frame or proof of the user's reported cause.

Each trial's audit now evaluates position and opacity approximation at 961 times per particle, after the timed interval. Reduced sampling can lower setup cost but worsen this error. `adaptive-keyframes` anchors the launch, initial fade-in, start of fade-out and end; it recursively adds samples where curvature or opacity changes warrant them. Recursion is bounded. The native default now uses this bounded adaptive approach after device and visual review. The diagnostic adjustable-layer case remains available to isolate sampling cost from the renderer architecture. The report retains sample counts and measured errors rather than assuming the tolerance was achieved.

## Measurements and reliability

- **Animation Hitches pass:** actual process-attributed hitch count, unioned hitch duration, longest clipped hitch, and first-500ms versus subsequent-flight hitch duration. Exported `hitches` rows are joined to complete `Renderer study` signpost intervals for the recorded PID. Missing/changing schemas, missing endpoints, duplicate or mismatched intervals produce **unavailable**, never an invented zero. Overlapping hitch durations are unioned and clipped to the trial window. This is not Apple's animation-active hitch time ratio: the 5.5-second trial includes settling time.
- **Time Profiler pass:** whole-process CPU time, synchronous setup time and the call stacks needed to explain expensive work. Setup ends after animation submission; it does not include Core Animation's later commit or render-server work. Native/adjustable renderers additionally split physics preparation and texture lookup.
- **Allocations pass:** baseline/peak sampled/settled footprint across repeated natural completions and cancellations. Bounded framework caches are expected; inspect live allocations and the trend before calling an increase a leak.
- **Scheduling:** first callback and p95/p99 main-thread `CADisplayLink` intervals remain available. They are not rendered FPS and do not replace the hitch trace.
- **Correctness:** requested populations and cleanup are checked in the app; UI tests tap through each active overlay and scroll the content beneath it. Natural cleanup and explicit cancellation both run. All benchmark-only overlays return no hit-test target. The shipping library's existing Reduce Motion, cancellation and navigation tests still run.

No screenshot capture, texture audit, per-frame console logging, or host/device polling runs inside the measured interval. Texture and interpolation audits run afterward. The runner validates run identity, complete expected trial sets, foreground/thermal conditions and matching start receipts. Each report retains source hashes, the manifest, exact Xcode/revision and worktree state. Partial files are retained on failure. No automatic speed ranking is produced from simulator runs or missing trace data.

Open a `.trace` from the report in Instruments. Select a `Renderer study` interval in Points of Interest, then examine the Animation Hitches track and whether the expensive work is in app commit, render prepare or render execute. That distinction determines whether to reduce main-thread preparation, layer/animation count, or GPU work. If the report's hitch field is unavailable, inspect the trace and exporter logs; do not infer smoothness from CPU alone.

## Research findings and optimization order

1. **Keep cached, shared raster images.** Apple recommends assigning a shared image directly to layer contents. PaperConfetti already does this. Avoid switching to per-frame `CAShapeLayer` path drawing or enabling `shouldRasterize` on a constantly changing particle subtree without evidence; rasterization introduces a bitmap/cache tradeoff. Merely setting `isOpaque` does not remove the alpha channel of an assigned image. The opaque-proxy test uses genuinely opaque images. [Core Animation performance guidance](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/CoreAnimation_guide/ImprovingAnimationPerformance/ImprovingAnimationPerformance.html), [shouldRasterize](https://developer.apple.com/documentation/quartzcore/calayer/shouldrasterize).
2. **Measure outside the app process too.** Apple separates commit, render preparation and GPU execution. Hundreds of layers can cost render-server time even when application CPU is low. Masks, dynamic shadows and effects can add offscreen work; the study's particle views avoid them. This motivates real hitch attribution, not an FPS label on a display-link callback. [Render-phase hitches](https://developer.apple.com/videos/play/tech-talks/10857/), [render loop and hitch measurement](https://developer.apple.com/videos/play/tech-talks/10855/).
3. **Native emitter experiments:** keep lifetimes and emissions bounded, remove completed emitters, avoid per-particle SpriteKit actions, and avoid reconfiguring properties every frame. The SpriteKit candidate uses one finite emitter per piece and a central analytic update loop, without per-particle SKActions. Native candidates submit position/fade tracks and optional tilt once per piece; their cost must be remeasured. CAEmitterLayer uses its default unordered source-over mode; additive mode would change our paper colors and appearance. [SpriteKit emitter optimization](https://developer.apple.com/documentation/spritekit/optimizing-emitter-node-performance), [CAEmitterLayer unordered mode](https://developer.apple.com/documentation/quartzcore/caemitterlayerrendermode/unordered?language=objc).
4. **Atlas test, not an assumption:** SpriteKit can combine compatible textures into fewer draw calls; common z positions and `ignoresSiblingOrder` help batching. Preloading and reusing textures avoids first-use stalls. The atlas variant keeps the same particle population and dimensions; the plain version is its direct comparison. Exact batching of emitters must still be verified in Instruments. [Node drawing performance](https://developer.apple.com/documentation/spritekit/maximizing-node-drawing-performance), [texture performance](https://developer.apple.com/documentation/spritekit/maximizing-texture-performance).
5. **Canvas remains a valid alternative, not a guaranteed upgrade.** Apple's particle example resolves an image once and shares it inside a Canvas; that reduces SwiftUI view overhead. A TimelineView/Canvas solution still updates and draws the population each frame. Our previous simulator-only Canvas prototype used more process CPU, which does not prove it would hitch more on this phone. [Apple Canvas particle example](https://developer.apple.com/videos/play/wwdc2021/10021/). [Vortex](https://github.com/twostraws/Vortex) is a relevant open-source particle library to inspect, but is not a measured competitor in this study.
6. **Separate aliasing from missed frames.** Thin squiggles/rings can shimmer as rotation makes their strokes smaller than a pixel, even with timely frames. This is a hypothesis to check visually, not a diagnosed cause. The 4× texture and no-tumble trials help investigate it. `padded-textures` and `trilinear-textures` use identical power-of-two backing images and preserve the original visible point bounds; only minification filtering changes. Apple notes some renderers may ignore trilinear filtering or impose power-of-two restrictions, so selecting it is not proof that mipmaps were used. Inspect appearance and device traces. [Core Animation scaling filters](https://developer.apple.com/documentation/quartzcore/scaling-filters). SpriteKit mipmaps are another future test; its documented memory cost is usually about one-third extra and its dimensions must be powers of two. [SpriteKit mipmaps](https://developer.apple.com/documentation/spritekit/sktexture/usesmipmaps).
7. **Metal is the next escalation if native systems cannot preserve the look smoothly.** Instanced quads with shared textures/atlas and per-particle data could retain our exact physics while avoiding hundreds of Core Animation layers. Apple's instancing discussion explains the draw-call reduction opportunity. It adds shader, lifecycle, accessibility and GPU resource-management work; we should justify it with render-server/GPU evidence first. No custom Metal renderer or performance claim is included here. [Metal instanced rendering](https://developer.apple.com/videos/play/wwdc2021/10286/).

Choose an optimization only if it improves repeated **physical** hitch measurements and keeps the visual quality/input behavior. First investigate launch setup versus later flight. Then compare samples, texture sizes and shape cases against their matched baseline. A lower-resolution texture is acceptable only if rings/stars/squiggles stay crisp on the phone; removing shapes, shortening visible flight, or lowering refresh rate is not a free performance win.

## Local validation

```sh
swift test --package-path Benchmarks
python3 -m unittest discover -s tools/tests -v
python3 tools/compare.py --simulator-smoke
python3 tools/validate.py
```

These checks validate automation, renderer presence/cleanup, parser safety and UI behavior. Simulator results do not establish physical GPU performance. CI runs the original and new smoke protocols on its existing Xcode matrix. The package remains dependency-free. Version 0.2 adds the flat/3D appearance choice while retaining the existing pop API.


Earlier v3 native-variety verification (before the v4 flight changes): five pure planning tests passed (population preservation, appearance diversity, seeded reproducibility, bounded trajectory deviation, empty/single cases). The full package/example validation passed, and the renderer smoke run covered control plus all six renderer variants. Eight benchmark UI tests passed, including real taps/scrolling through both native overlays, cancellation/replay, fresh mixes and cleanup. Simulator screenshots/video confirm visible mixed flat and edge-on particles. A separate five-circle diagnostic visibly emitted five pieces, guarding against the short-window no-emission failure; this does not establish an exact-count guarantee on every OS/device. The 3× native pose cache used 312 images / 4,154,880 CPU backing bytes. Physical smoothness is still unmeasured for these new variants.

## Public API decision

Version 0.2 uses one native renderer. Appearance is independent: `.threeDimensional` is the default, with `.flat` for a planar look. Existing `pop()` calls continue to work. SpriteKit was removed; the frozen 0.1 and adjustable-layer implementations remain only for benchmark comparisons. We will add a public renderer override only if future measurements establish a concrete benefit.

Different apps can favor different renderers. Core Animation uses graphics hardware but has app-side setup/commit and render-server costs. SpriteKit draws through Metal; the scene graph and our analytic update loop still consume CPU. Transparency/overdraw and texture sampling consume GPU resources. A CPU-heavy app and a GPU-heavy game can therefore favor different tradeoffs, and thermal state/hardware change the result. It is incorrect to say that the CPU does everything, or that native particles are free of CPU work. Atlas batching is an opportunity, not an automatic speed guarantee.

References: [Core Animation clock control](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/CoreAnimation_guide/AdvancedAnimationTricks/AdvancedAnimationTricks.html), [native birth rates](https://developer.apple.com/documentation/quartzcore/caemittercell/birthrate), [Core Animation](https://developer.apple.com/documentation/quartzcore), [hitch phases](https://developer.apple.com/documentation/xcode/understanding-hitches-in-your-app), [SpriteKit drawing performance](https://developer.apple.com/documentation/spritekit/maximizing-node-drawing-performance), [transparent scenes](https://developer.apple.com/documentation/spritekit/creating-a-scene-with-a-transparent-background), [particle targetNode](https://developer.apple.com/documentation/spritekit/skemitternode/targetnode), [SKTransformNode](https://developer.apple.com/documentation/spritekit/sktransformnode).


V4 local verification: nine pure motion/planning tests and 33 runner/parser tests passed. Full package/example validation passed (macOS tests, Release, iOS tests, example UI tests and DocC). Nine benchmark UI tests passed, covering all eight renderer variants, real taps/scrolling, repeated SpriteKit replay/atlas/3D cancellation, shuffle and cleanup. Three captured SpriteKit sequences (plain flat, plain 3D, atlas 3D) retained the static underlying title throughout 226–227 sampled frames per sequence; no full-surface flash was detected in those captures. This is bounded simulator evidence, not a guarantee about every device/OS.

Physical v4 screening is recorded separately in [FLIGHT_V4_RESULTS.md](FLIGHT_V4_RESULTS.md): six 720-piece instrumented candidates plus a 5,760-piece app-only upper-load check. Missing SpriteKit trace markers remain unavailable; the full intermediate-load matrix was not completed.


## V5 verification: emission timing and soft boundary

October 28, 2026, Xcode 27.2 RC. On the dedicated iPhone 18 Pro simulator (iOS 27.2), all **12** benchmark UI tests passed, including the three new actual-pixel emission checks. Six flat/3D replays showed all five cannons; the separate grid detected all 5,760 occupied slots. The old-clock control reproduced a missed first cannon under a 150ms submission stall. Normal 720/5,760 fancy-shape video captures show the softened boundary and clean settling. Simulator evidence does not establish a universal device capacity or hitch rate.

The connected iPhone 18 Pro Max (iOS 27.0.1) completed three rounds of each native flat/3D case at 720 and 5,760 pieces: one warm-up plus two measured repetitions. All clock-start and cleanup checks passed. This was an **app-only** screen without Instruments, not a frame-hitch measurement. Warm medians:

| Candidate | Synchronous setup | Scheduled clock start after play | Whole-trial CPU |
| --- | ---: | ---: | ---: |
| Native flat, 720 | 30.0ms | 95.4ms | 119.4ms |
| Native 3D, 720 | 32.7ms | 104.9ms | 113.2ms |
| Native flat, 5,760 | 109.4ms | 366.7ms | 327.1ms |
| Native 3D, 5,760 | 109.0ms | 381.5ms | 343.8ms |

Clock start is not first-visible-frame latency; it includes asynchronous readiness and start headroom. These measurements must not be compared directly with v4's instrumented 720-piece results. After the owner unlocked the iPhone, all three physical screenshot regressions passed: six repeated flat/3D bursts showed all five cannons (including a 350ms injected submission delay), the grid detected every one of the 5,760 separate particle positions, and the old-clock negative control reproduced the missing first cannon with a 150ms delay. Two earlier attempts failed to initialize UI automation and are retained as infrastructure failures, not passing tests. This closes the physical emission check for this device/OS; the diagnostic grid is not a guarantee of exact rate-based counts on all hardware or a measurement of fancy-shape frame delivery.

Ten numerical motion/planning tests, 34 Python runner/parser tests, and the full package/example validation (macOS/iOS tests, Release builds, example UI and DocC) passed. All eight renderer overlays still passed real tap/scroll checks in the simulator. Generated evidence remains ignored under `.artifacts/FlightV5AllSimulatorTests.xcresult`, `.artifacts/flight-v5-emission/`, `.artifacts/flight-v5-visual/`, and `.artifacts/flight-v5-device-screen/`, and `.artifacts/FlightV5DeviceEmissionConfirmed.xcresult` (physical pixel tests). These pre-promotion results informed the 0.2.0 native renderer promotion. Fresh production-renderer validation is recorded in VALIDATION.md.
