param(
    # Path to a built swift-windowsui.exe. When omitted, the script builds the
    # demo into the repo's default .build directory and probes that binary.
    [string]$ExePath = "",
    # Seconds to wait for the demo window to appear.
    [int]$WindowTimeoutSeconds = 30
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot

if ([string]::IsNullOrWhiteSpace($ExePath)) {
    & (Join-Path $PSScriptRoot "with-swift.ps1") swift build --package-path $repoRoot --product swift-windowsui
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
    $ExePath = Join-Path $repoRoot ".build/debug/swift-windowsui.exe"
}

if (-not (Test-Path $ExePath)) {
    Write-Error "Demo executable not found: $ExePath"
    exit 1
}

# Do not let the startup probe auto-exit the demo; it must stay up for UIA.
Remove-Item Env:\SWIFT_WINDOWSUI_STARTUP_PROBE_EXIT -ErrorAction SilentlyContinue

Add-Type -AssemblyName UIAutomationClient

function Format-Element($element) {
    $current = $element.Current
    $bounds = $current.BoundingRectangle
    return "{0} '{1}' [{2},{3} {4}x{5}]" -f `
        $current.ControlType.ProgrammaticName, $current.Name, `
        [int]$bounds.X, [int]$bounds.Y, [int]$bounds.Width, [int]$bounds.Height
}

$process = Start-Process -FilePath $ExePath -PassThru
$exitCode = 0

try {
    $deadline = (Get-Date).AddSeconds($WindowTimeoutSeconds)
    do {
        Start-Sleep -Milliseconds 250
        $process.Refresh()
    } while ($process.MainWindowHandle -eq 0 -and (Get-Date) -lt $deadline -and -not $process.HasExited)

    if ($process.MainWindowHandle -eq 0) {
        Write-Error "Demo window did not appear within $WindowTimeoutSeconds seconds."
        exit 1
    }

    $window = [System.Windows.Automation.AutomationElement]::FromHandle($process.MainWindowHandle)
    Write-Output ("Window: " + (Format-Element $window))

    # Print the UIA tree two levels deep below the window element.
    $all = [System.Windows.Automation.Condition]::TrueCondition
    $children = $window.FindAll([System.Windows.Automation.TreeScope]::Children, $all)
    Write-Output ("Level 1 elements: " + $children.Count)
    foreach ($child in $children) {
        Write-Output ("  " + (Format-Element $child))
        $grandchildren = $child.FindAll([System.Windows.Automation.TreeScope]::Children, $all)
        foreach ($grandchild in $grandchildren) {
            Write-Output ("    " + (Format-Element $grandchild))
        }
    }

    # Invoke the first button that supports the Invoke pattern.
    $buttonCondition = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
        [System.Windows.Automation.ControlType]::Button)
    $button = $window.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $buttonCondition)

    if ($null -eq $button) {
        Write-Output "INVOKE: no UIA Button element found. Demo controls only project accessibility"
        Write-Output "metadata that exists on retained nodes; unlabeled retained buttons currently"
        Write-Output "surface as their text child. See the lane report for the projection follow-up."
    } else {
        try {
            $invoke = $button.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
            Write-Output ("INVOKE: invoking button '" + $button.Current.Name + "'")
            $invoke.Invoke()
            Write-Output "INVOKE: success"
        } catch {
            Write-Output ("INVOKE: button '" + $button.Current.Name + "' has no Invoke pattern: " + $_.Exception.Message)
        }
    }
} finally {
    if (-not $process.HasExited) {
        $process.CloseMainWindow() | Out-Null
        if (-not $process.WaitForExit(5000)) {
            $process.Kill()
        }
    }
}

exit $exitCode
