param(
    [switch]$FrameDebug
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot

if ($FrameDebug) {
    $env:SWIFT_WINDOWSUI_FRAME_DEBUG = "1"
} else {
    Remove-Item Env:\SWIFT_WINDOWSUI_FRAME_DEBUG -ErrorAction SilentlyContinue
}

& (Join-Path $PSScriptRoot "with-swift.ps1") swift run --package-path $repoRoot swift-windowsui
exit $LASTEXITCODE
