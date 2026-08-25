param(
    [switch]$FrameDebug,
    [ValidateSet("d3d11", "software")]
    [string]$Backend
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot

if ($FrameDebug) {
    $env:SWIFT_WINDOWSUI_FRAME_DEBUG = "1"
} else {
    Remove-Item Env:\SWIFT_WINDOWSUI_FRAME_DEBUG -ErrorAction SilentlyContinue
}

if ($PSBoundParameters.ContainsKey("Backend")) {
    $env:SWIFT_WINDOWSUI_RENDER_BACKEND = $Backend.ToLowerInvariant()
}

& (Join-Path $PSScriptRoot "with-swift.ps1") swift run --package-path $repoRoot swift-windowsui
exit $LASTEXITCODE
