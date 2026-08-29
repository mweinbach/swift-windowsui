#Requires -Version 7.0
<#
.SYNOPSIS
Invokes existing Stage A only after an explicit fixed-template workflow request.
.DESCRIPTION
ValidateOnly checks the caller's hash and selection without SDK access or managed
reader initialization. A live invocation still passes all original Stage A
capture, ledger, root-plan, filesystem and seal guards. No baseline is modified.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][AllowEmptyString()][string]$TemplateSha256,
    [Parameter(Mandatory)][AllowEmptyString()][string]$DeveloperFrameworksSelection,
    [string]$CaptureRoot,
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'swiftui-overlay-workflow-common.ps1')
Assert-SwiftUIOverlayWorkflowOptions -TemplateSha256 $TemplateSha256 -DeveloperFrameworksSelection $DeveloperFrameworksSelection
$repositoryRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$templatePath = Join-Path $repositoryRoot 'docs/swiftui-overlay-root-plan.template.json'
if ((Resolve-SwiftUIBaselineFileSystemPath $templatePath) -cne [IO.Path]::GetFullPath($templatePath)) {
    throw 'The fixed root-plan template must not redirect through a filesystem alias.'
}
$templateBytes = Read-SwiftUIAuditBoundedText -Path $templatePath -MaximumBytes 131072
if ($templateBytes.sha256 -cne $TemplateSha256) { throw 'The fixed template does not match the explicit opt-in hash.' }
if ($ValidateOnly) {
    return [pscustomobject]@{
        status = 'template-hash-and-options-checked'; templateSha256 = $templateBytes.sha256
        developerFrameworksSelection = $DeveloperFrameworksSelection
        rootPlanValidated = $false; sdkObserved = $false; nativeCensusPerformed = $false
    }
}
if (-not $IsMacOS) { throw 'Live opt-in Stage A requires macOS; no SDK or source capture was opened.' }

