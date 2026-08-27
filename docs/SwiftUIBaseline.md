# SwiftUI desktop compatibility baseline

The compatibility destination in [`goal.md`](../goal.md) is pinned to the
complete public desktop SwiftUI surface in the **macOS 26.5 SDK supplied with
Xcode 26.6**, including SwiftUICore and its re-exports through SwiftUI. This is
an audit baseline, not a claim that this repository implements that surface.
The other rendering, template, integration, performance, accessibility, and
delivery requirements in the goal remain unchanged.

[`swiftui-baseline.json`](swiftui-baseline.json) is the machine-readable scope
and provenance manifest. Apple lists Xcode 26.6 with the macOS 26.5 SDK and
Swift 6.3 in its [SDK requirements](https://developer.apple.com/xcode/system-requirements)
and [Xcode release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-26_6-release-notes).
These are fixed release versions, not an instruction to follow the latest SDK.

| Dimension | Pinned value or current evidence |
| --- | --- |
| Public modules | SwiftUI and SwiftUICore; all exported graph partitions |
| SDK | macOS 26.5 from Xcode 26.6 |
| Compiler | Apple Swift 6.3 from that installation's XcodeDefault toolchain; Swift 6 language mode |
| Extraction targets | `arm64-apple-macosx26.5` and `x86_64-apple-macosx26.5` |
| Package deployment minimum | macOS 15; this does not limit the API audit to macOS 15 |
| Exact Xcode build, SDK build, compiler build string | Awaiting actual capture and review; deliberately null in the manifest |
| Native reference OS build | Awaiting qualification; not implied by the SDK version or export host |
| API inventory review and behavior conformance | Not completed by an export; tracked separately |

No SDK count, build identifier, hash, or conformance result may be filled from
an estimate. An empty exception list grants no platform-service exceptions.
Missing exported declarations, partial implementations, no-ops, and adapters
still require audit against the full goal; an inventory omission does not
remove them from scope.

## Capture on the pinned Mac

Install the stated Xcode release and PowerShell 7, then run the exporter from
the repository root in `pwsh`. Xcode 26.6 requires macOS Tahoe 26.2 or later,
according to Apple's requirements above. The exporter does not download
Xcode, accept licenses, change the machine's selected Xcode, invoke SwiftPM,
or modify the manifest. First-launch or license errors must be resolved on
the reference machine; a different toolchain is not an automatic fallback.

```powershell
# Use the actual installed path. This affects this PowerShell process only.
$env:DEVELOPER_DIR = "/Applications/Xcode_26.6.app/Contents/Developer"
pwsh -NoProfile -File scripts/export-swiftui-baseline.ps1

# Optional: select an empty evidence directory under artifacts/ or OS temp.
pwsh -NoProfile -File scripts/export-swiftui-baseline.ps1 `
    -OutputPath ./artifacts/swiftui-baseline/xcode-26.6-candidate
```

Windows PowerShell cannot export Apple's SwiftUI module. The script fails
before creating an output directory on unsupported hosts, wrong Xcode/SDK
versions, or a nonmatching compiler. It uses the selected XcodeDefault
compiler and extractor directly, passes arguments without a shell, and
extracts the four module/architecture combinations serially with an isolated
module cache. It never shares the repository's `.build` directory.

The initial matching-version capture remains an **unreviewed candidate**.
Release numbers alone do not establish an exact reviewed Apple build. Review
the observed Xcode/SDK/compiler identifiers and raw evidence, then explicitly
record those identifiers in `reviewedIdentity` and set its status to
`reviewed`. Do not invent identifiers to enable the strict mode. Later runs
can require that reviewed identity:

```powershell
pwsh -NoProfile -File scripts/export-swiftui-baseline.ps1 -RequireReviewedIdentity
```

Any populated identity pin is checked even without that switch. The switch
also rejects pending identity review. Neither mode edits the manifest,
approves new SDK versions, or marks conformance complete.

## Candidate capture in GitHub Actions

The [SwiftUI baseline candidate capture workflow](../.github/workflows/swiftui-baseline-capture.yml)
can be dispatched manually. It also runs on pushes to `main` that change its
workflow file, `.gitmodules`, `scripts/export-swiftui-baseline.ps1`,
`scripts/swiftui-baseline-common.ps1`, `scripts/test-checkout-metadata.ps1`,
or `docs/swiftui-baseline.json`.
General Swift source changes do not trigger this capture.

Checkout keeps `persist-credentials: false` and `submodules: false`. The
read-only `extern/zed` gitlink has its verified upstream mapping in
`.gitmodules`; the capture job never initializes or builds that reference.
`scripts/test-checkout-metadata.ps1` reproduces the missing-mapping failure
and verifies cleanup with the mapping in an isolated, uninitialized fixture.
Run it with `pwsh -NoProfile -File scripts/test-checkout-metadata.ps1`, or
Windows PowerShell using the repository's usual script invocation.

One `macos-26-intel` job uses PowerShell and explicitly selects
`/Applications/Xcode_26.6.app/Contents/Developer` through `DEVELOPER_DIR`.
The [published Intel runner inventory](https://github.com/actions/runner-images/blob/b9af839509d3aedd01d80a5ebcb46e1b7896e0e3/images/macos/macos-26-Readme.md)
lists this installation, the macOS 26.5 SDK, and PowerShell 7. That inventory
establishes availability, not an actual capture or reviewed build identity.
The job has a 90-minute limit and runs the existing exporter's four
module/architecture combinations serially. It does not install another
toolchain, invoke SwiftPM, or change the separate macOS reference-render
workflow.

Download the run's
`swiftui-macos-26.5-xcode-26.6-candidate-<run-id>-<attempt>` artifact before
its 30-day retention expires. Its `ci-context.json` records the actual
checked-out commit, requested manifest hash, workflow/run/attempt, runner
image and architecture, selected developer directory, and capture outcome.
The `capture/` directory contains the exporter's evidence described below.
The upload step runs even after failure and excludes only the disposable
`capture/module-cache/`; it never converts a failed capture into success.
A missing installation or wrong version fails the job without substituting
another SDK. Early failures can leave only the CI context, while interrupted
or failed captures are not complete evidence.

The workflow deliberately creates an **unreviewed candidate** and does not
pass `-RequireReviewedIdentity` while initial identity review is pending.
Any populated identity pins are still enforced by the exporter. It never
edits `reviewedIdentity`, fills build identifiers from a runner inventory,
or promotes conformance status. Review the actual capture identifiers,
hashes, raw graph partitions, public interfaces, and overlay definitions
before recording reviewed identity; then require that identity on subsequent
verification runs. Candidate export does not prove API audit completeness,
native behavior, visual parity, or release qualification.

## Evidence and preservation rules

Each run defaults to a new timestamped directory under
`artifacts/swiftui-baseline/`. Existing nonempty directories are rejected;
failed captures remain marked `failed` in `capture-status.json`. They are not
complete evidence and must not replace a reviewed capture.

| Artifact | Meaning |
| --- | --- |
| `baseline-manifest.json` | Unmodified copy of the requested scope and identity pins |
| `capture.json`, `capture.sha256` | Observed Xcode/SDK/compiler and host builds, tool hashes, exact native arguments/results, interface and inventory hashes, and explicit unqualified status |
| `SDKSettings.json` or `SDKSettings.plist` | SDK identity metadata copied and hashed from the selected installation; this is not a hash of the entire SDK |
| `graphs/<target>/<module>/*.symbols.json` | All raw compiler graphs, including extension partitions such as `SwiftUI@Foundation.symbols.json` |
| `interfaces/<module>/*.swiftinterface` | Public textual interfaces, unchanged and individually hashed; private and package interfaces are not copied |
| `cross-imports/<module>/` | Any `.swiftoverlay` declaration files found under those frameworks' module directories, copied and hashed for subsequent audit |
| `inventory.json` | Deterministic index by case-sensitive `identifier.precise`, with every target/module occurrence and raw graph location retained |
| `module-cache/` | Disposable extraction cache, not conformance evidence |

The exporter requests public symbols, extension blocks, and the SwiftUI /
SwiftUICore re-export relationship. It does not enable SPI, suppress
synthesized members or protocol implementations, filter underscore-prefixed
public names, or strip availability domains. The extraction flags are
defined by the [Swift 6.3 compiler](https://raw.githubusercontent.com/swiftlang/swift/swift-6.3-RELEASE/include/swift/Option/Options.td).
If an extraction option fails, the run fails; it does not retry with a reduced
surface.

The index distinguishes overloads by precise identifiers rather than display
names. Re-exported declarations retain all occurrences instead of overwriting
their declaring-module evidence. Availability entries, extension ownership,
generic constraints, and relationships to external modules are retained.
Every raw graph remains authoritative for metadata not projected into the
index. `graphSetSha256` hashes the ordinally sorted sequence of each relative
graph path, a tab, its lowercase SHA-256, and a newline; it identifies those
exact files, not a universal semantic hash across compiler installations.

Public interface import records include exported attributes and public
signature imports as different facts. Conditional compilation is deliberately
not evaluated by the small import index; surrounding conditions and complete
declarations remain in the original interface. Referenced Foundation or
other external modules are not erased from relationships. Their complete
APIs are not silently relabeled as declarations owned by SwiftUI.

## Inventory is not conformance

A successful compiler export proves that the selected toolchain produced
those files. It does not prove the graph generator includes every public
overload, conditional declaration, macro, synthesized requirement, or
platform adaptation needed by the goal. Reconcile the graph union with the
captured public interfaces and Apple documentation before declaring the API
audit complete. Document discrepancies rather than discarding them.

The [pinned extractor implementation](https://github.com/swiftlang/swift/blob/swift-6.3-RELEASE/lib/DriverTool/swift_symbolgraph_extract_main.cpp)
can silently skip cross-import overlay modules that fail to load. Verbose
command output records the modules it did emit, and captured overlay
declarations provide another audit input. Neither exit code zero nor an empty
overlay-definition list proves that all cross-import combinations were
covered. Their completeness remains explicitly unverified in the inventory
and capture records until reviewed against the SDK and public interfaces.

For each audited declaration or behavior, later conformance records must
identify its precise symbol/overload, public availability, relevant reference
behavior, implementation path, and semantic/interaction/accessibility/visual
test evidence. Compilation alone cannot promote a shim or ignored argument
to implemented. Exact native reference OS builds, fonts, appearance,
geometry, and fixture provenance belong with the behavior evidence.

The existing macOS reference workflow currently chooses an installed
compatible Xcode and refreshes its renders weekly. It remains useful for
exploration, but does not establish this fixed SDK or a qualified visual
reference. This exporter leaves that workflow unchanged. Native macOS
conformance execution, Windows comparisons, and release qualification remain
separate unfulfilled gates until their actual evidence is recorded.

## Standalone tooling tests

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-swiftui-baseline.ps1
# PowerShell 7, including on macOS:
pwsh -NoProfile -File scripts/test-swiftui-baseline.ps1
```

These tests use explicitly synthetic JSON and interface fixtures under
`scripts/fixtures/swiftui-baseline/`. They check version/build rejection,
pending review, module and architecture completeness, precise identifier
case sensitivity, overload/re-export preservation, extension relationships,
availability metadata, deterministic indexing, hashes, malformed input, and
the unsupported-host guard. Generated test evidence stays under `artifacts/`.
Passing these tests is not an Apple SDK capture or a SwiftUI conformance run.
