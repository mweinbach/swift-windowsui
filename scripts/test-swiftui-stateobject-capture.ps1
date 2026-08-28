[CmdletBinding()]
param([string]$OutputRoot, [string]$SDKCaptureFixtureRoot)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'swiftui-stateobject-capture-common.ps1')
$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if ([string]::IsNullOrEmpty($OutputRoot)) {
    $OutputRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('stateobject-capture-synthetic-' + [Guid]::NewGuid().ToString('N'))
}
$OutputRoot = [System.IO.Path]::GetFullPath($OutputRoot)
if (Test-Path -LiteralPath $OutputRoot) { throw 'Synthetic output directory already exists.' }
[void](New-Item -ItemType Directory -Path $OutputRoot -Force)
[void](Assert-SwiftUIStateObjectDirectory $OutputRoot)
$script:captureChecks = 0
$script:fakeRequests = 0
$script:fakeMetadataRequests = 0
$script:powerShellProcessRequests = 0
$testFailures = [System.Collections.Generic.List[string]]::new()
$testNames = [System.Collections.Generic.List[string]]::new()
$notRunTests = [System.Collections.Generic.List[string]]::new()
$utf8 = [System.Text.UTF8Encoding]::new($false, $true)

function Assert-CaptureTest {
    param([bool]$Condition, [string]$Message)
    $script:captureChecks++
    if (-not $Condition) { throw $Message }
}

function Assert-CaptureThrows {
    param([scriptblock]$Action, [string]$Message, [string]$ExpectedMessage)
    $caught = $false
    try { & $Action } catch {
        $caught = $true
        if (-not [string]::IsNullOrEmpty($ExpectedMessage)) {
            Assert-CaptureTest ($_.Exception.Message -match $ExpectedMessage) "Wrong rejection reason for ${Message}: $($_.Exception.Message)"
        }
    }
    Assert-CaptureTest $caught $Message
}

function Invoke-CaptureTest {
    param([string]$Name, [scriptblock]$Action)
    $testNames.Add($Name)
    try { & $Action } catch { $testFailures.Add("${Name}: $($_.Exception.Message)") }
}

function Write-CaptureFixtureText {
    param([string]$Path, [AllowEmptyString()][string]$Text)
    [void](Get-SwiftUIBaselineRelativePath -Root $OutputRoot -Path $Path)
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) { [void](New-Item -ItemType Directory -Path $parent -Force) }
    [System.IO.File]::WriteAllText($Path, $Text, $utf8)
}

function New-CaptureFakeRawProcess {
    param([string]$StdoutPath, [string]$StderrPath, [int]$ExitCode = 0)
    $stdout = Get-SwiftUIStateObjectFileHash $StdoutPath
    $stderr = Get-SwiftUIStateObjectFileHash $StderrPath
    return [pscustomobject]@{
        startedAtUtc = '2026-08-28T00:00:00Z'; finishedAtUtc = '2026-08-28T00:00:00Z'
        processStarted = $true; processId = 123; exitCode = $ExitCode; timedOut = $false; outputLimitExceeded = $false
        observedDiscardedBytes = 0; terminationRequested = $false; terminationCompleted = $true; allRedirectedStreamsClosed = $true
        terminationNote = 'Synthetic record only; no compiler process exists.'
        stdoutBytes = $stdout.bytes; stderrBytes = $stderr.bytes; stdoutSha256 = $stdout.sha256; stderrSha256 = $stderr.sha256
        durationSeconds = 0; error = $null; cleanupErrors = @()
    }
}

$matrixRoot = Join-Path $repositoryRoot 'scripts/fixtures/swiftui-stateobject-isolation'
$matrixPath = Join-Path $matrixRoot 'matrix.json'
$matrix = $null
if ($PSVersionTable.PSVersion.Major -ge 7) {
    $matrix = Read-SwiftUIStateObjectMatrix -Path $matrixPath -SourceRoot $matrixRoot
} else {
    # Test-only DTO for pure PowerShell 5.1 functions. This is not the strict
    # production reader, which is explicitly tested as unsupported below.
    $document = [System.IO.File]::ReadAllText($matrixPath) | ConvertFrom-Json
    $hash = Get-SwiftUIStateObjectFileHash $matrixPath
    $sourceFiles = @($document.sourceFiles | ForEach-Object {
        $fileHash = Get-SwiftUIStateObjectFileHash (Join-Path $matrixRoot $_.path)
        [pscustomobject]@{ path = $fileHash.path; relativePath = $_.path; sha256 = $fileHash.sha256; bytes = $fileHash.bytes }
    })
    $matrix = [pscustomobject]@{ document = $document; sha256 = $hash.sha256; contentSha256 = '7608f38966424c4f9ca8628836a11aea3388ede5d7b9858c6e99f42474cd887b'; targets = $document.targets; cases = $document.cases; sourceFiles = $sourceFiles }
}
$policy = Get-SwiftUIStateObjectCapturePolicy
$sdkFixtureFiles = @(); $sdkFixtureVerified = $false
if ($PSBoundParameters.ContainsKey('SDKCaptureFixtureRoot')) {
    Invoke-CaptureTest 'explicit SDK source fixture verification without native discovery' {
        $script:sdkFixtureFiles = @(Read-SwiftUIStateObjectCaptureFixtureFiles -Root $SDKCaptureFixtureRoot)
        Assert-CaptureTest ($sdkFixtureFiles.Count -eq 11) 'The explicit source fixture must contain exactly the eleven required pinned inputs.'
        $script:sdkFixtureVerified = $true
    }
}
$attemptID = '0123456789abcdef0123456789abcdef'
$fakeProfileHash = 'a' * 64
$emptyStderr = Join-Path $OutputRoot 'empty-stderr.txt'
Write-CaptureFixtureText $emptyStderr ''
$emptyHash = Get-SwiftUIStateObjectFileHash $emptyStderr

function Set-CaptureFakeAdmission {
    param($Receipt, $Case, [string]$Target)
    $script:fakeRequests++
    $Receipt.launchAttempted = $true
    $Receipt.process = [pscustomobject]@{
        processStarted = $true; exitCode = 0; timedOut = $false; outputLimitExceeded = $false; abnormalTermination = $false
        allRedirectedStreamsClosed = $true; terminationCompleted = $true; error = $null; notRunReason = $null; artifactIssues = @()
        sil = [pscustomobject]@{ path = 'synthetic/case.sil'; sha256 = ('b' * 64); bytes = 12 }
    }
    $Receipt.diagnostics = New-SwiftUIStateObjectEmptyDiagnostics
    $Receipt.diagnostics.stderr = [pscustomobject]@{ path = $emptyStderr; sha256 = $emptyHash.sha256; bytes = 0 }
    $Receipt.raw = [pscustomobject]@{ synthetic = $true; caseID = $Case.caseID; target = $Target }
}

