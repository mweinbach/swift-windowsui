# Mounted preference observation

`onPreferenceChange` keeps its last accepted preference value in the containing
host's mounted ownership. Windows, siblings, and nested observers do not share
history because they use one source location. The private owner includes both
the preference operation and concrete `PreferenceKey` type. Two keys with the
same `Value` type remain independent, as does an ordinary `onChange` modifier
at an otherwise matching structural position.

The existing typed path distinguishes sibling slots, conditional branches,
keyed rows, and explicit `.id` values. Reordering a surviving keyed occurrence
keeps its history. Removing and remounting an observer creates a fresh
generation; an old callback or value never resolves a replacement by its path.
Declared inactive alternatives follow the existing State preservation rules and
do not deliver new observations merely because their declarations still exist.

## Values and adoption

Preference writers, reducers, transforms, and background/overlay readers still
compute during component construction. This remains provisional application
work: a rejected candidate can execute a reducer, default getter, or transform.
The observer's equality comparison and action wait for successful adoption.

The observer resolves an empty private record through checked synthetic
ownership before reducing its materialized child. A closed or superseded
owner cannot publish an observer value or run observer equality/action.
Construction checks use a callback-free receipt after authored identity
lookups; they do not call an ordinary State resolver's precondition after
identity hashing can invalidate the build. This is an observer-specific
construction path, not a general change to State or StateObject resolution.
The separate [observer admission foundation](MountedObserverAdmission.md)
defines its epoch, materialization, and cleanup receipts.

The current Windows value policy is preserved:

| Accepted observation | Behavior |
| --- | --- |
| First explicit contribution | Notify once, including an explicit value equal to the default. |
| First missing contribution | Silently establish the key's default as the baseline. |
| Later missing/present transition with equal resolved values | Do not notify for presence alone. |
| Last contribution removed | Compare with the default and notify if the resolved value changed. |
| Explicit optional `nil` | Treat it as a present value, distinct from missing or unobserved. |
| Equal values on a later build | Keep the previous boxed baseline; a future change uses the current action. |

A retained tree reduces direct and descendant contributions in its existing
tree order. A transform boundary prevents an ancestor from reducing that
transformed subtree twice. This migration does not change reducer algorithms,
raw anchor values, or background/overlay construction. It does not establish
native reducer invocation counts, initial-default policy, or deep snapshot
semantics for reference-containing values.

Every admitted baseline is published before the accepted batch begins
comparison and callback delivery. Equality is application code: delivery is
claimed once and ownership is checked again after equality. An equal result
can restore the prior boxed baseline only while its delivery token is current.
Old/proposed values and callback captures stay pinned through their guarded
cleanup. A rejected candidate cannot advance the next accepted comparison.

## Reentry, transactions, and lifetime

Actions run after retained adoption and the existing terminal callback and
retirement work, before the matching root request completes. The retained build
guard and both captured transaction slots remain active through comparison,
actions, and displaced capture cleanup. Full transactions, explicit nil
animation, and the legacy animation tuple retain their existing distinction.

A callback's State write queues the usual later build; it does not cancel other
observers in the already accepted batch. Closing the host retires their owners
and suppresses remaining deliveries. Application writes are not rolled back.
The callback is not a subscription to an arbitrary model: a custom model that
does not invalidate still needs its application's ordinary rebuild path.

Retirement releases registry ownership of the comparison baseline. A retained
node's preference metadata or an application-held value can independently keep
a payload alive. This is ordinary Swift reference ownership, not a promise to
release externally retained values or freeze mutable reference contents.

## Boundaries and evidence

The primary host supplies `StateMountCoordinator` through `ViewBuildContext`.
A raw component without that coordinator has no mounted preference notification
history and does not invoke this observer. Raw preference writers, transforms,
and background/overlay readers still work; there is no callsite-registry
fallback for notifications. The separate `task(id:)` migration is not included.

An observer inside an adopted GeometryReader content scope can observe a later
scoped rebuild. An observer outside that scope is not automatically resampled
when only the descendant subtree changes. There is no new ancestor preference
refresh pass or guarantee that a sampled value represents final layout.
Current eager lazy-stack node construction still supplies its ordinary
preference contributions; future metadata-only lazy rows cannot manufacture
values without materialization. Partial lazy adoption requires a separate
accepted-subset integration, and remains outside this change.

The source fixtures are `MountedPreferenceValueTests`,
`MountedPreferenceLifecycleTests`, and `MountedPreferenceTransactionTests`,
plus the three mounted-host setup migrations in `WinSwiftUITests`.
`MountedObserverAdmissionTests` and `MountedObserverReentryTests` exercise the
observer construction foundation.
These names identify authored tests, not native or presentation qualification;
execution evidence is recorded separately in the validation handoff.

Native macOS comparison, callback-loop behavior, exact callback ordering,
post-layout anchor projection, public actor-isolation equivalence, and
presentation timing remain open. An adopted retained tree is not proof that
its pixels were presented. Apple's public descriptions of
[preference observation](https://developer.apple.com/documentation/swiftui/view/onpreferencechange(_:perform:))
and [tree-order reduction](https://developer.apple.com/documentation/swiftui/preferencekey/reduce(value:nextvalue:))
do not establish those remaining compatibility claims.
