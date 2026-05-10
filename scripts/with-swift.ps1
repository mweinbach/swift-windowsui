param(
    [switch]$CheckOnly,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Command
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$swiftRoot = Join-Path $env:LOCALAPPDATA "Programs\Swift"

$vsCandidates = @(
    "C:\Program Files\Microsoft Visual Studio\18\Community\Common7\Tools\VsDevCmd.bat",
    "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat"
)

function Get-LatestExistingPath([string]$Pattern) {
    $matches = Get-ChildItem -Path $Pattern -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending
    if ($matches) {
        return $matches[0].FullName
    }
    return $null
}

$vsDevCmd = $vsCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
$swiftBin = Get-LatestExistingPath (Join-Path $swiftRoot "Toolchains\*\usr\bin")
$swiftRuntime = Get-LatestExistingPath (Join-Path $swiftRoot "Runtimes\*\usr\bin")
$sdkRoot = Get-LatestExistingPath (Join-Path $swiftRoot "Platforms\*\Windows.platform\Developer\SDKs\Windows.sdk")

if (-not $vsDevCmd) { throw "VsDevCmd.bat was not found in the expected Visual Studio locations." }
if (-not $swiftBin) { throw "Swift toolchain bin directory was not found under $swiftRoot." }
if (-not $swiftRuntime) { throw "Swift runtime bin directory was not found under $swiftRoot." }
if (-not $sdkRoot) { throw "Swift Windows SDK root was not found under $swiftRoot." }

$vsArch = if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64" -or $env:PROCESSOR_ARCHITEW6432 -eq "ARM64") {
    "arm64"
} else {
    "x64"
}

cmd /d /s /c "`"$vsDevCmd`" -arch=$vsArch -host_arch=$vsArch >nul && set" |
    ForEach-Object {
        if ($_ -match "^(.*?)=(.*)$") {
            Set-Item -Path ("Env:" + $matches[1]) -Value $matches[2]
        }
    }

$env:PATH = "$swiftRuntime;$swiftBin;$env:PATH"
$env:SDKROOT = $sdkRoot
$env:SWIFT_REPO_ROOT = $repoRoot

if ($CheckOnly) {
    Write-Output "Swift environment ready."
    Write-Output "RepoRoot=$repoRoot"
    Write-Output "VSDevCmd=$vsDevCmd"
    Write-Output "VSArch=$vsArch"
    Write-Output "SwiftBin=$swiftBin"
    Write-Output "SwiftRuntime=$swiftRuntime"
    Write-Output "SDKROOT=$sdkRoot"
    exit 0
}

if (-not $Command -or $Command.Count -eq 0) {
    throw "No command was provided to with-swift.ps1."
}

$executable = $Command[0]
$arguments = @()
if ($Command.Count -gt 1) {
    $arguments = $Command[1..($Command.Count - 1)]
}

& $executable @arguments
exit $LASTEXITCODE
