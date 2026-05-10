param(
    [string]$OutputPath = "",
    [int]$Width = 1280,
    [int]$Height = 720,
    [double]$Scale = 1.0,
    [ValidateSet("scene", "frame")]
    [string]$Mode = "scene",
    [switch]$FrameDebug,
    [int]$WarmupMilliseconds = 0,
    [switch]$KeepOpen
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

$outputDirectory = Split-Path -Parent $OutputPath
if (-not [string]::IsNullOrWhiteSpace($outputDirectory)) {
    New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
}

$rawBmpPath = $OutputPath
if ([System.IO.Path]::GetExtension($OutputPath).ToLowerInvariant() -ne ".bmp") {
    $rawDirectory = if ([string]::IsNullOrWhiteSpace($outputDirectory)) { (Get-Location).Path } else { $outputDirectory }
    $rawBmpPath = Join-Path $rawDirectory ([System.IO.Path]::GetFileNameWithoutExtension($OutputPath) + ".raw.bmp")
}

& $withSwift swift run --package-path $repoRoot swift-windowsui-snapshot -- `
    --output $rawBmpPath `
    --width $Width `
    --height $Height `
    --scale $Scale `
    --mode $Mode
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

if ([System.IO.Path]::GetExtension($OutputPath).ToLowerInvariant() -eq ".bmp") {
    Write-Output "Screenshot=$OutputPath"
    Write-Output "Source=raw-$Mode"
    exit 0
}

Add-Type -AssemblyName System.Drawing
$bitmap = [System.Drawing.Image]::FromFile($rawBmpPath)
try {
    $bitmap.Save($OutputPath, [System.Drawing.Imaging.ImageFormat]::Png)
} finally {
    $bitmap.Dispose()
}

Write-Output "Screenshot=$OutputPath"
Write-Output "RawFrame=$rawBmpPath"
Write-Output "Source=raw-$Mode"
