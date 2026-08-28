# Structural child construction

`VStack` and `HStack` can lay out the children of a pure composition directly.
For example, a custom view with an explicitly annotated `@ViewBuilder` body
containing two views contributes two stack children, rather than an absolute
panel containing overlapping children. An empty composition contributes no
child and therefore adds no stack spacing.

This uses an optional package-scoped append callback on
`SwiftWindowsUI.Component`. Existing public initializers and
`makeNode(runtime:)` keep their single-node behavior. A parent
that accepts structural children calls `appendChildNodes(runtime:to:)`; the
component either appends its structural children or appends the result of its
ordinary node constructor. It does not construct a node to discover whether
that node should be flattened. Ordinary leaf components have no append callback
and need no temporary singleton array.

The callback must append without changing the destination's existing prefix.
A callback that appends nothing is different from a missing callback. A
component with a reconciliation key always contributes one aggregate node;
the key is not copied to its children. `asSingleNode()` returns a copy that
disables structural expansion, including after its key is cleared.

`[AnyView]`, `Group`, and `ForEach` opt into this path as pure composition
producers, and `EmptyView` supplies an empty structural result. Optional and
conditional views can forward the active child's capability through their
existing component dispatch. `AnyView` re-erasure and the identity wrapper
preserve it. The normal installed-value gateway still evaluates a selected
custom body or custom `makeComponent` implementation once per construction;
the child callback runs under its captured build context. Child identities
retain their existing builder slots, branches, and keys. State ownership does
not depend on inserting a container node, and no inactive body is evaluated to
find children or declarations.

For a raw structural producer, the identity wrapper preserves any identity
already supplied by each child. A child without one receives an identity under
the parent's content scope, keyed by its actual `nodeTag` String when present,
or by its local emitted slot when untagged. The destination's preexisting
prefix is not part of that slot. Repeated tags share a scoped key and therefore
match in FIFO order through the existing reconciliation buckets. This is a new
fallback policy for structural producers, not a promise that changing an
untagged child to a tagged one retains its node: those paths differ. The
existing single-node custom `makeComponent` identity path is unchanged.

Only the two basic linear stacks consume the new path. A key, a frame, an
explicit view ID, or a wrapper that constructs and decorates a node keeps that
aggregate boundary. Context-only modifiers can forward the capability.
Existing no-op modifier branches can forward it too. For example, an optional
background with no value leaves a structural body expanded, while a nonnil
background materializes its existing aggregate node. Changing that option can
therefore change the stack's direct child count; full native modifier behavior
is not established by this seam.
`composeComponent` remains opaque even for one structural child, while
`composeStructuralComponent` is the explicit opt-in used by the pure producers.
The single-child producer keeps its existing eager component construction;
zero or multiple children retain lazy node construction. Either request uses
one construction path, not both.

This does not change `ComponentHost`, `UI.stackPanel`, lazy stacks, lists,
grids, `ViewThatFits`, or other consumers that index content metadata. In
particular, the list-edit decorator around a `ForEach` row remains opaque;
a custom multi-child body inside that decorated row still uses its existing
aggregate layout. Likewise, an aggregate under a frame is not automatically
laid out with its enclosing stack's axis. Native behavior for all such
boundaries remains incomplete.

The public builder still returns `[AnyView]`. This change does not add inherited
`@ViewBuilder` behavior to the `View.body` requirement, change the canonical
builder signatures, or implement mutable typed `TupleView` rendering. Those
source and runtime changes remain separate work; this construction path is not
a claim of complete SwiftUI builder or container parity.

`StructuralComponentTests` covers the low-level construction paths, keys, and
empty results. `StructuralCompositionIdentityTests` covers captured context,
identity forwarding, raw keyed reordering and FIFO matching, and opaque
composition. `StructuralComponentMountedTests`
uses the real window host with a fake surface to check layout, reconciliation,
environment installation, and mounted State. Native reference qualification
and repository execution of new tests are separate from source review.
The integrated suites now pass all 34 new cases, alongside the unchanged
construction/headroom checks and focused State, StateObject, identity, stack,
list, and public API regressions. These are Windows semantic tests; complete
batch validation and native reference comparisons remain separate requirements.
