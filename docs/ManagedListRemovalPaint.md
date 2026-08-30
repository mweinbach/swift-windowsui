# Managed List removal paint

This is a source checkpoint. The bridge and its new regressions have not yet
been compiled or executed together. It does not close the original animation,
collection lifetime, accessibility, native rendering, or resource gates in
`goal.md`.

Managed flat List rows can retain a bounded visual tail after a checked
structural departure. The retained value contains renderer-neutral primitives,
owned bitmap and glyph bytes, placement, and native animation values. It does
not retain a ViewNode, State owner, observation, controller, task, Canvas
renderer, application callback, or executable weak reference. Viewport eviction
still removes physical activity without producing a removal tail.

## Admission and ownership

The normal scene or frame paint records the outgoing attachment's exact paint
footprint, including its admitted deferred draws. Native observations precede
the normal painter; a Canvas callback cannot detach and reattach a node and
certify old pixels with a new attachment proof. Resource bytes are copied into
owned buffers during that completed paint. A missing or unsupported range is
unavailable paint, not evidence of an empty row.

Removal resolves the existing transaction, animation modifiers, and clock once
under the actual ancestor transaction scope. The managed path checks the
original departing and incoming native forests around authored calls and after
temporary callback payloads unwind. Ordinary removal uses the same central
resolver and retains its existing overlay lifecycle. There is no `hasAppeared`
exception and no clearing of TabView's transitions. An attachment that has
never painted simply has no outgoing pixels after the same eligibility rule
has been evaluated.

The checked retirement path revokes attachment, task-slot, input, focus, and
accessibility authority before its cleanup callbacks. Paint becomes visible
only after that retirement drain finishes. State follows the accepted
declaration ledger: removing an exact identity retires that generation, while
switching away from a still-declared Tab page does not destroy its logical
State. A frozen paint value cannot make an escaped binding writable or make an
old UIA action current again.

Raw providers retain their existing nonidentity structural-removal refusal.
An ordinary sibling or nested raw List cannot borrow a managed ancestor's
transport permission. The native reconciliation machinery can already have
accepted an ownership-revocation prefix before a managed paint capture is
refused; the bridge does not claim whole-operation rollback for that path.

## Replay and current limits

Sources follow `GPUIScene.presentationOrder()` and retain only the selected
primitives and their referenced resource namespaces. Replay does not call the
old painter. Sources can animate inherited opacity by changing the top-level
primitive alphas rather than introducing group opacity over overlapping
descendants. Dependent material sources use that same projection inside their
existing backdrop isolation, with a unit-opacity consuming image. Root-owned
blur and color-effect boundaries require separate opacity provenance and are
not treated as ordinary primitive alpha. Original ancestor and descendant
node opacities and authored paint alphas must be within the unit interval so
replay does not try to recover values lost to saturation. Stored paint colors,
gradient stops, and text styles are checked before painting. Canvas operation
alphas are checked during the existing normal draw, before inherited opacity
is multiplied. The check retains only a native boolean witness, and an old
callback cannot certify its replacement. A Canvas assignment that emits an
out-of-range alpha remains ineligible for this projection until the actual
callback is replaced and an ordinary paint establishes its new output.

Changing translation is supported only when the frozen footprint has not
already lost pixels to a clip and the stationary ancestor clip is rectangular.
A dependent backdrop source keeps the original pixel domain; translating it
or changing its capture DPI or target dimensions is not admitted. Changing
scale or rotation is still refused: the current painter can reflow text, lower a transform to a
bounding box, or treat decorations and descendant transforms differently from
one affine transform of a combined picture. Reproducing those cases needs
per-primitive placement and effect provenance. Unfinished descendant property
animations are also refused rather than silently frozen.

Translation transports the frozen visual source. Fractional device movement
can resample it differently from a fresh primitive paint that snaps hairlines
or glyphs; exact native pixel parity for that motion remains unqualified.

Existing supported root timelines retain their original easing phase. Fresh
removal values start from the last presented pose, and a delayed state does
not run before its start time. Completion, host shutdown, and bounded resource
exhaustion release the paint without invoking application cleanup again.

The normal GPU scene route submits scene values and image render passes; it
does not rasterize the window on the CPU to capture or replay a removal. The
legacy frame route has no image-pass command, so its visual-tail presentation
uses the existing CPU scene rasterizer over already-issued frame commands.
This can rasterize the whole frame during the tail and is an explicit fallback
cost, not GPU performance parity. Reserved text/blur commands or clip-stack
shapes that the frame-to-scene bridge cannot preserve are refused. If a later
live frame becomes incompatible, its original commands are preserved and its
visual tails finish instead of degrading live content.

## Resource bounds and verification

Each normal-paint freeze and selected source is limited to 64 MiB of retained
storage; sources permit 65,536 primitive records, 1,024 selected spans, and
262,144 inspected entries. One paint visit records at most 256 nonidentity
managed roots using a shared immutable snapshot. A runtime retains at most 32
departures and 128 MiB of source storage. Exceeding a retention bound completes
the oldest visual values; executable retirement has already finished.

The live scene reserves its render-pass capacity first. Remaining capacity is
assigned to the newest departures, which still paint in chronological order.
Both declared and executed pass costs count, including repeated occurrences
and backdrop-isolation scratch planes. The existing scene limits remain
unchanged: 1,024 image passes, 4,194,304 pixels per source, and 16,777,216 pixels
across the pass graph. A discarded value cannot reappear when capacity later
becomes free. `retiredLazyListPaintBudgetCompletions` records these early visual
completions.

Source regressions cover guarded resolution and reentry, frozen resources and
paint namespaces, opacity overlap, timeline sampling, frame clip spans,
aggregate pass limits, public List removal, Tab state continuation, Canvas
callback isolation, tasks, input/UIA revocation, interrupted insertion, host
closure, and resource release. Fresh combined compilation and execution of
these tests and the unchanged original cases remain required. Retained visual
review, native D3D11/UIA qualification, and latency/memory measurements remain
open under the original goal.
