# GPU Workbench: independent Windows consumer

This is a **separate Swift package**, not another target in the toolkit package.
Copy this directory outside the swift-windowsui checkout before qualification.
It consumes public `WinSwiftUI`, `SwiftWindowsGraphics`, and
`SwiftWindowsRendererD3D11` products. It imports no demo code or toolkit test SPI.

The application has a dashboard, bound Settings page, shared observable draft,
explicit Save/Reload, per-user JSON persistence, a bundled PNG, and a private
`@State` counter in a reconstructing child. The saved-profile details preference
shows or hides the dashboard's saved-profile section. Its default preferences file is
`%LOCALAPPDATA%/SwiftWindowsUI.GPUWorkbench/settings.json`. Invalid names and
unreadable/unwritable storage report an error without discarding the draft.
Settings reads accept up to 64 KiB, with one extra byte read to detect overflow
before decoding. Oversized files are left unchanged.
Save refuses to overwrite an unreadable existing file. Repair or move that file
and retry; Reload replaces the draft only after a valid read. Atomic replacement
is used for saving. This is single-process persistence, not concurrent-writer
conflict resolution or cross-window AppStorage conformance.

This fixture is a practical checkpoint within the original project goal, not a
claim that the toolkit is production-ready. On 2026-09-03, an external copy at
toolkit commit `4330e98` passed all seven model tests and built the executable
with ordinary Release settings on Swift 6.3 for Windows x64. Its staged
deployment-only check also passed with developer paths removed, and unchanged
manifests rejected copies missing the resource bundle, PNG, or `swiftCore.dll`.
These negative checks stop at manifest validation, before launching the EXE.
The native acceptance sequence and clean-machine deployment remain unqualified;
the checkpoint is not complete. Later source revisions need fresh validation.

## Build as an independent consumer

The first qualification target is Swift 6.3 on Windows x64 with the Windows SDK
and Visual C++ build tools used by the toolkit. The manifest's tools-version 6.2
is a package-format minimum, not proof that earlier compilers support the runtime
reflection SPI. Record `swift --version`, SDK, architecture, toolkit commit, and
consumer source hashes with the run. Other compiler/architecture combinations
remain unqualified.

In PowerShell, choose a **new** external directory and the reviewed toolkit
checkout. Do not run any SwiftPM command concurrently with the main task's build:

```powershell
$ErrorActionPreference = 'Stop'
$toolkit = 'C:\Users\you\Projects\swift-windowsui'
$consumer = 'C:\ConsumerChecks\GPUWorkbench'
if (Test-Path -LiteralPath $consumer) { throw 'Choose a new consumer directory.' }
Copy-Item -LiteralPath (Join-Path $toolkit 'Examples\GPUWorkbench') -Destination $consumer -Recurse
$env:SWIFT_WINDOWSUI_CHECKOUT = $toolkit
powershell -NoProfile -ExecutionPolicy Bypass -File "$toolkit\scripts\with-swift.ps1" swift test --package-path $consumer --configuration release
if ($LASTEXITCODE -ne 0) { throw 'External release tests failed.' }
powershell -NoProfile -ExecutionPolicy Bypass -File "$toolkit\scripts\with-swift.ps1" swift build --package-path $consumer --configuration release --product GPUWorkbench
if ($LASTEXITCODE -ne 0) { throw 'External release build failed.' }
```

Use the toolchain's ordinary release settings. Do not disable reflection metadata
or add metadata-stripping flags: mounted `State` needs consumer-module metadata.
The seven model tests exercise persistence and failure handling; they do **not**
qualify mounted reflection. The native counter/rebuild check below is required
for that. The injected writer-denial test is not an actual filesystem ACL test.

## Stage the executable, DLLs, and complete resources

Ask SwiftPM for the release binary directory with `swift build --show-bin-path
--package-path <consumer> --configuration release` through the same build
environment. Inspect this build's `resource_bundle_accessor.swift`, and select
the complete generated `gpu-workbench_GPUWorkbench.resources` directory next
to the executable; verify its actual name rather than assuming a DLL carries it.

Use `dumpbin /DEPENDENTS` in the Visual Studio developer environment for the EXE
and recursively for each non-system DLL. Resolve the matching architecture's
Swift/Foundation/dispatch/C++ runtime closure explicitly. Do not copy Windows
system DLLs or use all of PATH as an implicit dependency source. The helper below
checks named files and copied hashes; it does not discover or prove the closure.
Choose a new destination with an existing parent and supply the reviewed paths:

```powershell
& "$consumer\scripts\stage-release.ps1" `
    -ExecutablePath $reviewedReleaseExe `
    -ResourceBundlePath $reviewedWholeResourceBundle `
    -DllPath $reviewedRuntimeDlls `
    -DestinationDirectory $newStage
powershell -NoProfile -ExecutionPolicy Bypass -File "$consumer\scripts\check-deployment.ps1" -PackageDirectory $newStage
if ($LASTEXITCODE -ne 0) { throw 'Deployment check failed.' }
```

Invoke `stage-release.ps1` with `&` from a PowerShell caller so the DLL array
remains an array; `powershell.exe -File` has version-dependent array handling.

