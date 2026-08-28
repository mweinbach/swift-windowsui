param()

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$script:bitmapAssertions = 0
$script:bitmapFakeCalls = New-Object 'System.Collections.Generic.List[object]'
$script:bitmapForbiddenCalls = 0

# This test suite must stay pure PowerShell/.NET. In particular the production
# C# adapter and the existing DirectWrite family probe cannot compile or run.
function Add-Type { $script:bitmapForbiddenCalls++; throw 'Native compilation is forbidden in this synthetic suite.' }
function swift { $script:bitmapForbiddenCalls++; throw 'SwiftPM is forbidden in this synthetic suite.' }
. (Join-Path $PSScriptRoot 'gallery-bitmap-font-attribution.ps1')
. (Join-Path $PSScriptRoot 'gallery-font-provenance.ps1')

function Assert-Bitmap {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "Bitmap font attribution test failed: $Message" }
    $script:bitmapAssertions++
}

function Assert-BitmapRejects {
    param([scriptblock]$Action, [string]$Message)
    $rejected = $false
    try { & $Action | Out-Null } catch { $rejected = $true }
    Assert-Bitmap $rejected $Message
}

function Write-BitmapFixtureJson {
    param($Value, [string]$Path)
    if ([IO.Path]::GetFileName($Path) -ceq 'provenance.json') {
        Write-GalleryFontProvenance -Provenance $Value -Path $Path
        return
    }
    [IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 24 -Compress), (New-Object Text.UTF8Encoding($false)))
}

function New-BitmapNativeFixture {
    param([string]$InvocationID, [string]$FixtureID = 'symbol-palette')
    $role = if ($FixtureID -ceq 'stepper') { 'increment' } else { 'folder' }
    [pscustomobject][ordered]@{
        schemaVersion = 1; invocationID = $InvocationID; fixtureID = $FixtureID; status = 'observed'
        runtime = [pscustomobject]@{ os = 'Windows 10.0.20348'; architecture = 'x86_64' }; pngFileName = "$FixtureID.png"
        report = [pscustomobject][ordered]@{
            schemaVersion = 1; kind = 'native-bitmap-font-attribution'; scope = 'bitmap-icons'; fixtureID = $FixtureID
            status = 'observed'; qualification = 'unqualified'
            coverage = [pscustomobject]@{ bitmapIcons = 'observed'; atlasGlyphs = 'not-instrumented'; textLayouts = 'not-instrumented'; sceneReferences = 'observed' }
            faces = @([pscustomobject]@{
                id = 'face-1'
                metadata = [pscustomobject]@{
                    status = 'observed'; familyName = 'Segoe MDL2 Assets'; faceName = 'Regular'; namesStatus = 'observed'
                    faceIndex = 0; simulations = 0; files = @([pscustomobject]@{ status = 'observed'; scope = 'system-fonts'; basename = 'segmdl2.ttf' })
                    filesStatus = 'observed'; axesStatus = 'not-implemented'
                }
            })
            observations = @([pscustomobject]@{ role = $role; purpose = 'display-bitmap'; backend = 'direct-write'; outcome = 'scene-referenced'; faceIDs = @('face-1'); count = 1 })
            limits = [pscustomobject]@{ maxFaces = 64; maxReceipts = 256; maxObservations = 256; dropped = 0 }
        }
    }
}

function New-BitmapFakeFingerprint {
    [pscustomobject]@{
        Status = 'observed'; Sha256 = ('e' * 64); Length = [long]4096; LastWriteTimeUtc = '2026-08-27T12:00:00.0000000Z'
        FileVersion = $null; Error = $null; EmbeddedVersions = @('Version 1.84'); VersionStatus = 'observed-embedded-name'; VersionError = $null
        BytesRead = [long]4196; Stable = $true; Validation = 'same-handle-final-path-and-file-id'
    }
}

$fakeFingerprinter = {
    param($scope, $basename, $remaining)
    $script:bitmapFakeCalls.Add([pscustomobject]@{ scope = $scope; basename = $basename; remaining = $remaining })
    New-BitmapFakeFingerprint
}

