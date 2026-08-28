# Bitmap font attribution

The gallery has an optional diagnostic for the bitmap icons in `symbol-palette`
and `stepper`. It records actual DirectWrite faces observed during bitmap draws,
then separately fingerprints approved local files referenced by those faces.
It does not change font selection, caches, rendering, the pixel thresholds, or
baseline qualification. The mode is off by default. Enabled runs cannot be used
as performance qualification samples.

The default diagnostic is **V1**. The explicitly selected V2 described below
adds actual glyph-run observations for the same fixed bitmap path. Existing
commands and hosted collection continue to emit and accept V1.

Use a new output directory and an explicit subset of the two supported fixtures:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gallery-compare.ps1 -BitmapFontAttribution -Entries symbol-palette,stepper -WorkDir artifacts/bitmap-font-run-001
```

`-SkipBuild` is allowed when intentionally inspecting a preexisting executable.
`-SkipRender`, `-UpdateBaselines`, and `-List` cannot be combined with this mode.
An existing `-WorkDir` or any other requested fixture is rejected before the
ordinary gallery probes or build. The wrapper passes a fresh native directory
and a per-invocation token together. Direct CLI callers must pass both
`--bitmap-font-attribution-dir` and `--bitmap-font-attribution-invocation`.

## Interpreting the files

The output directory contains:

- `current/<id>.png`: the normal retained scene render, preserved even if
  diagnostic collection is partial or unavailable.
- `bitmap-font-attribution/native/<id>.native-font-attribution.json`: the bounded
  native observation for that fixed fixture and invocation.
- `bitmap-font-attribution/report.json`: the validated native records, links to
  exact PNG/sidecar/profile digests, executable digests before and after rendering,
  and separately labeled disk observations.
- `provenance.json` and the ordinary gallery reports: the existing collector
  environment and pixel comparison, which remain separate from native ownership.

Every report remains **unqualified**. `observed` means that the recorded scope
was observed; it does not accept the current host as a baseline font profile.
Missing optional face metadata, unknown cache ownership, failed file access,
unresolved scene references, and exhausted limits remain explicit. The initial
native adapter leaves optional axes unimplemented, so partial records are
expected. Ordinary text layouts and atlas glyphs are not instrumented.

Candidate and missing-glyph sentinel probes are not displayed bitmap ownership.
A successful draw becomes an accepted bitmap only after extraction and caller
acceptance. GDI/vector fallback and preexisting cache hits do not inherit faces
from earlier probes. A selected scene reference is not proof that the bitmap
contributed visible pixels after clipping, occlusion, or compositing.

The session starts before node construction: icons are produced while
`Component.makeNode` runs during `ComponentHost.setContent`, not necessarily
while `View.makeComponent` runs. A weak link travels through inherited
`ViewBuildContext` environment values. Observation stops after the selected
`renderScene`, before the snapshotter's auxiliary `renderFrame`. The existing
`TextRenderDiagnosticsCounters.beginPass`, called by `ScenePainter.paintSnapshot`,
is separate; a pass counter cannot recover earlier bitmap construction.

| Production path | Stage 1 evidence and limit |
| --- | --- |
| Palette `Image` and Stepper chevrons through `Controls.icon` | Fixed roles only; actual bitmap `DrawGlyphRun` faces, followed separately by extraction, caller acceptance, and selected-scene association. |
| Candidate-family and missing-glyph sentinel probes | Separate probe purpose; a successful probe never proves displayed-bitmap ownership. |
| DirectWrite display bitmap | Bounded borrowed-face capture retains its COM reference; metadata is resolved after the draw callback. Face metadata does not include source text or glyphs. |
| Bitmap cache created within the same session | An unchanged bitmap content token can reuse its internal receipt. A copy preserves it; mutation does not. No cache token is exported. |
| Cache populated before the session | `bitmap-cache-hit-unobserved`; no font face is inferred from a family probe or matching pixels. |
| GDI fallback, vector fallback, or test override | Explicit backend/outcome with no invented DirectWrite face. Vector selection does not establish visible vector contribution. |
| Selected top-level static image resources | Uses `GPUIScene.presentationOrder()` and the last static binding for a texture ID. Unused registrations do not count as selected resources. |
| Nested image render passes, ambiguous bindings, or traversal limits | Scene association remains partial. An unvisited receipt is `scene-association-unobserved`, not a claim that the bitmap was absent. |
| Ordinary text, secure fields, text layouts, atlas glyphs, other fixtures | Not instrumented. This mode cannot establish typography attribution or resolve all residual icon differences. |

Existing public icon and snapshot signatures remain available. When the mode is
off, no session, metadata lookup, COM retention, font hashing, sidecar, or new
collector is created. The additional optional forwarding branches still require
the normal off/on pixel and performance checks; no timing equivalence is claimed.

The native envelope identifies its fixture, token, PNG basename, bounded runtime
description, and report schema. It does not embed a PNG checksum or executable
build revision. The wrapper's PNG checksum is an observation of the file after
rendering. Fresh output ownership, token/fixture checks, a completed invocation,
and unchanged executable fingerprints provide the association. The wrapper also
rechecks PNG, sidecar, profile, and executable digests after collection; a change
invalidates the affected association. The source revision and source-observation
digest describe the checkout observation, not the executable's embedded origin.
The native OS value comes from Foundation `ProcessInfo` and can be a compatibility
version; the collector's OS details are a separate observation.

The complete profile file must match the exact UTF-8 serialization emitted by
`Write-GalleryFontProvenance` for the wrapper's in-memory record. A fonts-only,
OS-only, or registration-only change cannot retain that association. A missing,
oversized, malformed, stale, or incorrectly named/tokened sidecar supplies no face
or disk attribution. JSON grammar is checked before conversion, including
duplicate keys, case/escape collisions, strict numbers, and surrogate pairs.
Comments, single quotes, unquoted keys, trailing commas, and unknown fields are
rejected across PowerShell versions. No raw parser/adapter exception is exported.

## Local font files and limits

Only `system-fonts` / `user-fonts` plus a safe basename can leave the native
adapter. The collector reconstructs the approved directory from Windows special
folders; it never substitutes a registry file merely because a family matches.
Only direct `.ttf`, `.otf`, and `.ttc` children are considered. Raw paths, UNC and
device paths, alternate data streams, dot segments, DOS device names, short-name
aliases, and path-like font labels cannot enter the report.
Approved font roots must be on a fixed local drive; mapped network drives are
not accepted as local font storage.

The lazy C# file adapter holds the directory chain open, rejects reparse points,
and checks the normalized final path of the opened file. It then checks the
128-bit file identity, size, attributes, and timestamps before and after reading.
The same read-only handle supplies SHA-256 and embedded name-ID-5 versions;
neither operation reopens a pathname. File sharing excludes writers and deletion.
Sharing or metadata failures remain unknown and never trigger a permissive retry.
These checks use the documented [final-path API](https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-getfinalpathnamebyhandlew)
and [file identity structure](https://learn.microsoft.com/en-us/windows/win32/api/winbase/ns-winbase-file_id_info).

This is an approved-path guarantee, not a claim that the physical file has no
other hard links. Other hard-link names are not enumerated or exported. A later
disk hash is never represented as a digest of the font bytes DirectWrite loaded.
`faceFileReference`, `diskObservation`, and `loadedBytesDigest` remain separate.
Registry records are only cross-referenced by the exact approved path and record
index; a family name or matching digest alone cannot establish ownership.

Each native sidecar and the aggregate are capped at 512 KiB. Native metadata is
limited to 64 faces, eight files per face, 256 observations, and 32 axes per face.
The collector considers at most 64 distinct scope/basename references, reads at
most 128 MiB per file, and charges at most 512 MiB across the invocation. Version
parser rereads count against the same budget. An I/O exception conservatively
charges its requested bytes; a failed injected adapter consumes its remaining
per-file allowance rather than creating more budget. Reads use a fixed buffer
with FileStream read-ahead disabled. An exactly full-budget hash can therefore
have an unknown version. Version output is capped at 16 strings of 512 UTF-16
units. TTC face-specific versions remain unknown; the whole-container disk hash
can still be observed.

The artifact reader operates on newly owned output files with size limits,
read-only sharing, reparse checks, and repeated digests. It does not claim the
font adapter's pinned-directory protection against a hostile process replacing
artifact directories. Neither file observation is proof of loaded bytes.

The serialized V1 native schema contains fixed fixture/role identifiers, unordered
purpose/backend/outcome aggregates, and bounded physical font metadata. It excludes
text, text hashes, glyph IDs/counts, input strings, secure-field metadata,
coordinates, timestamps/order of events, raw pointers, opaque reference keys,
cache keys, and bitmap content tokens. Invalid input is rejected, not echoed.

## Explicit V2 glyph and face-file observations

V2 requires both the existing diagnostic switch and an explicit version:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gallery-compare.ps1 -BitmapFontAttribution -BitmapFontAttributionVersion 2 -Entries symbol-palette,stepper -WorkDir artifacts/bitmap-font-v2-run-001
```

