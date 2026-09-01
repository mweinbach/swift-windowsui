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