The helper never overwrites a stage or retries a failed copy. A failed partial
directory stays available for inspection. Resolve build-output junctions first.
The stage manifest is a local integrity receipt, not a signature or protection
against concurrent hostile filesystem mutation. Ship the complete resource
directory. The PNG is a repository-authored 16-by-16 fixture, not downloaded art.

`check-deployment.ps1` verifies manifest bytes, launches only the staged EXE in a
fresh unrelated working directory, removes developer search paths from the
child environment, requires its deployment-only JSON receipt, and enforces a
30-second deadline. It does not launch through `with-swift.ps1`. The EXE verifies
that `Bundle.module` resolves beside itself and that the named PNG exists there;
an absolute fallback into the original build tree is rejected. This checks the
PNG signature, not decoder success or presented pixels.

Repeat against disposable stage copies with the bundle removed, with the PNG
removed, and with a required non-system DLL removed: all must fail. Rehashing an
intentionally incomplete manifest is not a passing negative control. Final
deployment qualification must also use a fresh Windows machine or VM where
neither the source/build tree nor Swift SDK/runtime installation exists, since
sanitizing PATH on the development machine is not equivalent.

No installer, updater, signing policy, or project license is selected here.
External distribution remains pending the owner's license decision and review
of runtime redistribution requirements.

## Native acceptance sequence

Run the staged release EXE from an unrelated directory in a fresh test profile.
Keep a manifest/commit record and record each check as pass/fail. The executable
must exit naturally when the final window closes; forced termination is failure.

1. Require a visible dashboard and the blue/teal bundled mark (a 16-by-16 source
   displayed at 32-by-32 points). A blank
   image is failure even if the deployment-only receipt passed.
2. Increment the local counter three times. Rebuild the parent twice. Require
   `Local count: 3` and `Parent rebuilds: 2`. This exercises private consumer
   reflection metadata in the optimized build, not merely model persistence.
3. Switch between Dashboard and Settings using the bound tabs and the explicit
   page buttons. On Settings, focus the name with the keyboard, clear it, Tab to
   Save, and press Enter. Require a visible validation error and no lost draft.
4. Type `Release Operator`, turn saved-profile details off with the keyboard, Tab to
   Save, and activate it. Require `Settings saved.` and no error. Return to the
   dashboard and require the new draft name and no saved-profile details section.
5. Reopen Settings. Require the same values. Rebuild again and require the local
   count still equals 3. Close the window; require process exit zero. Relaunch,
   reopen Settings, and require persisted preferences, including the disabled
   details toggle. Enable details, return to Dashboard, and require the details
   section with `Saved profile: Release Operator`. Return to Settings, turn
   details off, and require that section to disappear again on Dashboard. The
   session counter intentionally starts at zero on the new process.
6. With the app closed, back up the test profile's settings file and replace it
   with invalid JSON. Relaunch: require an error and unchanged corrupt bytes.
   Editing and Save must preserve the draft and refuse to replace that file.
   Restore the valid backup and Reload; require recovery without restarting.
7. Use a disposable test profile with denied storage access to check real access
   errors. Require a visible failure, unchanged saved file and draft, then allow
   access and retry successfully. Do not change permissions on a real profile.

AutomationIds are `workbench.displayName`, `.showSavedDetails`, `.save`, `.reload`,
`.dashboard`, `.settings`, `.status`, `.error`, `.draftSummary`, `.savedSummary`,
`.savedDetails`, `.increment`, `.localCount`, and `.rebuild`, all with
the `workbench` prefix. An eventual UI Automation driver must require exact
elements and Value/Toggle/Invoke patterns; missing elements or failed actions
are failures, not exploratory output. A UIA sequence does not replace the real
keyboard checks. This candidate supplies the manual reproducible sequence, not
an automated end-to-end driver.

## Verify the actual renderer separately

The composition root requests `D3D11RenderBackendFactory`. D3D11 can use WARP,
and `App.main` may substitute the software presenter. The app labels its request
accordingly; it does not claim hardware acceleration from the factory name.
Run a separate staged session with existing `--diagnostics
--diagnostics-no-input --diagnostics-gpu-timing --diagnostics-seconds 30
--diagnostics-output <new-absolute-report-path>`. Require a fresh parseable report,
actual D3D11 presentation, no software substitution, an adapter explicitly marked
non-software, successful native command receipts, and real hardware timing
samples. A zero exit without the report is failure. Retain the report rather
than manufacturing a pass from the requested backend label.

That diagnostic run is not native input latency, recovery, smooth-motion, or
general performance qualification. The sample inherits `App.handleFailure(_:)`'s
default, which awaits an ownerless Windows error dialog without using the
renderer. The callback runs on the main actor; the dialog itself runs on a
worker. Presenter-unavailable delivery occurs at most once per window lifetime
after pending presentation work and actor replies settle, and does not retry
graphics or close the window. Startup notification requires a successful native
owner stop/join and cleared ownership/cleanup queues with no fatal result; the
startup failure then retains its nonzero exit. Fatal or unproven ownership
failures skip the callback, and synchronous custom-platform startup keeps its
existing print/return behavior. Failure to show the dialog is logged. Actual
native alert delivery in this consumer remains unqualified; the sample does not
access internal hosts.

Documents, deep links, multi-window storage propagation, generic unbound
navigation, and full accessibility remain outside this initial sample's
advertised behavior and inside the original toolkit goal.
