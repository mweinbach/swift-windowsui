param(
    [string]$Filter = ""
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$argsList = @("test", "--package-path", $repoRoot)
if (-not [string]::IsNullOrWhiteSpace($Filter)) {
    $argsList += @("--filter", $Filter)
}

& (Join-Path $PSScriptRoot "with-swift.ps1") swift @argsList
exit $LASTEXITCODE
