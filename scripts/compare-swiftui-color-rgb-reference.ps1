<#
.SYNOPSIS
Compares explicit immutable Windows/native RGB-constructor capture roots.
.DESCRIPTION
No Swift or native program is executed. Source/command/report provenance,
observer controls, required comparisons, and bridge observations remain
separate. The optional API association creates a new attachment; it never
edits a capture, review packet, audit stream, baseline, or claim status.
#>
param(
    [Parameter(Mandatory)][string]$WindowsRoot,
    [Parameter(Mandatory)][string]$NativeRoot,
    [Parameter(Mandatory)][string]$OutputPath,
    [string]$ReviewPacketRoot,
    [string]$PreciseIdentifier
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "swiftui-color-rgb-reference-common.ps1")
$rgbCompareRepository = Resolve-SwiftUIBaselineFileSystemPath (Split-Path -Parent $PSScriptRoot)
$rgbCompareOutput = New-SwiftUIColorRGBOutputRoot -Path $OutputPath -RepositoryRoot $rgbCompareRepository -ExcludedRoots @($WindowsRoot, $NativeRoot, $ReviewPacketRoot)
$rgbCompareProtocol = Get-SwiftUIColorRGBProtocol
$rgbComparison = [pscustomobject][ordered]@{
    schemaVersion = 1; evidenceKind = "color-rgb-comparison-candidate"
    protocolId = $rgbCompareProtocol.protocolId; caseSetId = $rgbCompareProtocol.caseSetId; tolerance = $rgbCompareProtocol
    createdAtUtc = [DateTime]::UtcNow.ToString("o"); state = "failure"
    inputs = [pscustomobject]@{ windowsRoot = $WindowsRoot; nativeRoot = $NativeRoot; windowsCaptureSha256 = $null; nativeCaptureSha256 = $null }
    sourceCompilation = $null; provenance = $null; primary = $null; appKit = $null
    auxiliaryFiles = @()
    apiAssociation = [pscustomobject]@{ state = "unlinked"; reason = "no-explicit-review-packet" }
    qualification = [pscustomobject]@{ declarationReview = "unverified"; sourceReview = "unverified"; behaviorReview = "unverified"; releaseQualified = $false }
    failureCodes = @()
}
$rgbWindows = $null; $rgbNative = $null
try {
    $parserPath = Join-Path $rgbCompareOutput "json-parser-identity.json"
    Write-SwiftUIColorRGBJsonNew $parserPath (Get-SwiftUIColorRGBJsonParserIdentity)
    $rgbComparison.auxiliaryFiles += Get-SwiftUIColorRGBFileRecord $parserPath "json-parser-identity.json"
    $rgbWindows = Read-SwiftUIColorRGBCapture $WindowsRoot
    $rgbComparison.inputs.windowsCaptureSha256 = $rgbWindows.manifestSha256
    $rgbNative = Read-SwiftUIColorRGBCapture $NativeRoot
    $rgbComparison.inputs.nativeCaptureSha256 = $rgbNative.manifestSha256
    $result = Compare-SwiftUIColorRGBCaptures $rgbWindows $rgbNative
    foreach ($field in @("state", "sourceCompilation", "provenance", "primary", "appKit")) { $rgbComparison.$field = $result.$field }
    try {
        if (-not [string]::IsNullOrWhiteSpace($ReviewPacketRoot)) {
            if ([string]::IsNullOrWhiteSpace($PreciseIdentifier)) { throw "RGB_REVIEW_EXPLICIT_PRECISE_IDENTIFIER_REQUIRED" }
            $rgbComparison.apiAssociation = Read-SwiftUIColorRGBReviewAssociation -PacketRoot $ReviewPacketRoot -PreciseIdentifier $PreciseIdentifier -WindowsCapture $rgbWindows -NativeCapture $rgbNative
            $associationAfter = Read-SwiftUIColorRGBReviewAssociation -PacketRoot $ReviewPacketRoot -PreciseIdentifier $PreciseIdentifier -WindowsCapture $rgbWindows -NativeCapture $rgbNative
            if ($associationAfter.packetManifestSha256 -cne $rgbComparison.apiAssociation.packetManifestSha256) { throw "RGB_REVIEW_PACKET_CHANGED" }
        } elseif (-not [string]::IsNullOrWhiteSpace($PreciseIdentifier)) { throw "RGB_REVIEW_PACKET_REQUIRED_FOR_IDENTIFIER" }
    } catch {
        $code = [regex]::Match($_.Exception.Message, '^RGB_[A-Z0-9_]+').Value
        if ([string]::IsNullOrEmpty($code)) { $code = "RGB_REVIEW_ASSOCIATION_FAILURE" }
        Set-SwiftUIColorRGBComparisonFailure -Comparison $rgbComparison -Code $code -AssociationOnly
        $rgbComparison.apiAssociation = [pscustomobject]@{ state = "failure"; reason = $code }
    }
    # Collection roots may be archived elsewhere, but their exact bytes must
    # remain unchanged while comparing. Revalidation also covers report files,
    # binary snapshots, source bytes, logs, and optional packet inputs.
    $winAfter = Read-SwiftUIColorRGBCapture $WindowsRoot
    $nativeAfter = Read-SwiftUIColorRGBCapture $NativeRoot
    if ($winAfter.manifestSha256 -cne $rgbWindows.manifestSha256 -or $nativeAfter.manifestSha256 -cne $rgbNative.manifestSha256) { throw "RGB_CAPTURE_CHANGED_DURING_COMPARISON" }
} catch {
    $code = [regex]::Match($_.Exception.Message, '^RGB_[A-Z0-9_]+').Value
    if ([string]::IsNullOrEmpty($code)) { $code = "RGB_COMPARISON_FAILURE" }
    Set-SwiftUIColorRGBComparisonFailure -Comparison $rgbComparison -Code $code
    if (-not [string]::IsNullOrWhiteSpace($ReviewPacketRoot)) { $rgbComparison.apiAssociation = [pscustomobject]@{ state = "failure"; reason = $code } }
}
$rgbComparisonPath = Join-Path $rgbCompareOutput "comparison.json"
Write-SwiftUIColorRGBJsonNew -Path $rgbComparisonPath -Value $rgbComparison
$rgbComparisonHash = Get-SwiftUIColorRGBHash $rgbComparisonPath
Write-SwiftUIColorRGBTextNew -Path (Join-Path $rgbCompareOutput "comparison.sha256") -Text "$rgbComparisonHash  comparison.json`n"
if ($rgbComparison.apiAssociation.state -ceq "linked-unverified") {
    Write-SwiftUIColorRGBJsonNew -Path (Join-Path $rgbCompareOutput "api-association.json") -Value ([pscustomobject]@{
        schemaVersion = 1; evidenceKind = "unverified-color-rgb-review-attachment"
        comparisonSha256 = $rgbComparisonHash; windowsCaptureSha256 = $rgbWindows.manifestSha256; nativeCaptureSha256 = $rgbNative.manifestSha256
        association = $rgbComparison.apiAssociation; claimStatusChanges = @()
    })
}
Write-Host "RGB primary comparison: $($rgbComparison.state). Evidence: $rgbCompareOutput"
if ($null -ne $rgbComparison.appKit) { Write-Host "Separate AppKit comparison: $($rgbComparison.appKit.state)." }
Write-Host "Declaration, source, behavior, and release review remain unverified."
if ($rgbComparison.state -ceq "match-candidate") { exit 0 }
if ($rgbComparison.state -ceq "unsupported") { exit 2 }
exit 1
