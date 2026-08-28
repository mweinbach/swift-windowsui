[CmdletBinding(DefaultParameterSetName = 'MetadataOnly')]
param(
    [Parameter(Mandatory, ParameterSetName = 'MetadataOnly')][switch]$MetadataOnly,
    [Parameter(Mandatory, ParameterSetName = 'Cases')][switch]$Cases,
    [Parameter(Mandatory)][string]$OutputPath,
    [Parameter(Mandatory)][string]$SDKCaptureRoot,
    [Parameter(Mandatory)][string]$ExpectedCaptureManifestSHA256,
    [Parameter(Mandatory, ParameterSetName = 'Cases')][string]$ReviewedProfilePath,
    [Parameter(Mandatory, ParameterSetName = 'Cases')][string]$ReviewedProfileSHA256,
    [Parameter(Mandatory, ParameterSetName = 'Cases')][string]$ReviewedMatrixSHA256
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Deliberately before imports, path creation, or any native process. This is not
# a Windows capture adapter and has no override for the unsupported platform.
if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'StateObject compiler characterization requires PowerShell 7; PowerShell 5.1 native execution is unsupported.' }
if (-not $IsMacOS) { throw 'Native StateObject compiler characterization is supported only on the explicitly pinned macOS toolchain. Windows public-import cases remain unrun.' }
. (Join-Path $PSScriptRoot 'swiftui-stateobject-capture-common.ps1')

$repositoryRoot = Resolve-SwiftUIBaselineFileSystemPath (Join-Path $PSScriptRoot '..')
$matrixRoot = Join-Path $repositoryRoot 'scripts/fixtures/swiftui-stateobject-isolation'
$matrixPath = Join-Path $matrixRoot 'matrix.json'
$matrix = Read-SwiftUIStateObjectMatrix -Path $matrixPath -SourceRoot $matrixRoot
$policy = Get-SwiftUIStateObjectCapturePolicy
Assert-SwiftUIStateObjectCaptureSHA256 $ExpectedCaptureManifestSHA256 'Requested capture hash'
if ($ExpectedCaptureManifestSHA256 -cne $policy.captureManifestSHA256) { throw 'This authored matrix requires the exact selected capture 33135644721.' }
$output = New-SwiftUIStateObjectCaptureDirectory -Path $OutputPath -RepositoryRoot $repositoryRoot
$attemptID = [Guid]::NewGuid().ToString('N')
$mode = 'metadata-only'
if ($Cases) { $mode = 'cases' }
$started = [DateTime]::UtcNow.ToString('o')
$issues = [System.Collections.Generic.List[string]]::new()
$metadataRecords = [System.Collections.Generic.List[object]]::new()
$source = $null; $executionHost = $null; $compilerProfileHash = $null; $profileFile = $null
$results = @(); $caseRequests = 0; $status = 'blocked-preflight'
$reviewedProfile = $null; $sdkInputs = $null
$manifestHash = $null
[void](Write-SwiftUIStateObjectCaptureJson -Path (Join-Path $output.evidence 'startup.json') -Value ([pscustomobject]@{
    schemaVersion = 1; product = 'swiftui-stateobject-isolation'; attemptID = $attemptID; mode = $mode
    status = 'in-progress-not-evidence'; startedAtUtc = $started; caseRequests = 0
    matrixSHA256 = $matrix.sha256; requestedCaptureSHA256 = $ExpectedCaptureManifestSHA256
    qualification = $policy.qualification
}))

