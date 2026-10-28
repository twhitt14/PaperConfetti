# Parabolic flight screening — October 28, 2026

Benchmark-only `parabolic-v4-individual-timing`, tested on an iPhone 18 Pro Max (`iPhone19,3`), iOS 27.0.1, 120 Hz maximum. Release build, Xcode 27.2 RC. This is a limited development screen, not a published capacity guarantee or a change to the released library.

## 720 pieces, Animation Hitches attached

Five cannons, thirteen festive shapes, 10-point nominal size, the same three colors and per-round seeds. One warm-up and two measured repetitions per case. Values are warm medians over each roughly 5.5-second trial. CPU is cumulative app-process CPU time, not milliseconds per frame. Setup ends at animation submission; later rendering work is separate. These renderers have slightly different birth/orientation behavior and do not produce identical pixels.

| Candidate | App CPU ms | Setup ms | Settled MiB | Attributed hitch ms |
| --- | ---: | ---: | ---: | ---: |
| emitter-720 | 160.3 | 44.9 | 61.3 | 0.0 |
| emitter-3d-720 | 162.5 | 52.7 | 61.6 | 0.0 |
| sprite-720 | 1545.0 | 10.9 | 113.1 | 0.0 |
| sprite-3d-720 | 1903.7 | 5.0 | 113.1 | Unavailable |
| sprite-atlas-720 | 1888.9 | 4.9 | 110.8 | Unavailable |
| sprite-atlas-3d-720 | 1822.4 | 4.6 | 112.0 | Unavailable |

The native flat/3D trials and flat SpriteKit had complete marker/hitch exports. The remaining SpriteKit recordings lost trial markers, so their hitch fields stay unavailable. No conclusion about hitch-free playback is drawn from those gaps. Instruments itself can affect renderer cost; these values are screening evidence from one phone/session, not a universal ranking. GPU cost and battery usage are not inferred from app CPU.

Local receipt: `.artifacts/study-20261028T165336Z-bb5c06/report.html`. The larger 24-case run was intentionally stopped between recordings after these six completed cases; its top-level receipt therefore says interrupted. All six app payloads and trace/export evidence were preserved. No 1,440/2,880-piece result is implied by that receipt.

## 5,760 pieces, Instruments detached

One warm-up and **one** measured repetition per variant, rotating order. This deliberately omits Instruments because the SpriteKit capture was losing markers and producing very large traces. Do not compare these CPU totals directly with the instrumented 720-piece table. Hitch delivery is unmeasured; the callback column describes main-thread scheduling, **not FPS**. Thermal state was nominal in all retained measured trials.

| Candidate | App CPU ms | Setup ms | Callback p99 ms |
| --- | ---: | ---: | ---: |
| emitter-3d-5760 | 385.7 | 169.4 | 16.9 |
| emitter-5760 | 378.3 | 161.7 | 16.8 |
| sprite-3d-5760 | 2424.5 | 38.8 | 27.5 |
| sprite-5760 | 2378.4 | 41.9 | 30.9 |
| sprite-atlas-3d-5760 | 2386.3 | 31.5 | 27.4 |
| sprite-atlas-5760 | 2366.1 | 31.3 | 27.2 |

Every candidate submitted the requested population and passed bounded cleanup; SpriteKit additionally started all 5,760 pieces and produced scene updates. Native particle counts remain a rate-based request, not a public exact live-count query. These checks cannot establish that every piece reached a physical display frame. No renderer crashed in this screen.

Native particles retained steadier app callbacks, but their roughly 160–170ms setup at this extreme load is a real latency cost. SpriteKit showed larger callback delays. Neither result proves hitch-free rendering. This favors continuing visual/device review of native particles at the intended 720-piece load, rather than advertising 5,760 as a safe production budget.

Local app-only receipt: `.artifacts/flight-v4-upper-load/`. The full instrumented 24-case sweep (including intermediate counts, CPU and memory passes) remains available with `python3 tools/compare.py --suite stress`; it was **not completed** as part of this screen.

## What changed and what is still experimental

Each piece gets its own seeded rise duration and ±20% fall-duration variation. The two quadratic arcs meet at zero vertical velocity without a hold; the faster rise and gentler fall use different accelerations. In the deterministic motion fixture, time within five points of the peak decreased from 0.592 to 0.404 seconds. Flat and 3D modes share these equations.

Native particles now use one emitter layer per piece to preserve independent timing/tilt. SpriteKit uses a finite emitter under each independently moving transform node and a central analytic update loop. That CPU work, its scene graph and transparent drawing all matter. The extra SpriteKit app CPU here is a reason to continue investigating before choosing it as a public default. A future direct-sprite/instanced implementation could avoid maintaining a full emitter for every single piece, but has not been implemented or measured in this screen.

All candidates remain in the benchmark app. The published package's renderer, safety cap and public API remain unchanged. See [the study guide](RENDERER_STUDY.md) for repeatable commands, CPU/GPU distinctions and the proposed small advanced renderer override.

## Physical interaction verification

All nine benchmark UI tests passed on the connected iPhone, including real taps and scrolling through every renderer, repeated SpriteKit plain/atlas/3D replay and cancellation, seeded shuffle/replay, bounded cleanup, navigation and Reduce Motion. The full package/example suite, nine pure motion tests, 33 runner tests and the same nine benchmark UI tests also passed locally/on the simulator.
