# StateObject compiler characterization

This is a separate, manual compiler experiment for the frozen public
`StateObject` isolation fixtures. It records what the selected native compiler
admits or rejects. It does not change production `StateObject`, approve the
rejected private factory carrier, establish runtime safety, or claim SwiftUI
parity. The requirements in `goal.md` remain unchanged.

The [matrix](../scripts/fixtures/swiftui-stateobject-isolation/matrix.json)
contains 24 source files: 21 cases and three shared inputs. The files are exact
copies of the frozen paired public fixtures, with their original hashes and
source package provenance retained. Each case has one request for each of
`x86_64-apple-macosx26.5` and `arm64-apple-macosx26.5`: **42 planned native compiler
requests**, not 42 programs to run. The separate 21 Windows public requests
remain future work. This experiment neither consumes nor changes the 67 unrun
cells or any of the 179 files in the earlier frozen probe.

## Two separate dispatches

The [workflow](../.github/workflows/swiftui-stateobject-isolation.yml) has only
`workflow_dispatch`. Pushes, pull requests, schedules, and completion of another
workflow cannot start it. It uses `macos-26-intel`, a 45 minute job limit, and
`DEVELOPER_DIR=/Applications/Xcode_26.6.app/Contents/Developer`. It checks out an
explicit 40 character source commit without submodules or persisted Git
credentials. Its repository permissions are `contents: read` and `actions: read`;
it does not dispatch the SDK exporter or another workflow.

1. Select `metadata-only`. This downloads the selected successful SDK capture
   and records a new compiler profile. It compiles **zero case fixtures** and
   ends awaiting review. No success condition in this run starts case mode.
2. Review the profile, its raw metadata records, the source and harness hashes,
   and the exact matrix bytes outside the capture command. Keep the SHA-256 of
   `profile.json` and the SHA-256 of `matrix.json` as explicit review inputs.
   The profile remains an immutable candidate; the capture command never
   writes its own approval.
3. In a new dispatch, select `cases` and supply the metadata run, its exact
   artifact name, and both reviewed hashes. Missing or mismatched inputs stop
   before a case request. Case mode checks the current files and native
   environment against the reviewed profile; a different executable, SDK
   anchor, matrix, fixture, or harness is not an automatic replacement.

The supplied hashes bind an explicit selection. They are not proof that a
human performed a review, and an Actions success status is not production or
parity approval. Workflow provenance keeps the checked-out source commit
separate from the workflow commit. A later source commit must still provide
all relevant pinned bytes unchanged, including the reviewed harness, fixtures,
matrix, and baseline inputs; a different commit is not itself a substitute
for those checks.

Source provenance is checked against Git, not just a clean status report.
Nonempty `GIT_*` environment overrides are rejected alongside the compiler,
SDK, and loader overrides; rejected variable names are recorded without their
values. Every required repository input must be a regular blob in the selected `HEAD`.
The capture computes its Git blob SHA-1 directly from the actual file bytes,
without Git filters, and compares that value with the committed blob. It
records the initial commit and tree, then checks `HEAD`, the tree, tracked
worktree cleanliness, and the required file bytes again before finalization.
A later provenance failure does not erase already observed launches.

## SDK and compiler identity

The default input is SDK capture run `33135644721`, attempt `1`, artifact
`swiftui-macos-26.5-xcode-26.6-candidate-33135644721-1`. Its `capture/capture.json`
SHA-256 is:

```text
f900bef9de2e5c37b8145ad6bdae7a3fe1c9b679f15b324175e3f1c89797057d
```

The artifact is selected from the same repository by exact name and run ID,
then downloaded by the verified artifact ID. The workflow rejects an
unsuccessful or incomplete producer run, a producer
workflow mismatch, an attempt mismatch, an expired artifact, or an ambiguous
artifact name. It does not search for a newer successful capture or regenerate
missing evidence. The capture command validates the downloaded capture and
the selected live SDK before relying on them. The inventory is not needed for
these compiler cases and is not parsed to manufacture a result.

Each attempt has a new root under `artifacts/swiftui-stateobject-isolation/`.
The CLI writes archived output below `evidence/` and unarchived caches and
temporary SIL below `work/`. The raw workflow artifact contains only
`evidence/`, with its contents at the artifact root. Metadata artifacts are
named `swiftui-stateobject-isolation-metadata-only-<run>-<attempt>` and contain
`profile.json` at that root; case mode does not search nested directories for
another profile. The intake receipt is a separate
`swiftui-stateobject-isolation-workflow-intake-<run>-<attempt>` artifact.
It records producer identities and reported archive digests, not a second
approval of their content. Raw uploads are requested after capture failure
only when the new-path preflight succeeded; a rejected or preexisting path is
never archived as new evidence. Preflight failure may leave only the intake
receipt, and loss of the job or runner can prevent upload. Receipt creation
does not mutate a sealed capture manifest.

