param(
    [string]$Product = "swift-windowsui",
    [ValidateSet("debug", "release")]
    [string]$Configuration = "debug"
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
& (Join-Path $PSScriptRoot "with-swift.ps1") swift build --package-path $repoRoot --configuration $Configuration --product $Product
exit $LASTEXITCODE
