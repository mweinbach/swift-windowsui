<#
.SYNOPSIS
Builds the unreviewed audit ledger from one explicit successful export result.
.DESCRIPTION
Portable post-export orchestration only; no native tool or SwiftPM command
runs. All paths in ExportResultPath are relative to EvidenceRoot. The complete
source capture stays unchanged and must be retained alongside the full ledger,
not replaced by its small audit-context.json summary.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ExportResultPath,
    [Parameter(Mandatory)][string]$EvidenceRoot,
    [string]$ManifestPath = (Join-Path (Split-Path -Parent $PSScriptRoot) "docs/swiftui-baseline.json")
)

$ErrorActionPreference = "Stop"
$absoluteResultPath = [System.IO.Path]::IsPathRooted($ExportResultPath)
if ([System.IO.Path]::DirectorySeparatorChar -eq '\') {
    # .NET Framework reports C:relative and \current-drive as rooted too.
    $resultRoot = [System.IO.Path]::GetPathRoot($ExportResultPath)
    $absoluteResultPath = $absoluteResultPath -and $resultRoot -match '\A(?:[A-Za-z]:[\\/]|[\\/]{2}[^\\/]+[\\/][^\\/]+[\\/]?)\z'
}
if (-not $absoluteResultPath) {
    throw "ExportResultPath must be an explicit absolute path from the successful export step."
}
. (Join-Path $PSScriptRoot "swiftui-api-audit-common.ps1")
$comparison = [StringComparison]::Ordinal
if ([System.IO.Path]::DirectorySeparatorChar -eq '\') { $comparison = [StringComparison]::OrdinalIgnoreCase }
$repoRoot = Resolve-SwiftUIBaselineFileSystemPath -Path (Split-Path -Parent $PSScriptRoot)
$artifactRoot = Resolve-SwiftUIBaselineFileSystemPath -Path (Join-Path $repoRoot "artifacts")
[void](Get-SwiftUIBaselineRelativePath -Root $repoRoot -Path $artifactRoot)
if (-not $artifactRoot.Equals((Join-Path $repoRoot "artifacts"), $comparison)) {
    throw "The repository artifact directory must not redirect through a filesystem alias."
}
$evidencePath = Resolve-SwiftUIBaselineFileSystemPath -Path $EvidenceRoot
[void](Get-SwiftUIBaselineRelativePath -Root $artifactRoot -Path $evidencePath)
if (-not (Test-Path -LiteralPath $evidencePath -PathType Container)) {
    throw "Candidate EvidenceRoot must be the existing artifact directory for this export."
}
$resultPath = Resolve-SwiftUIBaselineFileSystemPath -Path $ExportResultPath
$resultRelativePath = Get-SwiftUIBaselineRelativePath -Root $evidencePath -Path $resultPath
$exportFile = Read-SwiftUIAuditMetadata -Path $resultPath -MaximumBytes 1048576
$export = $exportFile.value
Assert-SwiftUIAuditFields $export @{ schemaVersion = 'integer'; status = 'string' } 'Export result'
if ($export.schemaVersion -ne 1 -or $export.status -cne "exported-awaiting-review") {
    throw "Only a successful exported-awaiting-review result is eligible for a candidate audit."
}
Assert-SwiftUIAuditFields $export @{
    path = 'string'; manifestPath = 'string'; statusPath = 'string'; inventoryPath = 'string'
    manifestSha256 = 'string'; statusSha256 = 'string'; inventorySha256 = 'string'
    baselineManifestSha256 = 'string'; counts = 'object'
} 'Export result'
$sourcePath = Resolve-SwiftUIAuditArtifactPath -CaptureRoot $evidencePath -RelativePath $export.path -Kind Directory
$declaredPaths = @{}
foreach ($field in @("manifestPath", "statusPath", "inventoryPath")) {
    $declaredPaths[$field] = Resolve-SwiftUIAuditArtifactPath -CaptureRoot $evidencePath -RelativePath $export.$field
}
$outputPath = Resolve-SwiftUIBaselineFileSystemPath -Path (Join-Path $evidencePath "audit")
$contextPath = Resolve-SwiftUIBaselineFileSystemPath -Path (Join-Path $evidencePath "audit-context.json")
if (-not $outputPath.Equals((Join-Path $evidencePath "audit"), $comparison) -or
    -not $contextPath.Equals((Join-Path $evidencePath "audit-context.json"), $comparison)) {
    throw "Candidate audit output paths must not redirect through filesystem aliases."
}
$sourcePrefix = $sourcePath.TrimEnd([char[]]"\/") + [System.IO.Path]::DirectorySeparatorChar
foreach ($path in @($outputPath, $contextPath, $resultPath)) {
    [void](Get-SwiftUIBaselineRelativePath -Root $evidencePath -Path $path)
    if ($path.Equals($sourcePath, $comparison) -or $path.StartsWith($sourcePrefix, $comparison)) {
        throw "Candidate output, context and export result must be outside the read-only source capture."
    }
}
foreach ($path in @($outputPath, $contextPath)) {
    if (Test-Path -LiteralPath $path) { throw "Candidate audit evidence already exists; existing evidence is never overwritten." }
}

$context = [ordered]@{
    schemaVersion = 1
    evidenceKind = "api-audit-candidate-link"
    status = "in-progress"
    reviewStatus = "unreviewed"
    exportResult = [ordered]@{ path = $resultRelativePath; sha256 = $exportFile.sha256 }
    sourceCapture = [ordered]@{
        path = $export.path; status = $export.status
        captureManifestSha256 = $export.manifestSha256; captureStatusSha256 = $export.statusSha256
        inventorySha256 = $export.inventorySha256; baselineManifestSha256 = $export.baselineManifestSha256
        syntheticFixtureAsReported = $null
    }
    ciContext = $null
    audit = $null
    authority = [ordered]@{
        nativeExportPerformed = $false; identityReviewPerformed = $false
        windowsMatchingPerformed = $false; behaviorConformanceAssessed = $false; releaseQualified = $false
        note = "This step verifies and indexes the existing candidate; it does not review or qualify it."
    }
    generator = [ordered]@{
        path = "scripts/build-swiftui-api-audit-candidate.ps1"
        sha256 = (Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.ToLowerInvariant()
        powerShellVersion = $PSVersionTable.PSVersion.ToString()
    }
    startedAtUtc = [DateTime]::UtcNow.ToString("o")
    finishedAtUtc = $null
    error = $null
}
Write-SwiftUIBaselineJson -Value $context -Path $contextPath
try {
    foreach ($field in @("manifestSha256", "statusSha256", "inventorySha256", "baselineManifestSha256")) {
        Assert-SwiftUIAuditSha256 $export.$field "Export result.$field"
    }
    $sdkCapture = Read-SwiftUIAuditCapture -CaptureRoot $sourcePath -ManifestPath $ManifestPath
    $expectedPaths = @{
        manifestPath = Join-Path $sdkCapture.captureRoot "capture.json"
        statusPath = Join-Path $sdkCapture.captureRoot "capture-status.json"
        inventoryPath = $sdkCapture.inventoryPath
    }
    foreach ($field in $expectedPaths.Keys) {
        $expectedPath = Resolve-SwiftUIBaselineFileSystemPath -Path $expectedPaths[$field]
        if (-not $declaredPaths[$field].Equals($expectedPath, $comparison)) {
            throw "Export result.$field does not identify the selected capture's file."
        }
    }
    if ($export.manifestSha256 -cne $sdkCapture.captureSha256 -or
        $export.statusSha256 -cne $sdkCapture.statusSha256 -or
        $export.inventorySha256 -cne $sdkCapture.inventorySha256 -or
        $export.baselineManifestSha256 -cne $sdkCapture.baselineManifestSha256) {
        throw "Export result hashes do not match the selected successful capture."
    }
    Assert-SwiftUIAuditJsonEqual -Expected $sdkCapture.capture.inventory.counts -Actual $export.counts -Context "Export result counts"
    $context.sourceCapture.syntheticFixtureAsReported = Get-SwiftUIBaselineProperty -Value $sdkCapture.capture -Name "syntheticFixture"
    $ciPath = Join-Path $evidencePath "ci-context.json"
    if (Test-Path -LiteralPath $ciPath) {
        $ciPath = Resolve-SwiftUIAuditArtifactPath -CaptureRoot $evidencePath -RelativePath "ci-context.json"
        $ciFile = Read-SwiftUIAuditBoundedText -Path $ciPath -MaximumBytes 1048576
        $context.ciContext = [ordered]@{ path = "ci-context.json"; sha256 = $ciFile.sha256 }
    }
    Write-SwiftUIBaselineJson -Value $context -Path $contextPath

    # The existing builder streams and reconciles every graph and inventory
    # record. Never deserialize inventory.json or NDJSON records in this step.
    $auditResult = & (Join-Path $PSScriptRoot "build-swiftui-api-audit.ps1") -CaptureRoot $sourcePath -OutputDirectory $outputPath -ManifestPath $ManifestPath
    if ($auditResult -isnot [System.Management.Automation.PSCustomObject] -or $auditResult.reviewStatus -cne "unreviewed") {
        throw "Audit builder did not return exactly one unreviewed result."
    }
    $returnedRoot = Resolve-SwiftUIBaselineFileSystemPath -Path $auditResult.path
    $returnedManifest = Resolve-SwiftUIBaselineFileSystemPath -Path $auditResult.manifestPath
    if (-not $returnedRoot.Equals($outputPath, $comparison) -or
        -not $returnedManifest.Equals((Join-Path $outputPath "audit.json"), $comparison)) {
        throw "Audit builder returned a different output destination."
    }
    Assert-SwiftUIAuditSha256 $auditResult.manifestSha256 "Audit result.manifestSha256"
    $auditFile = Read-SwiftUIAuditMetadata -Path $returnedManifest -MaximumBytes 16777216
    $auditSeal = Read-SwiftUIAuditBoundedText -Path (Join-Path $outputPath "audit.sha256") -MaximumBytes 1024
    if ($auditFile.sha256 -cne $auditResult.manifestSha256 -or
        $auditSeal.text.TrimEnd([char[]]@(13, 10)) -cne ($auditFile.sha256 + "  audit.json") -or
        $auditFile.value.reviewStatus -cne "unreviewed" -or
        $auditFile.value.sourceCapture.captureManifestSha256 -cne $sdkCapture.captureSha256 -or
        $auditFile.value.sourceCapture.captureStatusSha256 -cne $sdkCapture.statusSha256 -or
        $auditFile.value.sourceCapture.inventorySha256 -cne $sdkCapture.inventorySha256) {
        throw "Returned audit manifest does not seal the selected unreviewed candidate."
    }
    # Normalize only this fixed, small count summary. CLR Int64 counters can
    # become Int32 when their JSON values are read on either PowerShell runtime.
    $returnedCounts = ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $auditResult.counts -Depth 8 -Compress -WarningAction Stop) -ErrorAction Stop
    Assert-SwiftUIAuditJsonEqual -Expected $auditFile.value.counts -Actual $returnedCounts -Context "Audit result counts"
    foreach ($entry in @(
        [pscustomobject]@{ path = $resultPath; sha256 = $exportFile.sha256 },
        [pscustomobject]@{ path = $expectedPaths.manifestPath; sha256 = $sdkCapture.captureSha256 },
        [pscustomobject]@{ path = $expectedPaths.statusPath; sha256 = $sdkCapture.statusSha256 }
    )) {
        if ((Get-FileHash -LiteralPath $entry.path -Algorithm SHA256).Hash.ToLowerInvariant() -cne $entry.sha256) {
            throw "Source capture metadata or the export result changed during audit creation."
        }
    }
    if ($null -ne $context.ciContext -and
        (Get-FileHash -LiteralPath $ciPath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $context.ciContext.sha256) {
        throw "The original CI context changed during audit creation."
    }
    $context.audit = [ordered]@{
        path = Get-SwiftUIBaselineRelativePath -Root $evidencePath -Path $returnedRoot
        manifestPath = Get-SwiftUIBaselineRelativePath -Root $evidencePath -Path $returnedManifest
        manifestSha256 = $auditResult.manifestSha256
        counts = $auditResult.counts
        reviewStatus = "unreviewed"
    }
    $context.status = "created-unreviewed-ledger"
} catch {
    $context.status = "failed"
    $context.error = $_.Exception.Message
    throw
} finally {
    $context.finishedAtUtc = [DateTime]::UtcNow.ToString("o")
    Write-SwiftUIBaselineJson -Value $context -Path $contextPath
}

Write-Host "The complete source capture and full unreviewed ledger must be retained together."
[pscustomobject][ordered]@{
    path = $outputPath
    manifestPath = $auditResult.manifestPath
    manifestSha256 = $auditResult.manifestSha256
    contextPath = $contextPath
    reviewStatus = "unreviewed"
}
