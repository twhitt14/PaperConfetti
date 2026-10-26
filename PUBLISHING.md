# Release workflow

PaperConfetti is a Git-hosted Swift package at
`https://github.com/twhitt14/PaperConfetti.git`. Its product/module is
`PaperConfetti`; SwiftPM derives the dependency identity `paperconfetti` from
that URL. It has no runtime dependencies.

The repository is currently private. A version tag and GitHub release are usable
by authorized collaborators without changing visibility. Only make the repository
public when Trevor explicitly requests it. No package registry or App Store
upload is needed. [Apple's publishing guide](https://developer.apple.com/documentation/xcode/publishing-a-swift-package-with-xcode).

## Publish a version

1. Work on `dev`; inspect the worktree and preserve unrelated changes.
2. Review all tracked files and history for credentials, private app configuration,
   generated artifacts, licensing omissions and unpublished installation URLs.
   Preserve the MIT license and ConfettiSwiftUI notice in the resource bundle.
3. Update the changelog and installation examples for the requested version.
   Package tags are independent of the example app's central 0.1.0 (1) settings;
   do not change app versions just to publish a package.
4. Run relevant local validation and push `dev`. Require both hosted CI jobs to
   pass for the exact intended source: physics, iOS renderer/lifecycle, example
   UI interaction tests, Release builds and DocC.
5. Integrate `dev` into `main` with `mergemain`; confirm local/remote branches
   agree and the worktree is clean. Require the main CI run to pass.
6. Create an annotated semantic version tag such as `0.1.0` on that verified
   commit, then push the tag. Never move an already-published version tag.
7. Wait for tag CI to pass. Resolve that exact tagged Git URL from a fresh
   consumer and verify the product/module and bundled attribution build.
8. Publish GitHub release notes describing features, requirements, actual
   validation and limitations. Verify the release points to the intended tag.

CI pins action commits, has read-only contents permission, cancels superseded
branch runs, bounds each job to 25 minutes and retains evidence for seven days.
It never creates tags or releases and has no publishing credentials. Use existing
GitHub authentication for authorized releases; never put tokens in this repository.

## Device validation and public discoverability

Simulator and CI tests establish behavior and compatibility for the tested
runtimes. They do not establish physical-device GPU/FPS or energy performance.
Before making device-performance claims, profile representative 60 Hz and 120 Hz
iPhones and an older supported device/OS with Instruments. Check rapid repeat and
cancel, background/resume, Reduce Motion, touch-through scrolling and cleanup.
Record these as device results separately from simulator measurements.

After an explicitly authorized visibility change, update the private-access note
in README and optionally submit the public repository to Swift Package Index.
Wordie's package dependency is a separate app change; a PaperConfetti release
does not change or deploy Wordie or any other application.

## CI configuration references

- [GitHub's Swift workflow guidance](https://docs.github.com/en/actions/tutorials/build-and-test-code/swift)
- [macOS 15 runner image / Xcode 16.4](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-Readme.md)
- [macOS 26 runner image / Xcode 26.6](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-Readme.md)
