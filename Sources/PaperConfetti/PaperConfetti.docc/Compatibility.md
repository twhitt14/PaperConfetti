# Compatibility and integration contract

Build against the stable public API while retaining iOS 16 support.

## Versioning

PaperConfetti 1.x follows [Semantic Versioning](https://semver.org/). Supported
public types, member names, parameter labels, and the documented lifecycle contract
remain source compatible within 1.x. Compatible additions use a minor release;
compatible fixes use a patch. Published tags are immutable. The iOS 16 minimum and
Swift tools 5.9 package declaration are retained for 1.x; this source package does
not promise a precompiled binary ABI.

The supported surface is available with ordinary `import PaperConfetti`. Testing
SPI, renderer/texture internals, benchmark apps, cache identity strings, and exact
seeded flight samples aren't extension points. A seed reproduces an event within
the same package version and inputs; bug fixes may change samples between versions.
Performance also depends on the host app, device, OS, and workload.

## Concurrency and ownership

``ConfettiConfiguration``, ``ConfettiMotion``, ``ConfettiAngle``, ``ConfettiEmitter``,
and ``ConfettiShape`` are sendable values. Controllers, UIKit hosts, and event
callbacks are main-actor isolated. Keep SwiftUI controllers in `@StateObject`;
this works on iOS 16 without requiring the newer Observation framework.

Use one controller per stable overlay. Reusing a controller simultaneously in
multiple hosts is unsupported; use separate controllers for overlapping effects.
Host removal, an inactive scene, or a Reduce Motion change cancels current motion.
Returning to the scene never replays a cancelled event. See <doc:Configuration>
for input handling and outcomes, and <doc:UIKitIntegration> for UIKit ownership.

## Accessibility and privacy

Both UI hosts pass all input through and keep decoration out of the accessibility
tree. The app should present accessible success text or appropriate haptics;
confetti must not be the only indication that an operation succeeded.

The library has no network requests, analytics, persistent storage, or collected
identifiers. Its resource bundle includes the MIT attribution and
`PrivacyInfo.xcprivacy`, declaring no tracking, collected data, or required-reason
API use. The manifest describes this library, not the integrating app. The source
review checked Apple's current [required-reason API list](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype);
animation uses Core Animation timing and does not call the listed boot-time APIs.

## Documentation and validation

Public comments follow Swift's [API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/)
and Apple's [symbol documentation guidance](https://developer.apple.com/documentation/xcode/writing-symbol-documentation-in-your-source-files).
Summaries, parameters, units, bounds, errors, and outcomes appear in Quick Help
and DocC. The validation command checks documented public symbols, compiles complete
examples in strict Swift 6 mode targeting iOS 16, and treats DocC warnings as errors.
It also runs behavioral, rendering, lifecycle, and input tests.

An iOS 16 deployment-target compile does not establish an iOS 16 runtime result.
Simulator and CI checks aren't device frame-rate, energy, or GPU measurements.
The repository's performance tables retain their measured release/device labels.
