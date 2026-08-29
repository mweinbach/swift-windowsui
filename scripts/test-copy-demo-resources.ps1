param([switch]$KeepFixtures)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
$copyScript = Join-Path $PSScriptRoot "copy-demo-resources.ps1"
$repoRoot = Split-Path -Parent $PSScriptRoot
$assets = Join-Path $repoRoot "Sources/SwiftWindowsDemo/Resources"
$script:assertions = 0

function Assert-ResourceCopy([bool]$Condition, [string]$Message) {
    $script:assertions++
    if (-not $Condition) { throw $Message }
}

function Assert-ResourceCopyThrows([scriptblock]$Action, [string]$Pattern) {
    $caught = $null
    try { & $Action | Out-Null } catch { $caught = $_ }
    Assert-ResourceCopy ($null -ne $caught) "Expected resource-copy refusal: $Pattern"
    if ($null -ne $caught) {
        Assert-ResourceCopy ($caught.Exception.Message -match $Pattern) "Unexpected resource-copy error: $($caught.Exception.Message)"
    }
}

function Get-TestResourceHash([string]$Path) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $stream = [System.IO.File]::OpenRead($Path)
    try {
        return [System.BitConverter]::ToString($sha.ComputeHash($stream)).Replace("-", "").ToLowerInvariant()
    } finally {
        $stream.Dispose()
        $sha.Dispose()
    }
}

# These are authored test patterns, not accepted rendering baselines.
$expectedHashes = @{
    "demo-bitmap-caps.png" = "ecf285824681960b96d4440e04dbfe5bbef3a847386568976ba81f3435dcd7db"
    "demo-bitmap-tile.png" = "a896c8dd1f3759f9632e08c5106a780deba95973a2f7fdeabd9a4d091741a8d2"
}
foreach ($name in $expectedHashes.Keys) {
    Assert-ResourceCopy ((Get-TestResourceHash (Join-Path $assets $name)) -ceq $expectedHashes[$name]) "Owned pattern changed: $name"
}