Invoke-CaptureTest 'inert imports and native entry gates' {
    foreach ($path in @('scripts/capture-swiftui-stateobject-isolation.ps1', 'scripts/swiftui-stateobject-capture-common.ps1')) {
        $tokens = $null; $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $repositoryRoot $path), [ref]$tokens, [ref]$errors)
        Assert-CaptureTest (@($errors).Count -eq 0) "PowerShell parse errors in $path"
        if ($path -like '*capture-common.ps1') {
            foreach ($statement in $ast.EndBlock.Statements) {
                Assert-CaptureTest ($statement -is [System.Management.Automation.Language.FunctionDefinitionAst] -or
                    ($statement -is [System.Management.Automation.Language.PipelineAst] -and $statement.Extent.Text.StartsWith('. (Join-Path'))) 'Common import contains a top-level workload.'
            }
        }
    }
    $entryText = [System.IO.File]::ReadAllText((Join-Path $repositoryRoot 'scripts/capture-swiftui-stateobject-isolation.ps1'))
    Assert-CaptureTest ($entryText.IndexOf('if (-not $IsMacOS)') -lt $entryText.IndexOf(". (Join-Path")) 'Native platform guard must precede imports and processes.'
    if ($PSVersionTable.PSVersion.Major -lt 7 -or [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
        $rejectedPath = Join-Path $OutputRoot 'unsupported-native-entry'
        Assert-CaptureThrows {
            & (Join-Path $PSScriptRoot 'capture-swiftui-stateobject-isolation.ps1') -MetadataOnly -OutputPath $rejectedPath `
                -SDKCaptureRoot (Join-Path $OutputRoot 'absent-sdk') -ExpectedCaptureManifestSHA256 $policy.captureManifestSHA256
        } 'Unsupported native entry unexpectedly returned successfully.'
        Assert-CaptureTest (-not (Test-Path -LiteralPath $rejectedPath)) 'Unsupported host created native evidence or work directories.'
    }
    if ($PSVersionTable.PSVersion.Major -lt 7) {
        Assert-CaptureThrows { Read-SwiftUIStateObjectJson $matrixPath } 'PowerShell 5.1 incorrectly claimed strict JSON support.'
    }
}

Invoke-CaptureTest 'workflow remains manual with separate review-gated modes and owned artifact selection' {
    $workflow = [System.IO.File]::ReadAllText((Join-Path $repositoryRoot '.github/workflows/swiftui-stateobject-isolation.yml'))
    Assert-CaptureTest ($workflow -match '(?m)^on:\r?\n  workflow_dispatch:') 'Workflow must expose only manual dispatch.'
    Assert-CaptureTest ($workflow -notmatch '(?m)^  (push|pull_request|schedule|workflow_run|workflow_call):') 'An automatic workflow trigger was introduced.'
    Assert-CaptureTest ($workflow -match 'runs-on: macos-26-intel' -and $workflow -match 'timeout-minutes: 45') 'Pinned runner or bounded job policy changed.'
    Assert-CaptureTest ([regex]::Matches($workflow, 'artifact-ids:').Count -eq 2 -and [regex]::Matches($workflow, 'merge-multiple: true').Count -eq 2) 'Exact verified artifact IDs must be used for both downloads.'
    Assert-CaptureTest ($workflow -match 'contents: read' -and $workflow -match 'actions: read' -and $workflow -notmatch '(?m)^\s+(contents|actions): write') 'Workflow permissions expanded.'
    Assert-CaptureTest ($workflow -match '-MetadataOnly' -and $workflow -match '-Cases' -and $workflow -match '-ReviewedProfileSHA256' -and $workflow -match '-ReviewedMatrixSHA256') 'Separate metadata/case invocations or review inputs disappeared.'
    Assert-CaptureTest ($workflow -notmatch '(?m)^\s+(swift|swiftc|xcodebuild) (build|run|test)|workflow_dispatch.*POST|gh workflow run') 'Workflow must not build/run a product or dispatch another workflow.'
}

Invoke-CaptureTest 'exact SIL-only commands and unchanged public sources' {
    $index = 0
    foreach ($target in $matrix.targets) {
        $caseIndex = 0
        foreach ($case in $matrix.cases) {
            $index++; $caseIndex++
            $arch = $target.Split('-')[0]
            $commandArgs = @{
                Matrix = $matrix; Case = $case; CompilerPath = '/pinned/swiftc'; SDKPath = $policy.sdkPath; Target = $target
                SourceRoot = $matrixRoot; CachePath = (Join-Path $OutputRoot "cache-$arch")
                SILPath = (Join-Path $OutputRoot "synthetic-$index.sil"); ModuleName = ('SOI_{0:D2}_{1}' -f $caseIndex, $arch)
            }
            $request = New-SwiftUIStateObjectCompilerRequest @commandArgs
            Assert-CaptureTest (@($request.arguments | Where-Object { $_ -ceq '-emit-sil' }).Count -eq 1) 'SIL must be the only output action.'
            Assert-CaptureTest (@($request.arguments | Where-Object { $_ -match '^-emit-(object|library|executable)$|^-D$|^-I|^-F' }).Count -eq 0) 'Compiler command contains an unreviewed action or overlay.'
            Assert-CaptureTest (@($request.arguments | Where-Object { $_ -like '*.swift' }).Count -eq (@($case.sharedSources).Count + 1)) 'A case received unrelated common sources.'
            foreach ($bad in @('-emit-executable', '-emit-library', '-emit-object', '-D', '-Xfrontend', '-swift-version')) {
                $changed = [pscustomobject]@{ filePath = $request.filePath; arguments = @($request.arguments) + @($bad) }
                Assert-CaptureThrows { Assert-SwiftUIStateObjectCompilerRequest -Request $changed @commandArgs } "Extra compiler flag $bad was accepted."
            }
        }
    }
    Assert-CaptureTest ($index -eq 42) 'The exact command matrix does not contain 42 requests.'
}

Invoke-CaptureTest '42 candidate admissions remain separate from safety and control requirements' {
    $record = Invoke-SwiftUIStateObjectCasePlan -Matrix $matrix -AttemptID $attemptID -CompilerProfileSHA256 $fakeProfileHash `
        -Request { param($case, $target, $index, $timeout, $receipt) Set-CaptureFakeAdmission $receipt $case $target } `
        -AssertStableInputs { } -ElapsedSeconds { 0 }
    Assert-CaptureTest ($record.completed -and $record.results.Count -eq 42) 'Ordinary admissions did not complete the bounded collection.'
    Assert-CaptureTest (@($record.results | Where-Object { $_.launchState -ceq 'confirmed-started' }).Count -eq 42) 'Confirmed launches were lost.'
    Assert-CaptureTest (@($record.results | Where-Object { $_.assessment.safetyRequirementMet -ceq $false }).Count -eq 4) 'Unsafe admissions must retain all four safety disagreements.'
    Assert-CaptureTest (@($record.results | Where-Object { $_.assessment.controlRequirementMet -ceq $false }).Count -eq 8) 'Admitted negative controls must remain disagreements.'
    foreach ($item in $record.results) {
        Assert-CaptureTest (-not $item.assessment.runtimeEvidence -and -not $item.assessment.parityClaimed -and -not $item.assessment.productionApprovalChanged) 'A candidate cell promoted qualification.'
    }
}

Invoke-CaptureTest 'no request starts after preflight drift or deadline' {
    foreach ($mode in @('drift', 'deadline')) {
        $before = $script:fakeRequests
        $guard = { throw 'Synthetic source/profile hash drift.' }
        $clock = { 0 }
        if ($mode -ceq 'deadline') { $guard = { }; $clock = { 1800 } }
        $record = Invoke-SwiftUIStateObjectCasePlan -Matrix $matrix -AttemptID $attemptID -CompilerProfileSHA256 $fakeProfileHash `
            -Request { param($case, $target, $index, $timeout, $receipt) Set-CaptureFakeAdmission $receipt $case $target } `
            -AssertStableInputs $guard -ElapsedSeconds $clock
        Assert-CaptureTest (-not $record.completed -and $record.results.Count -eq 42) 'Failed preflight lost planned cells.'
        Assert-CaptureTest ($script:fakeRequests -eq $before) 'A request ran after failed preflight.'
        Assert-CaptureTest (@($record.results | Where-Object { $_.launchState -ceq 'not-run' }).Count -eq 42) 'Never invoked cells were not kept as unrun.'
    }
}

Invoke-CaptureTest 'post-launch failure keeps the launched record and earlier outcomes' {
    $record = Invoke-SwiftUIStateObjectCasePlan -Matrix $matrix -AttemptID $attemptID -CompilerProfileSHA256 $fakeProfileHash `
        -Request {
            param($case, $target, $index, $timeout, $receipt)
            Set-CaptureFakeAdmission $receipt $case $target
            if ($index -eq 3) { throw 'Synthetic failure writing request.json after process collection.' }
        } -AssertStableInputs { } -ElapsedSeconds { 0 }
    Assert-CaptureTest (-not $record.completed -and $record.results.Count -eq 42) 'Post-launch failure lost the matrix.'
    Assert-CaptureTest ($record.results[0].assessment.observedOutcome -ceq 'source-admitted') 'An earlier valid result was rewritten as unrun.'
    Assert-CaptureTest ($record.results[2].launchState -ceq 'confirmed-started' -and $record.results[2].process.exitCode -eq 0) 'The failed collector lost an actual process receipt.'
    Assert-CaptureTest ($record.results[2].assessment.observedOutcome -ceq 'artifact-failure') 'Post-process collection failure was incorrectly qualified.'
    Assert-CaptureTest ($record.results[2].raw.synthetic -and $record.results[2].raw.caseID -ceq $matrix.cases[2].caseID -and
        $record.results[2].raw.target -ceq $matrix.targets[0] -and $record.results[2].collectionError -match 'request.json') 'Post-launch failure lost its original raw record or reason.'
    Assert-CaptureTest (@($record.results | Where-Object { $_.launchState -ceq 'not-run' }).Count -eq 39) 'The remaining cells were not retained as unrun.'
}

Invoke-CaptureTest 'unknown launch and invalid classification never fabricate unrun or erase history' {
    foreach ($failure in @('helper-throw', 'assessment')) {
        $faultKind = $failure
        $record = Invoke-SwiftUIStateObjectCasePlan -Matrix $matrix -AttemptID $attemptID -CompilerProfileSHA256 $fakeProfileHash `
            -Request {
                param($case, $target, $index, $timeout, $receipt)
                if ($index -eq 2 -and $faultKind -ceq 'helper-throw') {
                    $receipt.launchAttempted = $true; $receipt.raw = [pscustomobject]@{ invocationStarted = $true }
                    throw 'Synthetic exception inside an invoked helper; process launch is unconfirmed.'
                }
                Set-CaptureFakeAdmission $receipt $case $target
                if ($index -eq 2) { $receipt.process.sil.bytes = -1 }
            } -AssertStableInputs { } -ElapsedSeconds { 0 }
        Assert-CaptureTest (-not $record.completed -and $record.results.Count -eq 42) 'A classifier/helper failure discarded the matrix.'
        Assert-CaptureTest ($record.results[0].assessment.observedOutcome -ceq 'source-admitted') 'Earlier evidence was erased.'
        Assert-CaptureTest ($null -eq $record.results[1].assessment) 'An unverified receipt acquired an assessment.'
        if ($faultKind -ceq 'helper-throw') {
            Assert-CaptureTest ($record.results[1].launchState -ceq 'unknown-after-invocation' -and $null -eq $record.results[1].process) 'Unknown launch was incorrectly relabeled not-run.'
            Assert-CaptureTest ($record.results[1].raw.invocationStarted -and $record.results[1].collectionError -match 'unconfirmed') 'Unknown launch lost its raw invocation marker.'
        } else {
            Assert-CaptureTest ($record.results[1].launchState -ceq 'confirmed-started') 'Classifier failure lost confirmed launch.'
            Assert-CaptureTest ($record.results[1].raw.synthetic -and $record.results[1].raw.caseID -ceq $matrix.cases[1].caseID -and
                $record.results[1].collectionError -match 'classification failed') 'Classifier failure lost its raw record or failure reason.'
        }
        Assert-CaptureTest (@($record.results | Where-Object { $_.launchState -ceq 'not-run' }).Count -eq 40) 'Remaining requests were not kept unrun.'
    }
}

Invoke-CaptureTest 'fatal process states stop and retain the original failure' {
    foreach ($kind in @('timeout', 'output', 'streams', 'configuration', 'crash', 'integrity')) {
        $faultKind = $kind
        $record = Invoke-SwiftUIStateObjectCasePlan -Matrix $matrix -AttemptID $attemptID -CompilerProfileSHA256 $fakeProfileHash `
            -Request {
                param($case, $target, $index, $timeout, $receipt)
                Set-CaptureFakeAdmission $receipt $case $target
                switch ($faultKind) {
                    'timeout' { $receipt.process.timedOut = $true }
                    'output' { $receipt.process.outputLimitExceeded = $true }
                    'streams' { $receipt.process.allRedirectedStreamsClosed = $false }
                    'configuration' { $receipt.diagnostics.hasConfigurationFailure = $true }
                    'crash' { $receipt.diagnostics.hasCrashMarker = $true }
                    'integrity' { $receipt.process.artifactIssues = @('Synthetic stream/source hash mismatch.') }
                }
            } -AssertStableInputs { } -ElapsedSeconds { 0 }
        Assert-CaptureTest (-not $record.completed -and $record.results.Count -eq 42) 'Infrastructure failure did not stop the matrix.'
        Assert-CaptureTest ($record.results[0].launchState -ceq 'confirmed-started') 'Infrastructure failure lost its launch receipt.'
        Assert-CaptureTest (@($record.results | Where-Object { $_.launchState -ceq 'not-run' }).Count -eq 41) 'The matrix launched requests after an infrastructure stop.'
    }
}

# PowerShell 7-only profile/JSON and real PowerShell-child adapter cases are
# appended below. PowerShell 5.1 runs only the pure protocol and explicit gates.

Invoke-CaptureTest 'committed input membership is tied to actual blob bytes' {
    $fixtureRoot = Join-Path $OutputRoot 'git-blob-fixture'
    $first = Join-Path $fixtureRoot 'one.txt'; $second = Join-Path $fixtureRoot 'two.txt'
    Write-CaptureFixtureText $first 'one'; Write-CaptureFixtureText $second 'two'
    $listing = "100644 blob $(Get-SwiftUIStateObjectGitBlobSHA1 $first)`tone.txt`0" +
        "100644 blob $(Get-SwiftUIStateObjectGitBlobSHA1 $second)`ttwo.txt`0"
    Assert-SwiftUIStateObjectTrackedInputs -Listing $listing -Paths @('one.txt', 'two.txt') -RepositoryRoot $fixtureRoot
    Assert-CaptureTest $true 'Valid synthetic Git blob membership should pass.'
    Assert-CaptureThrows { Assert-SwiftUIStateObjectTrackedInputs -Listing '' -Paths @('one.txt', 'two.txt') -RepositoryRoot $fixtureRoot } 'Untracked required inputs were accepted.'
    Write-CaptureFixtureText $second 'changed while status could have a skip-worktree flag'
    Assert-CaptureThrows { Assert-SwiftUIStateObjectTrackedInputs -Listing $listing -Paths @('one.txt', 'two.txt') -RepositoryRoot $fixtureRoot } 'Blob-byte drift was accepted.'
    Assert-CaptureThrows { Assert-SwiftUIStateObjectTrackedInputs -Listing $listing.Replace('100644', '120000') -Paths @('one.txt', 'two.txt') -RepositoryRoot $fixtureRoot } 'Git symlink inputs were accepted as regular blobs.'
}

if ($PSVersionTable.PSVersion.Major -ge 7) {
    function Invoke-CaptureSnapshotTest {
        param([string]$Name, [scriptblock]$Action)
        if (-not $sdkFixtureVerified) {
            $notRunTests.Add("${Name}: the full SDK source fixture was not supplied or did not validate.")
            return
        }
        Invoke-CaptureTest $Name $Action
    }
    $fakeNativeRoot = Join-Path $OutputRoot 'fake-native-profile'
    [void](New-Item -ItemType Directory -Path $fakeNativeRoot)
    $fakeSource = [pscustomobject]@{
        commit = ('c' * 40); tree = ('d' * 40); trackedWorkingTree = ''
        workflow = [pscustomobject]@{ eventName = 'synthetic-no-native-execution' }
    }
    $fakeSourceFiles = @(Get-SwiftUIStateObjectCaptureSources -RepositoryRoot $repositoryRoot -Matrix $matrix)
    $fakeSDK = [pscustomobject]@{
        canonicalSDKPath = $policy.sdkPath
        settings = [pscustomobject]@{ path = "$($policy.sdkPath)/SDKSettings.json"; canonicalPath = "$($policy.sdkPath)/SDKSettings.json"; sha256 = $policy.sdkSettingsSHA256; bytes = 123 }
        anchors = @($policy.interfaceAnchors | ForEach-Object {
            $parts = $_.path.Split('/')
            $relative = "System/Library/Frameworks/$($parts[1]).framework/Modules/$($parts[1]).swiftmodule/$($parts[2])"
            [pscustomobject]@{
                capturePath = $_.path; sdkRelativeSource = $relative
                live = [pscustomobject]@{ path = "$($policy.sdkPath)/$relative"; canonicalPath = "$($policy.sdkPath)/$relative"; sha256 = $_.sha256; bytes = 123 }
                platform = $_.platform; interfaceArchitecture = $_.interfaceArchitecture
                producerCompiler = 'Apple Swift 6.3.2 effective-5.10'; producerModuleLanguageMode = '5'
            }
        })
        files = @((Get-SwiftUIStateObjectCaptureFilePolicy) | ForEach-Object {
            [pscustomobject]@{ path = $null; relativePath = $_.path; sha256 = $_.sha256; bytes = 123 }
        })
    }
    if ($sdkFixtureVerified) {
        $fakeSDK.files = $sdkFixtureFiles
        $fakeSDK.settings.bytes = @($sdkFixtureFiles | Where-Object { $_.relativePath -ceq 'SDKSettings.json' })[0].bytes
        foreach ($anchor in $fakeSDK.anchors) {
            $anchor.live.bytes = @($sdkFixtureFiles | Where-Object { $_.relativePath -ceq $anchor.capturePath })[0].bytes
        }
    }
    $fakeToolReader = {
        param($path)
        $hash = '1' * 64
        if ($path.EndsWith('/swift-frontend')) { $hash = '2' * 64 }
        [pscustomobject]@{ path = $path; canonicalPath = $path; sha256 = $hash; bytes = 123 }
    }
    $fakeMetadata = {
        param($id, $filePath, $arguments)
        $script:fakeMetadataRequests++
        $text = ''
        switch -Regex ($id) {
            '^xcode-version$' { $text = "Xcode 26.6`nBuild version 17F113`n"; break }
            '^sdk-path$' { $text = $policy.sdkPath + "`n"; break }
            '^sdk-version$' { $text = "26.5`n"; break }
            '^sdk-build$' { $text = "25F70`n"; break }
            '^find-(.+)$' { $text = "$($policy.developerDirectory)/Toolchains/XcodeDefault.xctoolchain/usr/bin/$($Matches[1])`n"; break }
            '^swift.+-version$' { $text = $policy.compilerVersionLine + "`n"; break }
            '^swift.+-target-.+$' {
                $text = ([pscustomobject]@{ compilerVersion = $policy.compilerVersionLine; target = [pscustomobject]@{ triple = $arguments[-1] } } | ConvertTo-Json -Depth 4) + "`n"
                break
            }
            '^host-version$' { $text = "26.6.1`n"; break }
            '^host-build$' { $text = "25G76`n"; break }
            '^host-architecture$' { $text = "x86_64`n"; break }
            default { throw "Unexpected fake metadata request $id" }
        }
        $stdout = Join-Path $fakeNativeRoot "metadata/$id.stdout.txt"; $stderr = Join-Path $fakeNativeRoot "metadata/$id.stderr.txt"
        Write-CaptureFixtureText $stdout $text; Write-CaptureFixtureText $stderr ''
        $process = New-CaptureFakeRawProcess $stdout $stderr
        $hash = '3' * 64
        if ($filePath.EndsWith('/swiftc')) { $hash = '1' * 64 }
        if ($filePath.EndsWith('/swift-frontend')) { $hash = '2' * 64 }
        $raw = [pscustomobject]@{
            id = $id; filePath = $filePath; canonicalPath = $filePath; executableSHA256 = $hash; executableBytes = 123
            arguments = @($arguments); workingDirectory = '/synthetic-metadata-work-never-executed'
            environment = [pscustomobject]@{ overrideNames = @('DEVELOPER_DIR', 'LANG', 'LC_ALL', 'TEMP', 'TMP', 'TMPDIR'); developerDirectory = $policy.developerDirectory }
            stdoutPath = "metadata/$id.stdout.txt"; stderrPath = "metadata/$id.stderr.txt"; process = $process
        }
        [void](Write-SwiftUIStateObjectCaptureJson -Path (Join-Path $fakeNativeRoot "metadata/$id.request.json") -Value $raw)
        [pscustomobject]@{ text = $text; stdoutPath = $stdout; raw = $raw }
    }
    $fakeCompilerProfile = $null; $fakeCompilerProfileFile = $null
    Invoke-CaptureTest 'metadata-only profile binds actual separate tools without case requests' {
        $before = $script:fakeRequests
        $script:fakeCompilerProfile = Get-SwiftUIStateObjectMetadataProfile -Matrix $matrix -SDKInputs $fakeSDK -AttemptID $attemptID `
            -Source $fakeSource -SourceFiles $fakeSourceFiles -ExecuteMetadata $fakeMetadata -InspectTool $fakeToolReader
        Assert-CaptureTest ($script:fakeRequests -eq $before -and $script:fakeMetadataRequests -eq 15) 'Metadata profile invoked a case or changed its metadata recipe.'
        Assert-CaptureTest ($fakeCompilerProfile.caseRequests -eq 0 -and $fakeCompilerProfile.status -ceq 'metadata-only-awaiting-review') 'Metadata candidate was promoted to case approval.'
        Assert-CaptureTest ($fakeCompilerProfile.tools[0].file.sha256 -cne $fakeCompilerProfile.tools[1].file.sha256) 'Frontend identity was inferred from the compiler or captured swift hash.'
        foreach ($request in $fakeCompilerProfile.metadataRequests) {
            Assert-CaptureTest (@($request.arguments | Where-Object { $_ -match 'emit-|\.swift$|\.sil$|^-I|^-F|^-D' }).Count -eq 0) 'Metadata-only mode contains a compilation request.'
        }
        Assert-CaptureTest (@($fakeCompilerProfile.sdk.anchors | Where-Object { $_.platform -ceq 'macOS' }).Count -eq 4) 'Desktop and Catalyst source anchors were conflated.'
        Assert-CaptureTest (@($fakeCompilerProfile.sdk.anchors | Where-Object { $_.platform -ceq 'Catalyst-source-only' }).Count -eq 2) 'Catalyst source anchor count changed.'
        $script:fakeCompilerProfileFile = Write-SwiftUIStateObjectCaptureJson -Path (Join-Path $fakeNativeRoot 'profile.json') -Value $fakeCompilerProfile
        if ($sdkFixtureVerified) {
            foreach ($file in $fakeCompilerProfile.sourceFiles) {
                $relative = 'sources/harness/' + [System.IO.Path]::GetFileName($file.path)
                if ($file.path -cnotin $policy.harnessPaths) { $relative = 'sources/' + $file.path.Substring('scripts/fixtures/swiftui-stateobject-isolation/'.Length) }
                [void](Copy-SwiftUIStateObjectCaptureInput -Source (Join-Path $repositoryRoot $file.path) -Destination (Join-Path $fakeNativeRoot $relative) -SHA256 $file.sha256)
            }
            [void](Copy-SwiftUIStateObjectCaptureInput -Source $matrixPath -Destination (Join-Path $fakeNativeRoot 'sources/matrix.json') -SHA256 $matrix.sha256)
            foreach ($file in $sdkFixtureFiles) {
                [void](Copy-SwiftUIStateObjectCaptureInput -Source $file.path -Destination (Join-Path $fakeNativeRoot "sdk/$($file.relativePath)") -SHA256 $file.sha256)
            }
            [void](Write-SwiftUIStateObjectCaptureJson -Path (Join-Path $fakeNativeRoot 'source-inputs.json') -Value ([pscustomobject]@{
                source = $fakeSource; files = $fakeSourceFiles; matrixSHA256 = $matrix.sha256; captureManifestSHA256 = $policy.captureManifestSHA256
            }))
        }
    }

    function Seal-CaptureFakeMetadataPacket {
        param([string]$Root)
        $manifest = [pscustomobject]@{
            schemaVersion = 1; product = 'swiftui-stateobject-isolation'; mode = 'metadata-only'; attemptID = $attemptID
            status = 'metadata-only-awaiting-review'; startedAtUtc = '2026-08-28T00:00:00Z'; finishedAtUtc = '2026-08-28T00:00:00Z'
            source = $fakeSource; executionHost = $fakeCompilerProfile.nativeHost
            captureManifestSHA256 = $policy.captureManifestSHA256; matrixSHA256 = $matrix.sha256
            compilerProfileSHA256 = $fakeCompilerProfileFile.sha256; reviewedProfileSHA256 = $null; reviewedMatrixSHA256 = $null
            profileFile = [pscustomobject]@{ path = 'profile.json'; sha256 = $fakeCompilerProfileFile.sha256; bytes = $fakeCompilerProfileFile.bytes }
            caseRequests = 0; unconfirmedCaseRequests = 0; expectedCaseRequests = 0; results = @()
            disagreements = [pscustomobject]@{ safety = 0; controls = 0; collectionSuccessDoesNotApproveSafety = $true }
            issues = @(); artifactFiles = @(Get-SwiftUIStateObjectEvidenceInventory $Root); qualification = $policy.qualification
        }
        $hash = Write-SwiftUIStateObjectCaptureJson -Path (Join-Path $Root 'manifest.json') -Value $manifest
        Write-CaptureFixtureText (Join-Path $Root 'manifest.sha256') "$($hash.sha256)  manifest.json`n"
    }

    function New-CaptureFakePacketCopy {
        param([string]$Name, [AllowNull()][scriptblock]$Mutate, [string]$OmitPath)
        $copyRoot = Join-Path $OutputRoot $Name
        [void](New-Item -ItemType Directory -Path $copyRoot)
        foreach ($file in (Get-SwiftUIStateObjectEvidenceInventory $fakeNativeRoot)) {
            if ($file.path -ceq $OmitPath) { continue }
            [void](Copy-SwiftUIStateObjectCaptureInput -Source (Join-Path $fakeNativeRoot $file.path) -Destination (Join-Path $copyRoot $file.path) -SHA256 $file.sha256)
        }
        if ($null -ne $Mutate) { & $Mutate $copyRoot }
        Seal-CaptureFakeMetadataPacket $copyRoot
        return $copyRoot
    }

    Invoke-CaptureSnapshotTest 'review requires both explicit hashes and the completed matching packet' {
        if ($null -eq $fakeCompilerProfileFile) { throw 'Synthetic metadata setup failed.' }
        Assert-CaptureThrows {
            Read-SwiftUIStateObjectReviewedProfile -Path $fakeCompilerProfileFile.path -ReviewedProfileSHA256 $fakeCompilerProfileFile.sha256 -ReviewedMatrixSHA256 $matrix.sha256 -Matrix $matrix
        } 'A profile without a final manifest was accepted.'
        Seal-CaptureFakeMetadataPacket $fakeNativeRoot
        $read = Read-SwiftUIStateObjectReviewedProfile -Path $fakeCompilerProfileFile.path -ReviewedProfileSHA256 $fakeCompilerProfileFile.sha256 -ReviewedMatrixSHA256 $matrix.sha256 -Matrix $matrix
        Assert-CaptureTest ($read.sha256 -ceq $fakeCompilerProfileFile.sha256) 'Valid synthetic reviewed-profile intake failed.'
        Assert-CaptureThrows { Read-SwiftUIStateObjectReviewedProfile -Path $fakeCompilerProfileFile.path -ReviewedProfileSHA256 ('0' * 64) -ReviewedMatrixSHA256 $matrix.sha256 -Matrix $matrix } 'Mismatched profile review hash was accepted.'
        Assert-CaptureThrows { Read-SwiftUIStateObjectReviewedProfile -Path $fakeCompilerProfileFile.path -ReviewedProfileSHA256 $fakeCompilerProfileFile.sha256 -ReviewedMatrixSHA256 ('0' * 64) -Matrix $matrix } 'Mismatched matrix review hash was accepted.'
        Assert-CaptureThrows { Read-SwiftUIStateObjectReviewedProfile -Path $fakeCompilerProfileFile.path -ReviewedProfileSHA256 '' -ReviewedMatrixSHA256 $matrix.sha256 -Matrix $matrix } 'Missing explicit profile hash was accepted.'
    }

    Invoke-CaptureSnapshotTest 'resealing an altered archive cannot change approved profile observations' {
        foreach ($kind in @('stdout', 'request', 'target')) {
            $faultKind = $kind
            $copy = New-CaptureFakePacketCopy -Name "tampered-$kind" -Mutate {
                param($root)
                switch ($faultKind) {
                    'stdout' { Write-CaptureFixtureText (Join-Path $root 'metadata/swiftc-version.stdout.txt') 'substituted compiler version' }
                    'request' { Write-CaptureFixtureText (Join-Path $root 'metadata/swiftc-version.request.json') '{"substituted":true}' }
                    'target' { Write-CaptureFixtureText (Join-Path $root 'metadata/swiftc-target-arm64.stdout.txt') '{"compilerVersion":"unrelated","target":{"triple":"arm64-apple-ios26.5-macabi"}}' }
                }
            }
            Assert-CaptureTest ((Get-SwiftUIStateObjectFileHash (Join-Path $copy 'profile.json')).sha256 -ceq $fakeCompilerProfileFile.sha256) 'Tamper test accidentally changed the reviewed profile.'
            Assert-CaptureThrows {
                Read-SwiftUIStateObjectReviewedProfile -Path (Join-Path $copy 'profile.json') -ReviewedProfileSHA256 $fakeCompilerProfileFile.sha256 -ReviewedMatrixSHA256 $matrix.sha256 -Matrix $matrix
            } 'A resealed mutable manifest bypassed the profile-bound raw evidence hashes.' 'metadata (streams disagree|request differs)'
        }
    }

    Invoke-CaptureSnapshotTest 'profile filename and mandatory copied snapshots cannot be omitted' {
        foreach ($relative in @('sources/harness/swiftui-stateobject-process-common.ps1', 'sources/paired-public/01-direct.swift',
                'sources/matrix.json', 'sdk/SDKSettings.json', 'source-inputs.json', 'metadata/swiftc-version.stdout.txt')) {
            $name = 'omitted-' + $relative.Replace('/', '-').Replace('.', '-')
            $copy = New-CaptureFakePacketCopy -Name $name -OmitPath $relative
            Assert-CaptureThrows {
                Read-SwiftUIStateObjectReviewedProfile -Path (Join-Path $copy 'profile.json') -ReviewedProfileSHA256 $fakeCompilerProfileFile.sha256 -ReviewedMatrixSHA256 $matrix.sha256 -Matrix $matrix
            } "Missing required snapshot $relative was accepted." 'does not exist|Cannot find path|missing|not found'
        }
        $alias = New-CaptureFakePacketCopy -Name 'renamed-profile' -OmitPath 'profile.json' -Mutate {
            param($root)
            [void](Copy-SwiftUIStateObjectCaptureInput -Source $fakeCompilerProfileFile.path -Destination (Join-Path $root 'alias.json') -SHA256 $fakeCompilerProfileFile.sha256)
        }
        Assert-CaptureThrows {
            Read-SwiftUIStateObjectReviewedProfile -Path (Join-Path $alias 'alias.json') -ReviewedProfileSHA256 $fakeCompilerProfileFile.sha256 -ReviewedMatrixSHA256 $matrix.sha256 -Matrix $matrix
        } 'Renamed profile bypassed the declared filename.' 'must name the packet profile.json'
    }

    Invoke-CaptureTest 'profile shape rejects weaker modes and missing tool pins' {
        foreach ($kind in @('tool', 'language', 'target', 'producer', 'runtime', 'missing-metadata', 'numeric-string', 'windows-path', 'environment')) {
            $copy = ($fakeCompilerProfile | ConvertTo-Json -Depth 40) | ConvertFrom-Json
            switch ($kind) {
                'tool' { $copy.tools[1].file.sha256 = $null }
                'language' { $copy.clientFlags[1] = '5' }
                'target' { $copy.targets[1] = 'arm64-apple-ios26.5-macabi' }
                'producer' { $copy.tools[0].versionOutput = 'Apple Swift version 6.3.2 effective-5.10' }
                'runtime' { $copy.qualification.runtimeEvidence = $true }
                'missing-metadata' { $copy.metadataRequests = @($copy.metadataRequests | Select-Object -First 14) }
                'numeric-string' { $copy.metadataRequests[0].process.stdoutBytes = '200000'; $copy.metadataRequests[0].process.stderrBytes = 100000 }
                'windows-path' { $copy.metadataRequests[0].workingDirectory = 'C:\not-a-native-producer-path' }
                'environment' { $copy.metadataRequests[0].environment.overrideNames += 'SDKROOT' }
            }
            Assert-CaptureThrows { Assert-SwiftUIStateObjectProfileShape -CompilerProfile $copy -Matrix $matrix } "Malformed profile $kind was accepted."
        }
    }

    $casePacketRoot = Join-Path $OutputRoot 'complete-case-packet'
    $casePacketManifest = $null; $casePacketValidated = $false
    Invoke-CaptureSnapshotTest 'complete synthetic case packet replays after archive relocation' {
        [void](New-Item -ItemType Directory -Path $casePacketRoot)
        $sourceCopy = Join-Path $casePacketRoot 'sources'
        [void](New-Item -ItemType Directory -Path $sourceCopy)
        foreach ($file in $matrix.sourceFiles) {
            [void](Copy-SwiftUIStateObjectCaptureInput -Source $file.path -Destination (Join-Path $sourceCopy $file.relativePath) -SHA256 $file.sha256)
        }
        [void](Copy-SwiftUIStateObjectCaptureInput -Source $matrixPath -Destination (Join-Path $sourceCopy 'matrix.json') -SHA256 $matrix.sha256)
        $reviewFiles = @(Get-SwiftUIStateObjectEvidenceInventory $fakeNativeRoot)
        foreach ($name in @('manifest.json', 'manifest.sha256')) {
            $hash = Get-SwiftUIStateObjectFileHash (Join-Path $fakeNativeRoot $name)
            $reviewFiles += [pscustomobject]@{ path = $name; sha256 = $hash.sha256; bytes = $hash.bytes }
        }
        foreach ($file in $reviewFiles) {
            [void](Copy-SwiftUIStateObjectCaptureInput -Source (Join-Path $fakeNativeRoot $file.path) `
                -Destination (Join-Path $casePacketRoot "reviewed-profile/$($file.path)") -SHA256 $file.sha256)
        }
        $packetMatrix = Read-SwiftUIStateObjectMatrix -Path (Join-Path $sourceCopy 'matrix.json') -SourceRoot $sourceCopy
        $originalOutput = '/synthetic-native-capture-that-was-never-executed'
        $plan = Invoke-SwiftUIStateObjectCasePlan -Matrix $matrix -AttemptID $attemptID -CompilerProfileSHA256 $fakeCompilerProfileFile.sha256 `
            -Request {
                param($case, $target, $index, $timeout, $receipt)
                $script:fakeRequests++
                $arch = $target.Split('-')[0]; $module = 'SOI_{0:D2}_{1}' -f $index, $arch
                $prefix = "requests/$arch/$module"
                $stdout = Join-Path $casePacketRoot "$prefix/stdout.txt"; $stderr = Join-Path $casePacketRoot "$prefix/stderr.txt"
                Write-CaptureFixtureText $stdout ''; Write-CaptureFixtureText $stderr ''
                Write-CaptureFixtureText (Join-Path $casePacketRoot "$prefix/case.sil") '// SYNTHETIC: no compiler generated this fixture.'
                $sil = Get-SwiftUIStateObjectFileHash (Join-Path $casePacketRoot "$prefix/case.sil")
                $rawProcess = New-CaptureFakeRawProcess $stdout $stderr
                $sources = @($packetMatrix.sourceFiles | Where-Object { $_.relativePath -cin (@($case.sharedSources) + @($case.source)) })
                $capturePaths = [ordered]@{}
                $rawSources = @($sources | ForEach-Object {
                    $capturePath = "$originalOutput/evidence/sources/$($_.relativePath)"
                    $capturePaths.Add($_.relativePath, $capturePath)
                    [pscustomobject]@{ path = $capturePath; relativePath = $_.relativePath; sha256 = $_.sha256; bytes = $_.bytes }
                })
                $arguments = @($matrix.document.requiredFlags) + @('-sdk', $policy.sdkPath, '-target', $target,
                    '-module-cache-path', "$originalOutput/work/module-cache/$arch", '-module-name', $module)
                foreach ($path in @($case.sharedSources) + @($case.source)) { $arguments += $capturePaths[$path] }
                $arguments += @('-o', "$originalOutput/work/$prefix/case.sil")
                $raw = [pscustomobject]@{
                    attemptID = $attemptID; target = $target; caseID = $case.caseID; compilerProfileSHA256 = $fakeCompilerProfileFile.sha256
                    filePath = $fakeCompilerProfile.tools[0].file.canonicalPath; arguments = $arguments; workingDirectory = "$originalOutput/work/$prefix"
                    environment = [pscustomobject]@{ overrideNames = @('DEVELOPER_DIR', 'LANG', 'LC_ALL', 'TEMP', 'TMP', 'TMPDIR'); developerDirectory = $policy.developerDirectory }
                    timeoutSeconds = $timeout; stdoutPath = "$prefix/stdout.txt"; stderrPath = "$prefix/stderr.txt"; sourceFiles = $rawSources; process = $rawProcess
                }
                $receipt.launchAttempted = $true; $receipt.raw = $raw
                $receipt.process = [pscustomobject]@{
                    processStarted = $true; exitCode = 0; timedOut = $false; outputLimitExceeded = $false; abnormalTermination = $false
                    allRedirectedStreamsClosed = $true; terminationCompleted = $true; error = $null; notRunReason = $null; artifactIssues = @()
                    sil = [pscustomobject]@{ path = "$prefix/case.sil"; sha256 = $sil.sha256; bytes = $sil.bytes }
                }
                $receipt.diagnostics = Get-SwiftUIStateObjectDiagnostics -StderrPath $stderr -Sources $sources -Case $case -DiagnosticPaths $capturePaths
                $receipt.diagnostics.stderr.path = "$originalOutput/evidence/$prefix/stderr.txt"
                [void](Write-SwiftUIStateObjectCaptureJson -Path (Join-Path $casePacketRoot "$prefix/request.json") -Value $raw)
            } -AssertStableInputs { } -ElapsedSeconds { 0 }
        Assert-CaptureTest $plan.completed 'The synthetic source-admission packet should complete collection.'
        $script:casePacketManifest = [pscustomobject]@{
            schemaVersion = 1; product = 'swiftui-stateobject-isolation'; mode = 'cases'; attemptID = $attemptID
            status = 'complete-characterization-candidate'; startedAtUtc = '2026-08-28T00:00:00Z'; finishedAtUtc = '2026-08-28T00:00:00Z'
            source = $fakeSource; executionHost = $fakeCompilerProfile.nativeHost
            captureManifestSHA256 = $policy.captureManifestSHA256; matrixSHA256 = $matrix.sha256
            compilerProfileSHA256 = $fakeCompilerProfileFile.sha256; reviewedProfileSHA256 = $fakeCompilerProfileFile.sha256; reviewedMatrixSHA256 = $matrix.sha256
            profileFile = [pscustomobject]@{ path = 'reviewed-profile/profile.json'; sha256 = $fakeCompilerProfileFile.sha256; bytes = $fakeCompilerProfileFile.bytes }
            caseRequests = 42; unconfirmedCaseRequests = 0; expectedCaseRequests = 42; results = @($plan.results)
            disagreements = [pscustomobject]@{ safety = 4; controls = 8; collectionSuccessDoesNotApproveSafety = $true }
            issues = @(); artifactFiles = @(Get-SwiftUIStateObjectEvidenceInventory $casePacketRoot); qualification = $policy.qualification
        }
        $hash = Write-SwiftUIStateObjectCaptureJson -Path (Join-Path $casePacketRoot 'manifest.json') -Value $casePacketManifest
        Write-CaptureFixtureText (Join-Path $casePacketRoot 'manifest.sha256') "$($hash.sha256)  manifest.json`n"
        $packet = Read-SwiftUIStateObjectCompletedEvidence $casePacketRoot
        Assert-CaptureTest ($packet.manifest.results.Count -eq 42 -and $packet.manifest.disagreements.safety -eq 4) 'Complete collection hid unsafe admission disagreements.'
        $script:casePacketValidated = $true
    }

    Invoke-CaptureSnapshotTest 'complete packet rejects invented cells, nested approval, and altered request artifacts' {
        if (-not $casePacketValidated) { throw 'The unmodified base packet did not validate; mutation coverage is not established.' }
        foreach ($kind in @('unknown-cell', 'nested-approval', 'changed-sil', 'weaker-argv', 'different-profile')) {
            $copyRoot = Join-Path $OutputRoot "case-packet-$kind"
            [void](New-Item -ItemType Directory -Path $copyRoot)
            foreach ($file in (Get-SwiftUIStateObjectEvidenceInventory $casePacketRoot)) {
                [void](Copy-SwiftUIStateObjectCaptureInput -Source (Join-Path $casePacketRoot $file.path) -Destination (Join-Path $copyRoot $file.path) -SHA256 $file.sha256)
            }
            $changed = ($casePacketManifest | ConvertTo-Json -Depth 40) | ConvertFrom-Json
            switch ($kind) {
                'unknown-cell' { $changed.results[0].caseID = 'invented-case'; $changed.results[0].assessment.caseID = 'invented-case' }
                'nested-approval' { $changed.results[0].assessment.runtimeEvidence = $true }
                'changed-sil' { Write-CaptureFixtureText (Join-Path $copyRoot 'requests/x86_64/SOI_01_x86_64/case.sil') 'replaced synthetic SIL' }
                'weaker-argv' {
                    $changed.results[0].raw.arguments[1] = '5'
                    Write-CaptureFixtureText (Join-Path $copyRoot 'requests/x86_64/SOI_01_x86_64/request.json') (($changed.results[0].raw | ConvertTo-Json -Depth 30) + "`n")
                }
                'different-profile' { $changed.results[21].assessment.compilerProfileSHA256 = 'f' * 64 }
            }
            $changed.artifactFiles = @(Get-SwiftUIStateObjectEvidenceInventory $copyRoot)
            $hash = Write-SwiftUIStateObjectCaptureJson -Path (Join-Path $copyRoot 'manifest.json') -Value $changed
            Write-CaptureFixtureText (Join-Path $copyRoot 'manifest.sha256') "$($hash.sha256)  manifest.json`n"
            $expected = switch ($kind) {
                'unknown-cell' { 'exact 21-case/two-target order' }
                'nested-approval' { 'cannot claim runtime, parity, or production approval' }
                'changed-sil' { 'Archived SIL is missing, empty, oversized, or changed' }
                'weaker-argv' { 'Archived compiler arguments differ' }
                'different-profile' { 'assessment belongs to a different scope' }
            }
            Assert-CaptureThrows { Read-SwiftUIStateObjectCompletedEvidence $copyRoot } "A resealed case packet accepted $kind." $expected
        }
    }

    Invoke-CaptureTest 'exit zero cannot substitute for bounded nonempty SIL and closed raw evidence' {
        foreach ($kind in @('missing', 'empty', 'oversized', 'stdout-tamper', 'valid')) {
            $root = Join-Path $OutputRoot "adapter-$kind"
            $stdout = Join-Path $root 'stdout.txt'; $stderr = Join-Path $root 'stderr.txt'; $sil = Join-Path $root 'unarchived.sil'
            Write-CaptureFixtureText $stdout ''; Write-CaptureFixtureText $stderr ''
            $raw = New-CaptureFakeRawProcess $stdout $stderr
            switch ($kind) {
                'empty' { Write-CaptureFixtureText $sil '' }
                'oversized' { [System.IO.File]::WriteAllBytes($sil, [byte[]]::new(8388609)) }
                'stdout-tamper' { Write-CaptureFixtureText $sil 'synthetic SIL'; Write-CaptureFixtureText $stdout 'unrecorded output' }
                'valid' { Write-CaptureFixtureText $sil 'synthetic SIL' }
            }
            $adapted = ConvertTo-SwiftUIStateObjectCaseProcess -Record $raw -StdoutPath $stdout -StderrPath $stderr -SILPath $sil `
                -ArchivedSILPath (Join-Path $root 'archived.sil') -Limits $matrix.document.limits
            if ($kind -ceq 'valid') { Assert-CaptureTest ($adapted.artifactIssues.Count -eq 0 -and $null -ne $adapted.sil) 'Valid synthetic SIL copy failed.' }
            else { Assert-CaptureTest ($adapted.artifactIssues.Count -gt 0 -and $null -eq $adapted.sil) 'Exit zero hid missing, oversized, or changed output.' }
        }
    }

    Invoke-CaptureTest 'first metadata process accepts an empty record list using only a PowerShell child' {
        $processRoot = Join-Path $OutputRoot 'fake-process-adapter'
        [void](New-Item -ItemType Directory -Path $processRoot)
        $records = [System.Collections.Generic.List[object]]::new()
        $powerShellPath = (Get-Process -Id $PID).Path
        Assert-CaptureTest ([System.IO.Path]::GetFileNameWithoutExtension($powerShellPath) -ceq 'pwsh') 'Only an identified pwsh executable may run the synthetic child.'
        $script:powerShellProcessRequests++
        $result = Invoke-SwiftUIStateObjectMetadataRequest -ID 'synthetic-powershell-only' -FilePath $powerShellPath `
            -Arguments @('-NoProfile', '-NonInteractive', '-Command', '[Console]::Out.Write("synthetic metadata only")') `
            -EvidenceRoot $processRoot -WorkingDirectory $processRoot -Environment ([ordered]@{ DEVELOPER_DIR = 'synthetic-no-SDK' }) -Records $records
        Assert-CaptureTest ($records.Count -eq 1 -and $result.text -ceq 'synthetic metadata only') 'The initial empty process-record list did not receive its result.'
        Assert-CaptureTest ($result.raw.process.exitCode -eq 0 -and $result.raw.process.allRedirectedStreamsClosed) 'The fake metadata process did not finish cleanly.'
        Assert-SwiftUIStateObjectRawProcess -Value $result.raw.process -MaxCombinedBytes 262144
    }
} else {
    $notRunTests.Add('Metadata profile and complete snapshot replay: PowerShell 7 strict JSON is required; no native or helper process runs in PowerShell 5.1.')
}

Invoke-CaptureTest 'raw byte limits reject numeric strings before arithmetic' {
    $root = Join-Path $OutputRoot 'raw-numeric-policy'
    $stdout = Join-Path $root 'stdout.txt'; $stderr = Join-Path $root 'stderr.txt'
    Write-CaptureFixtureText $stdout ''; Write-CaptureFixtureText $stderr ''
    foreach ($limit in @(262144, 1048576)) {
        $raw = New-CaptureFakeRawProcess $stdout $stderr
        $raw.stdoutBytes = [string]($limit - 1); $raw.stderrBytes = $limit - 1
        Assert-CaptureThrows { Assert-SwiftUIStateObjectRawProcess -Value $raw -MaxCombinedBytes $limit } 'String concatenation bypassed a raw output byte bound.' 'integer'
    }
}

if ($sdkFixtureVerified) {
    Invoke-CaptureTest 'SDK source fixture remains unchanged after all synthetic work' {
        $after = @(Read-SwiftUIStateObjectCaptureFixtureFiles -Root $SDKCaptureFixtureRoot)
        Assert-CaptureTest ($after.Count -eq $sdkFixtureFiles.Count) 'SDK source fixture count changed.'
        for ($i = 0; $i -lt $after.Count; $i++) {
            Assert-CaptureTest ($after[$i].path -ceq $sdkFixtureFiles[$i].path -and $after[$i].sha256 -ceq $sdkFixtureFiles[$i].sha256 -and
                $after[$i].bytes -eq $sdkFixtureFiles[$i].bytes) 'A read-only source fixture was modified.'
        }
    }
}

$sdkFixtureTotalBytes = [long]0
if ($sdkFixtureFiles.Count -gt 0) { $sdkFixtureTotalBytes = [long](($sdkFixtureFiles | Measure-Object -Property bytes -Sum).Sum) }
$receipt = [pscustomobject]@{
    schemaVersion = 1; kind = 'synthetic-stateobject-capture-protocol-tests'; powerShellVersion = $PSVersionTable.PSVersion.ToString()
    status = $(if ($testFailures.Count -eq 0) { 'passed' } else { 'failed' })
    assertions = $script:captureChecks; tests = $testNames.ToArray(); failures = $testFailures.ToArray()
    notRunTests = $notRunTests.ToArray()
    simulatedCaseRequests = $script:fakeRequests; simulatedMetadataRequests = $script:fakeMetadataRequests
    powerShellChildRequests = $script:powerShellProcessRequests
    compilerRequests = 0; nativeUIExecution = $false; CIExecution = $false
    nativeEntryPlatformEligible = ($PSVersionTable.PSVersion.Major -ge 7 -and $IsMacOS)
    nativeToolchainProfileVerified = $false
    sdkSourceFixture = [pscustomobject]@{
        provided = $PSBoundParameters.ContainsKey('SDKCaptureFixtureRoot'); verified = $sdkFixtureVerified
        fileCount = $sdkFixtureFiles.Count; totalBytes = $sdkFixtureTotalBytes
        files = $sdkFixtureFiles; sourceOnly = $true; nativeToolsInvoked = $false
    }
    qualification = (Get-SwiftUIStateObjectCapturePolicy).qualification
}
[void](Write-SwiftUIStateObjectCaptureJson -Path (Join-Path $OutputRoot 'test-results.json') -Value $receipt)
Write-Output ($receipt | ConvertTo-Json -Depth 8)
if ($testFailures.Count -gt 0) { throw ('Synthetic capture tests failed: ' + ($testFailures -join '; ')) }
