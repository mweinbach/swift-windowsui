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

function New-BitmapNativeFixtureV2 {
    param([string]$InvocationID, [string]$FixtureID = 'symbol-palette')
    $legacy = New-BitmapNativeFixture $InvocationID $FixtureID
    $role = if ($FixtureID -ceq 'stepper') { 'increment' } else { 'folder' }
    [pscustomobject][ordered]@{
        schemaVersion = 2; invocationID = $InvocationID; fixtureID = $FixtureID; status = 'observed'
        runtime = $legacy.runtime; pngFileName = $legacy.pngFileName
        report = [pscustomobject][ordered]@{
            schemaVersion = 2; kind = 'native-bitmap-font-attribution-v2'; scope = 'bitmap-icons'; fixtureID = $FixtureID
            status = 'observed'; qualification = 'unqualified'; attributionV1 = $legacy.report
            coverage = [pscustomobject]@{
                bitmapDrawGlyphRuns = 'observed'; faceFileStreams = 'observed'; sceneReferences = 'observed'
                atlasGlyphs = 'not-instrumented'; textLayouts = 'not-instrumented'; visiblePixels = 'not-observed'; loadedBytesDigest = 'not-observed'
            }
            faces = @([pscustomobject]@{
                id = 'draw-face-1'; metadata = $legacy.report.faces[0].metadata
                evidence = [pscustomobject]@{
                    faceType = 1; axes = @(); axesStatus = 'observed'; hasVariations = $false; filesStatus = 'observed'
                    files = @([pscustomobject]@{
                        index = 0; reference = [pscustomobject]@{ status = 'observed'; scope = 'system-fonts'; basename = 'segmdl2.ttf' }
                        status = 'observed'; operation = 'complete'; codeDomain = 'none'; streamLength = 4096
                        requestedBytes = 4096; readBytes = 4096; sha256 = ('d' * 64)
                        observationKind = 'face-file-stream-at-observation'; loadedBytesDigest = 'not-observed'
                    })
                }
            })
            glyphRuns = @([pscustomobject]@{
                id = 'glyph-run-1'; faceID = 'draw-face-1'; glyphCount = 3; glyphIndices = @(0, 17, 65535)
                drawResult = 0; drawStatus = 'succeeded'; count = 2
            })
            observations = @(foreach ($outcome in @('draw-produced', 'bitmap-accepted', 'scene-referenced')) {
                [pscustomobject]@{
                    role = $role; purpose = 'display-bitmap'; backend = 'direct-write'; outcome = $outcome; status = 'observed'
                    runIDs = @('glyph-run-1'); runCounts = @(2); count = 1
                }
            })
            limits = [pscustomobject]@{
                maxFaces = 64; maxReceipts = 256; maxObservations = 256; maxGlyphsPerRun = 128; maxRunsPerRaster = 16
                maxRuns = 256; maxGlyphs = 4096; maxFilesPerFace = 8; maxAxesPerFace = 32
                maxStreamBytesPerFile = 16777216; maxStreamBytesSession = 67108864; streamFragmentBytes = 65536
                copiedRuns = 2; copiedGlyphs = 6; requestedStreamBytes = 4096; readStreamBytes = 4096; dropped = 0
            }
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

function New-BitmapCollectionFixtureV2 {
    param([string[]]$EntryIds = @('symbol-palette'))
    $fixture = New-BitmapCollectionFixture $EntryIds
    $fixture.invocation | Add-Member NoteProperty nativeSchemaVersion 2
    foreach ($id in $EntryIds) {
        Write-BitmapFixtureJson (New-BitmapNativeFixtureV2 $fixture.invocation.invocationID $id) (Join-Path $fixture.invocation.nativeDirectory "$id.native-font-attribution.json")
    }
    $fixture
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

$baseV2Json = New-BitmapNativeFixtureV2 $token | ConvertTo-Json -Depth 24 -Compress
$nativeV2 = ConvertTo-GalleryBitmapNativeReportV2 $baseV2Json $token 'symbol-palette'
Assert-Bitmap ($nativeV2.schemaVersion -eq 2 -and $nativeV2.report.glyphRuns[0].glyphIndices[0] -eq 0 -and $nativeV2.report.glyphRuns[0].glyphIndices[2] -eq 65535) 'V2 copies the full UInt16 domain including notdef without changing within-run order'
Assert-Bitmap ($nativeV2.report.observations[0].runCounts[0] -eq 2 -and $nativeV2.report.glyphRuns[0].count -eq 2) 'V2 distinguishes repeated identical callbacks within a raster attempt'
Assert-Bitmap (($nativeV2.report.attributionV1 | ConvertTo-Json -Depth 24 -Compress) -ceq ($native.report | ConvertTo-Json -Depth 24 -Compress)) 'V2 nests the unchanged validated V1 report without granting V1 glyph fields'
Assert-Bitmap ($nativeV2.report.faces[0].evidence.axes.Count -eq 0 -and $nativeV2.report.faces[0].evidence.hasVariations -eq $false) 'observed static empty axes and HasVariations are separate observations'
Assert-Bitmap ($nativeV2.report.coverage.loadedBytesDigest -ceq 'not-observed' -and $nativeV2.report.faces[0].evidence.files[0].loadedBytesDigest -ceq 'not-observed') 'a V2 stream hash is never a digest of original rasterization bytes'
Assert-BitmapRejects { ConvertTo-GalleryBitmapNativeReport $baseV2Json $token 'symbol-palette' } 'the V1 reader rejects V2 rather than detecting or downgrading it'
Assert-BitmapRejects { ConvertTo-GalleryBitmapNativeReportV2 $baseJson $token 'symbol-palette' } 'the explicit V2 reader rejects a V1 sidecar'

$v2Mutations = @(
    { param($x) $x.schemaVersion = 1 },
    { param($x) $x.schemaVersion = '2' },
    { param($x) $x.schemaVersion = $true },
    { param($x) $x.report.schemaVersion = 1 },
    { param($x) $x.report.kind = 'native-bitmap-font-attribution' },
    { param($x) $x.report.attributionV1.schemaVersion = 2 },
    { param($x) $x.report.attributionV1 | Add-Member NoteProperty glyphRuns @() },
    { param($x) $x.report.attributionV1.observations[0] | Add-Member NoteProperty glyphIndices @(1) },
    { param($x) $x.invocationID = ('f' * 32) },
    { param($x) $x.fixtureID = 'stepper' },
    { param($x) $x.report.fixtureID = 'stepper' },
    { param($x) $x.pngFileName = '../PRIVATE_PATH_CANARY.png' },
    { param($x) $x.runtime.os = 'C:\PRIVATE_PATH_CANARY\Windows' },
    { param($x) $x.runtime.architecture = 'x86' },
    { param($x) $x.report.qualification = 'qualified' },
    { param($x) $x.report.coverage.visiblePixels = 'observed' },
    { param($x) $x.report.coverage.loadedBytesDigest = 'observed' },
    { param($x) $x.report.coverage.atlasGlyphs = 'observed' },
    { param($x) $x.report.coverage.textLayouts = 'observed' },
    { param($x) $x.report.coverage.faceFileStreams = 'partial' },
    { param($x) $x.report.faces = $null },
    { param($x) $x.report.faces = $x.report.faces[0] },
    { param($x) $x.report.faces[0].id = 'draw-face-0' },
    { param($x) $x.report.faces[0].id = 'draw-face-65' },
    { param($x) $x.report.faces += $x.report.faces[0] },
    { param($x) $extraFace = (New-BitmapNativeFixtureV2 $token).report.faces[0]; $extraFace.id = 'draw-face-2'; $x.report.faces += $extraFace; $x.report.limits.requestedStreamBytes = 8192; $x.report.limits.readStreamBytes = 8192 },
    { param($x) $x.report.faces[0].metadata | Add-Member NoteProperty referenceKey 'PRIVATE_TEXT_CANARY' },
    { param($x) $x.report.faces[0].evidence.faceType = 4294967296 },
    { param($x) $x.report.faces[0].evidence.axes = $null },
    { param($x) $x.report.faces[0].evidence.axesStatus = 'not-implemented' },
    { param($x) $x.report.faces[0].evidence.hasVariations = 0 },
    { param($x) $x.report.faces[0].evidence.axes = @([pscustomobject]@{ tag = 0; value = 1 }) },
    { param($x) $x.report.faces[0].evidence.axes = @([pscustomobject]@{ tag = 1952999287; value = '400' }) },
    { param($x) $x.report.faces[0].evidence.axes = @([pscustomobject]@{ tag = 1952999287; value = 3.5e38 }) },
    { param($x) $x.report.faces[0].evidence.axes = @([pscustomobject]@{ tag = 1952999287; value = 400 }, [pscustomobject]@{ tag = 1952999287; value = 500 }) },
    { param($x) $x.report.faces[0].evidence.files = @() },
    { param($x) $x.report.faces[0].evidence.files[0].index = 8 },
    { param($x) $x.report.faces[0].evidence.files += $x.report.faces[0].evidence.files[0] },
    { param($x) $x.report.faces[0].evidence.files[0].reference.basename = '../PRIVATE_PATH_CANARY.ttf' },
    { param($x) $x.report.faces[0].evidence.files[0].reference.scope = 'custom-fonts' },
    { param($x) $x.report.faces[0].evidence.files[0].reference.status = 'not-approved' },
    { param($x) $x.report.faces[0].evidence.files[0].status = 'partial' },
    { param($x) $x.report.faces[0].evidence.files[0].operation = 'read-private-path' },
    { param($x) $x.report.faces[0].evidence.files[0].operation = 'query-local-loader' },
    { param($x) $x.report.faces[0].evidence.files[0].codeDomain = 'hresult' },
    { param($x) $x.report.faces[0].evidence.files[0] | Add-Member NoteProperty code 0 },
    { param($x) $x.report.faces[0].evidence.files[0].streamLength = 0 },
    { param($x) $x.report.faces[0].evidence.files[0].streamLength = '4096' },
    { param($x) $x.report.faces[0].evidence.files[0].streamLength = 4096.5 },
    { param($x) $x.report.faces[0].evidence.files[0].streamLength = 16777217 },
    { param($x) $x.report.faces[0].evidence.files[0].requestedBytes = 4095 },
    { param($x) $x.report.faces[0].evidence.files[0].readBytes = 4095 },
    { param($x) $x.report.faces[0].evidence.files[0].readBytes = 4097 },
    { param($x) $x.report.faces[0].evidence.files[0].sha256 = ('D' * 64) },
    { param($x) $x.report.faces[0].evidence.files[0].sha256 = $null },
    { param($x) $x.report.faces[0].evidence.files[0].observationKind = 'actual-loaded-font-bytes' },
    { param($x) $x.report.faces[0].evidence.files[0].loadedBytesDigest = ('d' * 64) },
    { param($x) $x.report.faces[0].evidence.files[0] | Add-Member NoteProperty bytes @(1, 2) },
    { param($x) $x.report.glyphRuns = $null },
    { param($x) $x.report.glyphRuns[0].id = 'glyph-run-0' },
    { param($x) $x.report.glyphRuns[0].id = 'glyph-run-257' },
    { param($x) $x.report.glyphRuns += $x.report.glyphRuns[0] },
    { param($x) $x.report.glyphRuns[0].faceID = 'draw-face-2' },
    { param($x) $x.report.glyphRuns[0].faceID = 'DRAW-FACE-1' },
    { param($x) $x.report.glyphRuns[0].faceID = 'draw-Face-1' },
    { param($x) $x.report.glyphRuns[0].glyphCount = 2 },
    { param($x) $x.report.glyphRuns[0].glyphCount = 129 },
    { param($x) $x.report.glyphRuns[0].glyphIndices = $null },
    { param($x) $x.report.glyphRuns[0].glyphIndices[0] = -1 },
    { param($x) $x.report.glyphRuns[0].glyphIndices[0] = 65536 },
    { param($x) $x.report.glyphRuns[0].glyphIndices[0] = 1.5 },
    { param($x) $x.report.glyphRuns[0].drawResult = -1 },
    { param($x) $x.report.glyphRuns[0].drawResult = 2147483648 },
    { param($x) $x.report.glyphRuns[0].drawStatus = 'failed' },
    { param($x) $x.report.glyphRuns[0].count = 0 },
    { param($x) $x.report.glyphRuns[0].count = 257 },
    { param($x) $x.report.glyphRuns[0] | Add-Member NoteProperty text 'PRIVATE_TEXT_CANARY' },
    { param($x) $x.report.observations[0].role = 'secure-field' },
    { param($x) $x.report.observations[0].purpose = 'candidate-probe' },
    { param($x) $x.report.observations[0].outcome = 'probe-cache-hit' },
    { param($x) $x.report.observations[0].backend = 'gdi' },
    { param($x) $x.report.observations[0].status = 'not-observed' },
    { param($x) $x.report.observations[0].runIDs = @('glyph-run-2') },
    { param($x) $x.report.observations[0].runIDs = @('GLYPH-RUN-1') },
    { param($x) $x.report.observations[0].runIDs = @('glyph-Run-1') },
    { param($x) $x.report.observations[0].runIDs = @('glyph-run-1', 'glyph-run-1'); $x.report.observations[0].runCounts = @(1, 1) },
    { param($x) $x.report.observations[0].runCounts = @() },
    { param($x) $x.report.observations[0].runCounts = @(0) },
    { param($x) $x.report.observations[0].runCounts = @(3) },
    { param($x) $x.report.observations[0].runCounts = @(17) },
    { param($x) $x.report.observations[0].runCounts = @('2') },
    { param($x) $x.report.observations[0].count = 0 },
    { param($x) $x.report.observations[0].count = 2 },
    { param($x) $x.report.observations[0].count = 2147483647 },
    { param($x) $x.report.observations[0].runCounts = @(1); $x.status = 'partial'; $x.report.status = 'partial'; $x.report.coverage.bitmapDrawGlyphRuns = 'partial'; $x.report.observations = @($x.report.observations[0]) },
    { param($x) $x.status = 'partial'; $x.report.status = 'partial'; $x.report.coverage.bitmapDrawGlyphRuns = 'partial'; $x.report.observations[0].status = 'partial' },
    { param($x) $x.status = 'partial'; $x.report.status = 'partial'; $x.report.coverage.bitmapDrawGlyphRuns = 'partial'; $x.report.observations[1].status = 'partial' },
    { param($x) $x.report.observations[1].runCounts = @(1) },
    { param($x) $x.report.observations[2].role = 'star' },
    { param($x) $x.report.observations = @($x.report.observations[1], $x.report.observations[2]) },
    { param($x) $x.report.observations = @($x.report.observations[0], $x.report.observations[2]) },
    { param($x) $x.report.observations[0].outcome = 'draw-unavailable' },
    { param($x) $x.report.observations[1].outcome = 'bitmap-cache-hit-unobserved' },
    { param($x) $x.report.observations[1].outcome = 'vector-selected' },
    { param($x) $x.report.observations[1].outcome = 'testing-override' },
    { param($x) $x.report.observations[2].outcome = 'scene-association-unobserved' },
    { param($x) $x.report.observations += $x.report.observations[0] },
    { param($x) $x.report.observations[0] | Add-Member NoteProperty cacheKey 'PRIVATE_TEXT_CANARY' },
    { param($x) $x.report.limits.maxRuns = 257 },
    { param($x) $x.report.limits.maxStreamBytesSession = 67108865 },
    { param($x) $x.report.limits.copiedRuns = 1 },
    { param($x) $x.report.limits.copiedGlyphs = 5 },
    { param($x) $x.report.limits.copiedRuns = 3 },
    { param($x) $x.report.limits.copiedGlyphs = 4097 },
    { param($x) $x.report.limits.requestedStreamBytes = 4095 },
    { param($x) $x.report.limits.readStreamBytes = 4097 },
    { param($x) $x.report.limits.readStreamBytes = 4095 },
    { param($x) $x.report.limits.dropped = 1 },
    { param($x) $x | Add-Member NoteProperty eventOrder @(1) }
)
foreach ($mutate in $v2Mutations) {
    $value = ConvertFrom-Json $baseV2Json
    & $mutate $value
    $badJson = $value | ConvertTo-Json -Depth 24 -Compress
    Assert-BitmapRejects { ConvertTo-GalleryBitmapNativeReportV2 $badJson $token 'symbol-palette' } 'V2 malformed fields, privacy expansion, or fabricated receipt ownership fail closed'
}
foreach ($badJson in @(
    $baseV2Json.Replace('"schemaVersion":2', '"schemaVersion":2,"SchemaVersion":2'),
    $baseV2Json.Replace('"glyphCount":3', '"glyphCount":3,"\u0067lyphCount":3'),
    $baseV2Json.Replace('"glyphCount":3', '"glyphCount":03'),
    $baseV2Json.Replace('"glyphCount":3', '"glyphCount":+3'),
    $baseV2Json.Replace('"glyphCount":3', '/* comment */ "glyphCount":3'),
    $baseV2Json.Replace('Segoe MDL2 Assets', '\ud800'),
    ($baseV2Json + '{}'),
    (('[' * 25) + '0' + (']' * 25))
)) { Assert-BitmapRejects { ConvertTo-GalleryBitmapNativeReportV2 $badJson $token 'symbol-palette' } 'V2 retains lexical JSON, key collision, depth, and Unicode boundaries' }
Set-StrictMode -Version Latest
try {
    $strictV2 = ConvertTo-GalleryBitmapNativeReportV2 $baseV2Json $token 'symbol-palette'
    Assert-Bitmap ($null -eq $strictV2.report.faces[0].evidence.files[0].code) 'omitted Swift V2 optionals work under caller StrictMode'
} finally { Set-StrictMode -Off }

foreach ($mode in @('unsupported-axes', 'partial-axes', 'stream-hash-failed', 'remote-rejected', 'zero-stream', 'oversized-stream', 'uint64-stream')) {
    $value = ConvertFrom-Json $baseV2Json
    $value.status = 'partial'; $value.report.status = 'partial'
    $evidence = $value.report.faces[0].evidence; $file = $evidence.files[0]
    if ($mode -cin @('unsupported-axes', 'partial-axes')) {
        $evidence.axes = $null; $evidence.axesStatus = if ($mode -ceq 'unsupported-axes') { 'not-implemented' } else { 'failed' }
        if ($mode -ceq 'unsupported-axes') { $evidence.PSObject.Properties.Remove('hasVariations') }
    } else {
        $value.report.coverage.faceFileStreams = 'partial'; $evidence.filesStatus = 'partial'; $file.PSObject.Properties.Remove('sha256')
        switch ($mode) {
            'stream-hash-failed' { $file.status = 'failed'; $file.operation = 'hash-stream-fragment'; $file.codeDomain = 'ntstatus'; $file | Add-Member NoteProperty code (-1073741823) }
            'remote-rejected' {
                $file.status = 'nonlocal-or-custom'; $file.operation = 'query-local-loader'; $file.codeDomain = 'hresult'; $file | Add-Member NoteProperty code (-2147467262)
                $file.reference = [pscustomobject]@{ status = 'nonlocal-or-custom' }; $file.PSObject.Properties.Remove('streamLength')
            }
            'zero-stream' { $file.status = 'invalid-value'; $file.operation = 'get-stream-size'; $file.streamLength = 0 }
            'oversized-stream' { $file.status = 'limit-exceeded'; $file.operation = 'check-byte-budget'; $file.streamLength = 16777217 }
            'uint64-stream' { $file.status = 'limit-exceeded'; $file.operation = 'check-byte-budget'; $file.streamLength = [uint64]::MaxValue }
        }
        if ($mode -cne 'stream-hash-failed') {
            $file.requestedBytes = 0; $file.readBytes = 0; $value.report.limits.requestedStreamBytes = 0; $value.report.limits.readStreamBytes = 0
        }
    }
    $parsed = ConvertTo-GalleryBitmapNativeReportV2 ($value | ConvertTo-Json -Depth 24 -Compress) $token 'symbol-palette'
    Assert-Bitmap ($parsed.status -ceq 'partial') "legitimate V2 unknown or bounded rejection remains partial ($mode)"
    if ($mode -ceq 'uint64-stream') { Assert-Bitmap ($parsed.report.faces[0].evidence.files[0].streamLength -eq [uint64]::MaxValue) 'oversized UInt64 stream length remains exact without a floating-point round trip' }
    if ($mode -ceq 'stream-hash-failed') { Assert-Bitmap ($parsed.report.faces[0].evidence.files[0].readBytes -eq 4096 -and $null -eq $parsed.report.faces[0].evidence.files[0].sha256) 'hash failure preserves returned-byte accounting without publishing a partial digest' }
    if ($mode -ceq 'uint64-stream') {
        $exactSizeJson = $value | ConvertTo-Json -Depth 24 -Compress
        foreach ($invalidSize in @('18446744073709551616', '18446744073709551615.0', '18446744073709551615e0', '4096.0')) {
            $invalidSizeJson = $exactSizeJson.Replace('18446744073709551615', $invalidSize)
            Assert-BitmapRejects { ConvertTo-GalleryBitmapNativeReportV2 $invalidSizeJson $token 'symbol-palette' } 'overflow and fractional/exponent stream lengths cannot round into UInt64 observations'
        }
    }
}
foreach ($mode in @('failed-draw', 'empty-run', 'unknown-cache', 'gdi', 'vector', 'testing-override')) {
    $value = ConvertFrom-Json $baseV2Json
    $value.status = 'partial'; $value.report.status = 'partial'; $value.report.coverage.bitmapDrawGlyphRuns = 'partial'; $value.report.coverage.sceneReferences = 'partial'
    $value.report.observations = @($value.report.observations[0]); $observation = $value.report.observations[0]
    $observation.status = 'partial'; $observation.outcome = 'draw-unavailable'
    if ($mode -ceq 'failed-draw') { $value.report.glyphRuns[0].drawResult = -2147467259; $value.report.glyphRuns[0].drawStatus = 'failed' }
    elseif ($mode -ceq 'empty-run') { $value.report.glyphRuns[0].glyphCount = 0; $value.report.glyphRuns[0].glyphIndices = @(); $value.report.limits.copiedGlyphs = 0 }
    else {
        $value.report.glyphRuns = @(); $value.report.limits.copiedRuns = 0; $value.report.limits.copiedGlyphs = 0
        $observation.runIDs = @(); $observation.runCounts = @(); $observation.status = 'not-observed'
        switch ($mode) {
            'unknown-cache' { $observation.backend = 'unknown'; $observation.outcome = 'bitmap-cache-hit-unobserved' }
            'gdi' { $observation.backend = 'gdi'; $observation.outcome = 'bitmap-accepted' }
            'vector' { $observation.backend = 'vector'; $observation.outcome = 'vector-selected' }
            'testing-override' { $observation.backend = 'testing-override'; $observation.outcome = 'testing-override' }
        }
    }
    $parsed = ConvertTo-GalleryBitmapNativeReportV2 ($value | ConvertTo-Json -Depth 24 -Compress) $token 'symbol-palette'
    Assert-Bitmap ($parsed.status -ceq 'partial' -and $parsed.report.observations[0].status -cne 'observed') "V2 failure and unobserved routes retain no fabricated success ($mode)"
}

$value = ConvertFrom-Json $baseV2Json
$value.report.observations[1].outcome = 'bitmap-cache-hit-known'; $value.report.observations[1].count = 1000; $value.report.observations[2].count = 1000
$parsed = ConvertTo-GalleryBitmapNativeReportV2 ($value | ConvertTo-Json -Depth 24 -Compress) $token 'symbol-palette'
Assert-Bitmap ($parsed.report.limits.copiedRuns -eq 2 -and $parsed.report.observations[1].count -eq 1000) 'known cache and scene reuse do not multiply the count of actually copied callbacks'
$value.report.observations[1].role = 'star'; $value.report.observations[2].role = 'star'
Assert-Bitmap ((ConvertTo-GalleryBitmapNativeReportV2 ($value | ConvertTo-Json -Depth 24 -Compress) $token 'symbol-palette').report.observations[2].role -ceq 'star') 'known same-session content may be accepted for another allowed role with the identical complete run bag'

$value = ConvertFrom-Json $baseV2Json
$value.status = 'partial'; $value.report.status = 'partial'; $value.report.coverage.bitmapDrawGlyphRuns = 'partial'
foreach ($observation in $value.report.observations) { $observation.status = 'partial' }
Assert-Bitmap ((ConvertTo-GalleryBitmapNativeReportV2 ($value | ConvertTo-Json -Depth 24 -Compress) $token 'symbol-palette').report.observations[2].status -ceq 'partial') 'incomplete capture status propagates through the complete accepted and scene association chain'
$value = ConvertFrom-Json $baseV2Json
$value.status = 'partial'; $value.report.status = 'partial'; $value.report.coverage.bitmapDrawGlyphRuns = 'partial'; $value.report.coverage.sceneReferences = 'partial'
$value.report.observations[2].outcome = 'scene-association-unobserved'; $value.report.observations[2].status = 'not-observed'
$value.report.observations[2].runIDs = @(); $value.report.observations[2].runCounts = @()
$parsed = ConvertTo-GalleryBitmapNativeReportV2 ($value | ConvertTo-Json -Depth 24 -Compress) $token 'symbol-palette'
Assert-Bitmap ($parsed.report.observations[1].runIDs.Count -eq 1 -and $parsed.report.observations[2].runIDs.Count -eq 0) 'partial scene association retains the separate accepted receipt without assigning its runs to an unknown scene reference'
$value = ConvertFrom-Json $baseV2Json
$value.status = 'partial'; $value.report.status = 'partial'; $value.report.coverage.bitmapDrawGlyphRuns = 'partial'; $value.report.limits.dropped = 1
$value.report.observations = @($value.report.observations[0]); $value.report.observations[0].runCounts = @(1); $value.report.observations[0].status = 'partial'
Assert-Bitmap ((ConvertTo-GalleryBitmapNativeReportV2 ($value | ConvertTo-Json -Depth 24 -Compress) $token 'symbol-palette').report.limits.dropped -eq 1) 'explicit dropped partial evidence may omit a draw occurrence but cannot claim it was fully observed'

foreach ($count in @(16, 17)) {
    $value = ConvertFrom-Json $baseV2Json
    $value.report.glyphRuns[0].count = $count; $value.report.limits.copiedRuns = $count; $value.report.limits.copiedGlyphs = 3 * $count
    foreach ($observation in $value.report.observations) { $observation.runCounts = @($count) }
    $json = $value | ConvertTo-Json -Depth 24 -Compress
    if ($count -eq 16) { Assert-Bitmap ((ConvertTo-GalleryBitmapNativeReportV2 $json $token 'symbol-palette').report.observations[0].runCounts[0] -eq 16) '16 callbacks fit one raster attempt' }
    else { Assert-BitmapRejects { ConvertTo-GalleryBitmapNativeReportV2 $json $token 'symbol-palette' } '17 callbacks exceed the per-raster cap' }
}
foreach ($count in @(32, 33)) {
    $value = ConvertFrom-Json $baseV2Json
    $value.report.faces[0].evidence.axes = @(for ($i = 0; $i -lt $count; $i++) {
        $tag = 'a' + $i.ToString('000'); [long]$packed = 0
        for ($j = 0; $j -lt 4; $j++) { $packed += [long][char]$tag[$j] -shl (8 * $j) }
        [pscustomobject]@{ tag = $packed; value = $i }
    })
    $json = $value | ConvertTo-Json -Depth 24 -Compress
    if ($count -eq 32) { Assert-Bitmap ((ConvertTo-GalleryBitmapNativeReportV2 $json $token 'symbol-palette').report.faces[0].evidence.axes.Count -eq 32) '32 distinct valid axis tags fit the optional Face5 cap' }
    else { Assert-BitmapRejects { ConvertTo-GalleryBitmapNativeReportV2 $json $token 'symbol-palette' } '33 axes exceed the cap' }
}
foreach ($count in @(8, 9)) {
    $value = ConvertFrom-Json $baseV2Json
    $value.report.faces[0].evidence.files = @(for ($i = 0; $i -lt $count; $i++) {
        $file = (New-BitmapNativeFixtureV2 $token).report.faces[0].evidence.files[0]; $file.index = $i; $file.reference.basename = "font$i.ttf"; $file
    })
    $value.report.limits.requestedStreamBytes = 4096 * $count; $value.report.limits.readStreamBytes = 4096 * $count
    $json = $value | ConvertTo-Json -Depth 24 -Compress
    if ($count -eq 8) { Assert-Bitmap ((ConvertTo-GalleryBitmapNativeReportV2 $json $token 'symbol-palette').report.faces[0].evidence.files.Count -eq 8) 'eight actual file observations fit a face' }
    else { Assert-BitmapRejects { ConvertTo-GalleryBitmapNativeReportV2 $json $token 'symbol-palette' } 'nine file observations exceed the face cap' }
}
foreach ($count in @(64, 65)) {
    $value = ConvertFrom-Json $baseV2Json
    $value.report.faces = @(for ($i = 1; $i -le $count; $i++) { $face = (New-BitmapNativeFixtureV2 $token).report.faces[0]; $face.id = "draw-face-$i"; $face })
    $value.report.glyphRuns = @(for ($i = 1; $i -le $count; $i++) {
        [pscustomobject]@{ id = "glyph-run-$i"; faceID = "draw-face-$i"; glyphCount = 1; glyphIndices = @($i); drawResult = 0; drawStatus = 'succeeded'; count = 1 }
    })
    $value.report.observations = @(for ($i = 1; $i -le $count; $i++) {
        foreach ($outcome in @('draw-produced', 'bitmap-accepted', 'scene-referenced')) {
            [pscustomobject]@{ role = 'folder'; purpose = 'display-bitmap'; backend = 'direct-write'; outcome = $outcome; status = 'observed'; runIDs = @("glyph-run-$i"); runCounts = @(1); count = 1 }
        }
    })
    $value.report.limits.copiedRuns = $count; $value.report.limits.copiedGlyphs = $count
    $value.report.limits.requestedStreamBytes = 4096 * $count; $value.report.limits.readStreamBytes = 4096 * $count
    $json = $value | ConvertTo-Json -Depth 24 -Compress
    if ($count -eq 64) { Assert-Bitmap ((ConvertTo-GalleryBitmapNativeReportV2 $json $token 'symbol-palette').report.faces.Count -eq 64) '64 physical face observations fit the V2 cap without merging equal metadata' }
    else { Assert-BitmapRejects { ConvertTo-GalleryBitmapNativeReportV2 $json $token 'symbol-palette' } '65 physical face observations exceed the V2 cap' }
}
foreach ($count in @(256, 257)) {
    $value = ConvertFrom-Json $baseV2Json
    $value.status = 'partial'; $value.report.status = 'partial'; $value.report.coverage.bitmapDrawGlyphRuns = 'partial'; $value.report.coverage.sceneReferences = 'partial'
    $value.report.glyphRuns = @(for ($i = 1; $i -le $count; $i++) {
        [pscustomobject]@{ id = "glyph-run-$i"; faceID = 'draw-face-1'; glyphCount = 16; glyphIndices = @($i) + @(0..14); drawResult = 0; drawStatus = 'succeeded'; count = 1 }
    })
    $value.report.observations = @(for ($i = 1; $i -le $count; $i++) {
        [pscustomobject]@{ role = 'folder'; purpose = 'display-bitmap'; backend = 'direct-write'; outcome = 'draw-unavailable'; status = 'partial'; runIDs = @("glyph-run-$i"); runCounts = @(1); count = 1 }
    })
    $value.report.limits.copiedRuns = [math]::Min(256, $count); $value.report.limits.copiedGlyphs = [math]::Min(4096, $count * 16)
    $json = $value | ConvertTo-Json -Depth 24 -Compress
    if ($count -eq 256) { Assert-Bitmap ((ConvertTo-GalleryBitmapNativeReportV2 $json $token 'symbol-palette').report.glyphRuns.Count -eq 256) '256 runs, 256 observations, and 4096 copied glyphs fit the session caps' }
    else { Assert-BitmapRejects { ConvertTo-GalleryBitmapNativeReportV2 $json $token 'symbol-palette' } '257 runs or observations exceed the session caps' }
}
$value = ConvertFrom-Json $baseV2Json
$value.report.faces[0].evidence.files = @(for ($i = 0; $i -lt 4; $i++) {
    $file = (New-BitmapNativeFixtureV2 $token).report.faces[0].evidence.files[0]; $file.index = $i
    $file.streamLength = 16777216; $file.requestedBytes = 16777216; $file.readBytes = 16777216; $file
})
$value.report.limits.requestedStreamBytes = 67108864; $value.report.limits.readStreamBytes = 67108864
Assert-Bitmap ((ConvertTo-GalleryBitmapNativeReportV2 ($value | ConvertTo-Json -Depth 24 -Compress) $token 'symbol-palette').report.limits.readStreamBytes -eq 67108864) 'four 16 MiB streams fit the 64 MiB requested and returned session budget without allocating font bytes'

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

    $explicitV2 = New-GalleryBitmapFontAttributionInvocation (Join-Path $script:bitmapFixtureRoot 'explicit-v2-options') @('stepper') $token -Version 2
    Assert-Bitmap ($explicitV2.nativeSchemaVersion -eq 2) 'only an explicit version 2 invocation selects V2 collection'
    $defaultV1 = New-GalleryBitmapFontAttributionInvocation (Join-Path $script:bitmapFixtureRoot 'default-v1-options') @('stepper') $token
    Assert-Bitmap ($null -eq $defaultV1.PSObject.Properties['nativeSchemaVersion']) 'the default invocation retains the original V1 property set'
    $explicitV1 = New-GalleryBitmapFontAttributionInvocation (Join-Path $script:bitmapFixtureRoot 'explicit-v1-options') @('stepper') $token -Version 1
    Assert-Bitmap ($null -eq $explicitV1.PSObject.Properties['nativeSchemaVersion']) 'explicit version 1 remains identical to the default V1 mode'
    $invalidVersionPath = Join-Path $script:bitmapFixtureRoot 'invalid-version-options'
    Assert-BitmapRejects { New-GalleryBitmapFontAttributionInvocation $invalidVersionPath @('stepper') $token -Version 3 } 'unknown versions fail before invocation directory creation'
    Assert-Bitmap (-not (Test-Path -LiteralPath $invalidVersionPath)) 'invalid version options leave no output directory'

    $fixture = New-BitmapCollectionFixtureV2 @('symbol-palette', 'stepper')
    $script:bitmapFakeCalls.Clear()
    $result = Invoke-BitmapCollectionFixture $fixture
    Assert-Bitmap ($result.schemaVersion -eq 2 -and $result.kind -ceq 'gallery-bitmap-font-attribution' -and $result.status -ceq 'observed') 'explicit V2 uses the separate aggregate version without changing its qualification kind'
    Assert-Bitmap ($result.entries.Count -eq 2 -and $script:bitmapFakeCalls.Count -eq 1 -and $result.files.Count -eq 1) 'V2 retains the original bounded disk adapter and duplicate reference accounting'
    Assert-Bitmap ($result.entries[0].native.report.faces[0].evidence.files[0].sha256 -ceq ('d' * 64) -and $result.files[0].observation.file.sha256 -ceq ('e' * 64)) 'face-file stream hashes and later disk hashes remain separate observations even when they differ'
    Assert-Bitmap ($result.qualification.status -ceq 'unqualified' -and $null -eq $result.qualification.acceptedBaselineProfile -and $result.qualification.pixelGate -ceq 'unchanged' -and $result.qualification.performanceQualification -ceq 'excluded') 'V2 does not promote a font profile, pixel baseline, or performance claim'
    $serializedV2 = [IO.File]::ReadAllText($fixture.invocation.reportPath)
    Assert-Bitmap ($serializedV2 -notmatch 'PRIVATE_PATH_CANARY|PRIVATE_TEXT_CANARY|[A-Za-z]:\\|"(?:cacheKey|referenceKey|text|textHash|timestamp|eventOrder|rawPointer|bytes)"') 'V2 exports only approved face metadata, copied fixed-fixture glyph indices, and digests'
    Assert-Bitmap ($result.files[0].observation.loadedBytesDigest -ceq 'not-observed' -and $result.entries[0].native.report.coverage.loadedBytesDigest -ceq 'not-observed') 'V2 aggregation cannot relabel stream or disk observations as original loaded font bytes'

    foreach ($mode in @('v1-read-v2', 'v2-read-v1', 'missing-sidecar', 'wrong-token', 'private-field', 'oversize-sidecar', 'profile-mismatch', 'exe-bytes-mismatch')) {
        $fixture = if ($mode -ceq 'v1-read-v2') { New-BitmapCollectionFixture } else { New-BitmapCollectionFixtureV2 }
        $nativePath = Join-Path $fixture.invocation.nativeDirectory 'symbol-palette.native-font-attribution.json'
        $value = New-BitmapNativeFixtureV2 $fixture.invocation.invocationID
        switch ($mode) {
            'v1-read-v2' { Write-BitmapFixtureJson $value $nativePath }
            'v2-read-v1' { Write-BitmapFixtureJson (New-BitmapNativeFixture $fixture.invocation.invocationID) $nativePath }
            'missing-sidecar' { Remove-Item -LiteralPath $nativePath }
            'wrong-token' { $value.invocationID = ('0' * 32); Write-BitmapFixtureJson $value $nativePath }
            'private-field' { $value.report.glyphRuns[0] | Add-Member NoteProperty referenceKey 'PRIVATE_TEXT_CANARY'; Write-BitmapFixtureJson $value $nativePath }
            'oversize-sidecar' { [IO.File]::WriteAllBytes($nativePath, (New-Object byte[] 524289)) }
            'profile-mismatch' { [IO.File]::AppendAllText($fixture.profilePath, ' ') }
            'exe-bytes-mismatch' { [IO.File]::WriteAllText($fixture.executablePath, 'Changed synthetic executable bytes.') }
        }
        $script:bitmapFakeCalls.Clear()
        $result = Invoke-BitmapCollectionFixture $fixture
        Assert-Bitmap ($result.status -ceq 'partial' -and $null -eq $result.entries[0].native -and $result.files.Count -eq 0 -and $script:bitmapFakeCalls.Count -eq 0) "invalid or cross-version evidence never acquires V2 attribution ($mode)"
        Assert-Bitmap ($result.entries[0].png.status -ceq 'observed' -and (Test-Path -LiteralPath (Join-Path $fixture.invocation.currentDirectory 'symbol-palette.png'))) "V2 diagnostic rejection preserves the retained fixture PNG ($mode)"
        Assert-Bitmap ([IO.File]::ReadAllText($fixture.invocation.reportPath) -notmatch 'PRIVATE_') "V2 rejected fields cannot leak into the aggregate ($mode)"
        if ($mode -ceq 'v1-read-v2') { Assert-Bitmap ($result.schemaVersion -eq 1 -and [IO.File]::ReadAllText($fixture.invocation.reportPath) -notmatch 'glyphIndices|glyphRuns') 'a V2 sidecar cannot upgrade a V1 invocation or broaden its aggregate privacy schema' }
    }
    foreach ($version in @($null, 1, 3, '2', $true)) {
        $fixture = New-BitmapCollectionFixtureV2
        $fixture.invocation.nativeSchemaVersion = $version
        Assert-BitmapRejects { Invoke-BitmapCollectionFixture $fixture } 'invalid explicit invocation schema versions reject before path or output work'
        Assert-Bitmap (-not (Test-Path -LiteralPath $fixture.invocation.reportPath)) 'invalid explicit versions do not create an aggregate'
    }
    foreach ($mode in @('png', 'same-length-png', 'sidecar', 'profile', 'executable')) {
        $fixture = New-BitmapCollectionFixtureV2
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
            } else { [IO.File]::AppendAllText($script:bitmapMutatePath, ' changed during V2 collection') }
            New-BitmapFakeFingerprint
        }
        Assert-Bitmap ($result.status -ceq 'partial' -and $null -eq $result.entries[0].native -and $result.files.Count -eq 0) "V2 retains all late artifact mutation invalidation checks ($mode)"
    }
    $fixture = New-BitmapCollectionFixtureV2
    $result = Invoke-BitmapCollectionFixture $fixture
    $result.entries[0].native = [pscustomobject]@{ synthetic = ('x' * 524288) }
    Write-GalleryBitmapFontAttributionReport $result $fixture.invocation.reportPath
    Assert-Bitmap ($result.schemaVersion -eq 2 -and $result.limits.aggregateDropped -and $null -eq $result.entries[0].native -and $result.status -ceq 'partial' -and (Get-Item -LiteralPath $fixture.invocation.reportPath).Length -le 524288) 'oversized V2 aggregate retains the bounded partial seal instead of truncating JSON'

    # Source-level integration checks intentionally do not execute the wrapper,
    # whose ordinary path loads System.Drawing and the DirectWrite family probe.
    $gallerySource = [IO.File]::ReadAllText((Join-Path $repoRoot 'scripts/gallery-compare.ps1'))
    Assert-Bitmap ($gallerySource.IndexOf('Assert-GalleryBitmapFontAttributionOptions') -lt $gallerySource.IndexOf('New-GalleryFontProvenance -Executable')) 'unsupported diagnostic options reject before existing native probes'
    Assert-Bitmap ($gallerySource.Contains("'--bitmap-font-attribution-dir'") -and $gallerySource.Contains("'--bitmap-font-attribution-invocation'")) 'the fresh native directory and token are passed together'
    Assert-Bitmap ($gallerySource.Contains('[double] $MaxChangedPercent = 0.5') -and $gallerySource.Contains('[int] $ChannelTolerance = 8') -and $gallerySource.Contains('[int] $MaxChannelDelta = 64')) 'existing pixel thresholds remain unchanged'
    Assert-Bitmap ($gallerySource.Contains('status        = if ($failCount -eq 0) { "pass" } else { "fail" }')) 'pixel comparison status remains independent of diagnostics'
    $parseTokens = $null; $parseErrors = $null
    $galleryAst = [Management.Automation.Language.Parser]::ParseInput($gallerySource, [ref]$parseTokens, [ref]$parseErrors)
    Assert-Bitmap ($parseErrors.Count -eq 0) 'gallery wrapper remains valid PowerShell source'
    $versionParameter = @($galleryAst.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -ceq 'BitmapFontAttributionVersion' })
    Assert-Bitmap ($versionParameter.Count -eq 1 -and $versionParameter[0].DefaultValue.SafeGetValue() -eq 1) 'V1 remains the actual CLI parameter default'
    $versionGuard = @($galleryAst.EndBlock.Statements | Where-Object {
        $_ -is [Management.Automation.Language.IfStatementAst] -and $_.Extent.Text.Contains("ContainsKey('BitmapFontAttributionVersion')")
    })
    Assert-Bitmap ($versionGuard.Count -eq 1 -and $versionGuard[0].Extent.StartOffset -lt $gallerySource.IndexOf('New-GalleryFontProvenance -Executable')) 'explicit version without diagnostic mode is rejected before native probes and output'
    # Execute only the parsed parameter/guard expression, not the wrapper,
    # collector, native probe, renderer, or any build command.
    $optionHarness = [scriptblock]::Create($galleryAst.ParamBlock.Extent.Text + "`n" + $versionGuard[0].Extent.Text + "`n" + '$PSBoundParameters')
    $defaultOptions = & $optionHarness
    Assert-Bitmap (-not $defaultOptions.ContainsKey('BitmapFontAttributionVersion')) 'omitted version leaves ordinary wrapper options untouched'
    foreach ($version in @(1, 2, 3)) {
        Assert-BitmapRejects { & $optionHarness -BitmapFontAttributionVersion $version } 'explicit version alone cannot enable collection'
    }
    Assert-Bitmap ((& $optionHarness -BitmapFontAttribution -BitmapFontAttributionVersion 2).BitmapFontAttributionVersion -eq 2) 'version 2 is accepted only alongside the existing opt-in'
    Assert-BitmapRejects { & $optionHarness -BitmapFontAttribution -BitmapFontAttributionVersion 3 } 'the wrapper rejects unknown versions before any script body work'
    $argumentGuard = @($galleryAst.FindAll({ param($node)
        $node -is [Management.Automation.Language.IfStatementAst] -and $node.Extent.Text.StartsWith('if ($null -ne $bitmapAttributionInvocation)') -and
            $node.Extent.Text.Contains("'--bitmap-font-attribution-dir'")
    }, $true))
    Assert-Bitmap ($argumentGuard.Count -eq 1) 'the paired diagnostic CLI arguments have one explicit construction site'
    $argumentHarness = [scriptblock]::Create('param($bitmapAttributionInvocation, $BitmapFontAttributionVersion)' + "`n" +
        '$galleryRenderArguments = @()' + "`n" + $argumentGuard[0].Extent.Text + "`n" + ', $galleryRenderArguments')
    $argumentFixture = [pscustomobject]@{ nativeDirectory = 'synthetic-native-directory'; invocationID = $token }
    $offArguments = & $argumentHarness $null 1
    $v1Arguments = & $argumentHarness $argumentFixture 1
    $v2Arguments = & $argumentHarness $argumentFixture 2
    Assert-Bitmap ($offArguments.Count -eq 0 -and $v1Arguments.Count -eq 4 -and $v1Arguments -cnotcontains '--bitmap-font-attribution-version') 'ordinary and V1 argument arrays remain unchanged'
    Assert-Bitmap ($v2Arguments.Count -eq 6 -and $v2Arguments[4] -ceq '--bitmap-font-attribution-version' -and $v2Arguments[5] -ceq '2') 'only explicit V2 forwards the native version flag'

    $librarySource = [IO.File]::ReadAllText((Join-Path $repoRoot 'scripts/gallery-bitmap-font-attribution.ps1'))
    $libraryAst = [Management.Automation.Language.Parser]::ParseInput($librarySource, [ref]$parseTokens, [ref]$parseErrors)
    Assert-Bitmap ($parseErrors.Count -eq 0) 'the attribution library remains valid PowerShell source'
    $legacyReader = $libraryAst.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'ConvertTo-GalleryBitmapNativeReport' }, $false)
    $legacyReaderBytes = (New-Object Text.UTF8Encoding($false)).GetBytes($legacyReader.Extent.Text.Replace([string][char]13, ''))
    $legacyHasher = [Security.Cryptography.SHA256]::Create()
    try { $legacyReaderDigest = [BitConverter]::ToString($legacyHasher.ComputeHash($legacyReaderBytes)).Replace('-', '').ToLowerInvariant() }
    finally { $legacyHasher.Dispose() }
    Assert-Bitmap ($legacyReaderDigest -ceq 'e55e06efdd867b29c4e0d8b5382fd64c13f42a60aaaf5d236fa39439603df101') 'the entire V1 native reader is unchanged, including its strict field and privacy contract'
    $coordinatorSource = [IO.File]::ReadAllText((Join-Path $repoRoot 'scripts/capture-ci-bitmap-font-attribution.ps1'))
    Assert-Bitmap (-not $coordinatorSource.Contains('BitmapFontAttributionVersion') -and -not $coordinatorSource.Contains('--bitmap-font-attribution-version')) 'the CI coordinator does not opt in to V2'
    Assert-Bitmap ($script:bitmapForbiddenCalls -eq 0 -and -not ('SwiftWindowsUIBitmapFontFileAdapterV1' -as [type])) 'no Add-Type, native adapter, or SwiftPM invocation occurred'
} finally {
    $resolved = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $script:bitmapFixtureRoot).Path)
    if ([IO.Path]::GetDirectoryName($resolved) -cne $tempRoot -or [IO.Path]::GetFileName($resolved) -notmatch '^swift-windowsui-bitmap-font-test-[0-9a-f]{32}$') { throw 'Refusing cleanup outside the owned bitmap attribution fixture directory.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}

Write-Host "Bitmap font attribution synthetic tests passed ($script:bitmapAssertions assertions). No C# compilation, native calls, renderer, or SwiftPM."
exit 0
