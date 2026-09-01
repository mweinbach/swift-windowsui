# Overlay probe planning

Stage B adds a separate, bounded path from the Stage A filesystem census to
native import observations and supplemental symbol graphs. Planning is not an
SDK census, an API absence decision, or a compatibility qualification. The
original SwiftUI/SwiftUICore desktop scope, both macOS 26.5 targets, baseline
identity pins, nine audit streams, and completion gates are unchanged.

`scripts/swiftui-overlay-probe-intake.ps1` reads an existing successful capture,
its complete API ledger, and the sealed Stage A discovery report. The public
reader rejects synthetic or incomplete inputs. It reuses the existing strict
capture and census readers, then streams and semantically joins every discovery
record. The joins preserve exact definition occurrences, filesystem aliases,
ordered duplicate overlay names, target candidates, module context records,
directory completion, and source seals. Raw definition bytes are parsed again;
matching a filename or a saved summary does not replace this verification.

Every selected source directory and raw file must have the matching recorded
occurrence. Unclassified module contexts remain unresolved. Module maps are
retained as source evidence; they are not relocated or executed because relative
header and search paths would change meaning. Regular file checks precede opens,
including metadata preflight before older capture readers. These checks are
observations, not atomic filesystem isolation.

An explicit plan is a new UTF-8 JSON file, at most 1 MiB, with these fields:

| Field | Required meaning |
| --- | --- |
| `schemaVersion`, `evidenceKind` | `1`, `swiftui-overlay-probe-plan` |
| `sourceArtifacts` | Exact hashes of capture manifest, capture status, audit manifest, baseline manifest, inventory, graph set, discovery manifest, and root plan |
| `nativeProfileSha256` | An explicitly selected, separately recorded native tool profile; never an inferred executable |
| `languageMode` | `6` |
| `targetContexts` | Both `arm64-apple-macosx26.5` and `x86_64-apple-macosx26.5` for each explicitly selected C++ mode, with `targetVariant: null` |
| `pairs` | One to four exact definition occurrences and their original candidate IDs and ordered overlay-name occurrences |
| `limits` | Positive `maximumDefinitionPairs` at most 4 and `maximumDistinctOverlayModules` at most 16 |

Each pair records `pairId`, `definitionOccurrenceId`, `rawDefinitionSha256`,
`declaringModule`, `bystanderModule`, `overlayNameOccurrences`, and
`sourceCandidateIds`. The pair ID is the existing length-prefixed SHA-256 ID of
`('probe-pair', definitionOccurrenceId)`. Each name occurrence is `{index, name}`;
duplicate names and their indices are retained. The two candidate IDs must refer
to this definition on the two pinned targets. Declaring and bystander names must
match the non-null Stage A context exactly. Native-selected names are bounded
ASCII module identifiers, at most 128 characters, excluding bare `_`. Source
fragments, custom arguments, search paths, and unknown fields are rejected.

`cxxInteroperabilityMode` is explicitly `off` or `default`. Selecting a mode does
not imply it was tested or that C++ support is complete. Selecting an empty
`modules: []` definition preserves that observation with native load evidence
`not-performed`; it cannot establish API absence. Unselected candidates retain
an explicit `unselected` disposition, not `not applicable`.

The source-only planning entry points are:

```powershell
. ./scripts/swiftui-overlay-probe-intake.ps1
$inputs = Read-SwiftUIOverlayProbeInputs -CaptureRoot $capture -AuditRoot $audit `
    -DiscoveryRoot $discovery -ExpectedDiscoverySha256 $discoverySha
$selection = Read-SwiftUIOverlayProbePlan -Path $plan -ExpectedSha256 $planSha `
    -Inputs $inputs
```

The plan reader rereads the original sealed inputs and returns that canonical
context as `selection.inputs`. Mutating previously returned PowerShell objects
cannot remove an unselected occurrence or change a selected module association.
No compiler, SwiftPM command, or native workload runs from these functions.

The synthetic test suite uses actual strict JSON, NDJSON, definition, inventory,
and saved census readers with explicitly marked synthetic fixtures. An internal
test seam can construct synthetic inputs; the public entry points do not accept
that switch. PowerShell 7 may initialize the existing managed streaming helper
with in-process `Add-Type`; this does not launch an external compiler or native
SDK workload. Passing these tooling tests is not Apple SDK evidence.

The Stage A definition grammar and module-context rules are still an explicit
tooling profile, not a proven complete description of Apple SDK semantics.
Unknown syntax, ambiguous contexts, unavailable roots, and unsupported names
remain unresolved or fail intake; they do not create scope exceptions. Actual
Apple SDK capture and parser comparison are still required.