function New-BitmapCollectionFixture {
    param([string[]]$EntryIds = @('symbol-palette'))
    $directory = Join-Path $script:bitmapFixtureRoot ([Guid]::NewGuid().ToString('N'))
    $invocation = New-GalleryBitmapFontAttributionInvocation -WorkDir $directory -EntryIds $EntryIds -InvocationID ([Guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($invocation.currentDirectory)
    [void][IO.Directory]::CreateDirectory($invocation.nativeDirectory)
    $exePath = Join-Path $directory 'synthetic-gallery-never-executed.bin'
    [IO.File]::WriteAllText($exePath, 'Synthetic executable bytes. This file is never executed.')
    $exeHash = (Read-GalleryBitmapArtifact -Path $exePath -MaximumBytes 1024).sha256
    $exeRecord = [pscustomobject]@{ path = $exePath; status = 'observed'; sha256 = $exeHash; length = 55 }
    $profile = [pscustomobject][ordered]@{
        schemaVersion = 1; invocationID = $invocation.invocationID; stage = 'render-completed'
        capturedAt = '2026-08-27T12:01:02.1234567+00:00'
        source = [pscustomobject]@{ revision = ('a' * 40); status = 'observed-checkout-only'; executableBuildRevision = $null; root = 'C:\PRIVATE_PATH_CANARY\source'; changes = @() }
        executable = $exeRecord
        build = [pscustomobject]@{ status = 'skipped'; exitCode = $null }
        render = [pscustomobject]@{ status = 'succeeded'; exitCode = 0; executableAfter = $exeRecord; executableUnchanged = $true; requestedEntries = @($EntryIds) }
        fonts = [pscustomobject]@{
            registeredFontFiles = [pscustomobject]@{ files = @([pscustomobject]@{ file = [pscustomobject]@{ path = (Join-Path ([Environment]::GetFolderPath('Windows')) 'Fonts/segmdl2.ttf'); sha256 = ('e' * 64) } }) }
        }
        qualification = [pscustomobject]@{ status = 'unqualified'; acceptedBaselineProfile = $null }
    }
    $profilePath = Join-Path $directory 'provenance.json'
    Write-BitmapFixtureJson $profile $profilePath
    foreach ($id in $EntryIds) {
        # Collector tests hash opaque fixture bytes; no bitmap decoder, native
        # renderer, image editing, or fake claim of actual pixel tests is used.
        [IO.File]::WriteAllBytes((Join-Path $invocation.currentDirectory "$id.png"), [byte[]]@(137, 80, 78, 71, 1, 2, 3, 4))
        Write-BitmapFixtureJson (New-BitmapNativeFixture $invocation.invocationID $id) (Join-Path $invocation.nativeDirectory "$id.native-font-attribution.json")
    }
    [pscustomobject]@{ invocation = $invocation; profile = $profile; profilePath = $profilePath; executablePath = $exePath }
}

function Invoke-BitmapCollectionFixture {
    param($Fixture, [scriptblock]$Fingerprinter = $fakeFingerprinter)
    Complete-GalleryBitmapFontAttribution -Invocation $Fixture.invocation -Provenance $Fixture.profile -ProfilePath $Fixture.profilePath -FileFingerprinter $Fingerprinter
}

$token = '0123456789abcdef0123456789abcdef'
$baseNative = New-BitmapNativeFixture $token
$baseJson = $baseNative | ConvertTo-Json -Depth 24 -Compress
$native = ConvertTo-GalleryBitmapNativeReport -Json $baseJson -InvocationID $token -FixtureID 'symbol-palette'
Assert-Bitmap ($native.report.faces.Count -eq 1 -and $native.report.faces[0].metadata.faceIndex -eq 0) 'actual face metadata retains collection index zero'
Assert-Bitmap ($native.report.faces[0].metadata.axesStatus -ceq 'not-implemented' -and $null -eq $native.report.faces[0].metadata.axes) 'absent optional axes remain unknown'
Assert-Bitmap ($native.report.qualification -ceq 'unqualified' -and $native.report.coverage.atlasGlyphs -ceq 'not-instrumented') 'bitmap-only scope cannot qualify atlas glyphs'

foreach ($name in @('segoeui.ttf', 'SegoeIcons.ttf', 'font name.otf', 'collection.ttc')) { Assert-Bitmap (Test-GalleryBitmapSafeFontBasename $name) 'a direct approved basename is accepted lexically' }
foreach ($name in @('../secret.ttf', '..\secret.ttf', 'C:\private.ttf', '\\server\font.ttf', '\\?\C:\font.ttf', '\\.\C:\font.ttf', 'font.ttf:stream', 'font~1.ttf', 'font.ttf ', 'font.ttf.', 'CON.ttf', 'CON .ttf', 'COM1.ttf', 'LPT1.otf', 'CLOCK$.ttf', 'CONIN$.ttf', ('COM' + [char]0xb9 + '.ttf'), 'secret.bin', 'a..b.ttf', (('f' * 256) + '.ttf'), ('font' + [char]0 + '.ttf'))) {
    Assert-Bitmap (-not (Test-GalleryBitmapSafeFontBasename $name)) 'paths, device names, aliases, controls, and unsupported font types are rejected'
}

$schemaMutations = @(
    { param($x) $x.schemaVersion = 2 },
    { param($x) $x.schemaVersion = '1' },
    { param($x) $x.schemaVersion = $true },
    { param($x) $x.invocationID = ('f' * 32) },
    { param($x) $x.fixtureID = 'stepper' },
    { param($x) $x.pngFileName = '../other.png' },
    { param($x) $x.runtime.os = 'C:\PRIVATE_PATH_CANARY\private' },
    { param($x) $x.runtime.architecture = 'x86' },
    { param($x) $x.report.qualification = 'qualified' },
    { param($x) $x.report.coverage.atlasGlyphs = 'observed' },
    { param($x) $x.report.faces = $null },
    { param($x) $x.report.faces = $x.report.faces[0] },
    { param($x) $x.report.faces[0].metadata.faceIndex = -1 },
    { param($x) $x.report.faces[0].metadata.simulations = 4294967296 },
    { param($x) $x.report.faces[0].metadata.familyName = ('x' * 513) },
    { param($x) $x.report.faces[0].metadata.familyName = 'Family:Private' },
    { param($x) $x.report.faces[0].metadata.familyName = '/Users/PRIVATE_PATH_CANARY' },
    { param($x) $x.report.faces[0].metadata.familyName = '\\server\PRIVATE_PATH_CANARY' },
    { param($x) $x.report.faces[0].metadata.familyName = $null },
    { param($x) $x.report.faces[0].metadata.files = @() },
    { param($x) $x.report.faces[0].metadata.files[0].basename = '../private.ttf' },
    { param($x) $x.report.faces[0].metadata.files[0].scope = 'custom-fonts' },
    { param($x) $x.report.faces[0].metadata.files[0].status = 'not-approved' },
    { param($x) $x.report.faces[0].metadata.axesStatus = 'observed' },
    { param($x) $x.report.observations[0].role = 'editable-user-text' },
    { param($x) $x.report.observations[0].purpose = 'measurement' },
    { param($x) $x.report.observations[0].purpose = 'candidate-probe' },
    { param($x) $x.report.observations[0].backend = 'gdi' },
    { param($x) $x.report.observations[0].faceIDs = @('face-2') },
    { param($x) $x.report.observations[0].faceIDs = @('face-1', 'face-1') },
    { param($x) $x.report.observations[0].count = 1.5 },
    { param($x) $x.report.observations[0].count = '1' },
    { param($x) $x.report.observations[0].count = -1 },
    { param($x) $x.report.observations[0].count = 2147483648 },
    { param($x) $x.report.limits.maxFaces = 65 },
    { param($x) $x | Add-Member NoteProperty text 'PRIVATE_TEXT_CANARY' },
    { param($x) $x.report.faces[0].metadata | Add-Member NoteProperty path 'C:\PRIVATE_PATH_CANARY\font.ttf' },
    { param($x) $x.report.observations[0] | Add-Member NoteProperty glyphIDs @(10, 11) }
)
foreach ($mutate in $schemaMutations) {
    $value = ConvertFrom-Json $baseJson
    & $mutate $value
    $badJson = $value | ConvertTo-Json -Depth 24 -Compress
    Assert-BitmapRejects { ConvertTo-GalleryBitmapNativeReport $badJson $token 'symbol-palette' } 'malformed, broadened, or mismatched native fields are rejected'
}
foreach ($badJson in @(
    $baseJson.Replace('"schemaVersion":1', '"schemaVersion":1,"schemaVersion":1'),
    $baseJson.Replace('"schemaVersion":1', '"schemaVersion":1,"SchemaVersion":1'),
    $baseJson.Replace('"schemaVersion":1', '"schemaVersion":1,"\u0073chemaVersion":1'),
    (('[' * 25) + '0' + (']' * 25)),
    '{"a":"unterminated}',
    ($baseJson + '{}'),
    $baseJson.Replace('"schemaVersion":1', 'schemaVersion:1'),
    $baseJson.Replace('"schemaVersion":1', "'schemaVersion':1"),
    $baseJson.Replace('"schemaVersion":1', '"schemaVersion":0x1'),
    $baseJson.Replace('"schemaVersion":1', '"schemaVersion":01'),
    $baseJson.Replace('"schemaVersion":1', '"schemaVersion":+1'),
    $baseJson.Replace('"schemaVersion":1', '/* comment */ "schemaVersion":1'),
    $baseJson.Replace('"dropped":0}', '"dropped":0,}'),
    $baseJson.Replace('Segoe MDL2 Assets', '\ud800'),
    $baseJson.Replace('Segoe MDL2 Assets', '\udc00'),
    $baseJson.Replace('Segoe MDL2 Assets', '\ud800\ud800')
)) { Assert-BitmapRejects { ConvertTo-GalleryBitmapNativeReport $badJson $token 'symbol-palette' } 'duplicate/escaped/case-colliding keys and invalid/deep JSON fail closed' }
$unicodeJson = $baseJson.Replace('Segoe MDL2 Assets', 'Face \ud83d\ude00')
Assert-Bitmap ((ConvertTo-GalleryBitmapNativeReport $unicodeJson $token 'symbol-palette').report.faces.Count -eq 1) 'valid paired Unicode escapes remain accepted'
$emptyAxes = ConvertFrom-Json $baseJson
$emptyAxes.report.faces[0].metadata.axesStatus = 'observed'
$emptyAxes.report.faces[0].metadata | Add-Member NoteProperty axes @()
Assert-Bitmap ((ConvertTo-GalleryBitmapNativeReport ($emptyAxes | ConvertTo-Json -Depth 24 -Compress) $token 'symbol-palette').report.faces[0].metadata.axes.Count -eq 0) 'an observed empty axis set remains distinct from unimplemented axes'
Set-StrictMode -Version Latest
try {
    $strictNative = ConvertTo-GalleryBitmapNativeReport $baseJson $token 'symbol-palette'
    Assert-Bitmap ($null -eq $strictNative.report.faces[0].metadata.axes) 'omitted Swift optionals work under caller StrictMode'
} finally { Set-StrictMode -Off }

foreach ($count in @(64, 65)) {
    $value = ConvertFrom-Json $baseJson
    $value.report.faces = @(for ($i = 0; $i -lt $count; $i++) { $face = ConvertFrom-Json (($value.report.faces[0]) | ConvertTo-Json -Depth 12 -Compress); $face.id = "face-$i"; $face })
    $json = $value | ConvertTo-Json -Depth 24 -Compress
    if ($count -eq 64) { Assert-Bitmap ((ConvertTo-GalleryBitmapNativeReport $json $token 'symbol-palette').report.faces.Count -eq 64) '64 faces are within the native cap' }
    else { Assert-BitmapRejects { ConvertTo-GalleryBitmapNativeReport $json $token 'symbol-palette' } '65 faces exceed the native cap' }
}
foreach ($count in @(8, 9)) {
    $value = ConvertFrom-Json $baseJson
    $value.report.faces[0].metadata.files = @(for ($i = 0; $i -lt $count; $i++) { [pscustomobject]@{ status = 'observed'; scope = 'system-fonts'; basename = "font$i.ttf" } })
    $json = $value | ConvertTo-Json -Depth 24 -Compress
    if ($count -eq 8) { Assert-Bitmap ((ConvertTo-GalleryBitmapNativeReport $json $token 'symbol-palette').report.faces[0].metadata.files.Count -eq 8) 'eight file references fit the face cap' }
    else { Assert-BitmapRejects { ConvertTo-GalleryBitmapNativeReport $json $token 'symbol-palette' } 'nine files exceed the face cap' }
}

$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([char[]]@('/', '\'))
$script:bitmapFixtureRoot = Join-Path $tempRoot ('swift-windowsui-bitmap-font-test-' + [Guid]::NewGuid().ToString('N'))
Assert-Bitmap (-not (Test-Path -LiteralPath $script:bitmapFixtureRoot)) 'synthetic output directory is new and owned'
[void][IO.Directory]::CreateDirectory($script:bitmapFixtureRoot)
try {
    $fresh = Join-Path $script:bitmapFixtureRoot 'fresh-options'
    Assert-GalleryBitmapFontAttributionOptions @('symbol-palette', 'stepper') $true $false $false $false $fresh
    Assert-Bitmap (-not (Test-Path -LiteralPath $fresh)) 'option validation alone does not create files or run probes'
    foreach ($flags in @(@($false, $false, $false, $false), @($true, $true, $false, $false), @($true, $false, $true, $false), @($true, $false, $false, $true))) {
        Assert-BitmapRejects { Assert-GalleryBitmapFontAttributionOptions @('symbol-palette') $flags[0] $flags[1] $flags[2] $flags[3] $fresh } 'explicit entries/fresh render/no update/no list requirements are enforced'
    }
    Assert-BitmapRejects { Assert-GalleryBitmapFontAttributionOptions @('button') $true $false $false $false $fresh } 'unapproved fixtures cannot enter the collector'
    Assert-BitmapRejects { Assert-GalleryBitmapFontAttributionOptions @('symbol-palette') $true $false $false $false $script:bitmapFixtureRoot } 'existing work directories are rejected'
    Assert-BitmapRejects { New-GalleryBitmapFontAttributionInvocation $fresh @('symbol-palette') ('A' * 32) } 'tokens must be lowercase hex'

    $fixture = New-BitmapCollectionFixture @('symbol-palette', 'stepper')
    $script:bitmapFakeCalls.Clear()
    $result = Invoke-BitmapCollectionFixture $fixture
    Assert-Bitmap ($result.status -ceq 'observed' -and $result.invocationAssociation -ceq 'linked-to-completed-invocation') 'valid synthetic native evidence links to the completed invocation'
    Assert-Bitmap ($script:bitmapFakeCalls.Count -eq 1 -and $result.files.Count -eq 1) 'duplicate file references across fixtures share one fingerprint'
    Assert-Bitmap ($result.limits.chargedReadBytes -eq 4196 -and $result.files[0].observation.file.length -eq 4096) 'version rereads are included in the aggregate byte budget'
    Assert-Bitmap ($result.files[0].registeredFileMatches.Count -eq 1 -and $result.files[0].registeredFileMatches[0].sha256MatchesDiskObservation) 'registration matching is only a path-based cross-reference'
    Assert-Bitmap ($result.files[0].observation.loadedBytesDigest -ceq 'not-observed' -and $result.source.executableBuildRevision -eq $null) 'post-render disk observation cannot become loaded bytes or an embedded build revision'
    Assert-Bitmap ($result.entries[0].png.sha256 -cmatch '^[0-9a-f]{64}$' -and $result.entries[0].nativeSidecar.sha256 -cmatch '^[0-9a-f]{64}$') 'PNG and sidecar digests are included separately'
    Assert-Bitmap ($result.qualification.status -ceq 'unqualified' -and $result.qualification.pixelGate -ceq 'unchanged' -and $result.qualification.performanceQualification -ceq 'excluded') 'all qualification boundaries remain explicit'
    $serialized = [IO.File]::ReadAllText($fixture.invocation.reportPath)
    Assert-Bitmap ($serialized -notmatch 'PRIVATE_PATH_CANARY|PRIVATE_TEXT_CANARY|[A-Za-z]:\\|glyphIDs|cacheKey|referenceKey') 'aggregate output excludes private paths and forbidden payloads'
    Assert-Bitmap ((Get-Item -LiteralPath $fixture.invocation.reportPath).Length -le 524288) 'aggregate JSON is bounded'

    $disk = New-GalleryBitmapDiskObservation 'system-fonts' 'segmdl2.ttf' 536870912 { param($s, $n, $r) $x = New-BitmapFakeFingerprint; $x.EmbeddedVersions = @(); $x.VersionStatus = 'unknown'; $x.VersionError = 'unsupported-container'; $x }
    Assert-Bitmap ($disk.diskObservation -ceq 'observed-after-render' -and $disk.versionStatus -ceq 'unknown') 'unsupported TTC/SFNT version metadata does not fabricate a version or erase a valid disk hash'
    $callsBefore = $script:bitmapFakeCalls.Count
    $limited = New-GalleryBitmapDiskObservation 'system-fonts' 'segmdl2.ttf' 0 $fakeFingerprinter
    Assert-Bitmap ($limited.file.status -ceq 'limit-exceeded' -and $script:bitmapFakeCalls.Count -eq $callsBefore) 'exhausted total budget never calls the file adapter'
    $failed = New-GalleryBitmapDiskObservation 'system-fonts' 'segmdl2.ttf' 536870912 { throw 'C:\PRIVATE_PATH_CANARY\PRIVATE_TEXT_CANARY' }
    Assert-Bitmap ($failed.diskObservation -ceq 'not-observed' -and $failed.bytesRead -eq 134217728 -and ($failed | ConvertTo-Json -Depth 10) -notmatch 'PRIVATE_') 'adapter exceptions remain private and conservatively consume budget'
    $invalid = New-GalleryBitmapDiskObservation 'system-fonts' 'segmdl2.ttf' 536870912 { $x = New-BitmapFakeFingerprint; $x.BytesRead = 134217729; $x }
    Assert-Bitmap ($invalid.file.status -ceq 'failed' -and $null -eq $invalid.file.sha256) 'oversized adapter accounting cannot be accepted'
    $mutated = New-GalleryBitmapDiskObservation 'system-fonts' 'segmdl2.ttf' 536870912 { $x = New-BitmapFakeFingerprint; $x.Status = 'mutated'; $x.Error = 'file-mutated'; $x.Stable = $false; $x }
    Assert-Bitmap ($mutated.diskObservation -ceq 'not-observed' -and $null -eq $mutated.file.sha256) 'file mutation cannot retain a digest association'
    $invalidReference = New-GalleryBitmapDiskObservation 'system-fonts' 'C:\PRIVATE_PATH_CANARY\font.ttf' 536870912 $fakeFingerprinter
    Assert-Bitmap ($null -eq $invalidReference.basename -and $invalidReference.bytesRead -eq 0 -and ($invalidReference | ConvertTo-Json -Depth 10) -notmatch 'PRIVATE_') 'invalid standalone file references are redacted before output construction'
    $invalidInvocation = New-BitmapCollectionFixture
    $invalidInvocation.invocation.entries = @('../PRIVATE_PATH_CANARY')
    Assert-BitmapRejects { Invoke-BitmapCollectionFixture $invalidInvocation } 'invalid invocation entries reject before path construction or output'
    Assert-Bitmap (-not (Test-Path -LiteralPath $invalidInvocation.invocation.reportPath)) 'invalid invocation does not write a report containing untrusted identifiers'

    foreach ($mode in @('missing-sidecar', 'wrong-token', 'wrong-fixture', 'stale-sidecar', 'oversize-sidecar', 'invalid-utf8', 'unknown-field', 'render-skipped', 'render-failed', 'exe-changed', 'source-mismatch', 'profile-mismatch', 'exe-bytes-mismatch')) {
        $fixture = New-BitmapCollectionFixture
        $nativePath = Join-Path $fixture.invocation.nativeDirectory 'symbol-palette.native-font-attribution.json'
        $value = New-BitmapNativeFixture $fixture.invocation.invocationID
        switch ($mode) {
            'missing-sidecar' { Remove-Item -LiteralPath $nativePath }
            'wrong-token' { $value.invocationID = ('0' * 32); Write-BitmapFixtureJson $value $nativePath }
            'wrong-fixture' { $value.fixtureID = 'stepper'; Write-BitmapFixtureJson $value $nativePath }
            'stale-sidecar' { [IO.File]::SetLastWriteTimeUtc($nativePath, [DateTime]::UtcNow.AddDays(-1)) }
            'oversize-sidecar' { [IO.File]::WriteAllBytes($nativePath, (New-Object byte[] 524289)) }
            'invalid-utf8' { [IO.File]::WriteAllBytes($nativePath, [byte[]]@(0xc3, 0x28)) }
            'unknown-field' { $value.report | Add-Member NoteProperty secret 'PRIVATE_TEXT_CANARY'; Write-BitmapFixtureJson $value $nativePath }
            'render-skipped' { $fixture.profile.render.status = 'skipped'; Write-BitmapFixtureJson $fixture.profile $fixture.profilePath }
            'render-failed' { $fixture.profile.render.status = 'failed'; $fixture.profile.render.exitCode = 1; Write-BitmapFixtureJson $fixture.profile $fixture.profilePath }
            'exe-changed' { $fixture.profile.render.executableAfter = [pscustomobject]@{ status = 'observed'; sha256 = ('b' * 64) }; Write-BitmapFixtureJson $fixture.profile $fixture.profilePath }
            'source-mismatch' { $value = ConvertFrom-Json ([IO.File]::ReadAllText($fixture.profilePath)); $value.source.revision = ('b' * 40); Write-BitmapFixtureJson $value $fixture.profilePath }
            'profile-mismatch' { $value = ConvertFrom-Json ([IO.File]::ReadAllText($fixture.profilePath)); $value.fonts.registeredFontFiles.files[0].file.sha256 = ('b' * 64); Write-BitmapFixtureJson $value $fixture.profilePath }
            'exe-bytes-mismatch' { [IO.File]::WriteAllText($fixture.executablePath, 'Changed synthetic executable bytes.') }
        }
        $script:bitmapFakeCalls.Clear()
        $result = Invoke-BitmapCollectionFixture $fixture
        Assert-Bitmap ($result.status -ceq 'partial' -and $null -eq $result.entries[0].native -and $result.files.Count -eq 0 -and $script:bitmapFakeCalls.Count -eq 0) "invalid evidence must not acquire attribution ($mode)"
        Assert-Bitmap ((Test-Path -LiteralPath (Join-Path $fixture.invocation.currentDirectory 'symbol-palette.png')) -and $result.entries[0].png.status -ceq 'observed') "native PNG bytes survive unavailable or rejected diagnostics ($mode)"
        Assert-Bitmap ([IO.File]::ReadAllText($fixture.invocation.reportPath) -notmatch 'PRIVATE_') "rejected fields do not leak into aggregate JSON ($mode)"
    }

    foreach ($mode in @('png', 'same-length-png', 'sidecar', 'profile', 'executable')) {
        $fixture = New-BitmapCollectionFixture
        $script:bitmapMutatePath = switch ($mode) {
            'png' { Join-Path $fixture.invocation.currentDirectory 'symbol-palette.png' }
            'same-length-png' { Join-Path $fixture.invocation.currentDirectory 'symbol-palette.png' }
            'sidecar' { Join-Path $fixture.invocation.nativeDirectory 'symbol-palette.native-font-attribution.json' }
            'profile' { $fixture.profilePath }
            'executable' { $fixture.executablePath }
        }
        $script:bitmapSameLengthMutation = $mode -ceq 'same-length-png'
        $result = Invoke-BitmapCollectionFixture $fixture {
            param($s, $n, $r)
            if ($script:bitmapSameLengthMutation) {
                $bytes = [IO.File]::ReadAllBytes($script:bitmapMutatePath); $bytes[0] = 0
                [IO.File]::WriteAllBytes($script:bitmapMutatePath, $bytes)
            } else { [IO.File]::AppendAllText($script:bitmapMutatePath, ' changed after first digest') }
            New-BitmapFakeFingerprint
        }
        Assert-Bitmap ($result.status -ceq 'partial' -and $null -eq $result.entries[0].native -and $result.files.Count -eq 0) "artifact digest changes during collection invalidate associations ($mode)"
    }

    $fixture = New-BitmapCollectionFixture
    $value = New-BitmapNativeFixture $fixture.invocation.invocationID
    $value.status = 'partial'; $value.report.status = 'partial'; $value.report.faces[0].metadata.status = 'partial'
    Write-BitmapFixtureJson $value (Join-Path $fixture.invocation.nativeDirectory 'symbol-palette.native-font-attribution.json')
    $result = Invoke-BitmapCollectionFixture $fixture
    Assert-Bitmap ($result.status -ceq 'partial' -and $null -ne $result.entries[0].native -and $result.files.Count -eq 1) 'real-shaped partial metadata can retain observed files without inventing missing axes'
    $value.report.faces = @(); $value.report.observations[0].faceIDs = @(); $value.status = 'observed'; $value.report.status = 'observed'
    Write-BitmapFixtureJson $value (Join-Path $fixture.invocation.nativeDirectory 'symbol-palette.native-font-attribution.json')
    $result = Invoke-BitmapCollectionFixture $fixture
    Assert-Bitmap ($result.status -ceq 'partial' -and $result.files.Count -eq 0) 'a successful-looking DirectWrite observation with no owner is downgraded'

    foreach ($mode in @('bitmap-cache-hit-unobserved', 'scene-association-unobserved', 'gdi', 'vector', 'nonlocal-or-custom')) {
        $fixture = New-BitmapCollectionFixture
        $value = New-BitmapNativeFixture $fixture.invocation.invocationID
        $value.status = 'partial'; $value.report.status = 'partial'; $value.report.coverage.bitmapIcons = 'partial'
        if ($mode -ceq 'nonlocal-or-custom') {
            $value.report.faces[0].metadata.status = 'partial'; $value.report.faces[0].metadata.filesStatus = 'nonlocal-or-custom'
            $value.report.faces[0].metadata.files = @([pscustomobject]@{ status = 'nonlocal-or-custom' })
        } else {
            $value.report.faces = @(); $value.report.observations[0].faceIDs = @()
            if ($mode -cin @('gdi', 'vector')) { $value.report.observations[0].backend = $mode; $value.report.observations[0].outcome = if ($mode -ceq 'vector') { 'vector-selected' } else { 'bitmap-accepted' } }
            else { $value.report.observations[0].backend = 'unknown'; $value.report.observations[0].outcome = $mode }
        }
        Write-BitmapFixtureJson $value (Join-Path $fixture.invocation.nativeDirectory 'symbol-palette.native-font-attribution.json')
        $result = Invoke-BitmapCollectionFixture $fixture
        Assert-Bitmap ($result.status -ceq 'partial' -and $null -ne $result.entries[0].native -and $result.files.Count -eq 0) "legitimate unknown/fallback states remain linked but partial ($mode)"
    }

    $fixture = New-BitmapCollectionFixture
    $value = New-BitmapNativeFixture $fixture.invocation.invocationID
    $value.report.faces = @(for ($i = 0; $i -lt 9; $i++) {
        $face = (New-BitmapNativeFixture $fixture.invocation.invocationID).report.faces[0]
        $face.id = "face-$i"
        $face.metadata.files = @(for ($j = 0; $j -lt 8; $j++) { [pscustomobject]@{ status = 'observed'; scope = 'system-fonts'; basename = "font-$i-$j.ttf" } })
        $face
    })
    Write-BitmapFixtureJson $value (Join-Path $fixture.invocation.nativeDirectory 'symbol-palette.native-font-attribution.json')
    $script:bitmapFakeCalls.Clear()
    $result = Invoke-BitmapCollectionFixture $fixture
    Assert-Bitmap ($result.limits.filesDropped -and $result.files.Count -eq 64 -and $script:bitmapFakeCalls.Count -eq 64) '65th and later distinct file references do not invoke the adapter'
    $result = Invoke-BitmapCollectionFixture $fixture {
        param($s, $n, $r)
        $x = New-BitmapFakeFingerprint; $x.Length = [long]134217728; $x.BytesRead = [long]134217728
        $x.EmbeddedVersions = @(); $x.VersionStatus = 'unknown'; $x.VersionError = 'read-budget-exhausted'; $x
    }
    Assert-Bitmap ($result.limits.chargedReadBytes -eq 536870912 -and @($result.files | Where-Object { $_.observation.file.status -ceq 'observed' }).Count -eq 4) '512 MiB session budget stops after four full-budget files'

    # Exercise aggregate truncation without allocating a large native tree.
    $result.entries[0].native = [pscustomobject]@{ synthetic = ('x' * 524288) }
    Write-GalleryBitmapFontAttributionReport $result $fixture.invocation.reportPath
    Assert-Bitmap ($result.limits.aggregateDropped -and $result.status -ceq 'partial' -and (Get-Item -LiteralPath $fixture.invocation.reportPath).Length -le 524288) 'oversized aggregate drops detail with a bounded partial record'

    # Source-level integration checks intentionally do not execute the wrapper,
    # whose ordinary path loads System.Drawing and the DirectWrite family probe.
    $gallerySource = [IO.File]::ReadAllText((Join-Path $repoRoot 'scripts/gallery-compare.ps1'))
    Assert-Bitmap ($gallerySource.IndexOf('Assert-GalleryBitmapFontAttributionOptions') -lt $gallerySource.IndexOf('New-GalleryFontProvenance -Executable')) 'unsupported diagnostic options reject before existing native probes'
    Assert-Bitmap ($gallerySource.Contains("'--bitmap-font-attribution-dir'") -and $gallerySource.Contains("'--bitmap-font-attribution-invocation'")) 'the fresh native directory and token are passed together'
    Assert-Bitmap ($gallerySource.Contains('[double] $MaxChangedPercent = 0.5') -and $gallerySource.Contains('[int] $ChannelTolerance = 8') -and $gallerySource.Contains('[int] $MaxChannelDelta = 64')) 'existing pixel thresholds remain unchanged'
    Assert-Bitmap ($gallerySource.Contains('status        = if ($failCount -eq 0) { "pass" } else { "fail" }')) 'pixel comparison status remains independent of diagnostics'
    Assert-Bitmap ($script:bitmapForbiddenCalls -eq 0 -and -not ('SwiftWindowsUIBitmapFontFileAdapterV1' -as [type])) 'no Add-Type, native adapter, or SwiftPM invocation occurred'
} finally {
    $resolved = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $script:bitmapFixtureRoot).Path)
    if ([IO.Path]::GetDirectoryName($resolved) -cne $tempRoot -or [IO.Path]::GetFileName($resolved) -notmatch '^swift-windowsui-bitmap-font-test-[0-9a-f]{32}$') { throw 'Refusing cleanup outside the owned bitmap attribution fixture directory.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}

Write-Host "Bitmap font attribution synthetic tests passed ($script:bitmapAssertions assertions). No C# compilation, native calls, renderer, or SwiftPM."
exit 0