$tempParent = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\', '/')
$caseName = "swift-windowsui-demo-resources-" + [System.Guid]::NewGuid().ToString("N")
$caseRoot = Join-Path $tempParent $caseName
if (Test-Path -LiteralPath $caseRoot) { throw "Synthetic resource fixture directory already exists." }
[System.IO.Directory]::CreateDirectory($caseRoot) | Out-Null
try {
    # An intentionally arbitrary basename and nested paths prove that the
    # helper preserves the supplied bundle instead of guessing either one.
    $source = Join-Path $caseRoot "owned-demo.resources"
    $sourceAssets = Join-Path $source "Contents/Resources"
    $emptyDirectory = Join-Path $source "Metadata/Empty"
    $destination = Join-Path $caseRoot "package"
    foreach ($directory in @($sourceAssets, $emptyDirectory, $destination)) {
        [System.IO.Directory]::CreateDirectory($directory) | Out-Null
    }
    foreach ($name in $expectedHashes.Keys) {
        [System.IO.File]::Copy((Join-Path $assets $name), (Join-Path $sourceAssets $name), $false)
    }
    [System.IO.File]::WriteAllText((Join-Path $source "Metadata/recipe.txt"), "owned fixture metadata")
    [System.IO.File]::WriteAllText((Join-Path $destination "unrelated.txt"), "leave this file alone")
    $result = & $copyScript -BundlePath $source -DestinationDirectory $destination
    $copiedBundle = Join-Path $destination "owned-demo.resources"
    Assert-ResourceCopy ($result.DestinationBundlePath -ceq $copiedBundle) "The input bundle basename must survive copying."
    Assert-ResourceCopy ($result.FileCount -eq 3) "Every bundle file must be copied."
    Assert-ResourceCopy ($result.ByteCount -eq 307) "The copied byte total must include metadata."
    Assert-ResourceCopy (Test-Path -LiteralPath (Join-Path $copiedBundle "Metadata/Empty") -PathType Container) "Empty bundle directories must survive copying."
    Assert-ResourceCopy ([System.IO.File]::ReadAllText((Join-Path $copiedBundle "Metadata/recipe.txt")) -ceq "owned fixture metadata") "Bundle metadata must survive copying."
    Assert-ResourceCopy ([System.IO.File]::ReadAllText((Join-Path $destination "unrelated.txt")) -ceq "leave this file alone") "Other staged files must remain unchanged."
    foreach ($name in $expectedHashes.Keys) {
        Assert-ResourceCopy ((Get-TestResourceHash (Join-Path $copiedBundle "Contents/Resources/$name")) -ceq $expectedHashes[$name]) "Copied resource bytes differ: $name"
        Assert-ResourceCopy ((Get-TestResourceHash (Join-Path $sourceAssets $name)) -ceq $expectedHashes[$name]) "Source resource bytes changed: $name"
    }

    Assert-ResourceCopyThrows { & $copyScript -BundlePath $source -DestinationDirectory $destination } "already exists"
    Assert-ResourceCopy ([System.IO.File]::ReadAllText((Join-Path $copiedBundle "Metadata/recipe.txt")) -ceq "owned fixture metadata") "Refusal must not overwrite an existing bundle."

    $missing = Join-Path $caseRoot "missing.resources"
    [System.IO.Directory]::CreateDirectory($missing) | Out-Null
    [System.IO.File]::Copy((Join-Path $assets "demo-bitmap-caps.png"), (Join-Path $missing "demo-bitmap-caps.png"), $false)
    Assert-ResourceCopyThrows { & $copyScript -BundlePath $missing -DestinationDirectory $destination } "exactly one 'demo-bitmap-tile.png'"
    Assert-ResourceCopy (-not (Test-Path -LiteralPath (Join-Path $destination "missing.resources"))) "Missing resources must be refused before publication."

    $duplicate = Join-Path $source "Metadata/demo-bitmap-caps.png"
    [System.IO.File]::Copy((Join-Path $assets "demo-bitmap-caps.png"), $duplicate, $false)
    $freshDestination = Join-Path $caseRoot "ambiguous-package"
    [System.IO.Directory]::CreateDirectory($freshDestination) | Out-Null
    Assert-ResourceCopyThrows { & $copyScript -BundlePath $source -DestinationDirectory $freshDestination } "exactly one 'demo-bitmap-caps.png'"
    Assert-ResourceCopy (-not (Test-Path -LiteralPath (Join-Path $freshDestination "owned-demo.resources"))) "Ambiguous resources must not produce a destination bundle."

    Assert-ResourceCopyThrows { & $copyScript -BundlePath $source -DestinationDirectory $sourceAssets } "outside the source"
    Assert-ResourceCopyThrows { & $copyScript -BundlePath (Join-Path $source "Metadata/recipe.txt") -DestinationDirectory $destination } "filesystem directory"
    Assert-ResourceCopyThrows { & $copyScript -BundlePath $source -DestinationDirectory (Join-Path $caseRoot "does-not-exist") } "does not exist"
    Assert-ResourceCopy (-not (Test-Path -LiteralPath (Join-Path $caseRoot "does-not-exist"))) "The caller must create its staging directory explicitly."
} finally {
    # Never recursively remove a path outside this one newly created fixture.
    $resolved = [System.IO.Path]::GetFullPath($caseRoot)
    $expected = [System.IO.Path]::GetFullPath((Join-Path $tempParent $caseName))
    if ($resolved -cne $expected -or -not $resolved.StartsWith($tempParent + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing cleanup outside the owned synthetic fixture directory."
    }
    if ($KeepFixtures) {
        Write-Host "Preserved synthetic resource fixtures: $resolved"
    } else {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}

Write-Host "Demo resource copy fixtures passed ($script:assertions assertions; synthetic filesystem only)."
exit 0