Authenticated, successful native capture remains a separate execution step.
Neither this plan nor source-confirmed compiler behavior closes baseline
identity review, overlay coverage, declaration review, or behavior conformance.

## Native collection

`scripts/capture-swiftui-overlay-probes.ps1` is a separate macOS/PowerShell 7
entry point. Source approval and passing synthetic tests do not authorize a
native run. No workflow calls it automatically, and the existing Stage A
workflow is unchanged. The entry point refuses Windows before it reads an SDK
path or creates output. A successful, authentic Stage A census must already
exist; old failed captures and synthetic fixtures cannot enter this path.

Collection has two explicit steps. `-PrepareNativeProfile` reads the existing
sealed inputs, hashes the separately named frontend and the captured extractor,
SDK settings, and interfaces, then writes `native-profile.json` and its SHA-256
sidecar. It executes no Swift command, including no frontend version command.
The recorded extractor identity remains labeled as capture metadata, rather
than being reused as an observation of the separately named frontend.

```powershell
./scripts/capture-swiftui-overlay-probes.ps1 -PrepareNativeProfile `
    -CaptureRoot $capture -AuditRoot $audit -DiscoveryRoot $discovery `
    -ExpectedDiscoverySha256 $discoverySha `
    -FrontendPath /Applications/Xcode_26.6.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift-frontend `
    -OutputDirectory $freshProfileDirectory
```

Select the returned profile hash in the reviewed probe plan. The collection
call requires the exact plan hash and that same profile file:

```powershell
./scripts/capture-swiftui-overlay-probes.ps1 `
    -CaptureRoot $capture -AuditRoot $audit -DiscoveryRoot $discovery `
    -ExpectedDiscoverySha256 $discoverySha `
    -PlanPath $plan -ExpectedPlanSha256 $planSha -NativeProfilePath $nativeProfile `
    -OutputDirectory $freshCollectionDirectory
```

Output must be a new canonical child of repository `artifacts` or the OS temp
directory, outside the capture, census, ledger and live SDK/tool trees. On a Mac,
use the resolved physical temp path, such as `/private/tmp`, rather than an
aliased `/tmp`. There is no overwrite, retry, resume, alternate SDK, alternate
flag profile, or implicit selection of a frontend executable.

Before each native request, the collector rechecks the selected live root
states, including previously observed absence, and the exact physical tool/SDK
anchor bytes. It retains the literal executable, argument array, fixed source,
target, C++ mode, module cache, child environment overrides and source hashes
before entering the process helper. The process launches the selected logical
tool path, preserving its invocation name; canonical paths identify the bytes.
This distinction matters because the public Swift driver selects tool behavior
from the executable basename. The same identities are checked after ordinary
process completion. These observations are not atomic execution attestation.

Every nonempty selected definition runs four import controls per target and
mode: declaring module alone, bystander alone, declaring then bystander, and
bystander then declaring. Imports are generated from a frozen template with
escaped, lexically validated module identifiers. Empty definitions retain their
selected disposition and native load evidence `not-performed`; they launch no
probe. All ordered name occurrences remain in the plan even when one compiler
invocation can observe a repeated module name only once.

