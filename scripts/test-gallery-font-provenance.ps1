param()

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot "gallery-font-provenance.ps1")
$script:provenanceAssertions = 0

function Assert-Provenance {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "Gallery font provenance test failed: $Message" }
    $script:provenanceAssertions++
}

function Invoke-ProvenanceFixture {
    param([string[]]$Arguments)
    $ErrorActionPreference = "Continue"
    $output = @(& powershell -NoProfile -ExecutionPolicy Bypass @Arguments 2>&1)
    [pscustomobject]@{ exitCode = $LASTEXITCODE; output = ($output | ForEach-Object { $_.ToString() }) -join "`n" }
}

$noFiles = { [pscustomobject]@{ files = @(); errors = @(); resolution = "synthetic" } }
$probeCalls = New-Object 'System.Collections.Generic.List[string]'
$available = New-GalleryFontEnvironment -ClassicOverride $null -FontFiles $noFiles -ProbeFamily {
    param($family)
    $probeCalls.Add($family)
    $true
}
Assert-Provenance ($probeCalls.Count -eq 6 -and @($probeCalls | Select-Object -Unique).Count -eq 6) "only six allowlisted families are probed once each"
Assert-Provenance (($probeCalls -join '|') -ceq 'Segoe UI Variable Small|Segoe UI Variable Text|Segoe UI Variable Display|Segoe UI|Segoe Fluent Icons|Segoe MDL2 Assets') "probe order and family names are explicit"
Assert-Provenance ($available.uiPolicy.projectedChoice -eq "variable" -and $available.uiPolicy.projectedFamilies.Count -eq 3) "all three optical cuts project the variable policy"
Assert-Provenance ($null -eq $available.override.value -and -not $available.override.forcesClassic) "an absent override remains absent"
Assert-Provenance ($null -eq $available.icons.selectedFamily -and $null -eq $available.icons.actualGlyphFaces -and $null -eq $available.icons.perGlyphProbeResults) "family availability cannot fabricate glyph ownership or per-glyph probes"

$missing = New-GalleryFontEnvironment -ClassicOverride $null -FontFiles $noFiles -ProbeFamily { param($family) $family -cne "Segoe UI Variable Text" }
Assert-Provenance ($missing.uiPolicy.projectedChoice -eq "classic") "a missing optical cut projects classic"
Assert-Provenance ($missing.uiPolicy.projectedFamilies -is [array] -and $missing.uiPolicy.projectedFamilies.Count -eq 1) "a single projected family remains a JSON array"
Assert-Provenance ($missing.families[1].installed -eq $false -and $missing.families[1].status -eq "observed") "a known absent family is distinct from a failed probe"
$unknown = New-GalleryFontEnvironment -ClassicOverride $null -FontFiles $noFiles -ProbeFamily { param($family) $null }
Assert-Provenance ($unknown.uiPolicy.projectedChoice -eq "unknown" -and $unknown.uiPolicy.projectedFamilies.Count -eq 0) "unknown availability does not invent a selected family"
Assert-Provenance ($unknown.uiPolicy.projectedFamilies -is [array]) "an unknown policy has an empty family array, not a fabricated family or null list"
Assert-Provenance (@($unknown.families | Where-Object { $_.status -eq "unknown" -and $null -eq $_.installed }).Count -eq 6) "unknown probes remain null rather than absent"
$failed = New-GalleryFontEnvironment -ClassicOverride $null -FontFiles { throw "synthetic registry failure" } -ProbeFamily { param($family) throw "synthetic probe failure" }
Assert-Provenance ($failed.families[0].error -eq "synthetic probe failure" -and $failed.registeredFontFiles.errors[0] -eq "synthetic registry failure") "collection failures remain in the artifact"
$invalid = New-GalleryFontEnvironment -ClassicOverride $null -FontFiles $noFiles -ProbeFamily { param($family) "true" }
Assert-Provenance ($invalid.families[0].status -eq "unknown" -and $null -eq $invalid.families[0].installed) "a malformed probe result is not accepted as availability"
$forced = New-GalleryFontEnvironment -ClassicOverride "1" -FontFiles $noFiles -ProbeFamily { param($family) $true }
Assert-Provenance ($forced.uiPolicy.projectedChoice -eq "classic" -and $forced.families[0].installed -eq $true) "the override changes the policy projection, not measured availability"
foreach ($value in @("0", "true", " 1", "1 ")) {
    $notForced = New-GalleryFontEnvironment -ClassicOverride $value -FontFiles $noFiles -ProbeFamily { param($family) $true }
    Assert-Provenance ($notForced.uiPolicy.projectedChoice -eq "variable" -and -not $notForced.override.forcesClassic) "only the exact override value 1 is effective"
}
$unknownRoundTrip = $unknown | ConvertTo-Json -Depth 12 | ConvertFrom-Json
Assert-Provenance ($null -eq $unknownRoundTrip.families[0].installed -and $null -eq $unknownRoundTrip.icons.actualGlyphFaces) "unknown fields survive JSON round-trip"
$rejected = $false
try { Get-GalleryFontFamilyAvailability "Unrelated Personal Font" | Out-Null } catch { $rejected = $true }
Assert-Provenance $rejected "the native collector rejects families outside its allowlist before probing"

