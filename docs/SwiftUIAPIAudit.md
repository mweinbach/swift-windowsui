# SwiftUI API audit ledger

[`build-swiftui-api-audit.ps1`](../scripts/build-swiftui-api-audit.ps1) creates
stage 1 of the API audit: an immutable, entirely **unreviewed** ledger of a
successful candidate capture. It preserves the complete captured scope pinned
in [`swiftui-baseline.json`](swiftui-baseline.json): SwiftUI and SwiftUICore,
both desktop architectures, and every exported graph partition from the macOS
26.5 SDK in Xcode 26.6. It does not export an SDK, build Windows declarations,
parse Swift source, match overloads, assess behavior, or qualify a release.

A fresh successful native capture remains pending. The shared filesystem-root
resolver correction is integrated but awaits native Unix verification. This
ledger tooling, its synthetic fixtures, and local reindexing of earlier raw
graphs do not supply a successful native capture or complete identity review.
Capture prerequisites and provenance remain documented in
[`SwiftUIBaseline.md`](SwiftUIBaseline.md); the destination in
[`goal.md`](../goal.md) is unchanged.

## Run against a successful candidate

Run from the repository root using either PowerShell 7 or Windows PowerShell
5.1. The ledger reads downloaded evidence; it does not invoke Swift, Xcode,
SwiftPM, or a native reference application. The paths below are examples and
must name an actual successful candidate, not the earlier failed capture.

```powershell
pwsh -NoProfile -File scripts/build-swiftui-api-audit.ps1 `
    -CaptureRoot ./artifacts/downloaded-successful-candidate/capture

# Alternative invocation using Windows PowerShell 5.1:
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/build-swiftui-api-audit.ps1 `
    -CaptureRoot ./artifacts/downloaded-successful-candidate/capture
```

The default output is a new GUID directory under `artifacts/swiftui-api-audit/`.
The script prints the destination and returns a compact descriptor containing
the manifest path, hash, counts, and `reviewStatus = "unreviewed"`. It never
returns the complete ledger as a PowerShell object.

`-ManifestPath` defaults to `docs/swiftui-baseline.json`. An explicit
`-OutputDirectory` must not already exist, even as an empty directory, and
must be outside the source capture after resolving filesystem aliases. Keep
generated output under `artifacts/` or OS temp. For example, within a
PowerShell session:

```powershell
& ./scripts/build-swiftui-api-audit.ps1 `
    -CaptureRoot ./artifacts/downloaded-successful-candidate/capture `
    -OutputDirectory ./artifacts/swiftui-api-audit/first-candidate `
    -QueueFamily @('view-builder', 'file-export')
```

Selecting fewer queues changes only the queue records. This example still
retains and verifies the complete graph, identity, occurrence, relationship,
interface, and overlay evidence.

## Candidate ledger in GitHub Actions

The [pinned candidate workflow](../.github/workflows/swiftui-baseline-capture.yml)
builds this ledger from the SDK export in the same job, after the existing
material-candidate capture and before the unconditional artifact upload. The
`sdk-export` step writes the exporter's successful compact descriptor to
`artifacts/swiftui-baseline/github-actions/export-result.json` and publishes
explicit result/capture paths and status. The ledger does not discover a
"latest" directory or accept a different capture after failure.

Before native export, the workflow rejects artifact/evidence/capture paths
redirected through filesystem aliases and refuses an existing evidence
directory. It checks the exporter's returned paths and hashes against strict
capture intake before publishing the handoff and step outputs.

The candidate helper requires an absolute `-ExportResultPath`, matching the
path emitted through `GITHUB_OUTPUT`. Paths stored inside `export-result.json`
remain portable relative paths from `-EvidenceRoot`. The equivalent invocation
within a PowerShell session resolves the outer argument explicitly:

```powershell
$candidateEvidence = (Resolve-Path ./artifacts/swiftui-baseline/github-actions).Path
& ./scripts/build-swiftui-api-audit-candidate.ps1 `
    -ExportResultPath (Join-Path $candidateEvidence 'export-result.json') `
    -EvidenceRoot $candidateEvidence
