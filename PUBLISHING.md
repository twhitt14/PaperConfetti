# First public release

The repository is a standard Git-hosted Swift package: `Package.swift` is at the
root, the product/module is `PaperConfetti`, and there are no runtime dependencies.
Publication needs a public Git remote and a semantic version tag; there is no
central package upload step. [Apple's publishing guide](https://developer.apple.com/documentation/xcode/publishing-a-swift-package-with-xcode).

## Before publishing 0.1.0

- [ ] Choose the public repository owner and confirm the `paper-confetti` name.
- [ ] Create/connect the intended GitHub remote and push `dev` to run CI. No remote
      was assumed or created during extraction. CI requires no secrets.
- [ ] Confirm both hosted CI jobs pass: macOS physics tests, iOS package tests,
      example interaction tests, Release simulator build and DocC.
- [ ] Run the example on physical 60 Hz and 120 Hz iPhones, including an older
      supported device/OS. Check rapid repeat/cancel, background/resume, Reduce
      Motion, scrolling during flight, memory cleanup and energy. Record actual
      Instruments results; do not relabel simulator timings as device performance.
- [ ] Review the MIT license and retained ConfettiSwiftUI notice. Confirm README
      installation URL and remove the unreleased status after a public URL exists.
- [ ] Review `CHANGELOG.md`, choose the exact release version and integrate `dev`
      into `main`. Preserve existing history; never retag a released version.
- [ ] Tag that reviewed commit `0.1.0`, push the tag, and wait for tag CI to pass.
- [ ] Create release notes from the changelog. Verify a fresh consumer resolves
      the tagged Git URL and can import `PaperConfetti`.
- [ ] Optionally submit the public repository to Swift Package Index. The package
      remains usable directly by Git URL without an index listing.

Publishing is a separate owner-requested action. This preparation does not create
an external repository, push code publicly, create a tag or change Wordie's shipped
dependency. After publication, Wordie can switch its local package reference to a
versioned Git dependency in a separate reviewed app change.

## CI configuration references (checked October 25, 2026)

- [GitHub's Swift workflow guidance](https://docs.github.com/en/actions/tutorials/build-and-test-code/swift)
- [macOS 15 runner image / Xcode 16.4](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-Readme.md)
- [macOS 26 runner image / Xcode 26.6](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-Readme.md)

The workflow pins action commits, uses read-only contents permission, cancels
superseded branch runs, bounds jobs to 25 minutes and retains test evidence for
seven days. It has no publishing or deployment credentials.