try {
    if ($Cases) {
        # Intake first: no native metadata or case is run to replace a missing
        # review receipt. A profile plus matching complete raw packet is required.
        $reviewedProfile = Read-SwiftUIStateObjectReviewedProfile -Path $ReviewedProfilePath `
            -ReviewedProfileSHA256 $ReviewedProfileSHA256 -ReviewedMatrixSHA256 $ReviewedMatrixSHA256 -Matrix $matrix
        $compilerProfileHash = $reviewedProfile.sha256
    }
    $conflicts = @(Get-SwiftUIMaterialEnvironmentOverrides ([Environment]::GetEnvironmentVariables()))
    $conflicts += @([Environment]::GetEnvironmentVariables().Keys | Where-Object {
        $_ -match '^GIT_' -and -not [string]::IsNullOrEmpty([Environment]::GetEnvironmentVariable($_))
    })
    if ($conflicts.Count -gt 0) { throw "Conflicting native tool environment overrides: $($conflicts -join ', '). Values were not recorded." }
    if (-not [string]::IsNullOrEmpty($env:DEVELOPER_DIR) -and $env:DEVELOPER_DIR -cne $policy.developerDirectory) { throw 'DEVELOPER_DIR differs from the pinned Xcode selection.' }
    $scratch = Join-Path $output.work 'temporary'
    [void](New-Item -ItemType Directory -Path $scratch)
    $nativeEnvironment = [ordered]@{
        DEVELOPER_DIR = $policy.developerDirectory; TMPDIR = $scratch; TMP = $scratch; TEMP = $scratch
        LANG = 'C'; LC_ALL = 'C'
    }
    $metadata = {
        param($id, $filePath, $arguments)
        Invoke-SwiftUIStateObjectMetadataRequest -ID $id -FilePath $filePath -Arguments $arguments `
            -EvidenceRoot $output.evidence -WorkingDirectory $output.work -Environment $nativeEnvironment -Records $metadataRecords
    }
    $gitPath = (Get-Command git -CommandType Application -ErrorAction Stop).Source
    $gitPrefix = @('-c', 'core.fsmonitor=false', '--no-optional-locks', '-C', $repositoryRoot)
    $commit = & $metadata 'source-commit' $gitPath ($gitPrefix + @('rev-parse', '--verify', 'HEAD'))
    $tree = & $metadata 'source-tree' $gitPath ($gitPrefix + @('rev-parse', '--verify', 'HEAD^{tree}'))
    $dirty = & $metadata 'source-status' $gitPath ($gitPrefix + @('status', '--porcelain=v1', '--untracked-files=no'))
    if ($commit.text.Trim() -cnotmatch '^[0-9a-f]{40}$' -or $tree.text.Trim() -cnotmatch '^[0-9a-f]{40}$' -or $dirty.text.Trim() -cne '') {
        throw 'A clean committed source tree is required; no compiler request was made.'
    }
    $source = [pscustomobject]@{
        commit = $commit.text.Trim(); tree = $tree.text.Trim(); trackedWorkingTree = ''
        workflow = (Get-SwiftUIStateObjectWorkflowContext)
    }
    $sdkInputs = Read-SwiftUIStateObjectSDKInputs -CaptureRoot $SDKCaptureRoot -RepositoryRoot $repositoryRoot `
        -ExpectedCaptureManifestSHA256 $ExpectedCaptureManifestSHA256
    $sourceFiles = @(Get-SwiftUIStateObjectCaptureSources -RepositoryRoot $repositoryRoot -Matrix $matrix)
    $trackedPaths = @($sourceFiles | ForEach-Object { $_.path }) + @('scripts/fixtures/swiftui-stateobject-isolation/matrix.json', 'docs/swiftui-baseline.json')
    $tracked = & $metadata 'source-input-blobs' $gitPath ($gitPrefix + @('ls-tree', '-r', '-z', '--full-tree', 'HEAD', '--') + $trackedPaths)
    Assert-SwiftUIStateObjectTrackedInputs -Listing $tracked.text -Paths $trackedPaths -RepositoryRoot $repositoryRoot
    $ownedSources = Join-Path $output.evidence 'sources'
    [void](New-Item -ItemType Directory -Path $ownedSources)
    foreach ($file in $matrix.sourceFiles) {
        [void](Copy-SwiftUIStateObjectCaptureInput -Source $file.path -Destination (Join-Path $ownedSources $file.relativePath) -SHA256 $file.sha256 -MaxBytes 1048576)
    }
    [void](Copy-SwiftUIStateObjectCaptureInput -Source $matrixPath -Destination (Join-Path $ownedSources 'matrix.json') -SHA256 $matrix.sha256 -MaxBytes 1048576)
    $harnessRoot = Join-Path $ownedSources 'harness'
    [void](New-Item -ItemType Directory -Path $harnessRoot)
    foreach ($file in $sourceFiles | Where-Object { $_.path -cin $policy.harnessPaths }) {
        [void](Copy-SwiftUIStateObjectCaptureInput -Source (Join-Path $repositoryRoot $file.path) `
            -Destination (Join-Path $harnessRoot ([System.IO.Path]::GetFileName($file.path))) -SHA256 $file.sha256)
    }
    foreach ($file in $sdkInputs.files) {
        [void](Copy-SwiftUIStateObjectCaptureInput -Source $file.path -Destination (Join-Path $output.evidence "sdk/$($file.relativePath)") -SHA256 $file.sha256)
    }
    [void](Write-SwiftUIStateObjectCaptureJson -Path (Join-Path $output.evidence 'source-inputs.json') -Value ([pscustomobject]@{
        source = $source; files = $sourceFiles; matrixSHA256 = $matrix.sha256
        captureManifestSHA256 = $ExpectedCaptureManifestSHA256
    }))

    if ($MetadataOnly) {
        $inspectTool = { param($path) Get-SwiftUIStateObjectLiveFile -Path $path -AllowedRoot $policy.developerDirectory }
        $compilerProfile = Get-SwiftUIStateObjectMetadataProfile -Matrix $matrix -SDKInputs $sdkInputs -AttemptID $attemptID `
            -Source $source -SourceFiles $sourceFiles -ExecuteMetadata $metadata -InspectTool $inspectTool
        Assert-SwiftUIStateObjectProfileInputs -CompilerProfile $compilerProfile -Matrix $matrix -RepositoryRoot $repositoryRoot -SDKInputs $sdkInputs
        $saved = Write-SwiftUIStateObjectCaptureJson -Path (Join-Path $output.evidence 'profile.json') -Value $compilerProfile
        $compilerProfileHash = $saved.sha256
        $profileFile = [pscustomobject]@{ path = 'profile.json'; sha256 = $saved.sha256; bytes = $saved.bytes }
        $executionHost = $compilerProfile.nativeHost
        $status = 'metadata-only-awaiting-review'
        # This branch ends here. It does not discover a prior approval, invoke
        # the case plan, or promote this freshly generated hash into a review.
    } else {
        $compilerProfile = $reviewedProfile.document
        Assert-SwiftUIStateObjectProfileInputs -CompilerProfile $compilerProfile -Matrix $matrix -RepositoryRoot $repositoryRoot -SDKInputs $sdkInputs
        $version = & $metadata 'case-host-version' '/usr/bin/sw_vers' @('-productVersion')
        $build = & $metadata 'case-host-build' '/usr/bin/sw_vers' @('-buildVersion')
        $architecture = & $metadata 'case-host-architecture' '/usr/bin/uname' @('-m')
        $executionHost = [pscustomobject]@{
            macOSVersion = $version.text.Trim(); macOSBuildVersion = $build.text.Trim()
            architecture = $architecture.text.Trim(); powerShellVersion = $PSVersionTable.PSVersion.ToString()
        }
        foreach ($field in @('macOSVersion', 'macOSBuildVersion', 'architecture', 'powerShellVersion')) {
            if ($executionHost.$field -cne $compilerProfile.nativeHost.$field) { throw "Actual execution host $field differs from the reviewed compiler profile." }
        }
        $reviewRoot = Split-Path -Parent ([System.IO.Path]::GetFullPath($ReviewedProfilePath))
        $reviewInventory = @(Get-SwiftUIStateObjectEvidenceInventory $reviewRoot)
        foreach ($name in @('manifest.json', 'manifest.sha256')) {
            $hash = Get-SwiftUIStateObjectFileHash (Join-Path $reviewRoot $name)
            $reviewInventory += [pscustomobject]@{ path = $name; sha256 = $hash.sha256; bytes = $hash.bytes }
        }
        foreach ($file in $reviewInventory) {
            [void](Copy-SwiftUIStateObjectCaptureInput -Source (Join-Path $reviewRoot $file.path) `
                -Destination (Join-Path $output.evidence "reviewed-profile/$($file.path)") -SHA256 $file.sha256)
        }
        $profileFile = [pscustomobject]@{ path = 'reviewed-profile/profile.json'; sha256 = $reviewedProfile.sha256; bytes = $reviewedProfile.bytes }
        $ownedMatrix = Read-SwiftUIStateObjectMatrix -Path (Join-Path $ownedSources 'matrix.json') -SourceRoot $ownedSources
        $compilerPath = $compilerProfile.tools[0].file.canonicalPath
        $matrixClock = [System.Diagnostics.Stopwatch]::StartNew()
        $stable = {
            $currentMatrix = Read-SwiftUIStateObjectMatrix -Path $matrixPath -SourceRoot $matrixRoot
            if ($currentMatrix.sha256 -cne $ReviewedMatrixSHA256) { throw 'Matrix changed after explicit review.' }
            $currentOwned = Read-SwiftUIStateObjectMatrix -Path (Join-Path $ownedSources 'matrix.json') -SourceRoot $ownedSources
            if ($currentOwned.sha256 -cne $ReviewedMatrixSHA256) { throw 'Owned source matrix changed during the attempt.' }
            $currentProfile = Get-SwiftUIStateObjectFileHash $ReviewedProfilePath -MaxBytes 4194304
            if ($currentProfile.sha256 -cne $ReviewedProfileSHA256) { throw 'Reviewed profile changed during the attempt.' }
            Assert-SwiftUIStateObjectProfileInputs -CompilerProfile $compilerProfile -Matrix $currentMatrix -RepositoryRoot $repositoryRoot -SDKInputs $sdkInputs
        }
        $requestCase = {
            param($case, $target, $index, $timeout, $receipt)
            $arch = $target.Split('-')[0]
            $moduleName = 'SOI_{0:D2}_{1}' -f $index, $arch
            $requestRoot = Join-Path $output.evidence "requests/$arch/$moduleName"
            $working = Join-Path $output.work "requests/$arch/$moduleName"
            $cache = Join-Path $output.work "module-cache/$arch"
            foreach ($directory in @($requestRoot, $working, $cache)) {
                if (-not (Test-Path -LiteralPath $directory)) { [void](New-Item -ItemType Directory -Path $directory -Force) }
                [void](Assert-SwiftUIStateObjectDirectory $directory)
            }
            $silPath = Join-Path $working 'case.sil'
            $command = New-SwiftUIStateObjectCompilerRequest -Matrix $ownedMatrix -Case $case -CompilerPath $compilerPath `
                -SDKPath $compilerProfile.sdk.path -Target $target -SourceRoot $ownedSources -CachePath $cache -SILPath $silPath -ModuleName $moduleName
            $stdout = Join-Path $requestRoot 'stdout.txt'; $stderr = Join-Path $requestRoot 'stderr.txt'
            $raw = [pscustomobject]@{
                attemptID = $attemptID; target = $target; caseID = $case.caseID; compilerProfileSHA256 = $compilerProfileHash
                filePath = $command.filePath; arguments = $command.arguments; workingDirectory = $working
                environment = [pscustomobject]@{ overrideNames = @($nativeEnvironment.Keys | Sort-Object); developerDirectory = $policy.developerDirectory }
                timeoutSeconds = $timeout; stdoutPath = "requests/$arch/$moduleName/stdout.txt"; stderrPath = "requests/$arch/$moduleName/stderr.txt"
                sourceFiles = @($ownedMatrix.sourceFiles | Where-Object { $_.relativePath -cin (@($case.sharedSources) + @($case.source)) })
                process = $null
            }
            $receipt.raw = $raw
            [void](Write-SwiftUIStateObjectCaptureJson -Path (Join-Path $requestRoot 'request-start.json') -Value $raw)
            $receipt.launchAttempted = $true
            $process = Invoke-SwiftUIStateObjectProcess -FilePath $command.filePath -Arguments $command.arguments `
                -WorkingDirectory $working -StdoutPath $stdout -StderrPath $stderr -TimeoutSeconds $timeout `
                -MaxOutputBytes $matrix.document.limits.maxCombinedRawOutputBytes -Environment $nativeEnvironment
            $receipt.raw.process = $process
            $receipt.process = [pscustomobject]@{
                processStarted = $process.processStarted; exitCode = $process.exitCode; timedOut = $process.timedOut
                outputLimitExceeded = $process.outputLimitExceeded; abnormalTermination = ($null -ne $process.exitCode -and $process.exitCode -notin @(0, 1))
                allRedirectedStreamsClosed = $process.allRedirectedStreamsClosed; terminationCompleted = $process.terminationCompleted
                error = $process.error; notRunReason = $null; artifactIssues = @('Post-process collection is incomplete.'); sil = $null
            }
            $adapted = ConvertTo-SwiftUIStateObjectCaseProcess -Record $process -StdoutPath $stdout -StderrPath $stderr `
                -SILPath $silPath -ArchivedSILPath (Join-Path $requestRoot 'case.sil') -Limits $matrix.document.limits
            if ($null -ne $adapted.sil) { $adapted.sil.path = "requests/$arch/$moduleName/case.sil" }
            $receipt.process = $adapted
            try { $diagnostics = Get-SwiftUIStateObjectDiagnostics -StderrPath $stderr -Sources $raw.sourceFiles -Case $case } catch {
                $adapted.artifactIssues = @($adapted.artifactIssues) + @($_.Exception.Message)
                $diagnostics = New-SwiftUIStateObjectEmptyDiagnostics -Issues @($_.Exception.Message)
            }
            $receipt.diagnostics = $diagnostics
            [void](Write-SwiftUIStateObjectCaptureJson -Path (Join-Path $requestRoot 'request.json') -Value $raw)
        }
        $plan = Invoke-SwiftUIStateObjectCasePlan -Matrix $matrix -AttemptID $attemptID -CompilerProfileSHA256 $compilerProfileHash `
            -Request $requestCase -AssertStableInputs $stable -ElapsedSeconds { $matrixClock.Elapsed.TotalSeconds }
        $matrixClock.Stop()
        $results = @($plan.results)
        $caseRequests = @($results | Where-Object { $null -ne $_.process -and $_.process.processStarted }).Count
        if ($plan.completed) { $status = 'complete-characterization-candidate' } else {
            $status = 'incomplete-characterization'; $issues.Add($plan.stopReason)
        }
    }
    $finalCommit = & $metadata 'source-final-commit' $gitPath ($gitPrefix + @('rev-parse', '--verify', 'HEAD'))
    $finalTree = & $metadata 'source-final-tree' $gitPath ($gitPrefix + @('rev-parse', '--verify', 'HEAD^{tree}'))
    $finalDirty = & $metadata 'source-final-status' $gitPath ($gitPrefix + @('status', '--porcelain=v1', '--untracked-files=no'))
    if ($finalCommit.text.Trim() -cne $source.commit -or $finalTree.text.Trim() -cne $source.tree -or $finalDirty.text.Trim() -cne '') {
        throw 'Source commit, tree, or tracked work changed during the attempt.'
    }
    Assert-SwiftUIStateObjectTrackedInputs -Listing $tracked.text -Paths $trackedPaths -RepositoryRoot $repositoryRoot
} catch {
    $issues.Add($_.Exception.Message)
    if ($mode -ceq 'cases') { $status = 'incomplete-characterization' }
    elseif ($null -ne $profileFile) { $status = 'incomplete-metadata' }
}

# Any preflight failure in case mode still records every sealed cell as not run.
# This does not overwrite a previously executed record or the old probe's slots.
if ($mode -ceq 'cases' -and $results.Count -eq 0) {
    $ordinal = 0
    foreach ($target in $matrix.targets) {
        foreach ($case in $matrix.cases) {
            $ordinal++
            $results += [pscustomobject]@{
                ordinal = $ordinal; target = $target; caseID = $case.caseID
                launchState = 'not-run'; collectionError = $null
                process = (New-SwiftUIStateObjectNotRunProcess ('Preflight did not complete: ' + ($issues -join '; ')))
                diagnostics = (New-SwiftUIStateObjectEmptyDiagnostics); raw = $null; assessment = $null
            }
        }
    }
}
$safetyDisagreements = @($results | Where-Object { $null -ne $_.assessment -and $_.assessment.safetyRequirementMet -ceq $false }).Count
$controlDisagreements = @($results | Where-Object { $null -ne $_.assessment -and $_.assessment.controlRequirementMet -ceq $false }).Count
$manifest = [pscustomobject]@{
    schemaVersion = 1; product = 'swiftui-stateobject-isolation'; mode = $mode; attemptID = $attemptID; status = $status
    startedAtUtc = $started; finishedAtUtc = [DateTime]::UtcNow.ToString('o'); source = $source; executionHost = $executionHost
    captureManifestSHA256 = $ExpectedCaptureManifestSHA256; matrixSHA256 = $matrix.sha256; compilerProfileSHA256 = $compilerProfileHash
    reviewedProfileSHA256 = $(if ($Cases) { $ReviewedProfileSHA256 } else { $null })
    reviewedMatrixSHA256 = $(if ($Cases) { $ReviewedMatrixSHA256 } else { $null })
    profileFile = $profileFile; caseRequests = $caseRequests
    unconfirmedCaseRequests = @($results | Where-Object { $_.launchState -ceq 'unknown-after-invocation' }).Count
    expectedCaseRequests = $(if ($Cases) { 42 } else { 0 })
    results = $results
    disagreements = [pscustomobject]@{ safety = $safetyDisagreements; controls = $controlDisagreements; collectionSuccessDoesNotApproveSafety = $true }
    issues = $issues.ToArray(); artifactFiles = @(Get-SwiftUIStateObjectEvidenceInventory $output.evidence)
    qualification = $policy.qualification
}
$manifestFile = Write-SwiftUIStateObjectCaptureJson -Path (Join-Path $output.evidence 'manifest.json') -Value $manifest
$digestBytes = [System.Text.UTF8Encoding]::new($false).GetBytes("$($manifestFile.sha256)  manifest.json`n")
$digestStream = [System.IO.File]::Open((Join-Path $output.evidence 'manifest.sha256'), [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
try { $digestStream.Write($digestBytes, 0, $digestBytes.Length) } finally { $digestStream.Dispose() }
if ($issues.Count -eq 0) { [void](Read-SwiftUIStateObjectCompletedEvidence -Root $output.evidence) }
Write-Output ([pscustomobject]@{
    status = $status; evidenceRoot = $output.evidence; manifestSHA256 = $manifestFile.sha256
    compilerProfileSHA256 = $compilerProfileHash; matrixSHA256 = $matrix.sha256; caseRequests = $caseRequests
    unconfirmedCaseRequests = $manifest.unconfirmedCaseRequests
    safetyDisagreements = $safetyDisagreements; controlDisagreements = $controlDisagreements
    runtimeEvidence = $false; parityClaimed = $false; productionApprovalChanged = $false
})
if ($issues.Count -gt 0) { exit 1 }
