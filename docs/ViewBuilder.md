# ViewBuilder and typed composition

`View.body` inherits `@ViewBuilder`. A custom view can declare a concrete
single-view body, an opaque body, or multiple expressions without repeating the
attribute. Explicit `return` statements retain ordinary Swift return semantics.
The existing primitive and default `Never` bodies keep their implementations;
they are not coerced through an erased view.

```swift
struct PairBody: View {
    var body: some View {
        Text("First")
        Text("Second")
    }
}

struct SingleBody: View {
    var body: Text { Text("Concrete") }
}
```

The public `ViewBuilder` is a struct with static builder methods. An ordinary
expression and a single-expression block retain the expression's concrete
`View` type. An empty block produces `EmptyView`. A multiple-expression block
produces `TupleView<(repeat each Content)>`, one flat tuple of those expressions,
using parameter packs. Optional and conditional branches keep their typed
content, and limited availability erases through ordinary `AnyView`. A generic
`@ViewBuilder () -> Content` closure therefore retains typed content. Existing
public APIs whose closures return `[AnyView]` use contextual finalization into
the array representation; their signatures have not changed.

## Current tuple values and erasure

`TupleView.value` remains public and mutable. Rendering and declaration
discovery read its current value through an immutable accessor, rather than
using children cached by the initializer. Assigning the entire tuple or one
nested field therefore changes subsequent construction. A flat builder block
does not create nested binary pairs. An explicitly nested `TupleView`, however,
keeps that nesting in its public `value` type and its structural identity.

The builder uses a distinct internal initializer whose accessor traverses
parameter-pack fields. Public `TupleView.init(_:)` also supports a current
tuple of views and the existing single-view value path, including an actual
view stored as `Any` or a base-class reference. It first opens an actual view
without reflection. Otherwise, it inspects built-in tuple storage with
`Mirror(reflecting:)`, rejects `CustomReflectable` before inspection, and
requires every field to be a view.
An unsupported non-view value retains the old empty fallback; it is outside the
supported tuple-of-views contract and is not a native behavior claim.

An `AnyView` captures the same value for construction, declarations, and its
optional structural projection. Re-erasure preserves that capture and its
identity prefix. Earlier value copies and erasures keep their earlier captured
values when a later tuple copy is assigned. Normal Swift reference semantics
inside a captured value are unchanged.

## Projection, identity, and mounted State

The internal projection opens only known framework structure: `TupleView`,
`[AnyView]`, Optional, `_ConditionalContent`, `EmptyView`, the Windows loop/array
adapters, and stored content of unmodified `Group` and `ForEach`. Unknown custom
views and node or metadata decorators remain ordinary `AnyView` leaves. The
projection does not evaluate a body, call a custom `makeComponent`, or invoke
user-defined reflection to discover children.

Expansion uses an iterative work list. Its cursor carries only relative
identity segments and the current concrete type, not an installation receipt
or a copied build context. Tuple slots, active branches, original loop
iterations, content roles, and array occurrence ordinals are assigned before
empty values disappear. Rendering and current declaration discovery use those
same paths. Declaration exclusions retire removed known children while
preserving the existing conservative policy for an unevaluated opaque body;
they do not evaluate arbitrary inactive candidates.

The selected leaves still enter the existing installed-value construction
gateway. A custom body's structural result can then contribute children through
the package `Component` append capability described in
[StructuralComposition.md](StructuralComposition.md). This does not move State
ownership to a new renderer or change the mount registry or coordinator.

Contextual array finalization exposes logical leaves before ordinary
array-based consumers inspect their metadata. `ForEach` and data-driven `List`
also normalize explicit-return and prebuilt arrays before adding their existing
edit indices, implicit scroll targets, and selection tags. That boundary
preserves original array slots and repeated-fragment occurrence ordinals before
projection; removing an optional entry does not renumber a following sibling.
The actual metadata wrappers remain intact after decoration. Element indices
continue to identify source collection elements, while row suffixes identify
emitted leaves. A changed emitted suffix does not replace the typed identity of
a surviving source occurrence.

Node-decorating wrappers remain aggregate boundaries. Metadata-only projection
cannot flatten an arbitrary custom body inside a decorated list row. Other
explicit-return array routes containing newly supported erased aggregates retain
their existing consumer behavior; this slice does not normalize every grid,
tab, navigation, or auxiliary-content array. These are remaining compatibility
limits, not exceptions to the project's native API goal. The existing depth and
mounted-lifecycle tests still apply unchanged.

## Migration from Windows array helpers

The former builder inferred `[AnyView]` for almost every expression. That
unconstrained return shape conflicts with native concrete-body inference and is
not preserved as the default. Contextual legacy adapters remain where they are
unambiguous; the historical explicit-array helper prefix operations are
unchanged. Typed finalization and row normalization introduce their own scopes;
identity paths are not promised to be byte-for-byte equal across library
upgrades. Surviving logical occurrences within a running hierarchy retain the
same paths when siblings disappear or keyed data reorders.

| Direct Windows call | Inferred result now | Explicit array route |
| --- | --- | --- |
| `buildExpression(Text(...))` | `Text` | `let rows: [AnyView] = ViewBuilder.buildExpression(Text(...))` |
| `buildExpression(ForEach(...))` | The concrete `ForEach` | An explicit `[AnyView]` result selects the existing content adapter. |
| `buildBlock()` | `EmptyView` | `let rows: [AnyView] = ViewBuilder.buildBlock()` uses the disfavored array variadic adapter. |
| `buildBlock(Text(...), Text(...))` | Flat typed `TupleView` | Use `@ViewBuilder () -> [AnyView]` finalization or pass explicit arrays to the legacy block helper. |
| `buildExpression(existingRows)` | `_ViewBuilderArrayExpression` | An explicit `[AnyView]` result selects the historical occurrence-decorating adapter. |
| `buildBlock(existingRows)` | `[AnyView]` | The exact single-array helper and its old slot/occurrence rules remain. |
| Array-input Optional/Either/Array/LimitedAvailability | `[AnyView]` | Existing direct array helpers retain their return type and prefix behavior. |
| `buildExpression(())` | `EmptyView` | An explicit `[AnyView]` result remains an empty array. |

