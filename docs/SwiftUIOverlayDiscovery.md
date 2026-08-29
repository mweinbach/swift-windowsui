Stage A records a separate filesystem census associated with a successful pinned
SwiftUI capture and its complete sealed API ledger. It does not establish public
API completeness, resolve imports, run the compiler, or qualify behavior. The
original capture, its nine ledger streams, and the baseline manifest remain
unchanged. A successful census remains unreviewed; an incomplete census is
diagnostic evidence only. Stage B load probes and supplemental graph
reconciliation are not implemented by this change.

The baseline capture workflow can invoke this existing Stage A producer only
through an explicit manual request. Its default is unchanged: push runs and
ordinary manual runs perform no overlay census. Select
`capture_overlay_discovery: true`, supply the previously reviewed SHA-256 of
`docs/swiftui-overlay-root-plan.template.json` at the chosen workflow revision,
and choose `overlay_developer_frameworks` as exactly `not-selected` or
`selected-optional`. The default `unselected` value is deliberately invalid for
an opted-in request. Inputs reach PowerShell as environment values, not as
interpolated script text. No additional push paths, default tests, existing
capture flags, API allowlist entries, identity pins or qualification flags are
changed by this option.

Git keeps this hash-authorized template in LF form on Windows and macOS.
The caller still checks its exact bytes; it does not normalize or replace the
supplied authorization hash. The focused tests check this checkout policy and
the actual template line endings as well as the workflow's input guards.

The new caller first checks the template hash and choice without touching the
SDK or initializing the managed reader. That preflight has a two-minute step
limit and runs before SDK export. After a successful export and complete audit,
the optional census runs after the existing RGB step and before the existing
uploads, with a separate 20-minute limit inside the unchanged 90-minute job.
Independent material or RGB failure does not relabel a successful SDK/audit or
silently suppress the requested census; cancellation or failed export/audit
does suppress it. The native producer's original limits and failure behavior
remain intact. This is not permission to launch it before the caller, template
and actual execution have been reviewed.

`capture-swiftui-overlay-discovery-candidate.ps1` binds the existing successful
capture, audit and baseline hashes into the fixed template. It fills only the
two source-hash markers and the hashes of the explicitly named anchors. The
baseline-manifest hash remains literal and must match the supplied baseline. All
three root paths, both desktop targets, anchor paths, physical boundaries,
lookup grants and census limits come from the reviewed template. A changed
path or added/missing captured interface is an error, not a reason to expand
authorization. The optional choice may activate only the template's literal
developer-framework path and its one named Library metadata lookup. The
original template bytes, generated plan and caller/source hashes are retained
under the fresh `overlay-discovery-request/` sibling. The existing collector
alone creates the separate fresh `overlay-discovery/` output.

The template uses the recorded Xcode 26.6/MacOSX 26.5 logical locations as
conditional physical expectations. It does not assert that those paths are
present, canonical, readable or unchanged on a future runner. The unchanged
census must resolve each selected present root to that exact expected path;
there is no runtime realpath substitution, fallback installation or inferred
permission. Internal aliases within the authorized SDK/toolchain boundaries
remain subject to the existing recorder's rules. This profile grants metadata
lookups but no parent-directory listings. Its explicit acknowledgement retains
the BCL adapter's incidental link-target metadata queries, including possible
queries outside the reviewed boundary before controller checks. It does not
authorize outward content reads, listing or traversal; individual incidental
metadata queries are not fully observed. Consequently a missing or denied
selected-optional Frameworks root remains incomplete; it is not automatically
classified absent or changed to not-selected. This also avoids treating an
aliased optional parent as proof of absence at the literal expected location.

The generated root-plan hash is an integrity seal, not an independent approval
of values discovered at runtime. Authorization comes from the explicit request
for the reviewed fixed template and its narrow binding code. The resulting
plan still uses the original root-authorization schema and passes through
`capture-swiftui-overlay-discovery.ps1` unchanged, including strict metadata,
complete source-seal and live filesystem checks. Neither the producer nor its
validators are replaced by the new caller. Anchor hashes are observations from
the new successful capture; binding them does not fill baseline identity pins
or retroactively approve the historical capture.

The existing always-upload path retains both new siblings, including failure
receipts and hidden files, with its original 30-day retention and sole
module-cache exclusion. Early request validation does not precreate the SDK
evidence root: an invalid request remains a job-log failure, with no fabricated
SDK/census artifact. Later intake or census failures preserve the owned request
receipt and any producer diagnostics without retrying or rewriting the source
capture or audit. Existing missing-artifact failures are not suppressed.

