param(
    [switch]$CheckOnly,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Command
)

$ErrorActionPreference = "Stop"

$repoRoot = "C:\Users\maxw6\Projects\swift-windowsui"
$vsCandidates = @(
    "C:\Program Files\Microsoft Visual Studio\18\Community\Common7\Tools\VsDevCmd.bat",
    "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat"
)
$swiftToolchainCandidates = @(
    "C:\Users\maxw6\AppData\Local\Programs\Swift\Toolchains\6.3.0+Asserts\usr\bin",
    "C:\Users\maxw6\AppData\Local\Programs\Swift\Toolchains\6.3.0\usr\bin"
)
$swiftRuntimeCandidates = @(
    "C:\Users\maxw6\AppData\Local\Programs\Swift\Runtimes\6.3.0\usr\bin"
)
$sdkCandidates = @(
    "C:\Users\maxw6\AppData\Local\Programs\Swift\Platforms\6.3.0\Windows.platform\Developer\SDKs\Windows.sdk"
)

$vsDevCmd = $vsCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
$swiftBin = $swiftToolchainCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
$swiftRuntime = $swiftRuntimeCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
$sdkRoot = $sdkCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $vsDevCmd) { throw "VsDevCmd.bat was not found in the expected Visual Studio locations." }
if (-not $swiftBin) { throw "Swift toolchain bin directory was not found in the expected locations." }
if (-not $swiftRuntime) { throw "Swift runtime bin directory was not found in the expected locations." }
if (-not $sdkRoot) { throw "Swift Windows SDK root was not found in the expected locations." }

cmd /d /s /c "`"$vsDevCmd`" -arch=x64 -host_arch=x64 >nul && set" |
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
    Write-Output "VSDevCmd=$vsDevCmd"
    Write-Output "SwiftBin=$swiftBin"
    Write-Output "SwiftRuntime=$swiftRuntime"
    Write-Output "SDKROOT=$sdkRoot"
    exit 0
}

if (-not $Command -or $Command.Count -eq 0) {
    throw "No command was provided to windows-swift-env.ps1."
}

$executable = $Command[0]
$arguments = @()
if ($Command.Count -gt 1) {
    $arguments = $Command[1..($Command.Count - 1)]
}

& $executable @arguments
exit $LASTEXITCODE
