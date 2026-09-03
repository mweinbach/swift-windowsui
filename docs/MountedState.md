# Mounted State ownership

Ordinary `@State` and `@StateObject` in custom struct views belong to the mounted
view in one `WinSwiftUIWindowHost`. Reconstructing a child with the same typed
identity preserves its value. Reusing one source value at different tree positions or
in different hosts creates independent storage cells. A removed identity and
a later insertion at that path have different generations.

This implements a bounded part of the state requirement in
[`goal.md`](../goal.md), not full SwiftUI lifetime conformance. Focus,
gesture, namespace, storage, query, and borrowed observed wrappers retain their
existing mechanisms; this change does not give them mounted ownership automatically.

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
referenced object. Custom `View.body` declarations inherit `@ViewBuilder` from
`View`; mounted installation does not change public builder representation.

## StateObject construction and compatibility

`StateObject(wrappedValue:)` stores an escaping main-actor factory. Creating,
copying, or erasing the source view does not invoke that factory. Installation
of a new typed owner and property slot creates the object before evaluating
the body. Rebuilding that owner reuses its object without invoking a newly
supplied factory, even when initializer inputs change. Removing the owner and
later inserting the same path creates a new generation and invokes its factory
again. Factories that return an already-created object intentionally share
that reference; independent ownership does not clone class instances.

Object creation reserves its owner generation and declaration before calling
application code. Recursively resolving the same unfinished object rejects
the candidate with an installation diagnostic. Independent declarations can
initialize during that callback. Adoption cannot begin while a factory is
running, and the original epoch is checked again after it returns. A factory
that closes or supersedes its build cannot publish a cell into a replacement
epoch. The ordinary State seed-resolution policy is unchanged.

Installation observes the resolved object even when the body only passes a
projected binding without reading it. Published property changes continue
through the existing observed-object batching and captured transaction path;
member setters do not add a second State-style invalidation. Candidate
subscriptions use the same commit and abandonment rules as other observed
dependencies. Objects passed to `ObservedObject` or `environmentObject` remain
ordinary borrowed references, and closing their owner does not close another
host's subscription to that object.

Outside an installed view, the first wrapped-value access or member projection
creates a separate fallback object, cached by the source wrapper. Copies share
that fallback until a copy's public setter explicitly replaces its source.
Mounted creation never adopts the fallback cache: using the same source in two
hosts invokes the factory separately for those two owners. This standalone
policy, including App and Scene declarations not installed as views, is not a
claim of native SwiftUI container lifetime parity.

