param(
    [string]$OutputPath = "",
    [int]$WarmupMilliseconds = 2500,
    [switch]$FrameDebug,
    [switch]$KeepOpen
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$withSwift = Join-Path $PSScriptRoot "with-swift.ps1"

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $repoRoot "artifacts\demo-screenshot.png"
}

$outputDirectory = Split-Path -Parent $OutputPath
if (-not [string]::IsNullOrWhiteSpace($outputDirectory)) {
    New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
}

& $withSwift swift build --package-path $repoRoot --product swift-windowsui
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

$exe = Get-ChildItem -Path (Join-Path $repoRoot ".build") -Recurse -Filter "swift-windowsui.exe" |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if (-not $exe) {
    throw "Built swift-windowsui.exe could not be found under .build."
}

$swiftRoot = Join-Path $env:LOCALAPPDATA "Programs\Swift"
$swiftRuntime = Get-ChildItem -Path (Join-Path $swiftRoot "Runtimes\*\usr\bin") -ErrorAction SilentlyContinue |
    Sort-Object FullName -Descending |
    Select-Object -First 1
$swiftBin = Get-ChildItem -Path (Join-Path $swiftRoot "Toolchains\*\usr\bin") -ErrorAction SilentlyContinue |
    Sort-Object FullName -Descending |
    Select-Object -First 1

$processInfo = [System.Diagnostics.ProcessStartInfo]::new()
$processInfo.FileName = $exe.FullName
$processInfo.WorkingDirectory = $repoRoot
$processInfo.UseShellExecute = $false
$processInfo.Environment["PATH"] = (@($swiftRuntime.FullName, $swiftBin.FullName, $env:PATH) | Where-Object { $_ }) -join ";"

if ($FrameDebug) {
    $processInfo.Environment["SWIFT_WINDOWSUI_FRAME_DEBUG"] = "1"
} elseif ($processInfo.Environment.ContainsKey("SWIFT_WINDOWSUI_FRAME_DEBUG")) {
    $processInfo.Environment.Remove("SWIFT_WINDOWSUI_FRAME_DEBUG")
}

$process = [System.Diagnostics.Process]::Start($processInfo)

try {
    $deadline = (Get-Date).AddSeconds(15)
    while ($process.MainWindowHandle -eq [IntPtr]::Zero -and (Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 100
        $process.Refresh()
    }

    if ($process.MainWindowHandle -eq [IntPtr]::Zero) {
        throw "Demo window did not appear before the screenshot timeout."
    }

    Start-Sleep -Milliseconds $WarmupMilliseconds

    Add-Type @"
using System;
using System.Runtime.InteropServices;

public static class SwiftWindowsUIScreenCapture {
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);
}
"@

    $hwndTopMost = [IntPtr]::new(-1)
    $hwndNoTopMost = [IntPtr]::new(-2)
    $swpNoSize = 0x0001
    $swpNoMove = 0x0002
    $swpShowWindow = 0x0040

    [SwiftWindowsUIScreenCapture]::SetWindowPos(
        $process.MainWindowHandle,
        $hwndTopMost,
        0,
        0,
        0,
        0,
        $swpNoMove -bor $swpNoSize -bor $swpShowWindow
    ) | Out-Null
    [SwiftWindowsUIScreenCapture]::ShowWindow($process.MainWindowHandle, 5) | Out-Null
    [SwiftWindowsUIScreenCapture]::SetForegroundWindow($process.MainWindowHandle) | Out-Null
    Start-Sleep -Milliseconds 750

    $rect = [SwiftWindowsUIScreenCapture+RECT]::new()
    if (-not [SwiftWindowsUIScreenCapture]::GetWindowRect($process.MainWindowHandle, [ref]$rect)) {
        throw "Could not read the demo window bounds."
    }

    $width = $rect.Right - $rect.Left
    $height = $rect.Bottom - $rect.Top
    if ($width -le 0 -or $height -le 0) {
        throw "Demo window bounds were empty: ${width}x${height}."
    }

    Add-Type -AssemblyName System.Drawing
    $bitmap = [System.Drawing.Bitmap]::new($width, $height)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.CopyFromScreen($rect.Left, $rect.Top, 0, 0, $bitmap.Size)
        $bitmap.Save($OutputPath, [System.Drawing.Imaging.ImageFormat]::Png)
    } finally {
        $graphics.Dispose()
        $bitmap.Dispose()
    }

    [SwiftWindowsUIScreenCapture]::SetWindowPos(
        $process.MainWindowHandle,
        $hwndNoTopMost,
        0,
        0,
        0,
        0,
        $swpNoMove -bor $swpNoSize
    ) | Out-Null

    Write-Output "Screenshot=$OutputPath"
} finally {
    if (-not $KeepOpen -and -not $process.HasExited) {
        $process.CloseMainWindow() | Out-Null
        if (-not $process.WaitForExit(3000)) {
            $process.Kill()
            $process.WaitForExit()
        }
    }
}