For example, code that called `ViewBuilder.buildExpression(Text(...))` and then
indexed the inferred result should add its intended `[AnyView]` result type or
use an array-returning builder closure. Normal application view bodies should
retain their typed result instead of relying on the Windows helper return shape.
Explicit-return arrays and ordinary closures remain ordinary Swift values;
neither is silently transformed at the return statement.

Raw array expressions, Void expressions, `for` loops, and the underscored public
array-result protocol and carrier types are Windows compatibility extensions.
They are not evidence of native SwiftUI API conformance. The loop carrier assigns
iteration identity before dropping empty iterations. The array carrier allows
the same stored rows to pass through typed and array-returning contexts without
an `AnyView`-to-`Body` cast or a special overload on every control.

## Explicit Windows array builder

`WindowsArrayViewBuilder` preserves the former fixed `[AnyView]` builder as an
explicit Windows extension. Expressions are erased before block and loop
assembly. Its empty block, raw-array and Void expressions, optional/either
branches, loops, availability, and `ForEach` expression expansion retain the
historical array helpers and their occurrence, original slot, and iteration
prefix operations. Its block operation shares the same internal helper as the
canonical builder's explicit array compatibility overloads.

This is an explicit source migration for Windows array authoring, not a fix to
generic canonical opaque loops. With the recorded Swift 6.3 compiler, opaque
modifier/factory results inside canonical `for` bodies can fail while the
compiler infers the synthesized iteration array, before `buildArray` is called.
Contextual `[AnyView]` finalization after the block does not repair that earlier
inference step. The canonical concrete `Text`/tuple/body rules and the builders
on public controls remain unchanged. Native ViewBuilder does not declare
`buildArray`; ordinary `for` loops are a Windows extension.

For example, an existing Windows array helper can opt in at its own boundary:

```swift
@MainActor
@WindowsArrayViewBuilder
func windowsRows(values: [Int]) -> [AnyView] {
    for value in values {
        Text("Row \(value)").frame(height: 24)
    }
}

struct WindowsRowsBody: View {
    let values: [Int]

    var body: some View {
        VStack {
            windowsRows(values: values)
        }
    }
}
```

The helper now explicitly returns an array; it does not retain a generic
canonical loop result type. Its array can be inserted into an unchanged
canonical body through `_ViewBuilderArrayExpression`. The Windows annotation
applies only to that lexical body or closure. It does not change a nested
`VStack`, `Group`, `ForEach`, or other control's canonical builder, so an opaque
loop written inside such a nested closure can still encounter the limitation.
No shared demo source or public control builder is switched to this extension.

The old array prefix algorithm is retained inside the helper. Inserting that
array through canonical projection adds the adapter's type/content and array
scopes. This is not a promise of identical State identity across an API
migration; rendering and declared mounts must still agree within the resulting
hierarchy. Known structures retain the existing selected-leaf mount gateway,
declaration exclusions, and metadata wrappers. There is no new State registry
or body-discovery mechanism.

The three known canonical opaque-loop failures are preserved outside SwiftPM
targets in [the negative compile fixture](../Tests/CompileFixtures/ViewBuilder/README.md).
Its expected diagnostics require the exact three intended source locations,
not merely a nonzero compiler exit. The actual-module probe needs explicit
module, Clang, and SDK inputs from the integrated build and is separate from
the saved standalone model evidence.

## Validation boundaries

`CanonicalViewBuilderPublicTests` contains public-import fixtures for inherited
concrete/opaque/multiple bodies, control flow, generic and deferred consumers,
flat packs, explicit returns, primitive/default bodies, current tuple mutation,
and retained rendering. `CanonicalViewBuilderArrayCompatibilityTests` separates
the Windows helper and unsupported-value cases. The test assertion scaffold is
Windows-specific; it is not a paired native compilation harness.

`CanonicalViewBuilderMountedTests` exercises actual window-host State,
installation, reconciliation, geometry, and inactive known declarations.
`CanonicalViewBuilderMetadataTests` exercises real row wrappers, tags, editing
callbacks, typed keys, and scroll targets. `ViewListProjectionTests` covers the
cursor, deferred body construction, current exclusions, and iterative expansion.
The existing structural, State, list, scroll, and traversal-depth suites remain
required in addition to these fixtures.

`WindowsArrayViewBuilderTests`, `WindowsArrayViewBuilderMountedTests`, and
`WindowsArrayViewBuilderMetadataTests` separate the explicit Windows migration
from canonical builder coverage. They author opaque factory/modifier and loop
cases, direct array helper shapes, literal prefix rules, canonical insertion,
mounted State/reorder/declaration behavior, and actual List/ForEach metadata
ownership. The existing structural helper changes only its explicit builder
annotation; the migrated opaque-loop case retains its loop bodies and semantic
assertions and is named as a Windows migration. Neither those changes nor the
standalone typecheck/SIL evidence count as execution of the runtime tests.

The saved 201-check standalone model was design evidence only. Captured native
SDK interface bytes from failed, unreviewed capture `33110144606` informed the
native-first signatures; they do not prove a successful SDK capture, paired
native compilation, layout equivalence, or completion of the compatibility
goal. Repository compilation and runtime validation are distinct from source
review and must be recorded with the integrated revision.