Direct gallery callers add `--bitmap-font-attribution-version 2` to the paired
directory/invocation flags. A version flag alone is invalid. Selecting V2 is
never inferred from a sidecar: the collector chooses its strict parser from the
invocation. The existing V1 parser still rejects a V2 envelope, and its schema,
privacy allowlist, and default output are unchanged. The CI coordinator remains
V1 only; no workflow or gallery threshold changes accompany V2.

The V2 native report includes the original report as `attributionV1`, plus
separate `faces`, `glyphRuns`, and `observations` arrays. Only a
`display-bitmap` callback may contribute a V2 glyph run. The callback forwards
the original draw exactly once, keeps its HRESULT, and copies its borrowed
`glyphIndices` while the callback inputs remain valid. Within each run the
original order and glyph count are preserved, including glyph index zero
(`.notdef`). An empty run or failed draw is explicit incomplete evidence. An
oversized or invalid run is rejected as a whole, never exported as a complete
prefix. No source characters, cluster maps, advances, offsets, bidi levels,
descriptions, or layout positions are copied into the diagnostic.

Each retained callback face gets a distinct V2 record even if its names or
unknown metadata equal another face. IDs are assigned after content and bounded
co-run context sorting and identify records within this report, not globally
unique or stable font identities. Context refinement runs at most 64 iterations.
Unresolved equal contexts use unique private ranks from a fixed system-random
permutation, never a timestamp, address, or encounter-order fallback. Those ranks
are not serialized. This keeps ambiguous faces separate without publishing their
callback order; V2 does not promise complete graph canonicalization or stable
IDs between reports. Identical face/glyph/result runs are aggregated with a count. The
per-observation `runCounts` array records multiplicity within one raster
attempt, parallel to `runIDs`; an observation's own count can describe repeated
acceptance or cache reuse without implying additional draws. There are no
global event sequence numbers or timestamps.

