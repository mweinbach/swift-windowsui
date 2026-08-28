# SwiftUI API review units

An API review unit gathers evidence for **one exact exported identifier** from
an existing successful SDK candidate and its sealed stage-1 audit ledger. It
retains every occurrence of that identifier and every relationship whose
source or target is that identifier, while preserving the complete surrounding
context. Selection is case-sensitive; a display name, overload spelling,
prefix, regular expression, or candidate-queue label is not a substitute for
`identifier.precise`.

Creating a unit does not review an API or establish a SwiftUI-to-WinSwiftUI
mapping. Declaration, source, and behavior claims start separately as
`unverified`, with no evidence references. The source ledger and its records
remain `unreviewed`. The pinned desktop SDK scope and every requirement in
[`goal.md`](../goal.md) remain unchanged: a selected unit is a work item, not
an exception for everything outside it.

## Select a unit

Use [`select-swiftui-api-review-unit.ps1`](../scripts/select-swiftui-api-review-unit.ps1)
from a PowerShell 7 or Windows PowerShell 5.1 session. First choose the exact
identifier from `identities.ndjson`, then choose committed Windows source
files to attach as candidates. The script reads those files from a full Git
commit, not from the working tree. It performs no SDK export, Swift build,
source compilation, native reference run, or behavior assessment.

```powershell
$capture = (Resolve-Path ./artifacts/downloaded-successful-candidate/capture).Path
$audit = (Resolve-Path ./artifacts/downloaded-successful-candidate/audit).Path
$windowsRepository = (Resolve-Path .).Path
$windowsCommit = (& git -C $windowsRepository rev-parse --verify 'HEAD^{commit}').Trim()
# Replace this placeholder with one exact identifier copied from the ledger.
$nativeIdentifier = 'COPY_EXACT_IDENTIFIER_FROM_IDENTITIES_NDJSON'

& ./scripts/select-swiftui-api-review-unit.ps1 `
    -CaptureRoot $capture `
    -AuditRoot $audit `
    -PreciseIdentifier $nativeIdentifier `
    -WindowsRepositoryRoot $windowsRepository `
    -WindowsCommit $windowsCommit `
    -WindowsSourcePath @('Sources/WinSwiftUI/Core.swift', 'docs/swiftui-baseline.json') `
    -OutputDirectory (Join-Path $windowsRepository 'artifacts/swiftui-api-review/first-unit')
