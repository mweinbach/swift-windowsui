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

Retained `TrimmedShape` builds value geometry once from its content's unit
rectangle. Its layout callback reads the live inner paint size, scales the
untrimmed path, trims in that resolved metric and normalizes the result for one
presentation transform. It captures no authored shape, build context or temporary
node and does not call authored `path(in:)` during layout. Paint metadata and
passive erasure remain intact. Collapsed dimensions and rejected selections keep
an explicit empty path so they cannot fall back to a rectangular background.
The exact full-range route remains unchanged. Existing retained arc flattening
is still an approximation and is not a general arc rendering fix.

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

The `shape-trim-static` gallery entry provides a 600-by-400 dark fixture with
wide and tall quarter outlines, a half quadratic curve, and full/half/empty
fills against untrimmed references. Its shared demo source uses ordinary shape
APIs. A freshly linked executable from `a3dfc5f` rendered that one entry through
the retained snapshot and CPU rasterizer, and the resulting PNG was inspected.
The quarter outlines, half curve and full/half/empty fills are visible in the
expected panels; the gray complete-curve reference still shows segment faceting.
This adds no approved baseline, D3D11 execution, macOS reference comparison or
performance qualification.

Bounds-dependent custom shapes, literal and nested retained geometry, inset and
`strokeBorder` composition, hit/clip semantics, animated fractions, arbitrary
transforms, gradient/dash/antialiasing fidelity and native parity remain open.
This implementation does not complete the shape or rendering acceptance gates.
