# StateObject public compiler fixtures

These are compiler inputs, not runnable examples or compiler results. The 24
files in `paired-public/` are exact copies of the previously reviewed sources:
21 separate cases and three shared files. Do not format them, change their line
endings, strengthen their closure types, or combine case entry files.

`matrix.json` schedules each case once for `x86_64-apple-macosx26.5` and once for
`arm64-apple-macosx26.5`. That is 42 native SIL requests across eight families.
Each request receives only its listed shared sources followed by its entry
source. The direct counter checker receives only `00-mutable-counter.swift`.
The generic forwarding case has no shared source.

| Role | Cases | Interpretation |
| --- | ---: | --- |
| `admission-control` | 10 | Intended ordinary construction, access or transfer admission. |
| `intended-diagnostic-control` | 4 | Require an intended primary isolation or transfer error. |
| `source-observation-or-confound` | 5 | Record the actual result without predetermining admission. |
| `unsafe-wrapper-characterization` | 2 | Native behavior is unknown; the desired safety outcome is rejection. |

The native SDK is already an imported module. This matrix does not copy Apple's
StateObject implementation or introduce a second standalone mode. The public
sources select SwiftUI when available and WinSwiftUI otherwise; a native capture
must establish that the SwiftUI branch was used. The 21 possible Windows public
pairings need a separate approved framework/compiler profile and attempt. The
earlier local prototype results do not provide those public-import results.

All sources use the ordinary deferred initializer expression. `PureModel` has an
explicit MainActor annotation and a nonisolated initializer with an immutable
Int seed. The unsafe witnesses retain a mutable counter alias, defer its mutation
inside StateObject, schedule a wrapper-only MainActor read, and then reuse the
alias without awaiting the read. Their paired controls compute an immutable Int
before constructing the wrapper. Never invoke these functions or their tasks.
Never launch the App/Scene declarations, call `App.main`, evaluate a body getter,
or use private framework/runtime entry points. Compiling a body is allowed;
executing it is not.

The matrix is data, not authorization. A capture starts with all 42 cells
`not-run`. Before any compiler case is launched, a metadata-only profile must
record the actual compiler/frontend paths and hashes, and receive separate
review and manual authorization. Missing pins keep the case cells unrun. This
fixture package contains no native outcomes and does not change production
approval. The original rejected probe and its 67 unrun cells remain unchanged.

`requiredPriorControls` requires admitted controls. The separate
`requiredPriorObservationCases` array only requires a prior ordinary source
observation: the ordinary-model control is not required to admit. An unsafe
wrapper admission is described as wrapper-specific only when its positive
controls and the `requiresForWrapperSpecificAdmission` direct-counter rejection
are qualified. Every dependency uses the same
`(attemptID, target, compilerProfileSHA256, caseID)` context; other targets,
profiles and attempts cannot supply it.

`diagnosticExpectation` records the reviewed subject, diagnostic family and
source-operation lines. It does not predict an exact native caret position or
permit arbitrary message matching. A negative needs normal compiler rejection,
an intended primary error, and its controls. Notes alone or unrelated primary
errors leave the conclusion unqualified. Unknown native wording requires review.
Native admission of an unsafe witness is a source observation, not proof of an
executed race, and it cannot waive the desired safety requirement.

All source paths are relative to this directory. Source SHA256 values bind the
original raw bytes. The matrix content pin permits only CRLF-to-LF normalization
for Git checkouts; its raw file hash is recorded separately. The provenance
values are the original fixture manifest
`0b545ca4fb02507d02c5c11abceff23b981d3f00e52813d178deb9c35f27541e`, the original
probe package manifest
`fd60c674d9542fe88f7cd20af2d942d2527d4ac5a785e5b2242e9bafbe9c6c8d`, and the approved
matrix plan recorded in `provenance.approvedMatrixPlanSHA256`. No developer
directory or historical temporary path is needed to read or test this package.

Run the fixture checks from the repository with Windows PowerShell 5.1 or
PowerShell 7:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-swiftui-stateobject-fixtures.ps1
pwsh -NoProfile -File scripts/test-swiftui-stateobject-fixtures.ps1
```

Those tests read the committed files, verify the pinned matrix and source
hashes, inspect the source shapes, and create clearly synthetic not-run records
in memory. They never run Swift, launch another process, write compiler logs,
link a program or produce native evidence. Strict capture/result JSON parsing
and process-result validation belong to the separate characterization harness.