The initial diagnostic and trace profile follows public Swift commit
[`aa782beb23b8bd83bd16fca831532a05dd6cea39`](https://github.com/swiftlang/swift/tree/aa782beb23b8bd83bd16fca831532a05dd6cea39).
It has not been qualified against the actual Apple Swift 6.3.3 binary. The pure
helper builds explicit typecheck arguments with cross-import, module-loading,
diagnostic-name and loaded-module-trace flags. It recognizes the fixed search
path dump, cross-import and module-load remarks, and one version-2 trace record.
Unknown flags, diagnostic forms or trace fields make the batch visibly
incomplete; they never select another profile. Raw stdout, stderr and trace
bytes are retained.

An eligible load observation requires a natural zero exit and closed captured
streams, the exact declaring/bystander/overlay trigger, a matching module-load
remark, matching trace membership, and recorded identities for both the source
and loaded paths. Those module bytes must resolve inside selected physical
SDK/resource roots or the request's cache, and are copied into retained
evidence. The trace can name an interface while the remark also names a cached
binary; both identities matter. A trigger alone, a direct import, or a trace's
`isImportedDirectly` flag is insufficient.

The collector never claims which duplicate definition occurrence won module
resolution. A declaring-module-only control can itself activate an overlay
through transitive imports, so even a successful combined control does not
establish that adding the lexical bystander was necessary.

## Supplemental declarations and retained evidence

Eligible combined-control observations can request direct extraction of the
overlay module on that exact target and mode. Extraction is deduplicated by
module/target/mode, using one exact frontend observation as its basis while
retaining every related observation and candidate occurrence separately. The
extractor's re-export allowlist remains exactly `SwiftUI,SwiftUICore`. Direct
extraction does not itself prove cross-import activation.

`scripts/swiftui-overlay-probe-graphs.ps1` is a separate intake and streaming
adapter. It accepts sealed native invocation metadata and a frozen inventory of
every emitted graph partition. It does not create a fake baseline manifest or
relax the original primary-graph guard. Raw graph bytes are authoritative, and
the existing streaming writer retains repeated identifiers, constraints,
relationships, module metadata and bystanders. There is no identifier-count
ceiling. The raw declaring module can differ from the requested overlay;
filenames do not establish ownership.

The collector initially labels every emitted partition `unattributed-emission`.
The adapter can validate separate context-associated roles when supplied, but
does not turn tuple equality into proof of a unique physical emitter. Unknown
automatic overlays and non-underscore modules remain retained and unreviewed.
An empty, clean extraction is recorded as `no-public-graph-observed`, not proof
that the public API is empty or the census complete.

The collection retains the plan, native profile, collector/helper source files,
per-request launch and closure receipts, fixed import sources, bounded raw
diagnostics and traces, copied module identities, and the supplemental report.
`Read-SwiftUIOverlayProbeReport` checks an external expected report hash, its
sidecar, exact retained payload membership, plan-derived request coverage,
literal arguments, source/tool identities, process and stop-barrier accounting,
raw positive observation replay, and supplemental producer bindings. It reads
relocated retained evidence without opening recorded SDK paths. This is file
and semantic verification, not independent proof that a native process ran.

`probe-report.json` and its SHA-256 sidecar seal the retained payload. The
`.in-progress` marker concerns publication only. A sealed failed report still
retains its process uncertainty. `.work` is explicitly unsealed and disposable:
it contains compiler caches and original trace/graph outputs. Only copied and
sealed artifacts are admitted as retained evidence.

| Limit | Initial profile |
| --- | --- |
| Native requests | At most 64 import controls and 64 direct extractions |
| Request timeout | At most 120 seconds, shortened by the remaining batch launch budget |
| Batch launch budget | 1,200 seconds; later verification is not a hard wall-clock deadline |
| Captured stdout plus stderr | 8 MiB per request |
| Retained trace | 8 MiB per request |
| Copied module identity | 1 GiB per file, 8 GiB reserved per batch, including failed partial copies |
| Supplemental graphs | 4,096 files, 1 GiB per graph, 8 GiB total |
| Graph streaming | 16 MiB sort chunks, fan-in 16, 32 MiB maximum record; temporary sort output needs additional disk |
| Retained collection | 16,384 files and 32 GiB total; report JSON at most 16 MiB |

The file-size limits are counted retention and completed-output checks, not
hard OS disk caps on a running compiler, its cache, its trace or graph output.
The native process inherits its environment apart from recorded child-specific
overrides. No filesystem sandbox, memory quota, whole-SDK byte identity or
independent descendant census is established.

Natural exit with drained streams records `descendantsClosed: null`. Timeout,
output-limit termination, uncertain launch/exit, or cleanup uncertainty stops
all remaining native commands. This profile has no resume protocol, even if
the owned parent later appears closed. An operator must establish descendant
closure before separately authorizing another native command. Compiler
rejections and unsupported evidence also stop the batch without fallback.

Synthetic intake, native-parser, collector and graph suites exercise real
strict readers and streaming code with owned fixtures. Windows tests of the
complete report can use separately constructed, clearly labeled relocated
Mac-shaped fixtures to test POSIX recorded arguments; these are not native
capture artifacts. Neither those tests nor source review qualifies real macOS
filesystem behavior, native process cleanup, Apple parser semantics, SDK
coverage, declaration review, or runtime behavior.

The public-source details used by this profile are documented in
[cross-import trace tests](https://github.com/swiftlang/swift/blob/aa782beb23b8bd83bd16fca831532a05dd6cea39/test/CrossImport/module-trace.swift),
[loaded-module trace emission](https://github.com/swiftlang/swift/blob/aa782beb23b8bd83bd16fca831532a05dd6cea39/lib/FrontendTool/LoadedModuleTrace.cpp),
[symbol graph extraction](https://github.com/swiftlang/swift/blob/aa782beb23b8bd83bd16fca831532a05dd6cea39/lib/DriverTool/swift_symbolgraph_extract_main.cpp),
and [driver dispatch](https://github.com/swiftlang/swift/blob/aa782beb23b8bd83bd16fca831532a05dd6cea39/lib/DriverTool/driver.cpp#L459).
