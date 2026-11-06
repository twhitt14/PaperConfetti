# Migrating to 1.0

## From 0.4

The public method names and parameter labels are unchanged. `ConfettiConfiguration`
now conforms to `Sendable`; controllers and UI hosts remain main-actor isolated.
UIKit hosts can be loaded from storyboards. Colors retain color-space/pattern
identity, and source anchors follow a replacement controller even when the view
hasn't moved. These are corrections to existing behavior.

Change the dependency requirement to `from: "1.0.0"` to accept compatible 1.x
updates, or use an exact pin. Testing SPI and exact random trajectories are not
part of the [stable contract](../Sources/PaperConfetti/PaperConfetti.docc/Compatibility.md).

## From 0.3 and earlier

Version 0.4 intentionally refines the public API before 1.0.
iOS 16 and `@StateObject` remain supported. Plain `confetti.pop()` and
`.confettiOverlay(confetti)` integrations need no changes.

| Previous spelling | New spelling |
| --- | --- |
| `count`, `size`, `radius`, `fall` | `particleCount`, `particleSize`, `launchDistance`, `fallDistance` |
| `angle: 90`, `spread: 70` | `emissionAngle: .degrees(90)`, `spread: .degrees(70)` |
| `fallSpeedRange` | `fallSpeedMultiplierRange` |
| Manually divide `launchDuration` | `motion.launchSpeedMultiplier = 1.1` |
| `ConfettiEmitter(x:y:count:angle:spread:)` | `ConfettiEmitter(origin:particleCount:emissionAngle:spread:)` |
| `pop(ConfettiBurst(...), colors: ...)` | `pop(emitters:configuration:seed:completion:)` |
| Bool returned from `pop()` | `Void`; inspect `ConfettiOutcome` or lifecycle state |
| `ConfettiLayerView` | `ConfettiView`, with lifecycle/accessibility policy included |
| Manual button geometry preferences | `.confettiSource(id:controller:)` and `pop(fromSource:)` |

`ConfettiShape` is now a value type with the same named built-in members plus a
throwing `init(path:name:)`. Replace exhaustive switches with your own presentation
mapping or `shape.name`. Raw renderer, particle and texture types are not supported
public extension points; historical benchmarks access them through testing SPI.

New `drop()` showers and custom paths use the same native renderer, palettes,
flat/3D appearances and cancellation rules. One controller still plays one event
at a time. Multiple-emitter calls use each emitter's count, direction and delay;
configuration supplies shared paper and motion settings.