The captured SDK identifies Xcode 26.6 build `17F113`, macOS SDK 26.5 build
`25F70`, and Apple Swift 6.3.3
`(swiftlang-6.3.3.1.3 clang-2100.1.1.101)`. These are selected evidence, not
substitute identities if the runner changes. The original export hashed
`swift` and `swift-symbolgraph-extract`; it did **not** establish the actual
`swiftc` and `swift-frontend` executable hashes. Metadata mode must collect
their real resolved paths and bytes and preserve the metadata process records.
It must not infer one tool's hash from another tool's name or version line.

The profile contains a fixed recipe of 15 toolchain and host metadata requests:
four Xcode or SDK queries, four queries for each compiler tool (lookup,
version, and both target descriptions), and three host queries. Git source
checks are separate records, and none of these queries is a case request.
The expected version arguments are `swiftc --version` and
`swift-frontend -version`; each tool also receives `-print-target-info` with
the fixed SDK and target. These forms have not yet been exercised against
the pinned native binaries in this characterization. An unsupported form
must fail; the capture does not try another flag or infer missing metadata.

Case intake requires the complete metadata packet, not only `profile.json`.
The explicitly reviewed profile hash pins its embedded request records,
stdout and stderr hashes and byte counts, exact version text, and raw target
information hashes. The evidence reader checks those against the archived
streams and request JSON. Rewriting the outer archive manifest and its digest
cannot replace those observations while retaining the reviewed profile hash.
Before any case invocation, the current macOS version, OS build, host
architecture, and PowerShell version must also exactly match the reviewed
profile; the runner label alone is not that check.

The profile binds the captured SDK settings and six interface anchors to their
live counterparts, alongside compiler and harness identity. Four anchors are
desktop interfaces: SwiftUI and SwiftUICore for x86_64 and arm64e. The other two
are SwiftUICore Catalyst interfaces retained as provenance. There are two
desktop `StateObject` definitions, not four. The arm64e interface name is not
an additional compiler target; the matrix target remains arm64. No Catalyst
case or target variant is added. Interface producer flags, including Swift 5
language mode, are not client compiler flags.

These checks establish the recorded tool and SDK anchors. They do not attest
every dynamic library or system dependency loaded by the compiler, and they
are not native UI observations.

## Requests and resource limits

Each request imports the public SDK modules through the frozen source. The
command uses the exact listed shared inputs and case, an owned module cache
for that target, and an owned SIL output path. The fixed client flags are:

```text
-swift-version 6
-strict-concurrency=complete
-warnings-as-errors
-default-isolation nonisolated
-parse-as-library
-emit-sil
-whole-module-optimization
```

The command also fixes `-sdk`, `-target`, `-module-cache-path`, `-module-name`,
and `-o`. There are no prototype imports, import search overlays, source
rewrites, stronger factory annotations, downgraded flags, or automatic retry
flags. Requests are serial. The tool never links or executes the resulting
SIL, creates an application entry point, or runs the unsafe witness.

The limits are 120 seconds per request, 1 MiB combined raw stdout and stderr,
8 MiB archived SIL per case, and 1,800 seconds for the matrix. The tool does
not increase these limits or retry a failed request. New evidence paths must
be owned and unused; existing evidence is never overwritten.

Ordinary source admissions and rejections remain observations and do not by
themselves stop characterization. Tool or provenance failures do stop it:
cells that have not reached invocation stay explicitly unrun with the reason.
A crash, timeout, configuration or import failure, output violation, source
drift, or incomplete process and artifact record cannot become a qualified
compiler rejection.
All 42 cells remain visible even when only a prefix could be attempted.

Launch accounting preserves what was known before parsing, copying, or
classification failed:

| Launch state | Meaning |
| --- | --- |
| `confirmed-started` | The returned process record confirms the process started, even if collection later failed. |
| `confirmed-not-started` | The launcher was invoked and its returned record confirms the process did not start. |
| `not-run` | No launcher invocation was made for this cell. |
| `unknown-after-invocation` | The launcher was invoked but did not provide a process record that establishes whether a process started. |

`caseRequests` counts confirmed starts. `unconfirmedCaseRequests` separately
counts the unknown states; an unconfirmed invocation is not silently counted
as an unrun cell. A later collector or classifier exception preserves the
available process and raw records and stops subsequent requests. It never
retroactively relabels a confirmed or uncertain invocation as `not-run`.

The process helper is extracted from the complete
`Invoke-StateReferenceProcess` implementation in the frozen
`swiftui-state-reference-common.ps1`, lines 786-939, source SHA-256
`78975fc46f94849e22f62427fbcdf781dbb0be279b7c8019b66f8ccecca8e487`.
The extraction is renamed and explicitly requires PowerShell 7. Its provenance
and any separately reviewed changes are recorded in the new helper. Argument
arrays, raw byte limits, exit status, redirected stream closure, and cleanup
errors are retained. An exited owned parent process does not prove every
descendant was terminated.

One inherited limitation remains unchanged: an error before redirected streams
are initialized can leave `allRedirectedStreamsClosed` true for an empty stream
set. That flag alone proves neither launch nor successful stream collection.
The adapter rejects a non-null `record.error`, so this early failure cannot
become a successful metadata request or qualified compiler result.

## Interpreting results