Private attempt and bitmap receipts link these copied runs to extraction,
acceptance, known cache reuse, and selected top-level scene references. A capture
can be consumed only once, by its originating session and fixed role. Receipt
conflicts, changed bitmap content, or a cache populated before observation leave
ownership unknown. Probe captures retain their V1 face-only behavior and cannot
supply display glyph ownership. GDI, vector, and test override paths never
inherit DirectWrite glyph IDs. A scene reference still does not prove visible
pixel contribution after clipping, occlusion, or compositing.

An SDK-typed C++ helper queries optional `IDWriteFontFace5` axes and the actual
held face's file references. Axes can be unsupported, failed, or limited;
`HasVariations` is separate from the axis array because static faces may also
have axes. The helper validates exact counts, unique printable OpenType tags,
and finite values. V1's intentionally unimplemented axes remain unchanged.
See the [axis count contract](https://learn.microsoft.com/en-us/windows/win32/api/dwrite_3/nf-dwrite_3-idwritefontface5-getfontaxisvaluecount)
and [axis values contract](https://learn.microsoft.com/en-us/windows/win32/api/dwrite_3/nf-dwrite_3-idwritefontface5-getfontaxisvalues).

For file streams, remote loaders are rejected before any stream or size call.
The documented built-in local-loader interface and an approved fixed-drive
path are required; unknown/custom loaders without that interface are rejected.
This is an API eligibility check, not attestation against hostile in-process
COM implementations impersonating system interfaces. Held directory/file
handles reject reparse, short-name, substituted-drive, device, UNC, and alternate
stream paths. Only direct approved system/user font children are considered.
The file is held without writer/delete sharing, and its identity and metadata
are checked before and after stream hashing. Existing servicing hard links are
not prohibited merely by their link count; no other link names are exported.
No font is installed, downloaded, copied, or included in an artifact.

The hash is labeled **`face-file-stream-at-observation`**. It comes from a new
stream created through that face file's exact loader/key while those references
remain held. This is different from the collector's separately labeled
post-render disk read, and neither is proof of the original bytes consumed by
rasterization. `loadedBytesDigest` remains **`not-observed`** in every V2 file
record and in the report coverage. The API exposes no atomic snapshot tying a
new stream to earlier DirectWrite caches. Local streams can fail if their
reference no longer matches. The local gate precedes `GetFileSize` because
Microsoft documents that a remote asynchronous size query can download a font.
See [CreateStreamFromKey](https://learn.microsoft.com/en-us/windows/win32/api/dwrite/nf-dwrite-idwritefontfileloader-createstreamfromkey)
and [GetFileSize](https://learn.microsoft.com/en-us/windows/win32/api/dwrite/nf-dwrite-idwritefontfilestream-getfilesize).

The V2 limits are 128 copied glyphs per run, 16 callbacks per raster attempt,
256 copied runs and 4,096 copied glyphs per session. Faces share V1's 64-face
retention bound, including probe faces; there are at most eight files and
32 axes per face. A stream is capped at 16 MiB, with a 64 MiB session budget
and 64 KiB fragments. Requested fragment bytes are charged before each call;
returned bytes are counted separately, and failures do not refund requests.
SHA-256 is emitted only after a complete stream and successful final checks.
Fragments and owned COM/CNG handles are released on all return paths.
These counters bound requested/returned stream bytes, not physical operating
system I/O. Synchronous COM/file APIs have no per-call deadline; any enclosing
process timeout remains a separate limit. Native and aggregate sidecars retain
the existing 512 KiB caps.

V2 covers one bitmap icon path. It does not instrument ordinary or secure text,
atlas glyphs, all fallback decisions, nested render passes, or final visible
pixels. It does not establish full glyph repertoire coverage, identify the
fonts used to create historical baselines, qualify a hosted font profile, or
explain or repair the 67/85 hosted gallery mismatches.

## Validation boundary

Run the synthetic collector tests with:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-gallery-bitmap-font-attribution.ps1
```

They inject a PowerShell file adapter and use owned opaque fixture bytes. They
cover schema/privacy validation, association failures, digest changes, caps,
partial/fallback states, and unchanged comparison settings. They explicitly
forbid `Add-Type`, native calls, rendering, and SwiftPM. Passing them does **not**
validate the C# interop, actual file-handle behavior, SFNT parser, or native
rasterization. Those require the normal serial build/tests and an approved
Windows run comparing diagnostic off/on retained pixels and warm-cache behavior.
Diagnostic write failures preserve PNGs and must not change pixel pass/fail.

## Advisory collection after the hosted Full gate

The Windows Full job records a boundary immediately before its unchanged
`scripts/agent-check.ps1 -Full` command. After that command succeeds or fails,
and after the ordinary screenshot upload, a separate advisory step attempts
the two fixtures with `-BitmapFontAttribution -SkipBuild -Entries
symbol-palette,stepper`. It does not install fonts, rebuild, change the runner
or Swift setup/cache, update baselines, or change comparison tolerances. Full
has no `continue-on-error`; its original failure remains a job failure even if
the diagnostic passes. The existing manual `workflow_dispatch` Full selection
includes this collection; there is no separate bitmap diagnostic workflow.

The existing `windows-gallery-compare` upload includes
`bitmap-font-attribution-ci/<run-id>-<attempt>/` beneath
`artifacts/gallery-compare/`. The coordinator only accepts numeric run/attempt
identifiers in the expected Windows GitHub checkout. Evidence uses new files;
rerunning against an existing result or attempt does not overwrite it. Normal
gallery reports, provenance, images, and baselines remain outside this owned
directory. A missing/invalid boundary writes a blocked result when a fresh
safe output directory is available.

Before launching, `capture-ci-bitmap-font-attribution.ps1` requires a normal
gallery provenance record captured after this job's boundary, a successful
gallery build with numeric exit 0, and a matching nonempty executable digest
at the exact `.build/debug/swift-windowsui-gallery.exe` path. Boundary, receipt,
and current checkout must agree on a clean HEAD. The normal render can have
failed after that successful build; its original render status remains in the
result. Missing, stale, failed-build, dirty, or changed evidence blocks the
diagnostic without launching or rebuilding. A fresh successful incremental
build may keep the same executable bytes and an older modification time.
Existence or timestamps alone never qualify an executable. The usual
`.build/debug` directory alias is allowed; reparse executable leaves are not.

`boundary.json` records the pre-Full observation. An eligible invocation first
writes `attempt.json` and an exact byte copy of the normal provenance, then
prepares the existing Swift runtime environment and rechecks source, receipt,
and executable observations. Only the existing offscreen gallery wrapper is
launched, through a hidden process with literal argv. It cannot launch the demo
window or select an alternate executable. A completed run adds `result.json`,
separate child stdout/stderr logs, and the wrapper's `render/` outputs. Native
font metadata is collected by the wrapper, not rerun by the CI coordinator.

Each log spool has a hard **16 MiB** cap. Both streams are drained concurrently
even after reaching the cap; the exact prefix and discarded-byte count are
retained. `limit-exceeded`, read failure, or write failure means incomplete evidence, never a
complete raw log or successful association. No custom process-tree killer is
added. The advisory step has a ten-minute Actions limit, but cancellation,
runner loss, or the existing job timeout may prevent finalization or uploads;
an unfinished attempt and any prefixes remain incomplete.

The actual child exit code is always separate from the coordinator exit code.
Child exit 1 is preserved after reports and streams are retained. It is labeled
`completed-with-pixel-mismatches` only with a completed successful render, both
fixed PNG observations, the full two-entry comparison, and actual threshold
breaches. Missing baseline/current files or incomplete reports are not pixel
mismatches. A post-validation error or log overflow after child exit 0 makes
the coordinator exit 1 without rewriting the recorded child code; a nonzero
child code remains primary. Pixel status and attribution status are separate:
a passing pixel comparison can have partial or unavailable font attribution.
Every result remains unqualified.

Capture metadata failures still retain independent observations of available
log prefixes, fixed output files, and the executable after the child exits.
If result publication itself fails, the coordinator keeps any known nonzero
child exit and leaves existing files intact; it does not claim a saved result.
The coordinator also checks the aggregate's existing source, PNG, and sidecar
digest links without rerunning native collection. Partial entries may retain
an unverified association even when the overall invocation completed.

JSON receipts are capped at 512 KiB, checked as strict UTF-8/JSON before parsing,
and reject duplicate or case-aliased keys. Executable observations are capped
at 256 MiB. Output inspection uses a fixed list, with 32 MiB per PNG, 512 KiB per
JSON/sidecar, 1 MiB for report text, and 16 MiB for HTML. These are read/spool
limits, not a claim that native execution or all generated files are bounded
by the coordinator. Directory checks and repeated file digests do not pin
directory handles against a hostile replacement. Existing reparse parents in
the fixed render subdirectories are rejected. Checkout metadata is not an
embedded executable build revision; a disk font digest is not the font bytes
DirectWrite loaded. The diagnostic does not qualify CI, font profiles,
performance, API compatibility, or visible glyph contribution.

Run `scripts/test-ci-bitmap-font-attribution.ps1` under Windows PowerShell 5.1
and PowerShell 7 for synthetic boundary, receipt, source/path, command, stream,
exit-preservation, and workflow checks. Its source observer, environment setup,
and executor are fake adapters, with owned opaque fixture files. It does not
run SwiftPM, the gallery, the font probe, or a native renderer. Passing these
tests does not validate hosted execution, actual process pipes, or font output.
