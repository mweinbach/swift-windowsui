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
`scripts/swiftui-baseline-common.ps1`, `scripts/swiftui-baseline-streaming.ps1`,
their baseline fixture tests and fixture data, `scripts/test-checkout-metadata.ps1`,
or `docs/swiftui-baseline.json`. The job runs the checkout and inventory fixtures
before exporting; changes to ordinary Swift source do not trigger this capture.
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

An `arm64` target can appear as `aarch64` in a serialized module's graph.
The validator accepts those two exact spellings only for the requested
`arm64` architecture; `x86_64` must still match exactly. It preserves the
observed module metadata and the full requested target rather than rewriting
either. LLVM defines that specific [architecture alias](https://github.com/swiftlang/llvm-project/blob/swift-6.3-RELEASE/llvm/lib/TargetParser/Triple.cpp#L429),
and Swift writes the [module triple's architecture name](https://github.com/swiftlang/swift/blob/swift-6.3-RELEASE/lib/SymbolGraphGen/JSON.cpp#L45).
This does not admit `arm64e`, `arm64ec`, another SDK, or another target.

### Inventory memory and failure behavior

SDK symbol graphs can exceed the size of a single CLR string. The exporter
therefore uses `Write-SwiftUIBaselineInventory`, which returns a compact
summary and writes the complete index directly to disk. It never reads a
whole graph or the final inventory into `ConvertFrom-Json`, and never sends
the complete inventory to `ConvertTo-Json`. The object-returning
`New-SwiftUIBaselineInventory` convenience function is limited to small
synthetic fixtures of at most 16 MiB; it is not the SDK export path.

`swiftui-baseline-streaming.ps1` compiles the same embedded C# implementation
with PowerShell's standard `Add-Type` on Windows PowerShell 5.1 and PowerShell
7. It uses no Python package, downloaded assembly, or private runtime path.
Native SDK export still requires PowerShell 7 on macOS. The reader validates
UTF-8 JSON a record at a time and retains nested JSON values without numeric
conversion, special treatment of `__type`, or loss of null/empty arrays.
Unknown root values are validated and skipped without materialization; their
complete bytes remain in the authoritative raw graph.

Declaration payloads and relationships are spooled to a new, owned scratch
directory beside the output. Bounded sort runs contain decoded precise
identifiers, 64-bit source sequences, and 64-bit payload offsets, not all
declaration objects. Runs merge using ordinal identifier order and original
occurrence order. The final writer streams even a single identifier's long
occurrence list. Metadata, relationships, availability, extension data, and
the existing inventory schema remain intact. Raw SHA-256 hashes cover the
same bytes parsed, including a UTF-8 BOM and trailing whitespace.

The defaults are a 16 MiB estimated index buffer, at most 16 open merge
readers, and 33,554,432 source characters per retained JSON record. A single
identifier larger than the sort buffer is handled as one bounded record.
Memory depends on these buffers, the largest retained record/identifier, and
the graph file list, not the total declaration count or graph byte size.
There is no total SDK size or declaration-count cutoff. JSON nesting beyond
256 levels and records beyond the explicit record budget fail with an error;
the exporter does not truncate fields or retry with a smaller API surface.
The `InventorySortChunkBytes`, `InventoryMergeFanIn`, and
`InventoryMaximumRecordCharacters` exporter parameters expose the resource
budgets without changing SDK pins or scope.

The final inventory is published only after parsing, sorting, writing, and
hashing succeed. Existing output files are never overwritten, and failures
remove only the invocation's owned scratch directory. If cleanup also fails,
the original error is retained with the cleanup error. `capture.json` records
the indexing runtime, source digest, budgets and measured record/sort counts;
`exporterSources` also hashes the streaming script. None of these statistics
promotes the inventory to API completeness or behavior conformance.

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

The [first API audit stage](SwiftUIAPIAudit.md) can seed an immutable,
unreviewed ledger from a successful, hash-verified candidate. It streams full
raw records and retains every identity and occurrence; its family queues do
not filter the ledger. Windows declaration mapping, interface/overlay review,
and behavioral conformance remain separate work. A locally reindexed failed
capture cannot be used as an official audit input.

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

# Optional scale regression: a synthetic graph larger than 1 GiB, with an
# 80,003-occurrence identifier. Allow about 5 GiB of free artifact space.
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-swiftui-baseline-memory.ps1 -Large
pwsh -NoProfile -File scripts/test-swiftui-baseline-memory.ps1 -Large

# Benchmark an already downloaded, read-only capture. Output goes to a new
# artifacts directory outside the capture; the source status is not changed.
pwsh -NoProfile -File scripts/measure-swiftui-baseline-inventory.ps1 `
    -CaptureRoot ./artifacts/downloaded-candidate/capture
```

These tests use explicitly synthetic JSON and interface fixtures under
`scripts/fixtures/swiftui-baseline/` and generated records. They check version/build rejection,
pending review, module and architecture completeness, precise identifier
case sensitivity, overload/re-export preservation, extension relationships,
availability metadata, deterministic indexing, hashes, malformed input, and
the unsupported-host guard. Streaming tests force multiple merge passes,
Unicode across buffer boundaries, numeric preservation, 64-bit run records,
output collision and error cleanup. A fresh PowerShell child process runs
the memory regression with a measured peak working set ceiling of 768 MiB;
the default fixture is small, while `-Large` exercises the original
whole-string failure and a long occurrence group. Generated test evidence
stays under `artifacts/`.
Passing these tests is not an Apple SDK capture or a SwiftUI conformance run.

Peak memory is the current benchmark process's kernel peak, not its final
working set or a sample of other processes. On macOS, where the [.NET process
implementation does not populate its peak field](https://github.com/dotnet/runtime/blob/v10.0.0/src/libraries/System.Diagnostics.Process/src/System/Diagnostics/ProcessManager.OSX.cs#L60-L67),
the adapter calls public `getrusage(RUSAGE_SELF)` in the system library.
The Darwin 64-bit [rusage layout](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/sys/resource.h#L139-L178)
is 144 bytes with `ru_maxrss` at byte 32. The [kernel assigns peak resident size](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/kern_resource.c#L1694)
in [bytes](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/mach/task_info.h#L296-L307),
so no Linux-style KiB multiplier is applied. Reports identify the metric,
units and process scope, leave unsupported Mac paged/private metrics null,
and fail if a true positive peak cannot be obtained. ABI tests on Windows
do not constitute native execution of the Darwin call; the macOS workflow
must exercise that branch on its actual host.

`measure-swiftui-baseline-inventory.ps1` runs on either supported PowerShell
runtime and records elapsed time, process memory, counts, source graph hashes
and the output hash in `benchmark.json`. Reindexing a failed capture produces
local benchmark evidence only. It does not manufacture a successful native
`capture.json`, modify `capture-status.json`, review the observed identity,
reconcile interfaces/overlays, or change the pinned baseline manifest.
Source and output ancestors are resolved before the containment check,
including Windows junctions and macOS aliases such as `/tmp` to `/private/tmp`.
Output through an alias into the capture is rejected before writing.
