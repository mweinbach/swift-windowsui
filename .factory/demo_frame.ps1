$probe = Join-Path $env:TEMP 'swift-windowsui-frame-probe.log'
Remove-Item $probe -ErrorAction SilentlyContinue
$env:SWIFT_WINDOWSUI_FRAME_DEBUG = '1'
$env:SWIFT_WINDOWSUI_STARTUP_PROBE_PATH = $probe
$env:SWIFT_WINDOWSUI_STARTUP_PROBE_EXIT = '1'

& 'C:\Users\maxw6\Projects\swift-windowsui\.factory\windows-swift-env.ps1' swift run --package-path 'C:\Users\maxw6\Projects\swift-windowsui' swift-windowsui
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Get-Content $probe