```

The helper validates the successful descriptor and its contained capture,
then delegates complete evidence verification to `build-swiftui-api-audit.ps1`.
It publishes the ledger to `audit/` beside `capture/`, with a small
`audit-context.json` recording outcome, hashes, and counts. Successful creation
sets its status to `created-unreviewed-ledger`, with `reviewStatus` still
`unreviewed`. The source capture is not modified. Existing output is not
overwritten, and failure does not substitute a reindexed or synthetic
inventory for the native candidate.

The step requires that the job is not cancelled, that `sdk-export` succeeded,
and that its emitted status is `exported-awaiting-review`. It does not require
the material-candidate step to succeed, so a material failure can leave useful
SDK audit evidence while the job still reports failure. The ledger has a
20-minute step timeout within the existing 90-minute job limit. SDK export
and ledger generation invoke no SwiftPM or native reference application;
the separate material step builds and runs `macos-reference-renderer` with
the exported compiler/SDK in its own SwiftPM scratch directory.

The existing artifact upload uses `always()` and includes the entire
`artifacts/swiftui-baseline/github-actions/` tree. Its only exclusion is
`capture/module-cache/**`. Keep the complete raw capture and original
inventory, all ledger NDJSON files and source metadata copies, and the sealed
`audit.json`/`audit.sha256` alongside `ci-context.json`, `export-result.json`,
and `audit-context.json`; material evidence is also retained when produced.
The small summaries and hashes are not a substitute for the full evidence.
Failure can leave only the contexts or earlier completed stages. An upload
does not establish that a capture or ledger completed successfully.

This workflow still produces only unreviewed candidates. Exact native capture
success, declaration/interface/overlay review, Windows matching, and behavior
conformance remain separate evidence requirements. A fresh successful native
capture is still pending; this workflow integration does not claim one.

## Input verification

The input must have the exporter's successful candidate statuses:
`capture-status.json` must say `exported-awaiting-review`, and `capture.json`
must say `exported-awaiting-inventory-and-behavior-review`. Behavior remains
`not-verified`, and every capture qualification flag must be the Boolean
`false`. A candidate may still await exact identity review; successful intake
does not perform that review.

The complete chain of recorded hashes must agree with the supplied bytes.
The status digest and `capture.sha256` must seal the actual `capture.json`.
The captured baseline copy, SDK settings, declared public interfaces, and
overlay definitions must match their recorded hashes. The baseline ID,
toolchain, scope, requested module/target matrix, and observed identity must
agree. The declared and discovered interface, overlay, and graph file sets
must match, including extension partitions; missing files, undeclared files,
duplicate paths, and aliases escaping the capture are rejected.

The writer then streams every raw graph and the complete existing
`inventory.json`. It checks graph hashes and metadata, the graph-set digest,
precise identifiers, every projected declaration occurrence and relationship,
record ordering, and all declared counts. A changed inventory digest, omitted
occurrence, duplicate occurrence, mismatched projection, malformed record, or
unfinished JSON input fails the run. It does not accept an inventory hash
alone as proof that the inventory accounts for the raw graphs.

Projection reconciliation is intentionally stricter than general semantic
JSON equality. It accepts insignificant whitespace and reordered outer
projection fields, but preserves nested object member order, string escapes,
and numeric spellings from the exporter. An equivalent manually reordered
nested object therefore fails closed. This stage consumes the checked
exporter's inventory; it is not a normalizer for other inventory producers.

The original failed capture is not eligible. Reindexing its raw files with
`measure-swiftui-baseline-inventory.ps1` produces local benchmark evidence,
not the missing successful capture manifest and hash chain. Renaming a
reindexed inventory or changing a failed status is not a native recapture.
This tool never repairs a capture or edits its statuses, hashes, or baseline.

The expected baseline may contain later, matching identity-review metadata;
that does not rewrite the captured baseline or the historical
`exactIdentityPreviouslyReviewed` value. Both baseline copies are retained.
The captured Mac executable and exporter-source hashes are **reported
provenance**. The Windows audit does not open those Mac paths or substitute
hashes of local executables. Its own generator-source hashes are recorded
separately. Hash consistency does not authenticate an Apple installation or
establish API completeness.

## Ledger schema and retained records

`audit.json` uses schema version 1, evidence kind
`unreviewed-native-api-audit-ledger`, status
`awaiting-declaration-interface-and-behavior-review`, and
`reviewStatus = "unreviewed"`. `audit.sha256` seals that manifest. The manifest
records each record-file hash and size, source metadata copies, source capture
identity and hashes, pinned scope, counts, selected queues, resource settings,
generator hashes, and remaining work. Every generated record is unreviewed.
The evidence-kind label does not turn a synthetic fixture into native evidence.
Any reported synthetic-fixture marker is copied into the manifest explicitly;
the authoritative original capture metadata remains available alongside it.

The record files are UTF-8 newline-delimited JSON: one complete JSON object
per line. Consumers can stream them independently instead of deserializing
the entire ledger.

| File | Retained evidence |
| --- | --- |
| `identities.ndjson` | One record per exact, case-sensitive `identifier.precise`, in ordinal order, with its occurrence count |
| `occurrences.ndjson` | Every raw symbol object, including all mixins, plus graph path, requested module, target, original symbol index, and precise identifier |
| `relationships.ndjson` | Every complete relationship object and its graph provenance/index, including external targets, constraints, fallbacks, and unknown fields |
| `graph-fields.ndjson` | Graph root fields other than the symbol/relationship arrays, including metadata, module information, and unknown values, with their source field index |
| `partitions.ndjson` | Every graph's path, hash, module/target provenance, metadata, and symbol/relationship counts |
| `inventory-facts.ndjson` | Inventory root facts outside its graph/symbol/relationship arrays, including provenance, counts, and unknown fields |
| `interface-facts.ndjson` | Public-interface file facts and numbered source lines, preserving each line's text and line ending |
| `overlay-facts.ndjson` | Cross-import definition file facts and numbered source lines with their line endings |
| `candidate-queues.ndjson` | Lexical family candidates referring to exact identifiers; no compatibility decision or scope exclusion |

`source-metadata/` contains byte-for-byte copies of the captured and expected
baseline manifests, capture manifest/status/seal, SDK settings, public
interfaces, and overlay definitions. Their bytes are hashed again after
copying. These copies remain authoritative for metadata not represented
losslessly by the small parsed file-fact records.

Raw graphs remain authoritative and are **not copied into the ledger**.
Neither is the original inventory. Retain the complete source capture next
to the ledger: `sourceCapture.path`, its sealed metadata, and partition hashes
identify the external evidence. Embedded raw JSON values preserve symbol and
relationship fields, numeric spellings, unknown mixins, and absent versus
null versus empty availability, but are not replacements for the original
graph file bytes and formatting.

`preciseIdentifiers` counts exported identities, not unique audited Swift
APIs. Repeated identities within a graph, architecture variants, re-exports,
extensions, and synthesized declarations retain their occurrences. An exact
identifier is a capture key, not a portable SwiftUI-to-WinSwiftUI matching key.
The containing graph's requested module must not be inferred from or used to
rewrite a mangled identifier's module spelling. These counts cannot be used
as a completed compatibility percentage.

## Candidate queues and interpretation limits

`-QueueFamily` accepts these names; all five are enabled by default:

| Queue | Examples of lexical candidates |
| --- | --- |
| `view-builder` | `ViewBuilder`, `View`, and `View.body` |
| `binding-projections` | `Binding` and its members |
| `image-resizing` | `Image`, its `ResizingMode`, and `resizable(...)` |
| `long-press` | `LongPressGesture` and `View.onLongPressGesture(...)` |
| `file-export` | File-document types/configurations and `View.fileExporter(...)` |

Selection uses case-sensitive `pathComponents` spellings. A matching
occurrence can place its identifier in a selected queue; this is a starting
point for review, not an exhaustive semantic family classification. Queues
never remove other records or decide whether a declaration applies. There
is no availability, architecture, underscore-name, synthesized-member,
deprecation, or platform-service exclusion pass.

Interface facts are source lines, not parsed Swift declarations. Compiler
headers, module flags, imports, conditional-compilation blocks, attributes,
macros, and signatures remain available for later review. The compiler and
language mode that produced a textual interface are separate facts from the
extractor identity and requested extraction language mode. Do not replace an
interface's `swift-compiler-version` or `-swift-version` header with the
extractor's values. An overlay definition's presence does not show that the
compiler loaded it or that all of its declarations were exported.

Stage 1 does not perform Swift grammar parsing, Windows declaration capture
or matching, overload/default-implementation resolution, availability or
conditional-compilation evaluation, public-interface completeness review,
macro/overlay reconciliation, or behavior conformance assessment. Those
steps need explicit reviewed mappings and evidence at pinned toolchain and
source revisions. Nothing is marked implemented, compatible, excluded,
reviewed, or release-qualified by this command.

An [exact-identifier review unit](SwiftUIAPIReview.md) can gather one identity's
complete occurrences and incident relationships with the full surrounding
context and explicitly pinned Windows source blobs. It does not perform the
review: declaration, source, and behavior claims still start unverified.

## Resource bounds and publication

The writer uses the shared buffered JSON record reader, a disk-backed ordinal
index, and bounded merge readers. It streams large occurrence groups and
never loads a complete graph, inventory, or ledger into a PowerShell JSON
object. There is no aggregate graph-file or total-input size cutoff that
silently narrows the capture. Disk space and runtime still grow with the full
input and emitted ledger; retain enough space for source evidence, record
files, and temporary index runs.

| Parameter | Default | Purpose |
| --- | --- | --- |
| `-SortChunkBytes` | 16,777,216 bytes | Estimated buffered index budget before sorting to disk |
| `-MergeFanIn` | 16 | Maximum run readers used in one index merge |
| `-MaximumRecordCharacters` | 33,554,432 characters | Maximum single JSON record/value or interface/overlay source line |
| `-MaximumMetadataBytes` | 16,777,216 bytes | Maximum individual parsed control-metadata file |

These are explicit processing bounds, not a promised total process-memory
ceiling. Invalid encoding, malformed input, or an exceeded record/metadata
budget fails without truncating a record or omitting a file. A larger valid
record requires an explicit supported budget increase. It is never handled
by accepting partial evidence.

Graph metadata is emitted immediately and represented by digests during
inventory reconciliation, rather than accumulated as complete metadata
objects for every partition. The graph/file tables and explicitly bounded
control metadata remain in memory. The optional large regression creates two
individual graphs above 1 GiB and an inventory above 2 GiB, with one identifier
repeated across the disk sort runs; allow about 10 GiB of free scratch space.

All output is prepared in a unique staging directory beside the requested
destination. Only after complete stream reconciliation, text-file checks,
metadata copying/hash checks, and manifest sealing does the script publish
the directory with a same-filesystem rename. An existing destination is
never overwritten. Failure leaves no published final ledger and triggers
cleanup of the checked, owned staging directory; a cleanup failure is also
reported. This publication boundary is not a hardware-durability guarantee.
The source capture remains read-only throughout.

## Validation workflow

Quick, Full, and the pinned macOS capture workflow run these synthetic tooling
tests serially. They can also be invoked directly:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-swiftui-api-audit-capture.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-swiftui-api-audit.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-swiftui-api-audit-memory.ps1

# Explicit larger generated stress fixture; allow substantial disk/time.
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-swiftui-api-audit-memory.ps1 -Large
```

The same scripts can be invoked with `pwsh -NoProfile -File`. Capture-intake
tests exercise statuses, seals, identity/scope consistency, file discovery,
path containment, and metadata bounds. Ledger tests exercise complete raw
record preservation and reconciliation, queues, source-line facts, rejection,
and publication. Memory tests exercise streamed graphs, inventories, and long
occurrence groups using generated fixtures; the large case is opt-in.

The workflow integration has a separate synthetic/static test:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-swiftui-api-audit-workflow.ps1
```

It checks the explicit export-result handoff and workflow wiring using owned
synthetic evidence; it does not trigger GitHub Actions, invoke the native SDK
exporter, run SwiftPM, or capture native reference behavior. It can also run
with `pwsh -NoProfile -File`.

Fixtures created by `swiftui-api-audit-test-fixtures.ps1` are explicitly
synthetic and remain unreviewed. Its hash-resealing helper is only for owned
test fixtures and must not be used to repair native artifacts. Test results,
integration commits, and any later native capture/review must be recorded
separately; this document supplies no native run result or conformance count.