$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([char[]]@('/', '\'))
$fixtureRoot = Join-Path $tempRoot ("swift-windowsui-font-provenance-test-" + [Guid]::NewGuid().ToString("N"))
Assert-Provenance (-not (Test-Path -LiteralPath $fixtureRoot)) "fixture directory is new and owned"
[void][IO.Directory]::CreateDirectory($fixtureRoot)
try {
    # A minimal synthetic SFNT name table, not an installed font binary.
    Initialize-GalleryFontProbe
    $versionBytes = [Text.Encoding]::BigEndianUnicode.GetBytes("Version 1.25")
    $fontBytes = New-Object byte[] (46 + $versionBytes.Length)
    $fontBytes[1] = 1; $fontBytes[5] = 1
    $fontBytes[12] = 0x6e; $fontBytes[13] = 0x61; $fontBytes[14] = 0x6d; $fontBytes[15] = 0x65
    $fontBytes[23] = 28; $fontBytes[27] = 18 + $versionBytes.Length
    $fontBytes[31] = 1; $fontBytes[33] = 18
    $fontBytes[35] = 3; $fontBytes[37] = 1; $fontBytes[38] = 4; $fontBytes[39] = 9
    $fontBytes[41] = 5; $fontBytes[43] = $versionBytes.Length
    [Array]::Copy($versionBytes, 0, $fontBytes, 46, $versionBytes.Length)
    $fontPath = Join-Path $fixtureRoot "synthetic-name-table.ttf"
    [IO.File]::WriteAllBytes($fontPath, $fontBytes)
    $versions = @([SwiftWindowsUIGalleryFontProbe]::ReadFontVersions($fontPath))
    Assert-Provenance ($versions.Count -eq 1 -and $versions[0] -ceq "Version 1.25") "embedded name ID 5 supplies a real version when FileVersionInfo cannot"
    $fingerprint = Get-GalleryFileFingerprint $fontPath
    Assert-Provenance ($fingerprint.status -eq "observed" -and $fingerprint.sha256 -match '^[0-9a-f]{64}$' -and $fingerprint.length -eq $fontBytes.Length) "file identity contains a digest and size, not font bytes"
    $fontBytes[44] = 255; $fontBytes[45] = 255
    [IO.File]::WriteAllBytes($fontPath, $fontBytes)
    $rejected = $false
    try { [SwiftWindowsUIGalleryFontProbe]::ReadFontVersions($fontPath) | Out-Null } catch { $rejected = $true }
    Assert-Provenance $rejected "out-of-bounds version offsets are rejected"
    [IO.File]::WriteAllBytes($fontPath, [byte[]]@(0, 1, 0))
    $rejected = $false
    try { [SwiftWindowsUIGalleryFontProbe]::ReadFontVersions($fontPath) | Out-Null } catch { $rejected = $true }
    Assert-Provenance $rejected "truncated files cannot fabricate a font version"
    Assert-Provenance ((Get-GalleryFileFingerprint (Join-Path $fixtureRoot "missing.exe")).status -eq "missing") "a missing executable is recorded explicitly"

    $processDirectory = [Environment]::CurrentDirectory
    $otherDirectory = Join-Path $fixtureRoot "other-process-directory"
    [void][IO.Directory]::CreateDirectory($otherDirectory)
    Push-Location -LiteralPath $fixtureRoot
    try {
        [Environment]::CurrentDirectory = $otherDirectory
        $relativeFile = Get-GalleryFileFingerprint "synthetic-name-table.ttf"
        Assert-Provenance ($relativeFile.path -ceq $fontPath -and $relativeFile.status -eq "observed") "relative executable/file paths follow PowerShell's location, not the process directory"
        Write-GalleryFontProvenance ([pscustomobject]@{ marker = "owned-relative-fixture" }) "relative-provenance.json"
        Assert-Provenance ((Test-Path -LiteralPath (Join-Path $fixtureRoot "relative-provenance.json")) -and -not (Test-Path -LiteralPath (Join-Path $otherDirectory "relative-provenance.json"))) "relative artifact output uses the same PowerShell location"
        Assert-Provenance ((Get-GallerySourceProvenance ".").root -ceq $fixtureRoot) "relative source attribution follows the PowerShell location"
    } finally {
        [Environment]::CurrentDirectory = $processDirectory
        Pop-Location
    }

    $galleryScript = Join-Path $repoRoot "scripts/gallery-compare.ps1"
    $missingExe = Join-Path $fixtureRoot "missing-gallery.exe"
    $listWork = Join-Path $fixtureRoot "list"
    $listing = Invoke-ProvenanceFixture @("-File", $galleryScript, "-List", "-WorkDir", $listWork)
    Assert-Provenance ($listing.exitCode -eq 0 -and -not (Test-Path -LiteralPath $listWork)) "-List remains free of probes and artifacts"

    # The build-failure case cannot invoke SwiftPM: its child verifies that
    # `swift` resolves to this owned exit-only shim before calling the gate.
    $shim = Join-Path $fixtureRoot "swift.cmd"
    [IO.File]::WriteAllText($shim, "@exit /b 19`r`n")
    $buildWrapper = Join-Path $fixtureRoot "build-failure.ps1"
    @'
param($ShimDirectory, $GalleryScript, $Executable, $WorkDirectory)
$ErrorActionPreference = "Stop"
$env:PATH = $ShimDirectory + ";" + $env:PATH
$expected = [IO.Path]::GetFullPath((Join-Path $ShimDirectory "swift.cmd"))
if ((Get-Command swift -ErrorAction Stop).Source -ine $expected) { throw "Refusing fixture: Swift shim was not resolved." }
& $GalleryScript -GalleryExe $Executable -Entries button -WorkDir $WorkDirectory
exit $LASTEXITCODE
'@ | Set-Content -LiteralPath $buildWrapper -Encoding UTF8
    $oldExe = Join-Path $fixtureRoot "old-gallery.exe"
    [IO.File]::WriteAllText($oldExe, "preexisting executable fixture, never executed")
    $buildWork = Join-Path $fixtureRoot "build-failure"
    $buildFailure = Invoke-ProvenanceFixture @("-File", $buildWrapper, "-ShimDirectory", $fixtureRoot, "-GalleryScript", $galleryScript, "-Executable", $oldExe, "-WorkDirectory", $buildWork)
    Assert-Provenance ($buildFailure.exitCode -ne 0) "a failed build still fails the gallery invocation"
    $initialPath = Join-Path $buildWork "provenance-initial.json"
    Assert-Provenance (Test-Path -LiteralPath $initialPath) "initial provenance survives an early build failure"
    $initial = Get-Content -Raw -LiteralPath $initialPath | ConvertFrom-Json
    $failure = Get-Content -Raw -LiteralPath (Join-Path $buildWork "provenance.json") | ConvertFrom-Json
    Assert-Provenance ($initial.stage -eq "before-build" -and $initial.build.status -eq "pending") "later failure does not overwrite the initial record"
    Assert-Provenance ($failure.stage -eq "build-failed" -and $failure.build.exitCode -eq 19) "the actual failing build phase and exit are recorded"
    Assert-Provenance ($failure.executableAssociation -like 'preexisting-or-partial-file-after-failed-build*' -and $null -eq $failure.source.executableBuildRevision) "an old executable is never attributed to the failed checkout build"
    Assert-Provenance ($initial.executable.sha256 -eq $failure.executable.sha256 -and $initial.invocationID -eq $failure.invocationID) "initial and final evidence retain the same invocation and preexisting binary identity"

    $renderShim = Join-Path $fixtureRoot "gallery-failure.cmd"
    [IO.File]::WriteAllText($renderShim, "@exit /b 27`r`n")
    $renderWork = Join-Path $fixtureRoot "render-failure"
    $renderFailure = Invoke-ProvenanceFixture @("-File", $galleryScript, "-SkipBuild", "-GalleryExe", $renderShim, "-Entries", "button", "-WorkDir", $renderWork)
    Assert-Provenance ($renderFailure.exitCode -ne 0) "render failure stays a failure"
    $failure = Get-Content -Raw -LiteralPath (Join-Path $renderWork "provenance.json") | ConvertFrom-Json
    Assert-Provenance ($failure.stage -eq "render-failed" -and $failure.render.exitCode -eq 27 -and $failure.render.imageAssociation -like 'unverified-*') "partial or preexisting images are not labeled successful renders"

    # Synthetic pixels exercise the real comparison status without running a
    # renderer. Missing executable/provenance does not approve a font profile.
    Add-Type -AssemblyName System.Drawing
    $baseline = Join-Path $fixtureRoot "baseline"
    $compareWork = Join-Path $fixtureRoot "compare"
    $current = Join-Path $compareWork "current"
    [void][IO.Directory]::CreateDirectory($baseline)
    [void][IO.Directory]::CreateDirectory($current)
    $bitmap = New-Object Drawing.Bitmap(2, 2)
    try {
        $bitmap.SetPixel(0, 0, [Drawing.Color]::White)
        $bitmap.Save((Join-Path $baseline "button.png"), [Drawing.Imaging.ImageFormat]::Png)
        $bitmap.Save((Join-Path $current "button.png"), [Drawing.Imaging.ImageFormat]::Png)
        $arguments = @("-File", $galleryScript, "-SkipBuild", "-SkipRender", "-GalleryExe", $missingExe, "-Entries", "button", "-BaselineDir", $baseline, "-WorkDir", $compareWork)
        $match = Invoke-ProvenanceFixture $arguments
        Assert-Provenance ($match.exitCode -eq 0) "matching synthetic pixels retain the original comparison success"
        $report = Get-Content -Raw -LiteralPath (Join-Path $compareWork "report.json") | ConvertFrom-Json
        Assert-Provenance ($report.status -eq "pass" -and $report.schemaVersion -eq 2) "comparison schema preserves the pixel status"
        Assert-Provenance ($report.fontProvenance.qualification.status -eq "unqualified" -and $null -eq $report.fontProvenance.qualification.acceptedBaselineProfile) "pixel success never certifies an unknown baseline profile"
        Assert-Provenance ($report.fontProvenance.render.imageAssociation -like 'unknown-existing-images*' -and $report.fontProvenance.executable.status -eq "missing") "SkipRender cannot attribute existing PNGs to the current host or missing executable"
        $bitmap.SetPixel(0, 0, [Drawing.Color]::Red)
        $bitmap.Save((Join-Path $current "button.png"), [Drawing.Imaging.ImageFormat]::Png)
        $mismatch = Invoke-ProvenanceFixture $arguments
        Assert-Provenance ($mismatch.exitCode -ne 0) "provenance never turns a real pixel mismatch into success"
        $report = Get-Content -Raw -LiteralPath (Join-Path $compareWork "report.json") | ConvertFrom-Json
        Assert-Provenance ($report.status -eq "fail" -and $report.summary.failing -eq 1) "the existing pixel gate and thresholds remain authoritative"
    } finally { $bitmap.Dispose() }
} finally {
    $resolved = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $fixtureRoot).Path)
    if ([IO.Path]::GetDirectoryName($resolved) -cne $tempRoot -or [IO.Path]::GetFileName($resolved) -notmatch '^swift-windowsui-font-provenance-test-[0-9a-f]{32}$') {
        throw "Refusing cleanup outside the owned provenance fixture directory."
    }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}

Write-Host "Gallery font provenance tests passed ($script:provenanceAssertions assertions). Synthetic fixtures only; no SwiftPM or font changes."
exit 0