# Fixed artifact siblings preserve the SDK export's fresh-directory preflight.
# The request directory is distinct from the collector's not-yet-created output.
$evidenceRoot = Join-Path $repositoryRoot 'artifacts/swiftui-baseline/github-actions'
$expectedCaptureRoot = Join-Path $evidenceRoot 'capture'
$auditRoot = Join-Path $evidenceRoot 'audit'
$requestRoot = Join-Path $evidenceRoot 'overlay-discovery-request'
$outputRoot = Join-Path $evidenceRoot 'overlay-discovery'
$manifestPath = Join-Path $repositoryRoot 'docs/swiftui-baseline.json'
if ([string]::IsNullOrWhiteSpace($CaptureRoot) -or -not [IO.Path]::IsPathRooted($CaptureRoot) -or
    [IO.Path]::GetFullPath($CaptureRoot) -cne [IO.Path]::GetFullPath($expectedCaptureRoot)) {
    throw 'CaptureRoot must be the exact successful SDK export output in this checkout.'
}
foreach ($path in @($evidenceRoot, $expectedCaptureRoot, $auditRoot, $requestRoot, $outputRoot, $manifestPath)) {
    [void](Get-SwiftUIBaselineRelativePath -Root $repositoryRoot -Path $path)
    if ((Resolve-SwiftUIBaselineFileSystemPath $path) -cne [IO.Path]::GetFullPath($path)) {
        throw 'Opt-in evidence and input paths must not redirect through filesystem aliases.'
    }
}
foreach ($path in @($evidenceRoot, $expectedCaptureRoot, $auditRoot)) {
    if (-not (Test-Path -LiteralPath $path -PathType Container)) { throw 'A complete export and audit must already exist.' }
}
foreach ($path in @($requestRoot, $outputRoot)) {
    if (Test-Path -LiteralPath $path) { throw 'Opt-in request/output already exists; no overwrite or retry is allowed.' }
}
[void](New-Item -ItemType Directory -Path $requestRoot)
$contextPath = Join-Path $requestRoot 'request.json'
$context = [ordered]@{
    schemaVersion = 1; evidenceKind = 'overlay-discovery-workflow-request'; status = 'in-progress'
    authorization = 'explicit workflow opt-in to the reviewed template hash and fixed materializer; generated root-plan hash is an integrity seal'
    templateSha256 = $TemplateSha256; developerFrameworksSelection = $DeveloperFrameworksSelection
    sourceCaptureSha256 = $null; sourceAuditSha256 = $null; baselineManifestSha256 = $null; rootPlanSha256 = $null
    repository = $env:GITHUB_REPOSITORY; eventCommit = $env:GITHUB_SHA; workflowCommit = $env:GITHUB_WORKFLOW_SHA
    workflowRef = $env:GITHUB_WORKFLOW_REF; runId = $env:GITHUB_RUN_ID; runAttempt = $env:GITHUB_RUN_ATTEMPT
    sourceFiles = @(); identityReviewPerformed = $false; overlayCompleteness = 'unverified'; releaseQualified = $false
    startedAtUtc = [DateTime]::UtcNow.ToString('o'); finishedAtUtc = $null; error = $null
}
Write-SwiftUIBaselineJson -Value $context -Path $contextPath
$failure = $null
$result = $null
try {
    $templateCopy = Join-Path $requestRoot 'root-plan.template.json'
    $copyBytes = [Text.UTF8Encoding]::new($false).GetBytes($templateBytes.text)
    $copyStream = [IO.File]::Open($templateCopy, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { $copyStream.Write($copyBytes, 0, $copyBytes.Length) } finally { $copyStream.Dispose() }
    if ((Read-SwiftUIAuditBoundedText $templateCopy 131072).sha256 -cne $TemplateSha256) { throw 'Copied template bytes do not match their authorization.' }
    foreach ($name in @('capture-swiftui-overlay-discovery-candidate.ps1', 'swiftui-overlay-workflow-common.ps1')) {
        $source = Read-SwiftUIAuditBoundedText -Path (Join-Path $PSScriptRoot $name) -MaximumBytes 131072
        $context.sourceFiles += [ordered]@{ path = 'scripts/' + $name; bytes = $source.bytes; sha256 = $source.sha256 }
    }
    . (Join-Path $PSScriptRoot 'swiftui-overlay-discovery-common.ps1')
    # This checks small intake metadata and stream lengths. The unchanged Stage A
    # entrypoint below performs its complete source hashing and live observation.
    $inputs = Read-SwiftUIAPIReviewInputs -CaptureRoot $expectedCaptureRoot -AuditRoot $auditRoot -ManifestPath $manifestPath
    $template = Read-SwiftUIOverlayMetadata -Path $templateCopy -MaximumBytes 131072
    if ($template.sha256 -cne $TemplateSha256) { throw 'Root-plan template changed after opt-in validation.' }
    $layout = Get-SwiftUIOverlayExpectedLayout -SourceContext ([pscustomobject]@{ inputs = $inputs })
    $plan = New-SwiftUIOverlayWorkflowRootPlan -Template $template.value -Layout $layout `
        -SourceCaptureSha256 $inputs.captureContext.captureSha256 -SourceAuditSha256 $inputs.auditManifestSha256 `
        -BaselineManifestSha256 $inputs.currentExpectedBaselineManifestSha256 -DeveloperFrameworksSelection $DeveloperFrameworksSelection
    $planPath = Join-Path $requestRoot 'root-plan.json'
    $planBytes = [Text.UTF8Encoding]::new($false).GetBytes((ConvertTo-Json -InputObject $plan -Depth 100 -WarningAction Stop) + "`n")
    if ($planBytes.Length -gt 131072) { throw 'Generated root plan exceeds the fixed caller metadata budget.' }
    $planStream = [IO.File]::Open($planPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { $planStream.Write($planBytes, 0, $planBytes.Length) } finally { $planStream.Dispose() }
    $planFile = Read-SwiftUIAuditBoundedText $planPath 131072
    $context.sourceCaptureSha256 = $inputs.captureContext.captureSha256
    $context.sourceAuditSha256 = $inputs.auditManifestSha256
    $context.baselineManifestSha256 = $inputs.currentExpectedBaselineManifestSha256
    $context.rootPlanSha256 = $planFile.sha256
    Write-SwiftUIBaselineJson -Value $context -Path $contextPath
    $result = & (Join-Path $PSScriptRoot 'capture-swiftui-overlay-discovery.ps1') `
        -CaptureRoot $expectedCaptureRoot -AuditRoot $auditRoot -ManifestPath $manifestPath `
        -RootPlanPath $planPath -ExpectedRootPlanSha256 $planFile.sha256 -OutputDirectory $outputRoot
    $complete = Get-SwiftUIAuditProperty $result 'complete'
    if ($complete -isnot [bool] -or -not $complete) { throw 'The existing Stage A collector did not report a complete observation.' }
    $context.status = 'filesystem-recorded-awaiting-probe-review'
} catch {
    $failure = $_
    $context.status = 'failed'
    $context.error = [ordered]@{ type = $_.Exception.GetType().FullName; hResult = $_.Exception.HResult; message = $_.Exception.Message }
} finally {
    $context.finishedAtUtc = [DateTime]::UtcNow.ToString('o')
    try { Write-SwiftUIBaselineJson -Value $context -Path $contextPath } catch {
        if ($null -ne $failure) {
            throw [AggregateException]::new('Opt-in Stage A failed and its final request receipt could not be written.', [Exception[]]@($failure.Exception, $_.Exception))
        }
        throw
    }
}
if ($null -ne $failure) { throw $failure }
$result
