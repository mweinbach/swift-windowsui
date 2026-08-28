# Canonical opaque-loop negative compilation fixture

This fixture preserves the known Swift 6.3 inference failure for opaque
`some View` expressions inside the Windows `for` extension of the canonical
ViewBuilder. It is not a runtime XCTest and is not expected to compile. The
explicit WindowsArrayViewBuilder migration has separate positive tests under
`Tests/SwiftWindowsCoreLogicTests`.

Package.swift declares `SwiftWindowsPortableTests` and, on Windows,
`SwiftWindowsCoreLogicTests`, with their corresponding default directory paths.
It does not declare `Tests/CompileFixtures` as a target or include it in either
test target. The test script's source discovery is rooted at
`Tests/SwiftWindowsCoreLogicTests`, and it invokes the declared SwiftPM tests;
it does not add this sibling directory to a target.
Do not move this source into an existing target or include it with a broad
manual source glob.

`expected-diagnostics.json` identifies the three intended source-location
diagnostic headers. A nonzero exit code alone never satisfies this fixture.
Require exactly those three errors, with the expected file, line, column, and
message. Reject import, module, SDK, configuration, missing-file, and unrelated
typechecking errors. Count diagnostic headers once; the compiler repeats the
message beside its caret source excerpt, which is not another error.

No actual-module compilation was executed when these fixture files were
authored. The separately preserved standalone model evidence typechecked
explicit Windows boundaries and rejected the original canonical loops, but it
used stubs and is not an execution of this fixture against WinSwiftUI.

## Explicit build inputs

The parent validation must supply an already-built WinSwiftUI module from the
integrated revision, its actual dependency module search directories, its
Clang module-map/header arguments, and the exact Windows SDK root. Record the
revision, toolchain version, source hash, input paths, arguments, output, and
exit code with that validation. Do not accept a stale module merely because a
directory exists. Do not run SwiftPM concurrently to obtain the module.

The following is an invocation template through the existing environment
wrapper, not a validated command or guessed build-path selection. Replace all
input placeholders with the parent build's actual paths and arguments. No new
validation script or test-discovery change is introduced by this fixture.

```powershell
$fixtureModuleSearchPaths = @('<absolute module directory from the integrated build>')
$fixtureClangArguments = @('<actual -Xcc/module-map/header arguments, one argument per entry>')
$fixtureSdkRoot = '<absolute Windows SDK root used by that build>'
$fixtureOutputRoot = '<new absolute directory under artifacts or OS temp>'
New-Item -ItemType Directory -Path $fixtureOutputRoot | Out-Null
$fixtureArguments = @(
    'swiftc', '-swift-version', '6', '-parse-as-library', '-typecheck',
    '-sdk', $fixtureSdkRoot,
    '-module-cache-path', (Join-Path $fixtureOutputRoot 'module-cache')
)
foreach ($fixtureModulePath in $fixtureModuleSearchPaths) {
    $fixtureArguments += @('-I', $fixtureModulePath)
}
$fixtureArguments += $fixtureClangArguments
$fixtureArguments += (Resolve-Path 'Tests/CompileFixtures/ViewBuilder/CanonicalOpaqueLoops.swift').Path
& .\scripts\with-swift.ps1 -Command $fixtureArguments *> (Join-Path $fixtureOutputRoot 'compiler.log')
$fixtureCompilerExit = $LASTEXITCODE
```

Compare the recorded log with `expected-diagnostics.json` before reporting the
expected rejection. If a newer compiler accepts the fixture, record that as a
changed result requiring review and rerun the relevant positive/public and
mounted suites; do not silently refresh the expected errors. This fixture
documents an open Windows compiler compatibility limit, not a relaxation of
the project's native SwiftUI API goal.
