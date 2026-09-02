# Path trimming

`Path.trimmedPath(from:to:)` selects a fraction of the total drawn length across
lines, quadratic and cubic curves, circular arcs and closing edges. Moves do not
add length or connect separate contours. Partial contours remain open; a whole
selected closed contour retains its close command. An exact `[0, 1]` selection
returns the original path elements unchanged, including inputs that a downstream
renderer may reject. Equal valid fractions return an empty path.

Partial selections require ordered, finite fractions in `0...1`. Invalid or
unrepresentable geometry and exhausted work limits reject the entire selection.
The internal checked operation reports a typed failure; the nonthrowing public
API returns an empty path. It never substitutes the original path or an accepted
prefix after a failure.

Curve length uses adaptive De Casteljau subdivision with chord and control
polygon bounds. Endpoint inversion measures split prefixes, so even a collinear
curve with nonuniform parameter speed trims by distance. The length approximation
allows `1e-7` logical units across the path plus `1e-8` of each control polygon's
length. Inversion separately allows the larger of `1e-7` units and `1e-8` of the
selected segment's length. Accumulated path error is additional; these policies
are not a universal endpoint error guarantee or a native conformance claim.

Subdivision reuses unused sibling error allowance within that same tolerance.
The right child's bounds are paid for once, used to reserve only the allowance
it may need, and reused after the left child returns. Nonfinite or negative
remaining allowances and a combined reported error above the original tolerance
reject the selection. The right bound is now read before the left subtree, so
the order of competing failures can differ; no work is refunded. This remains
floating-point estimation, not outward-rounded interval arithmetic.

Default limits admit at most 65,536 input elements, 131,072 derived segments,
1,048,576 work steps, 24 curve subdivision levels and 56 inversion iterations.
Arc angles and sweeps are bounded by `8192*pi`. Arithmetic checks reject lost
length, nonfinite intermediates and unrepresentable arc extents without trapping.

For an arc whose nonzero sweep opposes the requested direction, an exact whole
turn remainder retains one turn in that direction. Equal original angles remain
zero, aligned multiple turns retain their admitted length, and nonintegral reverse
wrapping keeps the existing policy. Apple's [WWDC24 SwiftUI Path example at 7:07](https://developer.apple.com/videos/play/wwdc2024/10104/)
demonstrates the single clockwise `0...360` circle. The symmetric and multiple
turn rules are explicit implementation policies, not separately observed native
results. Existing drawing and containment code still differ on some raw arc
boundaries; full-range copying does not repair those consumers. An arc after
`close` starts its own contour. General line/curve continuation after `close`
is outside partial admission.

Retained `TrimmedShape` recognizes a rectangle and its ordered point insets,
including `AnyShape` erasure. Construction preserves an immutable descriptor;
layout applies its scalar insets to the live inner paint rectangle before
trimming. An inset of ten points stays ten points when the view resizes. This
route also resolves full-range inset rectangles. Raw negative derived dimensions
keep the existing public rectangle path's reversed edges, rather than introducing
a new clamp. Nonfinite intermediate coordinates, dimensions or extents reject
the whole geometry.

The descriptor admits at most 65,536 inset operations, including zero amounts.
This is separate from the unchanged Core path-element and work limits. Immutable
balanced blocks share their scalar storage across erasure and descriptor copies;
each prepend copies at most 17 root references, not the entire inset sequence.
Construction flattens the admitted sequence once. Layout retains only that array
and trim fractions, with no authored shape, callback, build context or temporary
paint owner. These representation bounds are not a measured performance result.
A recognized rejection remains rejected through wrappers and never retries an
authored or unit-rectangle fallback.

Other retained content still builds value geometry once in its unit rectangle,
then scales and trims that geometry in the live inner paint metric. Its existing
full-range route, and the plain rectangle's full-range route, remain unchanged.
Neither route calls authored `path(in:)` during layout. Paint metadata and passive
erasure remain intact. Collapsed paint dimensions and rejected selections keep
an explicit empty path so they cannot become rectangular backgrounds. The result
is normalized for one presentation transform. Existing retained arc flattening
remains an approximation and is not a general arc rendering fix.

There are 26 original analytic portable tests, six additional reversal controls
and 12 retained geometry/pixel tests. At `a3dfc5f`, fresh execution passed all
44 of those cases, including the retraced quadratic that previously rejected
with `workLimit` and all six sibling-allowance reversal controls. The retained
cases cover wide/tall dimensions,
Bézier controls, empty and partial fills, layout/reconciliation callback counts,
live border width, resizing, passive erasure, origin placement, display scales
and rejection. The complete 98-case shape/selection cohort passed with no skips,
including the independently corrected Arc assertion and twelve Arc coordinate
controls. This is focused execution, not a full-suite or native parity result.
Exact source, raw logs and outcomes are recorded in the append-only
[goal ledger](../goal.md).

All eighteen `RetainedRectangleInsetTrimTests` passed at `b09f0a2`, within a
fresh 144-case geometry and selection run with no failures or skips. Their
independent line-length and pixel oracles cover point insets, full/half/empty
fills, raw reversed edges, ordered floating-point arithmetic, descriptor sharing
and bounds, rejection, resizing, live stroke width, origin/DPI placement,
erasure, reconciliation and lifetime. All twelve existing
`TrimmedShapeGeometryTests` remain unchanged and passed in that same run.

The preceding run at `15119eb` passed 143 cases and failed one new fixture:
its expected emitted stroke width did not follow the live border width. The
correction preserves the stored style assertion and adds before/after pixels
that distinguish stale geometry from the correct live-width stroke. Production
code, the other seventeen new methods, all helpers and every existing test were
unchanged. Both runs remain recorded in the goal ledger. These focused results
do not establish full-suite, D3D11, native SwiftUI or performance qualification.

The `shape-trim-static` gallery entry provides a 600-by-400 dark fixture with
wide and tall quarter outlines, a half quadratic curve, and full/half/empty
fills against untrimmed references. Its shared demo source uses ordinary shape
APIs. A freshly linked executable from `a3dfc5f` rendered that one entry through
the retained snapshot and CPU rasterizer, and the resulting PNG was inspected.
The quarter outlines, half curve and full/half/empty fills are visible in the
expected panels; the gray complete-curve reference still shows segment faceting.
This adds no approved baseline, D3D11 execution, macOS reference comparison or
performance qualification.

Bounds-dependent custom shapes, literal paths, nested trimmed geometry, other
built-in inset geometry, the trimmed-shape inset no-op, and `strokeBorder`
composition remain open. So do hit/clip semantics, animated fractions, arbitrary
transforms, gradient/dash/antialiasing fidelity and native parity.
This implementation does not complete the shape or rendering acceptance gates.