`scripts/test-swiftui-overlay-workflow.ps1` checks the new pure binding functions,
input gates and artifact wiring using source and small synthetic objects. It
does not run the existing census/intake reader, compiler, native probes or
multi-gigabyte graph/ledger checks. The existing full workflow and discovery
suites remain separate validation; their managed helper compilation is not
part of that focused check.

This option can establish a new observation's recorded filesystem contents and
their consistency with its captured anchors. It cannot prove the old run's
loaded binary/textual/cache slice, native overlay activation, declaration
ownership, API completeness or behavior. Stage B resolver/load evidence is
still unimplemented, the original raw-payload review prerequisite is unchanged,
and identity pins remain held pending the required review.

The tooling is PowerShell under `scripts/`. Pure parser, fake filesystem, and
artifact checks run on Windows PowerShell 5.1 and PowerShell 7. The live
entrypoint requires macOS and PowerShell 7, and refuses other platforms before
opening an SDK path. This implementation has synthetic validation only: the
actual Darwin adapter has not been exercised against an SDK. Existing managed
streaming/strict JSON helpers may compile in the PowerShell process; no new C#
source, P/Invoke adapter, Swift compilation, SDK command, or external filesystem
command is introduced.

An invocation requires an explicitly reviewed root authorization and its
previously recorded SHA-256:

```powershell
pwsh -NoProfile -File scripts/capture-swiftui-overlay-discovery.ps1 `
    -CaptureRoot $savedCaptureRoot `
    -AuditRoot $savedAuditRoot `
    -ManifestPath $baselineManifestPath `
    -RootPlanPath $reviewedRootPlanPath `
    -ExpectedRootPlanSha256 $reviewedRootPlanSha256 `
    -OutputDirectory $newOwnedOutputDirectory
```

These variables refer to actual saved artifacts and a new output location, not
example SDK paths or a guessed newest capture. Output must be under OS temp or
this checkout's `artifacts/`, outside the source capture, ledger, observed roots,
and tool anchor boundaries. Existing output is refused. No overwrite,
retry-until-success, directory rename workaround, permission adjustment, or
automatic root expansion occurs.

Before any SDK observation, intake requires the existing successful capture
status, matching pinned manifest and exact saved targets, all nine ledger
streams, public interface and overlay copies, raw graph sources, and their
seals. The extra intake pass hashes every ledger stream, inventory, and raw
graph without loading the large JSON inputs as strings or DOMs. It reproduces
the graph-set digest and rechecks source seals after observation. This is
integrity verification; it does not repeat the ledger's semantic reconciliation
or promote the recorded extractor identity. A failed historical export cannot
be used as an official input. Fixtures require explicit internal switches and
cannot pass the live entrypoint.

The root authorization is strict bounded JSON with `schemaVersion: 1` and
`evidenceKind: "overlay-discovery-root-authorization"`. Duplicate JSON keys are
rejected. Its exact bytes, including unknown fields, are copied and sealed.
Required fields are:

| Field | Required meaning |
| --- | --- |
| `sourceCaptureSha256`, `sourceAuditSha256`, `baselineManifestSha256` | Exact hashes of the supplied successful artifacts and baseline. |
| `targetContexts` | Each recorded pinned target exactly once, with `targetVariant: null` for this profile. A directory name does not establish an invocation variant. |
| `roots` | All three selections below, with `rootId`, `selection`, `logicalPath`, `expectedPhysicalPath`, `allowedPhysicalBoundary`, and `reason`. |
| `identityAnchors` | Both captured tools, SDK settings, and every captured public interface. Each has the exact `anchorId`, `logicalPath`, `expectedSha256`, and narrow `allowedPhysicalBoundary`. |
| `lookupAuthorizations` | Individually named exact ancestor/link metadata or nonrecursive parent listings, with `lookupId`, `kind`, `exactPath`, `purpose`, `mayEnumerateChildren`, and `mayTraverseDescendants: false`. |
| `limits` | Explicit positive overrides, or an empty object to accept the recorded defaults. |
| `allowIncidentalLinkTargetMetadata` | Must be the JSON boolean `true`, acknowledging the BCL limitation below. Omission, `false`, or string coercion is refused. |

Use the captured developer directory as `D`, its selected
`Toolchains/XcodeDefault.xctoolchain` as `T`, and
`D/Platforms/MacOSX.platform` as `P`. The root selections are fixed:

| Root ID | Exact logical location | Selection |
| --- | --- | --- |
| `selected-sdk` | The captured SDK under `P/Developer/SDKs` | `required` |
| `selected-swift-resources` | `T/usr/lib/swift` | `required` |
| `platform-developer-frameworks` | `P/Developer/Library/Frameworks` | `selected-optional` or `not-selected` |

