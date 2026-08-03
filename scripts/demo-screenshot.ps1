param(
    [string]$OutputPath = "",
    [int]$Width = 1280,
    [int]$Height = 720,
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
        "--width", $Width,
        "--height", $Height,
        "--scale", $Scale,
        "--mode", $Mode,
        "--appearance", $Appearance
    )
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
    foreach ($screen in @("dashboard", "settings", "data")) {
        $screenPath = Join-Path $outputDirectory "demo-screenshot-$screen$suffix$extension"
        Invoke-DemoScreenshot -Path $screenPath -Screen $screen
    }
} else {
    Invoke-DemoScreenshot -Path $OutputPath -Screen ""
}
