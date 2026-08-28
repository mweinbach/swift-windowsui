#Requires -Version 7.0
<#
.SYNOPSIS
Records a separate, unreviewed filesystem census for a successful pinned SDK
capture and complete sealed audit ledger. No compiler, SDK command or load probe
runs. The original artifacts and baseline are never modified.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$CaptureRoot,
    [Parameter(Mandatory)][string]$AuditRoot,
    [Parameter(Mandatory)][string]$RootPlanPath,
    [Parameter(Mandatory)][string]$ExpectedRootPlanSha256,
    [Parameter(Mandatory)][string]$OutputDirectory,
    [string]$ManifestPath = (Join-Path $PSScriptRoot '../docs/swiftui-baseline.json')
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'swiftui-overlay-discovery-common.ps1')

# Platform refusal precedes any SDK path access. Synthetic providers are only
# available through the internal test harness, never this native entrypoint.
if (-not $IsMacOS) { throw 'Live overlay discovery requires macOS and PowerShell 7; no SDK path was opened.' }
$source = Read-SwiftUIOverlayDiscoveryInputs -CaptureRoot $CaptureRoot -AuditRoot $AuditRoot -ManifestPath $ManifestPath
$rootPlan = Read-SwiftUIOverlayRootPlan -Path $RootPlanPath -ExpectedSha256 $ExpectedRootPlanSha256 -SourceContext $source
$provider = New-SwiftUIOverlayMacFileSystemProvider
$result = Invoke-SwiftUIOverlayCensus -SourceContext $source -RootPlanContext $rootPlan -Provider $provider -OutputDirectory $OutputDirectory
$result
if (-not $result.complete) { throw "Overlay census is incomplete. Sealed diagnostic report: $($result.manifestPath)" }