The matrix separates ten admission controls, four intended diagnostic
controls, five source observations or confounds, and two unsafe wrapper
witnesses. The native outcome is not assumed from the historical Windows
expectation. In particular, an unsafe witness has a desired safety outcome of
rejection while the native compiler's outcome remains to be observed.

A negative control qualifies only after a normal compiler rejection with the
intended primary diagnostic at a valid position in the exact input source,
and after its required positive controls are established. Notes, quoted error
text, caret echoes, an error substring, or an unrelated primary error do not
establish the intended rejection. The factory case must diagnose the factory
call; rejecting the `StateObject` construction for another reason does not
qualify it. Unknown native wording stays in the raw evidence and is flagged
for review instead of being guessed into a pass.

Dependencies are keyed by the same attempt, target, compiler profile hash,
and case ID. A result from another target or run cannot satisfy a prerequisite.
An ordinary model inference observation is not silently treated as an
admission control. To attribute an admitted mutable capture specifically to
the wrapper, the corresponding immutable capture controls and the direct
mutable capture checker rejection must qualify in the same scope.

A completed case packet is checked against the exact ordered 21 cases for
each of the two targets. The evidence reader verifies command argument arrays,
owned input and output paths, raw process and stream records, and required SIL
hashes and sizes. It maps the original capture paths recorded in commands and
diagnostics to the hashed source files archived with that packet. This allows
the archive to move without reading from its old native filesystem locations
or accepting arbitrary replacement sources. It then replays diagnostic parsing
and assessment with the same attempt, target, and profile dependency keys.
This replay invokes no compiler. An outer manifest digest alone does not
satisfy those checks, and a diagnostic from another source or a control from
another scope cannot satisfy the recorded dependencies. These checks establish
packet consistency; they are not an independent attestation that a compiler
produced the files. Unknown launches or incomplete records do not qualify as a
completed packet.

If an unsafe witness emits SIL, preserve that admission and its review flags.
It is not a passed safety requirement, even if native SwiftUI also admits it.
Code generation does not execute the witness or prove an actual race. SIL can
support a later structural review without approving the rejected production
carrier. Every result keeps runtime evidence, parity, and production approval
false.

Diagnostic text alone cannot authenticate an arbitrary unprefixed diagnostic
header injected as a separate physical line. The frozen inputs, pinned
compiler, raw process record, and artifact hashes are the provenance boundary;
the parser does not provide a stronger guarantee.

## Validation scope

The four fixture, protocol, process, and capture test scripts check fixture
integrity and synthetic protocols. Where their process checks launch a child,
it is a PowerShell process, not Swift or a native UI. The capture suite covers
fake metadata and case requests, launch uncertainty, committed input checks,
archive tampering, and relocated packet replay. It can also use previously
captured SDK source files as explicit fixture data. Neither those data checks
nor fake process results are native compiler profile execution.
PowerShell 7 exercises the actual bounded process helper and strict JSON
reader. PowerShell 5.1 exercises supported pure checks and explicit unsupported
paths; it does not stand in for a native process run or the PowerShell 7 JSON
reader. The public capture entry requires PowerShell 7 on macOS. Windows is
not a supported native capture environment.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-swiftui-stateobject-fixtures.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-swiftui-stateobject-process.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-swiftui-stateobject-isolation.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-swiftui-stateobject-capture.ps1
```

Run the same scripts with `pwsh -NoProfile -File` for PowerShell 7 coverage.
The capture test script optionally accepts `-SDKCaptureFixtureRoot` pointing
to the `capture` directory from the already captured run `33135644721`.
It performs no live SDK discovery or native tool invocation. It verifies
exactly the eleven required pinned source files before and after the tests,
copies their bytes into owned fake packets, and leaves the supplied capture
unchanged. The test report records the source fixture's verified file count,
byte counts, and per-file provenance separately from fake process requests.

Without that argument, groups requiring complete source snapshots for positive
packet checks, profile intake, and replay are reported as **not-run**, not
passed. Other available protocol checks can still run; their success is not
full snapshot coverage. An explicitly
supplied root that is missing or fails validation makes the tests fail; it does
not trigger a search for another fixture or a silent fallback. After extracting
the existing artifact, the explicit PowerShell 7 command shape is:

```powershell
pwsh -NoProfile -File scripts/test-swiftui-stateobject-capture.ps1 `
    -SDKCaptureFixtureRoot "<downloadedartifact>/capture"
```

Replace the placeholder with the existing artifact's extraction directory.
This parameter belongs to the synthetic test script, not the native capture
entry. Supplying it does not create an approved compiler profile or authorize
case execution. PowerShell 5.1 still does not support the strict JSON reader
or native capture path, even when the source fixture is supplied.

Passing those tests or static workflow review does not mean the native metadata
profile, the 42 native requests, the separate Windows matrix, or runtime
behavior has been observed. Keep actual execution receipts distinct from
source review and fabricated protocol fixtures. The native PowerShell 7 capture
path, including its expected compiler metadata flags, remains unrun at this
documentation update. No synthetic test count is a native request count.
