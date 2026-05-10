param(
    [string]$Product = "swift-windowsui"
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
& (Join-Path $PSScriptRoot "with-swift.ps1") swift build --package-path $repoRoot --product $Product
exit $LASTEXITCODE
