# PaperConfetti contributor guidance

- Work on `dev`. Preserve the existing history. Merge into `main` when integration/release is requested; the shared `mergemain` helper expects `dev`. Use `/usr/bin/git` for authenticated remote operations.
- This is a standalone Swift package. It must build without Wordie, Firebase, accounts, credentials or any sibling checkout. The example uses a relative dependency on this repository's root.
- Wordie and Disney Trivia are reference repositories during package work. Do not edit or deploy them, their Git state or services as part of this task.
- Keep the controller method API simple: `.confettiOverlay(controller)` plus `controller.pop()`. Preserve deterministic physics, bounded particle budgets, Reduce Motion, scene cancellation and touch pass-through.
- Standard Debug/Release configurations only. The example's marketing/build versions live at project level; do not change existing values without explicit owner instruction. This example has no App Store deployment workflow. Package release tags require a publication request.
- Run `swift test` and `python3 tools/validate.py` for relevant package/renderer changes. Use the dedicated PaperConfetti Example simulator; never erase or use a personal simulator. Inspect screenshots for visual changes.
- CI validates macOS physics and iOS package/example tests. Keep token permissions read-only, pin Actions, preserve the MIT license and original ConfettiSwiftUI notice. No runtime dependencies or analytics.
- Generated builds, logs, xcresults and captures belong under ignored `.artifacts/`. Commit intended source/doc/test files; preserve unrelated owner work.

- Physical profiling: use `python3 tools/profile.py` and `Documentation/PROFILING.md`. Keep the pinned ConfettiSwiftUI dependency benchmark-only. Never report simulator callback timings as device frame delivery; preserve incomplete results and distinguish instrument passes. The dedicated simulator smoke command and Python runner tests are suitable for CI.

- Renderer experiments live in `Benchmarks/App/Study*.swift` and `Benchmarks/Study.json`, with `tools/compare.py` and `Documentation/RENDERER_STUDY.md`. Keep them benchmark-only until physical evidence supports changing the library. Every new renderer must preserve input pass-through and bounded cleanup. Never equate callback timing, simulator results or missing trace exports with smooth physical frame delivery. Keep the original ConfettiSwiftUI protocol reproducible.
