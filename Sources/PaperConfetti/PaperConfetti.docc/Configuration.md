# Configuring paper and flight

Choose a small starting effect, then customize the settings your interface needs.

## One configuration, two event types

``ConfettiConfiguration`` describes the palette, silhouettes, motion, and appearance.
Single-cannon `pop()` and `drop()` use its particle count. A multi-cannon request
instead takes each ``ConfettiEmitter``'s origin, count, angle, spread, and delay;
the remaining configuration is shared.

All distances are in the host's local points. Zero degrees points right, 90 points
up. Spread is the full fan width. Launch distance is nominal: the softened outer
tail can travel farther. A shower starts above the top edge and descends at least
the host height. Its `duration` controls emission, not the entire effect.

## Input limits

| Setting | Supported behavior |
| --- | --- |
| Colors | First 16; an empty palette emits nothing |
| Shapes | First 32 distinct geometries; an empty palette emits nothing |
| Emitters | First 32, in order |
| Particle counts | Negative becomes zero; at most 6,000 across the whole event |
| Emitter delay | Finite values clamped to 0–60 seconds |
| Emitter origin and angle | Must be finite; direction is normalized to a rotation |
| Spread | Absolute value clamped to 360 degrees; must be finite |
| Launch and fall distance | Greater than zero, at most 5,000 points |
| Nominal size | 1–64 points, before shape proportions and size variation |
| Per-shape fall multiplier | Range entirely within 0.25–4 |
| Launch speed multiplier | 0.25–4, affecting ascent only |
| Custom launch duration | Range within 0.05–4 seconds, before the speed multiplier |
| Spin and tumble | Magnitude ranges within 0–100 radians per second |
| Size variation | Range within 0.1–3 |
| Flutter | 0–100 points |
| Fade-out start | 0–0.95 of descent; fading completes before cleanup |
| Shower emission duration | 0–10 seconds |
| Custom paths | Up to 512 elements, finite nonzero bounds, aspect ratio at least 1:64 |

Numeric values used by an event and their range bounds must be finite. An emitter
with a non-finite origin, delay, angle, or spread is skipped; other valid emitters
still play. Invalid shared flight settings emit nothing. Explicit emitters replace
the configuration’s count, direction, and spread. Showers ignore the configuration’s
direction and spread; they still validate launch distance and all motion settings,
including ascent settings, before constructing the falling flight.

These limits prevent common allocation mistakes; they aren't a performance
recommendation or a total-memory guarantee. Large paper, many unique shapes/colors,
and high particle counts increase preparation and compositing work. Global image
caches are bounded; images used by an active flight remain retained until cleanup.
Start with the default budget and profile your app on representative devices.

## Replacement and completion

One controller or UIKit host owns one event. An accepted request replaces the old
event immediately, even if its configuration later produces no particles. The old
request receives ``ConfettiOutcome/cancelled`` and the empty request receives
``ConfettiOutcome/notPresented`` once mounted and evaluated. An unavailable host,
missing source ID, or invalid shower duration rejects the new request without
replacing an active one. Reduce Motion omits new motion and reports
``ConfettiOutcome/reducedMotion`` for an active host.

Callbacks are asynchronous, once-only, and main-actor isolated. A request before
first mount or nonzero layout may remain pending until layout, replacement,
cancellation, or release. Use weak captures when a completion refers to its owner.
Don't gate essential application behavior on animation completion.

## Custom paths and adaptive colors

``ConfettiShape/init(path:name:)`` snapshots a filled Core Graphics path. It
preserves proportions and uses even-odd fill for holes. Convert an open stroked
line to a filled outline before passing it. Names are display labels; equal
geometry shares a cache entry regardless of its name.

Dynamic colors resolve against the host's traits when a new flight starts.
Already flying paper keeps its captured color and origin. Retain a stable,
full-size host outside moving keyboard and scroll containers, and start a new
event if you deliberately need a different appearance.