Two existing public API extensions are retained deliberately: `wrappedValue`
has a mutating setter, and `projectedValue` returns `StateObject<ObjectType>`.
Native SwiftUI exposes a get-only wrapped object and an
`ObservedObject<ObjectType>.Wrapper` projection instead, as documented in
[`wrappedValue`](https://developer.apple.com/documentation/swiftui/stateobject/wrappedvalue)
and [`projectedValue`](https://developer.apple.com/documentation/swiftui/stateobject/projectedvalue).
A mounted whole-object assignment replaces the value in its existing cell,
advances the usual live
State revision, and invalidates that host. Previously created member bindings
follow this replacement within the same generation. An unmounted assignment
changes only that source value, not its previous copies or installed owners.
Initializer and access remain main-actor constrained; this slice does not
adopt native initializer isolation or public Wrapper compatibility.

Member bindings capture only the installed cell and key path. After retirement
their write guards run before projected getter, modify, or setter operations,
and cannot reconnect to a later owner. A getter still reads the retained object
with ordinary reference semantics. Raw objects and bindings made through
borrowed wrappers are not revoked by another wrapper's ownership. An escaped
member binding legitimately retains its last object until released, but does
not retain the authored factory or fallback cache. An escaped raw StateObject
projection or installed view can retain those source values as well.

A measured or superseded candidate may run an object factory and then discard
its result. No framework can roll back that factory's external side effects.
Never-evaluated inactive declarations do not run factories; previously mounted
inactive scopes retain the existing State declaration-preservation policy.
Exact speculative-construction, cyclic standalone initialization, inactive
container, and stale-access semantics still require native qualification.

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
Hosted readers also require their exact accepted construction receipt: merely
composing a reader or preserving its inactive State does not admit a deferred
build. Accepted reader replacement retires the old receipt without resetting
the surviving State owner.

## Containers and retirement

Item sheets include the selected item's typed ID in the presentation content's
identity. Updating a value with the same ID preserves that content's State;
selecting another ID retires its old generation and starts from the new seed.
The stable sheet host and background child retain their existing identities,
including background editing state. An accepted active nil presentation also
retires its content before a later presentation starts a fresh generation.
StateObject follows its separate mounted ownership contract described above.
Native dismissal ordering is not qualified by these ownership changes.

Inactive tabs preserve known declarations through modifier, optional,
conditional, array, Group, and ForEach paths without evaluating custom bodies.
Opaque inactive bodies and auxiliary builder captures stay unevaluated until
their next evaluation; deeper native inactive-lifetime behavior is unqualified.
An inactive sheet's Binding value is not read just to preserve its declared
State; binding validation waits until its page evaluates.

The reviewed Calendar candidate gives `ViewThatFits` an explicit retained
ownership boundary. Selection still chooses the first child whose intrinsic
size fits the context canvas, with the last child as fallback; this is not full
SwiftUI proposal probing. Known declarations in unselected alternatives can
survive while that boundary remains accepted. A freshly rejected alternative
cannot publish new ownership or retire a selected sibling. The intended result
is that changing which alternative fits does not reset a surviving calendar's
browsed month or make an escaped old button callback valid again.

The boundary owns physical identity and retirement, while the selected child
supplies sizing, hit testing, and accessibility content rather than an extra
panel in the projected tree. Saved actions still require their original
selected path; switching away and back does not repair that path. State
preservation does not grant permission to invoke an old action or rebuild
through an old deferred reader. Removal withdraws the boundary's original
accepted ownership before cleanup can call application code; stale attempts
cannot borrow a replacement merely because its identity matches. This policy
does not make other layout containers retain inactive content.

On 2026-09-03 at `5a8e828`, the focused Calendar selection completed with 131
passing methods and five failing methods; the adjacent 19 internal text snapshot
tests passed. The original graphical DatePicker and MultiDatePicker
rejected-candidate regressions still fail, along with recursive deferred state
and a catalog reentry fixture whose storage-only mutation did not perform the
asserted physical attachment revocation. Selected UIA phase revocation,
repeated action layout, container metadata and the nested deferred facade now
pass their focused regressions. These results do not qualify broader Task
and lifecycle behavior, paint-cache replay, installed-source handling, or
native SwiftUI lifetime parity.

OutlineGroup uses
typed hierarchical row identities and parent-local duplicate ordinals, but
retains its existing eager construction and expansion behavior.

Boolean and item sheet dismissal actions in a mounted host use a separate
accepted presentation lifetime. Same-ID accepted rebuilds preserve that
lifetime and publish the latest binding, callback, and interactive focus
configuration. Accepted absence, item replacement, or tab inactivity retires
the action even when State and StateObject survive. Returning to that tab or
item starts new dismissal authority; an escaped old action cannot revive or
touch binding accessors, callbacks, or focus. A provisional action from a
discarded candidate never borrows an earlier accepted presentation's authority.

Activity is recorded for selected, constructed presentations, not appearance
or paint visibility. Root adoption updates the whole host; a GeometryReader
adoption updates only its content scope and its boundary lease. Skipped,
superseded, or abandoned builds do not replace accepted activity. Intermediate
model writes coalesced before any accepted presentation change do not invent
an inactive interval. Covered actions are suspended during adoption, and all
new configurations publish before retirement cleanup can call application
code. Close revokes presentation and deferred-reader authority before releasing
State or configuration payloads; it adds no native lifecycle callbacks.
Retired sessions reject dismissal before reading configuration storage. Cleanup
detaches stored collections while retaining their outgoing values locally, then
releases captures after those writes end. A payload's deinitializer can therefore
reenter dismissal or close without accessing a collection or configuration that
is still being modified. Normal finish preserves accepted session configurations.

Raw contexts without a StateMountCoordinator keep their existing dismissal
behavior, without the hosted lifetime guarantee. Explicit accepted dismissal
keeps the existing setter, onDismiss, and invalidation order; environment
dismissal does not acquire interactive focus restoration. External binding
changes do not gain synthesized onDismiss callbacks. Native callback ordering,
other presentation APIs, and atomic compare-and-set across arbitrary custom
Binding accessors remain unqualified.

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
queued-transaction, timing, StateObject factory/lifetime/observation, and
combined editor teardown suites. See
[`Testing.md`](Testing.md) for serial invocation and
[`goal.md`](../goal.md) for exact executed results, failures, and corrections.
Standalone reflection probes do not replace production module compilation or
real retained-host tests. Native SwiftUI comparisons, complete wrapper
ownership, lazy collection lifetime, and hardware timing remain open.
