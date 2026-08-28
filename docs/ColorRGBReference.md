# Canonical RGB constructor reference

`swiftui-color-rgb-reference` observes
`Color.init(_:red:green:blue:opacity:)` through the same public constructor
source on Windows and macOS. It compares numeric components, not pixels.
Reports and comparisons remain unreviewed candidates. Neither a successful
build nor matching sampled values qualifies the complete declaration, all
inputs, rendering behavior, or the release goals.

The fixture is separate from the standards-derived tests described in
[ColorSpaceConversion.md](ColorSpaceConversion.md). It contains no RGB transfer
function, primaries matrix, or native expected-color table. Every row binds
`Color.init(_:red:green:blue:opacity:)` to
`(Color.RGBColorSpace, Double, Double, Double, Double) -> Color` and invokes it.
The constructor source differs only in its SwiftUI/WinSwiftUI import.

## Observers and component meaning

The three observers run in separate processes. Each process constructs every
case again; collection records three repetitions per observer.

| Observer | Public operation and recorded values |
| --- | --- |
| `windows-retained` | Construct `WinSwiftUI.Color` and read its public `red`, `green`, `blue`, and `alpha` Float fields. |
| `swiftui-resolved` | Construct native `SwiftUI.Color`, call `resolve(in:)` with explicit light and dark environments, and read `red`, `green`, `blue`, and `opacity`. Record the separate linear RGB getters as diagnostics. |
| `appkit-extended-srgb` | Construct the same native Color, bridge it with `NSColor(color)`, convert with `usingColorSpace(.extendedSRGB)`, then read the four floating-point components with `getComponents`. |

