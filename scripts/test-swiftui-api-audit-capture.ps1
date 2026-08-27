# Exercises only explicitly synthetic capture metadata. No SDK export runs.
param([string]$RepositoryRoot = (Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $RepositoryRoot 'scripts/swiftui-api-audit-common.ps1')
. (Join-Path $RepositoryRoot 'scripts/swiftui-api-audit-test-fixtures.ps1')
$ownedRoot = Join-Path ([IO.Path]::GetTempPath()) ('swiftui-audit-intake-probe-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($ownedRoot)
$expectedManifestPath = Join-Path $ownedRoot 'expected-baseline.json'
Copy-Item -LiteralPath (Join-Path $RepositoryRoot 'docs/swiftui-baseline.json') -Destination $expectedManifestPath
$fixture = New-SwiftUIAuditTestCapture -Root (Join-Path $ownedRoot 'capture') -ManifestPath $expectedManifestPath
$captureBytes = [IO.File]::ReadAllBytes($fixture.CapturePath)
$statusBytes = [IO.File]::ReadAllBytes($fixture.StatusPath)
$sealBytes = [IO.File]::ReadAllBytes($fixture.CaptureHashPath)
$baselineBytes = [IO.File]::ReadAllBytes($fixture.ManifestPath)
$script:assertions = 0
function Check([bool]$Value, [string]$Name) {
    if (-not $Value) { throw "Assertion failed: $Name" }
    $script:assertions++
}
function Intake { Read-SwiftUIAuditCapture -CaptureRoot $fixture.Root -ManifestPath $expectedManifestPath }
function Restore {
    [IO.File]::WriteAllBytes($fixture.CapturePath, $captureBytes)
    [IO.File]::WriteAllBytes($fixture.StatusPath, $statusBytes)
    [IO.File]::WriteAllBytes($fixture.CaptureHashPath, $sealBytes)
    [IO.File]::WriteAllBytes($fixture.ManifestPath, $baselineBytes)
    [IO.File]::WriteAllBytes($expectedManifestPath, $baselineBytes)
}
function Reseal($Capture) {
    Write-SwiftUIBaselineJson -Path $fixture.CapturePath -Value $Capture
    [void](Update-SwiftUIAuditTestCaptureHashes -Root $fixture.Root -CaptureOnly)
}
function Reject([string]$Name, [scriptblock]$Action, [string]$Pattern) {
    $caught = $null
    try { & $Action | Out-Null } catch { $caught = $_ }
    if ($null -eq $caught) { throw "Expected rejection: $Name" }
    if ($Pattern -and $caught.Exception.Message -notmatch $Pattern) {
        throw "Wrong rejection for ${Name}: $($caught.Exception.Message)"
    }
    $script:assertions++
}
$context = Intake
Check ($context.graphInputs.Count -eq 6) 'six graphs'
Check ($context.publicInterfaces.Count -eq 4) 'four interfaces'
Check ($context.crossImportDefinitions.Count -eq 1) 'one overlay'
Check ($context.inputFiles.Count -eq 11) 'all small hashed inputs including current baseline'
Check (-not $context.capture.exactIdentityPreviouslyReviewed) 'candidate remains unreviewed'
Check ($context.captureSha256 -ceq (Get-FileHash -LiteralPath $fixture.CapturePath -Algorithm SHA256).Hash.ToLowerInvariant()) 'exact capture byte hash'
Check ($context.inputFiles.kind -notcontains 'inventory') 'inventory not claimed rehashed'
Check ($context.publicInterfaces[0].record.path -ceq $context.publicInterfaces[0].relativePath) 'original interface record retained'

$inventoryLock = [IO.File]::Open($fixture.InventoryPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::None)
$graphLock = [IO.File]::Open($context.graphInputs[0].path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::None)
try { Check ((Intake).graphInputs.Count -eq 6) 'inventory and raw graph bytes never opened' }
finally { $graphLock.Dispose(); $inventoryLock.Dispose() }

$status = Read-SwiftUIAuditTestSmallJson $fixture.StatusPath
$status.status = 'failed'
Write-SwiftUIBaselineJson $status $fixture.StatusPath
Reject 'failed status' { Intake } 'successful matching candidate'
Restore
$capture = Read-SwiftUIAuditTestSmallJson $fixture.CapturePath
$capture.status = 'EXPORTED-AWAITING-INVENTORY-AND-BEHAVIOR-REVIEW'
Reseal $capture
Reject 'case-sensitive status' { Intake } 'candidate status'
Restore
$capture = Read-SwiftUIAuditTestSmallJson $fixture.CapturePath
$capture.qualification.releaseQualified = $true
Reseal $capture
Reject 'false qualification required' { Intake } 'cannot claim qualification'
Restore
$capture = Read-SwiftUIAuditTestSmallJson $fixture.CapturePath
$capture.qualification.behaviorConformanceVerified = 'false'
Reseal $capture
Reject 'qualification must be boolean' { Intake } 'must be boolean'
Restore
$status = Read-SwiftUIAuditTestSmallJson $fixture.StatusPath
$status.captureManifestSha256 = '0' * 64
Write-SwiftUIBaselineJson $status $fixture.StatusPath
Reject 'status hash seal' { Intake } 'manifest SHA-256 mismatch'
Restore
[IO.File]::WriteAllText($fixture.CaptureHashPath, ('0' * 64) + "  capture.json`n", [Text.UTF8Encoding]::new($false))
Reject 'digest sidecar seal' { Intake } 'does not seal'
Restore
[IO.File]::WriteAllBytes($fixture.StatusPath, [byte[]]@(0xff, 0x7b, 0x7d))
Reject 'strict UTF8' { Intake } 'Unable to translate|invalid|UTF-8'
Restore
$text = [Text.Encoding]::UTF8.GetString($statusBytes)
[IO.File]::WriteAllText($fixture.StatusPath, '[' + $text + ']', [Text.UTF8Encoding]::new($false))
Reject 'root array cannot unwrap' { Intake } 'JSON object root'
Restore
Reject 'metadata byte cap' { Read-SwiftUIAuditCapture -CaptureRoot $fixture.Root -ManifestPath $expectedManifestPath -MaximumMetadataBytes 10 } 'exceeds MaximumMetadataBytes'

$expected = Read-SwiftUIAuditTestSmallJson $expectedManifestPath
$expected.reviewedIdentity.status = 'reviewed'
$expected.reviewedIdentity.xcodeBuildVersion = $context.capture.observedIdentity.xcodeBuildVersion
$expected.reviewedIdentity.sdkBuildVersion = $context.capture.observedIdentity.sdkBuildVersion
$expected.reviewedIdentity.swiftCompilerVersionLine = $context.capture.observedIdentity.swiftCompilerVersionLine
$expected.evidence.sdkCapture = 'reviewed'
Write-SwiftUIBaselineJson $expected $expectedManifestPath
$reviewed = Intake
Check ($reviewed.expectedBaselineSha256 -cne $reviewed.baselineManifestSha256) 'review evolution need not preserve whole manifest hash'
Check (-not $reviewed.capture.exactIdentityPreviouslyReviewed) 'later review cannot alter capture identity history'
$expected.reviewedIdentity.sdkBuildVersion = 'WrongBuild'
Write-SwiftUIBaselineJson $expected $expectedManifestPath
Reject 'later pinned identity mismatch' { Intake } 'Pinned identity mismatch'
Restore
$capture = Read-SwiftUIAuditTestSmallJson $fixture.CapturePath
$capture.exactIdentityPreviouslyReviewed = $true
Reseal $capture
Reject 'review claim checked against captured baseline' { Intake } 'contradicts the captured baseline'
Restore
$expected = Read-SwiftUIAuditTestSmallJson $expectedManifestPath
$expected.toolchain.xcodeVersion = '26.7'
Write-SwiftUIBaselineJson $expected $expectedManifestPath
Reject 'pin drift' { Intake } 'differs from the pinned baseline'
Restore
$capture = Read-SwiftUIAuditTestSmallJson $fixture.CapturePath
$capture.inventory.sha256 = 'F' * 64
Reseal $capture
Reject 'inventory digest syntax' { Intake } 'lowercase SHA-256'
Restore
$capture = Read-SwiftUIAuditTestSmallJson $fixture.CapturePath
$capture.publicInterfaces[0].path = 'interfaces/SwiftUI/../outside.swiftinterface'
Reseal $capture
Reject 'traversal' { Intake } 'traversing component'
Restore
$extraPath = Join-Path $fixture.Root 'interfaces/SwiftUI/extra.swiftinterface'
[IO.File]::WriteAllText($extraPath, 'extra', [Text.UTF8Encoding]::new($false))
Reject 'undeclared interface' { Intake } 'Undeclared publicInterfaces artifact'
[IO.File]::Delete($extraPath)
$overlay = $context.crossImportDefinitions[0].path
[IO.File]::AppendAllText($overlay, 'changed', [Text.UTF8Encoding]::new($false))
Reject 'changed overlay bytes' { Intake } 'SHA-256 mismatch'
[IO.File]::WriteAllText($overlay, ([IO.File]::ReadAllText($overlay, [Text.Encoding]::UTF8).Replace('changed', '')), [Text.UTF8Encoding]::new($false))
Check ((Intake).crossImportDefinitions.Count -eq 1) 'overlay restored'
$capture = Read-SwiftUIAuditTestSmallJson $fixture.CapturePath
$capture.tools[0].path = '/not-on-this-host/swift'
$capture.exporterSources[0].path = 'reported/not-copied-exporter.ps1'
Reseal $capture
Check ((Intake).capture.tools[0].path -ceq '/not-on-this-host/swift') 'reported tool paths are preserved without probing'
Restore
if ([IO.Path]::DirectorySeparatorChar -eq '\') {
    $outside = Join-Path $ownedRoot 'outside'
    [void][IO.Directory]::CreateDirectory($outside)
    Copy-Item -LiteralPath $context.publicInterfaces[0].path -Destination (Join-Path $outside 'outside.swiftinterface')
    $alias = Join-Path $fixture.Root 'interfaces/SwiftUI/alias'
    [void](New-Item -ItemType Junction -Path $alias -Target $outside)
    $capture = Read-SwiftUIAuditTestSmallJson $fixture.CapturePath
    $capture.publicInterfaces[0].path = 'interfaces/SwiftUI/alias/outside.swiftinterface'
    Reseal $capture
    Reject 'declared junction escapes' { Intake } 'not contained'
    Restore
    Reject 'discovered junction escapes' { Intake } 'not contained'
    [IO.Directory]::Delete($alias)
}
Check ((Intake).publicInterfaces.Count -eq 4) 'final fixture intact'
[pscustomobject]@{ Assertions = $script:assertions; Runtime = $PSVersionTable.PSVersion.ToString(); Root = $ownedRoot } | ConvertTo-Json