Each selected root needs an explicit canonical physical mapping within the
selected physical Xcode installation, and its physical boundary must equal
that root. Neither `/` nor a containing SDKs/toolchain directory is an allowed
substitute. A not-selected root has null physical fields and remains
`not-selected`, never absent. Anchor boundaries admit only the two exact tool
files or recorded SDK files for content reads. Parent listing authorizations
are exact immediate parents used to distinguish absence from failure; they
never become a subtree or a grant to open sibling contents.

`Get-SwiftUIOverlayExpectedLayout` can describe the logical roots and anchor
names from an already verified source context without inspecting the SDK.
It does not authorize physical mappings. Callers must review those mappings
and any necessary ancestor/link lookups explicitly. This profile does not
accept new roots, custom module maps outside the selected roots, or inferred
target variants. A newly necessary boundary needs a separately reviewed
follow-up; failure does not silently shrink the full compatibility goal.

The controller uses nonrecursive directory enumeration with hidden entries
included and inaccessible entries reported as errors. It retains ordinary
entry metadata as well as every `.swiftcrossimport` directory,
`.swiftoverlay` file, module map, and Swift module/interface location throughout
the selected trees. It does not search only for underscore-prefixed overlay
names or only for definitions owned by SwiftUI. Definitions where another
module lists SwiftUI or SwiftUICore as a bystander remain in the census.
Framework version aliases, repeated logical paths, and definitions in other
target directories remain distinct occurrences. Directory-name module and
target associations are unreviewed spelling observations, not import or
availability decisions.

