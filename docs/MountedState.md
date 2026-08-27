# Mounted State ownership

Ordinary `@State` in custom struct views belongs to the mounted view in one
`WinSwiftUIWindowHost`. Reconstructing a child with the same typed identity
preserves its value. Reusing one source value at different tree positions or
in different hosts creates independent storage cells. A removed identity and
a later insertion at that path have different generations.

This implements a bounded part of the state requirement in
[`goal.md`](../goal.md), not full SwiftUI lifetime conformance. `@StateObject`
still constructs eagerly and retains its legacy wrapper storage. Focus,
gesture, namespace, storage, query, and observed wrappers retain their existing
mechanisms; this change does not give them mounted ownership automatically.

## Identity and installation

The host's `StateMountCoordinator` owns a `StateMountRegistry`. Structural
identity includes concrete view types, builder positions and branches,
auxiliary builder roles, and typed Hashable IDs. A typed writable property
key path identifies each declaration inside its owner. Existential properties
also distinguish their concrete types.

Before a custom view's body is evaluated, `DynamicPropertyInstaller` copies
the source value, resolves its mounted cells, and rewrites that copy. It does
not retarget the original view's seed box. Private fields and nested struct
dynamic properties are supported. Nested properties update before their
containing property, and each installed occurrence receives one `update()`.
An already installed default-body delegate reuses the copy; a newly erased
view receives its own dispatch even if the concrete type is unchanged.

The adapter obtains typed key paths through Swift reflection SPI. It does
not mutate `Mirror` output or write raw field offsets. Installation preflights
metadata before running factories or updates. Unsupported class or enum
dynamic properties, immutable owning/custom declarations, ambiguous property
slots, and ownership schema replacement during `update()` reject the
candidate and report a host diagnostic. Explicitly trusted legacy non-owning
leaves with no-op updates can remain immutable in framework controls.

Consumer reflection metadata must remain enabled, including in release
builds. Reflection field names are not required. Stripped nonempty metadata
and the adapter's own metadata canary are checked, but a stripped zero-size
consumer cannot be distinguished from a truly empty type. A reflected `Void`
field can be ambiguous with failed demangling and is diagnosed. These are
current toolchain limits, not proof of general compiler-version conformance.

Outside a mounted host, a State wrapper keeps its seed storage and the
existing standalone build-context behavior. Initial values are ordinary Swift
values: copying a reference value into separate cells does not clone the
referenced object. Inherited `View.body` result-builder compatibility remains
separate work; installation does not change public builder representation.

## Candidate builds and adoption

Root construction and deferred GeometryReader construction use provisional
build epochs. The committed tree keeps its ownership and observed-object
subscriptions while a candidate is composed. An abandoned candidate releases
its provisional ownership and subscriptions without rolling back accepted
application mutations or other application side effects.

Before adoption changes a retained node, outgoing State owners lose write
permission. If preparation is cancelled before the first node mutation, the
old ownership can be restored unless the host has closed. Once in-place
adoption begins, it finishes before the next queued build; a newer mutation
does not promise rollback of that adoption. Successful completion runs under
the accepted build's transaction. Closing the host suppresses completion.

Every accepted live State write advances a host-local mutation revision before
invalidation and before releasing the previous value. Rebuild requests capture
that revision. A request superseded by an actual later write is rejected before
work or adoption. A control's redundant fallback invalidation has the same
revision and cannot replace the preceding binding transaction. This is a
coarse host-wide policy; independent simultaneous State transaction semantics
still need native reference qualification.

The root/deferred build guard drains queued work iteratively. Ordinary
observed-object notification coalescing remains separate from this queue.
Candidate observation tokens are staged and generation checked so that
reentrant notifications cannot disconnect the still-committed tree.

GeometryReader retains a generation-specific lease for a strict descendant
content scope. Resolving its actual layout slot rebuilds that scope without
sweeping sibling State. A removed or closed reader's captured closure cannot
evaluate content, even if the same path is later mounted again. A deferred
build skipped during active construction is retried after the guard ends.

## Containers and retirement

Inactive tabs preserve known declarations through modifier, optional,
conditional, array, Group, and ForEach paths without evaluating custom bodies.
Opaque inactive bodies and auxiliary builder captures stay unevaluated until
their next evaluation; deeper native inactive-lifetime behavior is unqualified.
ViewThatFits keeps candidate namespaces disjoint and discards rejected
provisional candidates without retiring a selected sibling. OutlineGroup uses
typed hierarchical row identities and parent-local duplicate ordinals, but
retains its existing eager construction and expansion behavior.

A retired State cell is a last-value read handle. Removal or close releases
registry ownership, while an escaped binding or installed value may retain
the last value until that handle is released. Reference values keep ordinary
alias semantics; this is not a deep freeze. Retired raw, member, and collection
bindings do not reconnect to a replacement generation. Their write guard runs
before projected read/modify/set operations can cause side effects, does not
retain rejected payloads, and does not invalidate a host.

Editor replay and State writes must both be revoked before teardown releases
application payloads. Otherwise a State value's deinitializer could replay an
editor, or a discarded undo payload could write an escaped State binding.
The combined teardown marks editor sessions first, closes State ownership,
then selectively purges those editor histories and detaches input. Both close
paths stop render lifecycle delivery and cancel tasks after write revocation.
Explicit window close keeps the existing pointer, focus, and window-closed
callbacks; host deinitialization performs ownership cleanup without those
callbacks. Neither path adds whole-tree `onDisappear` delivery for window
closure. That native lifecycle behavior remains separate qualification work.
See [`TextInputUndo.md`](TextInputUndo.md) for editor eligibility and limitations.

## Accounting and validation

`ComponentHost` measures each actual root build attempt, including epoch setup,
composition, node construction, reconciliation, and commit. Retirement cleanup
adds elapsed rebuild time without another attempt count. Completion callbacks
remain outside rebuild cost, although callbacks inside a rendered frame still
contribute to that frame's wall time. Stale requests rejected before work do
not count; initial constructor setup is excluded from the reload counter.

The initial composition timer does not measure every nested body: bodies
evaluated during node construction remain in that phase. Frame reports can
aggregate multiple rebuilds; their percentiles are not individual-reload
percentiles. The additional ownership and departure traversals have real
cost and are not a performance qualification.

Quick includes the installation, registry, root/deferred lifecycle, container,
queued-transaction, timing, and combined editor teardown suites. See
[`Testing.md`](Testing.md) for serial invocation and
[`goal.md`](../goal.md) for exact executed results, failures, and corrections.
Standalone reflection probes do not replace production module compilation or
real retained-host tests. Native SwiftUI comparisons, complete wrapper
ownership, lazy collection lifetime, and hardware timing remain open.