Native [Color.Resolved](https://developer.apple.com/documentation/swiftui/color/resolved)
stores extended linear sRGB. Its public
[red](https://developer.apple.com/documentation/swiftui/color/resolved/red),
[green](https://developer.apple.com/documentation/swiftui/color/resolved/green),
and [blue](https://developer.apple.com/documentation/swiftui/color/resolved/blue)
getters expose encoded sRGB; the `linearRed` family exposes linear values.
The observer reads these documented getters directly. It does not encode the
linear diagnostics with a second copy of the Windows conversion.

The AppKit observer requires the actual converted color space to match
`NSColorSpace.extendedSRGB`, have the RGB model, and expose four components.
It records the actual space name, model, count, and identity comparison. A nil
conversion or unexpected model/identity/count remains an unsupported
observation with its reason and available metadata. The component count is
not read for a non-RGB model. Apple documents
[getComponents](https://developer.apple.com/documentation/appkit/nscolor/getcomponents(_:))
for custom component spaces, while its older `getRed` accessor is restricted
to named RGB spaces. There is no fallback to device RGB, unit sRGB, a PNG, or
the standards formula.

The native observers need no application, visible window, event loop, screen
capture, or system-setting change. The Windows observer is synchronous and
does not rely on native App task scheduling. These properties do not remove
the need to build and execute each observer before treating its results as
evidence.

## Fixed cases and comparison

The protocol has 23 required finite cases and two separately labeled
exploratory P3-input cases. All inputs are Double values; opacity is 0, 0.625,
or 1. Values outside the ordinary unit RGB interval are deliberate finite
controls. This is a fixed sample set, not a claim about every value between
the samples.

| Space | Required RGB samples |
| --- | --- |
| sRGB | Black, white, `(0.25,0.5,0.75)`, and `(-0.5,1.25,2)`; the interior triple also has zero and fractional opacity cases. |
| Linear sRGB | Black, white, `(0.25,0.5,0.75)`, `(0.001,0.0030,0.0032)`, `(-0.001,-0.0030,-0.0032)`, and `(-0.25,0.5,2)`; the interior triple also has zero and fractional opacity cases. |
| Display P3 | Black, white, neutral `(0.5,0.5,0.5)`, interior `(0.1,0.2,0.3)`, and the three unit primaries; P3 red also has zero and fractional opacity cases. |

The two exploratory P3 triples are `(1.2,-0.2,0.5)` and
`(-0.1,-0.2,-0.3)`, with opacity 1. Their output and differences remain in
the report, but do not contribute to required-domain agreement. Apple's
[RGB initializer documentation](https://developer.apple.com/documentation/swiftui/color/init(_:red:green:blue:opacity:))
explicitly discusses extended sRGB and linear-sRGB inputs; the exploratory
rows do not infer an equivalent documented extended-P3 input contract.

NaN, infinity, extreme finite overflow, Float underflow/subnormals, signed-zero
identity, and opacity outside `[0,1]` are excluded. Their existing Windows
policies remain Windows-only policies. The fixture also excludes white/HSB
constructors, dynamic colors, renderer blending/output spaces, and complete
default-argument overload resolution. Windows `Color.Resolved` is not used.

For Windows retained Float values versus native resolved Float values, widen
both to Double and apply the fixed per-component bound:

```text
epsilon = 1.1920928955078125e-7
RGB:   abs(w - n) <= max(2e-6, 16 * epsilon * max(abs(w), abs(n)))
alpha: abs(w - n) <= 2 * epsilon
```

The report retains each absolute difference, bound, original storage type,
and bit pattern. No case, component, environment, or repetition is averaged
away. Every required primary comparison must meet its bound. A tolerance
change requires a new protocol version and review; it is not a way to repair
a failed capture. AppKit agreement uses the same stated bound as a separate
diagnostic and cannot widen or replace the primary comparison.

Native controls check completeness, finite data, black/white distinction,
sRGB identity, linear-getter identity for the linear constructor, extended
sRGB retention, and constant-color light/dark agreement. Clamped, empty,
constant, nonfinite, or unstable native output remains inconclusive. Finite
Windows clipping against a valid native observation is a mismatch, not an
unsupported observer. Alpha pairs are recorded without assuming that native
zero-alpha construction preserves RGB: any resulting disagreement remains
visible rather than being normalized away.

## Collection and provenance

Build and run only when the relevant SwiftPM/build directory is reserved.
Windows collection uses the repository's `with-swift.ps1` environment and the
release `swiftui-color-rgb-reference` product. Native collection requires
PowerShell 7 on the Mac that produced a complete sealed baseline capture.
Both captures require the same clean committed tree, including the fixture
and collection scripts. Hidden Git index flags and extra untracked or ignored
build inputs are rejected. The Windows capture archives the committed build
inputs as well as the five shared fixture files.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/capture-swiftui-color-rgb-reference.ps1 -Platform Windows -OutputPath artifacts/color-rgb/windows-run-001
pwsh -NoProfile -File scripts/capture-swiftui-color-rgb-reference.ps1 -Platform Native -CaptureRoot artifacts/swiftui-baseline/github-actions/capture -OutputPath artifacts/color-rgb/native-run-001
pwsh -NoProfile -File scripts/compare-swiftui-color-rgb-reference.ps1 -WindowsRoot artifacts/color-rgb/windows-run-001 -NativeRoot artifacts/color-rgb/native-run-001 -OutputPath artifacts/color-rgb/comparison-001
```

Output directories must be new. Existing SDK captures, audit streams, review
packets, and comparison results are never overwritten. Use explicit paths;
there is no newest-directory selection or successful-result fallback.

Native collection reuses the baseline capture validator. It requires the
unchanged Xcode 26.6/macOS SDK 26.5/Apple Swift 6.3 policy and records the exact
observed build strings. It typechecks the same source against both pinned
`arm64-apple-macosx26.5` and `x86_64-apple-macosx26.5` targets, then compiles an
optimized executable for the actual native host. Actual execution needs a
compatible macOS 26.5-or-later runtime. Cross-architecture typechecking is
source evidence, not native execution on the other architecture. A translated
process does not count as the requested native-host observation.

Evidence records the source commit/tree, exact compiled source files and
hashes, package configuration where used, baseline/capture hashes, compiler
and frontend identities, command arguments, executable hash, process identity,
OS/build/architecture facts, run nonces, input Double bits, output Float/Double
bits, process outcomes, and report hashes. Source and relevant artifacts are
rechecked after execution. Raw logs remain local evidence; reports never copy
the full process environment or credentials. Exit zero without a valid,
complete, correctly attributed report does not pass collection.

Git blob identity and the SHA-256 of the physical compiled bytes are recorded
separately. A checkout's CRLF-only representation change is explicitly labeled;
it is not reported as an exact Git blob. Comparison still requires identical
physical bytes for all five shared Swift files on both platforms. The existing
`*.swift text eol=lf` repository rule supports that requirement.

A timeout, output-limit error, or unclosed redirected stream stops the
collector with `cleanupComplete = false`; it does not run another command.
In particular, PowerShell 5.1 cannot guarantee descendant-process cleanup
through this collector. A surviving descendant and ownership of the SwiftPM
build directory can remain unknown. That ownership must be resolved before
a retry; the report does not claim automatic cleanup of the process tree.

The report schema is `canonical-rgb-constructor-v1`, case set
`canonical-rgb-finite-23-plus-exploratory-p3-2-v1`. Numeric records preserve
nonfinite classifications and original bit patterns with a null numeric
value; they never write NaN as a JSON number or substitute zero. An unavailable
AppKit conversion therefore differs from a nonfinite result or crashed process.

## Results and API review

The workflow keeps these outcomes separate:

- `match-candidate`: every required valid primary observation agrees within
  the fixed bounds. Declaration, source, behavior, and release claims remain
  unverified until review.
- `mismatch`: valid observations disagree; the exact case/component/repetition
  and difference remain visible.
- `unsupported`: the requested runtime/API/bridge cannot supply the requested
  observation; a native control can also mark its reference inconclusive.
- `failure`: compilation/process errors, timeout/crash, missing or malformed
  evidence, or source/tool/provenance mismatch. Partial evidence is preserved.

AppKit availability/agreement and exploratory P3 rows remain separate even
when the required primary comparison matches. They cannot turn a mismatch
into a pass or populate a missing primary reference.

An optional API association must name an explicit sealed review packet. It
preserves that packet's manifest hash, precise identifier, occurrence tuples
(graph path, symbol index, module and target), Windows commit/blob hashes,
and separate observation/comparison hashes. It does not infer a SwiftUICore
identifier from the SwiftUI spelling, modify the original audit streams, or
advance any review claim. Missing or unreviewed mapping remains explicit.
Pass both `-ReviewPacketRoot` and `-PreciseIdentifier` to request this separate
attachment. The precise identifier must be copied from the sealed native
ledger, and the packet's Windows source candidates must be present in the
captured build inputs. Attachment validation checks the sealed packet's bytes
and explicit source association; it does not repeat the selector's full native
ledger reconciliation or approve the Windows declaration mapping.

`scripts/test-swiftui-color-rgb-reference.ps1` tests report and provenance
rejection, the fixed comparison bounds, negative controls, and separate
outcomes using synthetic files under PowerShell 5.1 and 7. These are tooling
tests; they do not compile Swift, execute a native color constructor, or
provide native color evidence.
