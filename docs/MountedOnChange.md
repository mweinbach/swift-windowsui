# Mounted change observation

`onChange` stores its previous value in the containing host's mounted view
ownership. Two windows, two sibling occurrences, and nested modifiers do not
share history merely because they were authored at the same source location.
The existing typed identity path distinguishes structural positions, conditional
branches, keyed rows, and explicit `.id` values. Removing a modifier retires its
history; mounting the same source value again starts a new observation.

The public zero-argument, one-value `perform:`, and old/new-value overloads keep
their current call shapes. A first accepted build establishes the baseline.
With `initial: true`, it also delivers once, with identical old and new values
for the two-value overload. An observed optional `nil` is a baseline, not an
uninitialized record. Every rebuild uses that build's action and captures.

This observer does not subscribe to an arbitrary model or poll for changes. A
State write or existing observed-object notification requests the usual host
rebuild. A custom model that does not invalidate its host still requires the
application's existing invalidation path.

## Adoption and callback order

The modifier stages its proposed value and action when its component is
materialized. Merely constructing an unused component does not admit an
observer. Abandoned root builds and measured-but-rejected `ViewThatFits`
candidates neither advance history nor deliver actions. Previously accepted,
declared inactive alternatives follow the existing mount preservation rules;
they do not compare values while inactive.

An adopted epoch first publishes every admitted observer's proposed baseline, without
calling application equality or action code. The existing terminal callback and
mount retirement phase then finishes. Before request completion, each observer
compares its old and new values and, when needed, calls its current action.
Delivery follows materialization order within that accepted batch. Nested
modifier order is an implementation detail, not a native ordering guarantee.

Both full and legacy animation transaction slots remain those captured by the
existing retained build. An explicit transaction with no animation is distinct
from an absent transaction. The build guard remains active through comparison,
actions, and displaced value/capture cleanup. Reentrant reloads queue behind
that work. A later State write does not cancel the remaining observers of an
already adopted batch; closing the host revokes their ownership and skips them.
Equality is application code too, so delivery rechecks its owner after equality
returns. An equal result restores the previous boxed baseline only while the
owner and delivery token still match. This preserves the existing Windows
policy when custom `Equatable` ignores a payload field; it is not evidence of
native equivalence. Both old and proposed values remain alive until the
accepted callback batch finishes, including any cleanup caused by that restore.

The mount retains its comparison baseline, not an old action closure. Retirement
releases registry ownership. Values and captured reference objects keep their
ordinary Swift reference semantics; this is not a deep copy or a promise to
release objects still retained by application handles.

## Boundaries and validation

The primary `WinSwiftUIWindowHost` supplies `StateMountCoordinator` and the
matching `ViewBuildContext`. A manually constructed component with no mount
coordinator has no adoption or retirement boundary and does not admit an
`onChange` callback. There is no process-wide fallback. The in-memory regression
host uses the real coordinator, `ComponentHost`, and retained runtime; its plain
test models use explicit reloads rather than pretending to have subscriptions.

The separate `onPreferenceChange` and `task(id:)` adapters still use their legacy
callsite registry. Their lifetime semantics are not changed or qualified by
this slice. General authored identity hashing inside the existing State mount
resolver also remains a shared foundation boundary; the new staging admission
rechecks close and supersession after its own identity lookups.

The focused fixtures are `MountedOnChangeIsolationTests`,
`MountedOnChangeLifecycleTests`, `MountedOnChangeAdmissionTests`, and
`MountedOnChangeTransactionTests`, plus the three retained-host migrations in
`WinSwiftUITests`. They cover separate hosts and siblings, identity/remount,
candidate rejection, equality/action/cleanup reentry, deferred geometry, and
transaction propagation. Native macOS comparison, exact appearance/task order,
callback-loop policy, public actor-isolation equivalence, and presentation
timing remain unqualified. An adopted retained tree is not proof that its pixels
were presented.

Apple's public reference describes the
[old/new-value overload](https://developer.apple.com/documentation/swiftui/view/onchange(of:initial:_:)-4psgg)
and the
[zero-argument overload](https://developer.apple.com/documentation/swiftui/view/onchange(of:initial:_:)-8wgw9).
Those public descriptions do not by themselves establish parity for this
retained implementation's scheduling and lifetime boundaries.
