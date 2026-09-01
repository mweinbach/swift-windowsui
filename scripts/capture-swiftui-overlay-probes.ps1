#Requires -Version 7.0
<#
.SYNOPSIS
Records separate, unreviewed native overlay observations for an explicit plan.
.DESCRIPTION
PrepareNativeProfile only hashes explicitly named files on the pinned Mac. It
does not execute a Swift command. Collection requires that profile's separately
selected hash in a strict probe plan. No automatic profile, flag, SDK, root or
retry fallback is allowed. Existing capture/census/ledger bytes remain unchanged.
#>
[CmdletBinding(DefaultParameterSetName = 'Collect')]
param(
    [Parameter(Mandatory)][string]$CaptureRoot,
    [Parameter(Mandatory)][string]$AuditRoot,
    [Parameter(Mandatory)][string]$DiscoveryRoot,
    [Parameter(Mandatory)][string]$ExpectedDiscoverySha256,
    [Parameter(Mandatory)][string]$OutputDirectory,
    [string]$ManifestPath = (Join-Path $PSScriptRoot '../docs/swiftui-baseline.json'),
    [Parameter(Mandatory, ParameterSetName = 'Prepare')][switch]$PrepareNativeProfile,
    [Parameter(Mandatory, ParameterSetName = 'Prepare')][string]$FrontendPath,
    [Parameter(Mandatory, ParameterSetName = 'Collect')][string]$PlanPath,
    [Parameter(Mandatory, ParameterSetName = 'Collect')][string]$ExpectedPlanSha256,
    [Parameter(Mandatory, ParameterSetName = 'Collect')][string]$NativeProfilePath
)
$ErrorActionPreference = 'Stop'
if (-not $IsMacOS) {
    throw 'Live Stage B requires macOS and PowerShell 7; no SDK path or native command was opened.'
}
. (Join-Path $PSScriptRoot 'swiftui-overlay-probe-collector.ps1')
$inputs = Read-SwiftUIOverlayProbeInputs -CaptureRoot $CaptureRoot -AuditRoot $AuditRoot `
    -DiscoveryRoot $DiscoveryRoot -ExpectedDiscoverySha256 $ExpectedDiscoverySha256 -ManifestPath $ManifestPath
if ($PrepareNativeProfile) {
    Write-SwiftUIOverlayProbeNativeProfile -Inputs $inputs -FrontendPath $FrontendPath -OutputDirectory $OutputDirectory
    return
}
$plan = Read-SwiftUIOverlayProbePlan -Path $PlanPath -ExpectedSha256 $ExpectedPlanSha256 -Inputs $inputs
$profile = Read-SwiftUIOverlayProbeNativeProfile -Path $NativeProfilePath -ExpectedSha256 $plan.nativeProfileSha256 -Inputs $inputs
$result = Invoke-SwiftUIOverlayProbeCollection -Inputs $inputs -Plan $plan -NativeProfile $profile -OutputDirectory $OutputDirectory
$result
if (-not $result.successful) {
    throw "Native overlay observations remain incomplete or failed; preserved report: $($result.reportPath)"
}
