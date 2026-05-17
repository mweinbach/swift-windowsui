param(
    [string[]]$Path = @(),
    [switch]$AllSwift,
    [switch]$ContractsOnly,
    [switch]$SkipContracts
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$withSwift = Join-Path $PSScriptRoot "with-swift.ps1"
$contractScript = Join-Path $PSScriptRoot "check-contracts.ps1"
$swiftFormatConfig = Join-Path $repoRoot ".swift-format"

if (-not $SkipContracts) {
    & $contractScript
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
}

if ($ContractsOnly) {
    exit 0
}

if (-not (Test-Path -LiteralPath $swiftFormatConfig)) {
    Write-Error ".swift-format is missing."
    exit 1
}

if ($Path.Count -gt 0) {
    $swiftFiles = @($Path) |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        ForEach-Object {
            if ([System.IO.Path]::IsPathRooted($_)) {
                $_
            } else {
                Join-Path $repoRoot $_
            }
        } |
        Where-Object { Test-Path -LiteralPath $_ }
} elseif ($AllSwift) {
    $swiftFiles = @("Package.swift")
    $swiftFiles += Get-ChildItem -LiteralPath (Join-Path $repoRoot "Sources"), (Join-Path $repoRoot "Tests") -Recurse -Filter "*.swift" -File |
        ForEach-Object { $_.FullName }
} else {
    $tracked = @(& git -C $repoRoot diff --name-only --diff-filter=ACMR HEAD -- "*.swift")
    $untracked = @(& git -C $repoRoot ls-files --others --exclude-standard -- "*.swift")
    $swiftFiles = @($tracked + $untracked) |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        ForEach-Object { Join-Path $repoRoot $_ } |
        Where-Object { Test-Path -LiteralPath $_ }
}

$swiftFiles = @($swiftFiles | Sort-Object -Unique)

if ($swiftFiles.Count -eq 0) {
    Write-Host "No Swift files selected for swift-format lint."
    exit 0
}

Write-Host "Running swift-format lint on $($swiftFiles.Count) Swift file(s)."
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("swift-windowsui-format-" + [System.Guid]::NewGuid().ToString("N"))
$repoRootFull = [System.IO.Path]::GetFullPath($repoRoot)

try {
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    $tempFiles = @()

    foreach ($file in $swiftFiles) {
        $fullFile = [System.IO.Path]::GetFullPath($file)
        if ($fullFile.StartsWith($repoRootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
            $relative = $fullFile.Substring($repoRootFull.Length).TrimStart("\", "/")
        } else {
            $relative = Split-Path -Leaf $fullFile
        }

        $tempFile = Join-Path $tempRoot $relative
        $tempDir = Split-Path -Parent $tempFile
        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

        $text = [System.IO.File]::ReadAllText($fullFile)
        $text = $text -replace "`r`n", "`n" -replace "`r", "`n"
        $encoding = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($tempFile, $text, $encoding)
        $tempFiles += $tempFile
    }

    & $withSwift swift-format lint --configuration $swiftFormatConfig --strict @tempFiles
    exit $LASTEXITCODE
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        $resolvedTemp = (Resolve-Path -LiteralPath $tempRoot).Path
        $tempBase = [System.IO.Path]::GetTempPath()
        if ($resolvedTemp.StartsWith($tempBase, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $resolvedTemp -Recurse -Force
        }
    }
}
