<#
.SYNOPSIS
    Render the demo through the retained runtime and write PNGs.

.PARAMETER Width
.PARAMETER Height
    Surface size in DEVICE PIXELS. With -Scale 1 these are also the window's
    point size.

.PARAMETER LogicalWidth
.PARAMETER LogicalHeight
    Window size in POINTS. When given, the surface becomes logical x scale, so
    -LogicalWidth 1280 -LogicalHeight 720 -Scale 2 is a true 2x render of the
    same layout a 1x 1280x720 render produces — not a magnified quadrant.
    Mutually exclusive with -Width/-Height.
#>
param(
    [string]$OutputPath = "",
    [int]$Width = 1280,
    [int]$Height = 720,
    [int]$LogicalWidth = 0,
    [int]$LogicalHeight = 0,
    [double]$Scale = 1.0,
    [ValidateSet("scene", "frame")]
    [string]$Mode = "scene",
    [switch]$FrameDebug,
    [int]$WarmupMilliseconds = 0,
    [switch]$KeepOpen,
    [switch]$AllScreens,
    [ValidateSet("light", "dark")]
    [string]$Appearance = "dark"
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$withSwift = Join-Path $PSScriptRoot "with-swift.ps1"

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $repoRoot "artifacts\demo-screenshot.png"
}

if ($FrameDebug) {
    $Mode = "frame"
}

if (($LogicalWidth -gt 0) -ne ($LogicalHeight -gt 0)) {
    throw "-LogicalWidth and -LogicalHeight must be supplied together."
}
$useLogicalSize = $LogicalWidth -gt 0
if ($useLogicalSize -and ($PSBoundParameters.ContainsKey("Width") -or $PSBoundParameters.ContainsKey("Height"))) {
    throw "-LogicalWidth/-LogicalHeight and -Width/-Height set the same thing from opposite ends; pass one pair."
}

function Invoke-DemoScreenshot {
    param(
        [string]$Path,
        [string]$Screen
    )

    $outputDirectory = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($outputDirectory)) {
        New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
    }

    $rawBmpPath = $Path
    if ([System.IO.Path]::GetExtension($Path).ToLowerInvariant() -ne ".bmp") {
        $rawDirectory = if ([string]::IsNullOrWhiteSpace($outputDirectory)) { (Get-Location).Path } else { $outputDirectory }
        $rawBmpPath = Join-Path $rawDirectory ([System.IO.Path]::GetFileNameWithoutExtension($Path) + ".raw.bmp")
    }

    $snapshotArgs = @(
        "run", "--package-path", $repoRoot, "swift-windowsui-snapshot", "--",
        "--output", $rawBmpPath,
        "--scale", $Scale,
        "--mode", $Mode,
        "--appearance", $Appearance
    )
    if ($useLogicalSize) {
        $snapshotArgs += @("--logical-size", "$($LogicalWidth)x$($LogicalHeight)")
    } else {
        $snapshotArgs += @("--width", $Width, "--height", $Height)
    }
    if (-not [string]::IsNullOrWhiteSpace($Screen)) {
        $snapshotArgs += @("--screen", $Screen)
    }

    & $withSwift swift @snapshotArgs
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }

    if ([System.IO.Path]::GetExtension($Path).ToLowerInvariant() -eq ".bmp") {
        Write-Output "Screenshot=$Path"
        Write-Output "Source=raw-$Mode"
        return
    }

    Add-Type -AssemblyName System.Drawing
    $bitmap = [System.Drawing.Image]::FromFile($rawBmpPath)
    try {
        $bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    } finally {
        $bitmap.Dispose()
    }

    Write-Output "Screenshot=$Path"
    Write-Output "RawFrame=$rawBmpPath"
    Write-Output "Source=raw-$Mode"
}

if ($AllScreens) {
    $outputDirectory = Split-Path -Parent $OutputPath
    if ([string]::IsNullOrWhiteSpace($outputDirectory)) {
        $outputDirectory = (Get-Location).Path
    }
    $extension = [System.IO.Path]::GetExtension($OutputPath)
    if ([string]::IsNullOrWhiteSpace($extension)) {
        $extension = ".png"
    }
    $suffix = if ($Appearance -eq "light") { "-light" } else { "" }
    # A 2x render is a different artifact, not a newer version of the 1x one:
    # keep them side by side so the pair can be compared.
    if ($Scale -ne 1.0) {
        $suffix += "-{0}x" -f ($Scale.ToString([System.Globalization.CultureInfo]::InvariantCulture))
    }
    foreach ($screen in @("dashboard", "settings", "data")) {
        $screenPath = Join-Path $outputDirectory "demo-screenshot-$screen$suffix$extension"
        Invoke-DemoScreenshot -Path $screenPath -Screen $screen
    }
} else {
    Invoke-DemoScreenshot -Path $OutputPath -Screen ""
}
