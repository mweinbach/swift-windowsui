# Custom progress styles

`ProgressViewStyle` is a public main-actor protocol with a `ViewBuilder` body,
`Configuration` alias, and associated `Body: View`. A custom struct style can
return ordinary views, use the configuration's labels, or delegate through
`ProgressView(configuration)`. The retained implementation compiled and passed
the focused Windows run recorded below. Native comparison and broader release
validation remain pending.

```swift
struct FramedProgressStyle: ProgressViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading) {
            configuration.label
            ProgressView(configuration)
                .labelsHidden()
            configuration.currentValueLabel
        }
        .padding(8)
    }
}

ProgressView("Transfer", value: 0.4)
    .progressViewStyle(FramedProgressStyle())
```

The generic modifier carries a style through the inherited build environment.
It calls the authored style body separately for each consuming progress view;
it does not cache a style's nodes or install one shared state owner for every
control beneath a modifier. A style that returns its own content replaces the
primitive. A style that delegates uses the existing progress renderer.

## Configuration and delegation

`ProgressViewStyleConfiguration` exposes an optional `fractionCompleted` and
separate optional `Label` and `CurrentValueLabel` views. Indeterminate progress
keeps a nil fraction. For finite inputs, the current retained fraction clamps
`value / total` into zero through one, and nonpositive totals produce zero.
Native behavior for boundary inputs is not qualified. Existing primitive
handling of nonfinite values remains unsafe and outside this increment.

The configuration privately retains the original numeric inputs so delegation
does not normalize them a second time. Its public label properties are mutable:
removing or replacing a label in a copy controls what the delegate builds.
Private original label arrays cannot overwrite that change. Labels remain view
sources, not rendered strings or cached nodes. Configuration delegates preserve
different label/current-value identity scopes even when the two sources have
the same concrete view type. Ordinary preexisting progress initializers retain
their existing primitive path; this does not establish general label-ownership
conformance for every old initializer.

Before invoking a custom body, the retained implementation consumes that exact
style installation in a derived environment. A configuration delegate sees the
remaining inherited styles, then the built-in fallback. Repeated installations
of the same concrete style type remain distinct. A new explicit style inside a
body applies within that body's scope, while siblings keep their own inherited
styles. This prevents implicit same-installation recursion; it is not a guard
against deliberately recursive authored view code.

This remaining-chain behavior is a retained candidate contract. Native chained
style behavior, unusual empty-label builders, nested progress controls inside
configuration labels, and full custom-body `labelsHidden` semantics still need
reference characterization. Configuration remains source data and does not
capture a runtime, window, coordinator, node, or original build context.

## Mounted ownership

Supported struct styles install through the same typed dynamic-property helper
as custom views and modifiers. Returned bodies use normal mounted view dispatch.
The consuming control occurrence, concrete style type, and body position form
its ownership path. Same-type rebuilds preserve state; replacing the style type,
removing the occurrence, or closing its host retires that ownership. Reusing a
source style for two controls or hosts does not intentionally share mounted
State. The new tests cover these rules, including discarded candidates and
escaped bindings, and passed in the focused root run recorded below.

The current generic installer requires independently installed structs. Class
and enum style installation remains an explicit framework gap; this increment
does not bypass the installer or silently run owning properties without a mount.
Raw component clients without a coordinator also do not acquire hosted state
lifetime guarantees. Existing reflection and dynamic-property limitations apply.

## Built-in styles and Windows migration

`DefaultProgressViewStyle`, `LinearProgressViewStyle`, and
`CircularProgressViewStyle` conform to the public protocol and expose their
native-shaped `.automatic`, `.linear`, and `.circular` conveniences. Their bodies
reuse the existing progress primitives. `TimerProgressViewStyle` and `.timer`
remain Windows compatibility extensions and do not add timer ticking.

The former concrete struct named `ProgressViewStyle` is now named
`ProgressViewStyleProfile`. It keeps the four fixed profiles and their equality
and Sendable behavior, and it also conforms to the new protocol. Explicit
Windows-only annotations of the old concrete type must use the new profile
name or a concrete style type. Generic APIs can constrain their argument to
`ProgressViewStyle`; existential storage uses `any ProgressViewStyle` where
appropriate.

`EnvironmentValues.progressViewStyle`, its initializer argument, and the
corresponding `ViewBuildContext` property remain Windows compatibility surfaces
whose type is `ProgressViewStyleProfile`. They report the nearest built-in
fallback, not an arbitrary custom style. Existing inferred environment readers
and built-in equality tests keep their meanings. Explicitly assigning a profile
replaces inherited custom installations, even when the assigned profile value
is unchanged; environment copies keep their siblings isolated.

This increment does not supply native generic `ProgressView<Label,
CurrentValueLabel>` syntax, all native constructor/modifier isolation rules,
deprecated tint initializers, Foundation.Progress observation, automatic timer
or indeterminate animation, or full protocol/conformer conformance. Existing
Windows Sendable/Equatable extensions are not native compatibility evidence.
Fully replaced custom bodies control their own accessibility content; defaults
are preserved for configuration delegates, without adding a hidden duplicate
progress control behind arbitrary authored content.

## Validation status

The new source suites are `ProgressViewStyleConfigurationTests`,
`ProgressViewStyleEnvironmentTests`, and `ProgressViewStyleMountedTests`.
They cover custom-body execution, finite values, mutable configuration labels,
style precedence, built-in/profile compatibility, environment inheritance,
normal state lifetime, and rejected stale ownership. Preexisting built-in
appearance, geometry, accessibility, grouped-form, and public-facade tests are
unchanged. Source checks are not runtime qualification.

Root source tree `05759e76c9b0f2bb3c0675efc6a690ba04a9dece` passed one
focused Windows run: 171 XCTest cases (38 new style cases and 133 preserved
regressions), with no failures or skips. Seven serial NONSharded stock calls
completed their normal incremental builds and each reported zero Swift Testing
cases. The complete 5,461-case generated XCTest registry was reconciled; the
5,290 unselected XCTest cases and 134 Swift Testing declarations were not run.
The run record is `artifacts/goal-seventh-progress171-root-v1-exit.json`;
[goal.md](../goal.md) retains the source and audit evidence.

Shared-source macOS compilation, native style behavior, CPU/D3D11 style
comparison, broader Quick/Full validation, and release qualification remain
pending. The pinned SDK candidate is still unreviewed, and every original goal
gate remains unchanged.
