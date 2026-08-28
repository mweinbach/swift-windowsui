# Bitmap font attribution

The gallery has an optional diagnostic for the bitmap icons in `symbol-palette`
and `stepper`. It records actual DirectWrite faces observed during bitmap draws,
then separately fingerprints approved local files referenced by those faces.
It does not change font selection, caches, rendering, the pixel thresholds, or
baseline qualification. The mode is off by default. Enabled runs cannot be used
as performance qualification samples.

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

The serialized native schema contains fixed fixture/role identifiers, unordered
purpose/backend/outcome aggregates, and bounded physical font metadata. It excludes
text, text hashes, glyph IDs/counts, input strings, secure-field metadata,
coordinates, timestamps/order of events, raw pointers, opaque reference keys,
cache keys, and bitmap content tokens. Invalid input is rejected, not echoed.

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