The public BCL adapter may query a symbolic link target's metadata before the
controller inspects the returned entry. Explicit nonrecursive enumeration and
`AttributesToSkip = 0` do not eliminate that behavior: .NET's Unix enumerator
can determine the target's directory status during entry initialization.
The root plan must acknowledge this possibility; the report states that these
incidental queries are not individually observed. The controller never
deliberately opens outward file contents or enumerates outward directories.
It makes no no-stat, atomic-observation, or race-proof filesystem claim.
See the [.NET 10 Unix enumerator](https://github.com/dotnet/runtime/blob/v10.0.0/src/libraries/System.Private.CoreLib/src/System/IO/Enumeration/FileSystemEnumerator.Unix.cs)
and [entry initialization](https://github.com/dotnet/runtime/blob/v10.0.0/src/libraries/System.Private.CoreLib/src/System/IO/Enumeration/FileSystemEntry.Unix.cs).

The BCL's link API can also return null on a readlink failure, and its UTF-8
conversion can replace malformed bytes. Missing/ambiguous targets, replacement
characters, unsupported path text, outward aliases, cycles, and lookup errors
make the observation incomplete. They never establish absence. The report
preserves returned text where representable but does not claim it captured raw
filesystem name bytes. Parent segments after unresolved link-target
components are refused instead of being normalized into a possibly different
path. See the BCL [link target API](https://github.com/dotnet/runtime/blob/v10.0.0/src/libraries/System.Private.CoreLib/src/System/IO/FileSystemInfo.cs)
and [readlink adapter](https://github.com/dotnet/runtime/blob/v10.0.0/src/libraries/Common/src/Interop/Unix/System.Native/Interop.ReadLink.cs).

Readable empty directories, readable directories with no matching entries,
not-selected roots, confirmed absence, partial enumeration, and unvisited
entries have distinct facts. Absence requires a recognized not-found result
and a completed authorized parent listing. Permission errors, partial parent
listings, or missing authorization remain unknown. Each traversed directory
gets two enumeration receipts with matching membership and metadata.
Candidate contents get two bounded matching reads, and all tool/settings/
interface anchors must match their saved bytes before and after traversal.
Changes fail the observation without retry. These checks concern an interval:
`observationAtomic` and `wholeInstallationByteIdentityEstablished` remain
`false`, even when all anchors match.

Definition decoding uses the named `swiftcrossimport-canonical-v1` profile.
It accepts strict UTF-8, an optional BOM, LF or CRLF, ordinary comments,
optional `%YAML 1.2` and a single document marker, version `1`, and either
`modules: []` or the canonical two-space `- name: Identifier` sequence.
Names retain their order, duplicates, and nonunderscore spellings.
Missing or duplicate required keys fail; unknown versions, quoting, flow forms,
tags, aliases, multidocument input, tabs, or other unrecognized syntax remain
unsupported by this profile. Raw bytes are retained before parsing whenever
the copy budget permits. A partial or unsupported parse never becomes a known
empty module list.

The profile is informed by the public [Swift 6.3 definition implementation](https://github.com/swiftlang/swift/blob/swift-6.3-RELEASE/lib/AST/Module.cpp)
and its [canonical fixture](https://github.com/swiftlang/swift/blob/swift-6.3-RELEASE/test/CrossImport/Inputs/lib-templates/lib/swift/DeclaringLibrary.swiftcrossimport/BystandingLibrary.swiftoverlay).
This is not proof that the Apple 6.3.3 compiler has identical parsing or
search behavior. Some syntax refused here may be accepted natively.
Module maps are sealed as exact raw content without claiming Clang grammar
parsing. The original interface producer and the observed extractor remain
distinct; neither is inferred from the other.

Every completed definition occurrence produces an unreviewed candidate for
both pinned targets, including unknown-format definitions with unknown name
lists. Seed and reverse-bystander hints annotate this complete set instead
of removing records. This conservative queue avoids an unbounded in-memory
import-closure graph, but it is not itself an import closure or load result.
Global, module-local, and target-directory lookup rules still need native
review, informed by the public [Swift module loader](https://github.com/swiftlang/swift/blob/swift-6.3-RELEASE/lib/AST/ModuleLoader.cpp).

Output contains `root-plan.json`, exact copied contents under `raw/`, six
NDJSON streams, and a final `discovery.json` with a `discovery.sha256` seal:

| Stream | Facts retained |
| --- | --- |
| `filesystem-facts.ndjson` | Root state, names, metadata, directory completion/partial receipts, copies, and unvisited boundaries. |
| `alias-facts.ndjson` | Returned link text, logical/physical context, and repeat/cycle/outward/dangling/unsupported outcomes. |
| `definition-facts.ndjson` | Directory states, every definition occurrence, raw seals, profile result, all name occurrences, and issues. |
| `module-context-facts.ndjson` | Module-map copies and Swift module/interface metadata locations; no invented module resolution. |
| `candidate-pairs.ndjson` | Every recorded definition occurrence on both targets with unreviewed context and selection hints. |
| `issues.ndjson` | Explicit failures, affected paths, bounded exception causes and HRESULTs where available. |

Record IDs are versioned SHA-256 values over length-prefixed UTF-8 identity
components. They distinguish occurrences instead of deduplicating paths or
duplicate names. Raw content SHA-256 values are separate. The manifest seals
each stream and copy with its byte length, records counts and limits, binds
source artifacts and script hashes, and records actual PowerShell/CLR versions
and the observation interval.

Defaults are 500,000 yielded entries across enumeration passes, 50,000
directory occurrences, depth 64, 64 link hops per resolution, 10,000 candidate
copies, 16 MiB per copied file, 256 MiB total copied content, 256 MiB of NDJSON,
1 MiB per parsed definition, 64 KiB per parsed line, 4,096 names per definition,
and 16 MiB per metadata document. Anchor reads are capped at 1 GiB per file;
derived lookup, enumeration and total-read budgets are recorded. Limits stop
or fail rather than truncate silently. A parse-budget failure retains the
current raw file if safely copied and stops later candidates. Cleanup attempts
every owned handle even when another read, flush or close fails, and retains
the original error when reporting cleanup errors. Final metadata or sealing
failure leaves an in-progress, ineligible output.

Only `filesystem-recorded-awaiting-probe-review` with complete matching
metadata and seals is eligible for further review. A sealed
`failed-incomplete-observation` is retained for diagnosis but returns failure
from the live entrypoint. `Read-SwiftUIOverlayDiscoveryReport` requires the
explicit manifest hash, rejects incomplete/synthetic reports by default, and
checks all declared copies/streams and fixed Stage A claims. Its bounded
metadata checks reject a failed report relabeled as successful; it does not
replay NDJSON semantics or perform compiler verification. Every qualification
flag remains false. Even a complete zero-definition census establishes only
zero definitions observed in these recorded roots, not complete public
SwiftUI/SwiftUICore coverage.

Run the standalone synthetic suite in separate fresh processes:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-swiftui-overlay-discovery.ps1
pwsh -NoProfile -File scripts/test-swiftui-overlay-discovery.ps1
```

It creates only owned synthetic artifacts and an injected in-memory Unix
filesystem, preserves failure receipts, and records the actual PowerShell
version. Independently authored parser fixtures cover accepted and rejected
syntax. Filesystem fixtures distinguish absence from denial, preserve hidden/
reverse/alias occurrences, reject outward or ambiguous paths, detect changing
bytes/membership, enforce budgets and acknowledgement, check immutable output
and seals, and exercise cleanup failures. They do not validate Darwin
behavior, native compiler diagnostics, positive overlay loads, supplemental
graph reconciliation, or API/behavior conformance.