```

`-WindowsCommit` must identify an actual commit with its complete 40-character
SHA-1 object ID; a branch name, abbreviated hash, blob ID, or SHA-256 repository
format is not accepted in this stage. Installed Git must support
`--no-lazy-fetch`. Unsupported Git or absent local objects fails the operation;
the helper never fetches missing objects from a remote. Source paths
must name regular committed files inside that repository. A directory,
submodule gitlink, symbolic link, missing file, or traversing path cannot
stand in for a source blob. The selected files may be candidates for later
review; their presence alone makes no declaration or source-compatibility
claim. Uncommitted edits are not silently included.

The packet records the observed checkout HEAD and dirty-state details
separately from the requested commit. Partial or unavailable checkout
observations retain their status and error; they do not change the source
binding or imply that the working tree equals the copied commit.

The output must be new and outside both the source capture and audit.
Existing evidence is never overwritten. Omitting `-OutputDirectory` requests
a new generated artifact directory. `-ManifestPath` defaults to the pinned
`docs/swiftui-baseline.json`. The result is a compact descriptor with the
published path, manifest path/hash, and `reviewStatus = "unreviewed"`.

## Evidence and verification

The selector verifies the complete successful capture and sealed audit before
publishing a unit. It does not trust just the requested identifier's rows or
the ledger's declared hashes. Raw graph records are read sequentially and
paired with the ledger records; the original inventory is independently
verified, and the identity index accounts for every occurrence. Corruption
in another identity, relationship, partition, or context stream still fails
selection. Failed captures, reindexed failed exports, incomplete NDJSON,
wrong digests, and missing identifiers are not eligible inputs. Small control
metadata that PowerShell projects into objects also rejects duplicate property
names and case aliases, including nested ones, before PowerShell can silently
choose one value. This rule does not merge or discard distinct keys in raw
SDK settings, native symbol/relationship JSON, or its NDJSON records; their
unknown fields remain preserved.

The packet contains a sealed `review-unit.json` and `review-unit.sha256`, with
these evidence groups:

| Evidence | Purpose |
| --- | --- |
| `native/identity.ndjson` | One exact case-sensitive identity and its occurrence count |
| `native/occurrences.ndjson` | All occurrences, including duplicates, re-exports, architecture variants, and full unknown mixins |
| `native/relationships.ndjson` | Every source/target incident relationship, preserving constraints, external endpoints, and unknown fields |
| Six `context/*.ndjson` streams | Complete `graph-fields`, `partitions`, `inventory-facts`, `interface-facts`, `overlay-facts`, and `candidate-queues` streams from the source ledger |
| `context/source-metadata/` | Complete captured metadata and original interface/overlay bytes copied from the source ledger |
| `context/audit.json`, `context/audit.sha256`, `context/current-expected-baseline-manifest.json` | The original audit seal and the current expected baseline; historical provenance is not replaced with the current tool's identity |
| `windows-source/` | Byte copies of the explicitly selected Git blobs at the pinned Windows commit |

The schema is version 1 with evidence kind `unreviewed-api-review-unit`, status
`awaiting-declaration-source-and-behavior-review`, and `reviewStatus` set to
`unreviewed`. `selection.comparison` is `ordinal-exact`. Complete source-ledger
counts remain under `counts.nativeLedger`; `counts.selected` describes the
one identity and its selected occurrences/incident relationships. Record and
source-metadata tables seal their output paths, sizes, and hashes.

All raw symbol fields remain available, including structured function
signatures, generic and extension context, availability, unknown numeric
values, and case-distinct mixins. Absent, null, and empty values retain their
distinctions. Incident relationships do not prove conformance or witness
selection. Macro and synthesized declarations are not silently dropped.

The complete context remains necessary even for one identifier: an interface
line is not a parsed declaration, conditional imports have not been evaluated,
and an overlay's presence does not prove that all of its declarations were
exported. Interface producer/compiler headers remain separate from the
extractor identity and extraction language mode. Windows Git object IDs and
file hashes identify source bytes, not a compiler result or semantic match.

Declarations present only in interfaces, without an exported precise
identifier, remain unreviewed in that full context. The selector does not
invent identifiers or fall back to names for them. They remain within the
unchanged baseline scope even though this selector cannot select them.

The source raw graphs and complete original ledger remain unchanged and must
be retained alongside the unit. Raw SDK graph files remain authoritative;
the packet is not a new SDK capture or a replacement for the complete original
evidence. Its narrow selection does not reduce the baseline's scope or convert
exported-identity counts into a completed API audit.

## Review boundaries

Declaration, source, and behavior conclusions require independent evidence.
Later declaration review must resolve ownership, exact overloads, generic
conditions, availability, extensions, requirements/default implementations,
macros, and external dependencies. Source review must establish the intended
Windows mapping and compilation behavior at a specified toolchain and commit.
Behavior review needs the relevant native and Windows runtime, visual, input,
accessibility, and error-path evidence. No one of these claims substitutes
for the others.

This first selector attaches no such conclusions. Its `claims` array contains
`declaration`, `source-compatibility`, and `behavior`, each with status
`unverified` and an empty `evidenceRefs` array. The packet's `evidenceReferences`
array is also empty. It never marks an API implemented, compatible, excluded,
reviewed, or release-qualified. Native
successful capture and qualification status are tracked separately in
[`SwiftUIBaseline.md`](SwiftUIBaseline.md) and
[`SwiftUIAPIAudit.md`](SwiftUIAPIAudit.md).

## Resource limits and tests

Selection streams the raw graphs, inventory, ledger records, and occurrence
groups using the shared record reader and disk-backed ordinal index. It does
not load the complete SDK evidence into a JSON DOM. These settings provide
explicit processing bounds:

| Parameter | Default | Bound |
| --- | --- | --- |
| `-MaximumRecordCharacters` | 33,554,432 characters | One JSON record/value, identifier, or source-context line |
| `-MaximumMetadataBytes` | 16,777,216 bytes | An individual control metadata file, including the completed output manifest |
| `-MaximumSourceBytes` | 16,777,216 bytes | Each committed Windows source blob and their combined bytes |
| `-SortChunkBytes` | 16,777,216 bytes | Estimated buffered ordinal-index data before sorting to disk |
| `-MergeFanIn` | 16 | Run readers in an index merge |

These settings do not impose a total native graph/inventory size cutoff or
promise a total process-memory ceiling. Invalid or over-budget input fails
rather than truncating a record or omitting evidence. The selector publishes
only a fully verified packet from a new staging directory; existing
destinations are immutable.

The synthetic regression entry point is:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-swiftui-api-review-unit.ps1
# Or use pwsh -NoProfile -File with the same script.
```

The tests use owned synthetic captures and ledgers, read committed repository
blobs without changing Git history, and mutate only fixture evidence. They
cover exact identity selection, every occurrence and incident relationship,
raw/context preservation, source pins, input immutability, malformed or
inconsistent evidence, metadata duplicates, resource limits, and output
containment. A bounded repeated-identity fixture crosses multiple external
sort runs; it is not a native performance benchmark. No actual native
execution or performance benchmark is supplied by this tooling task. Native
capture, semantic review, behavior conformance, and native performance evidence
remain pending separately.
