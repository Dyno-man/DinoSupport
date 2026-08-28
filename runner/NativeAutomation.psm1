Set-StrictMode -Version Latest

function Assert-DinoSupportNativeAutomationAvailable {
    if ($env:OS -ne 'Windows_NT') { throw 'Native UI Automation is supported only on Windows.' }
    Add-Type -AssemblyName UIAutomationClient
    Add-Type -AssemblyName UIAutomationTypes
}

function Start-DinoSupportNativeRecipe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object]$Task,
        [Parameter(Mandatory)] [object]$StopControl,
        [Parameter(Mandatory)] [datetime]$ExecutionDeadline
    )

    if ($Task.ExecutorKind -ne 'native' -or $Task.ActionType -ne 'inspectNotepadWindow' -or @($Task.AllowedApps).Count -ne 1 -or $Task.AllowedApps[0] -ne 'Notepad') {
        throw 'The native recipe is outside the supported Notepad scope.'
    }
    Assert-DinoSupportNativeAutomationAvailable
    $trace = [System.Collections.ArrayList]::new()
    [void]$trace.Add([ordered]@{ event = 'nativeRecipeStarted'; application = 'Notepad'; atUtc = (Get-Date).ToUniversalTime().ToString('o') })
    $process = Start-Process -FilePath 'notepad.exe' -PassThru
    try {
        do {
            Update-DinoSupportStopControl $StopControl
            $root = [System.Windows.Automation.AutomationElement]::RootElement
            $condition = [System.Windows.Automation.PropertyCondition]::new([System.Windows.Automation.AutomationElement]::ProcessIdProperty, $process.Id)
            $window = $root.FindFirst([System.Windows.Automation.TreeScope]::Children, $condition)
            if ($window) { break }
            Start-Sleep -Milliseconds 100
        } while ((Get-Date) -lt $ExecutionDeadline)
        if (-not $window) { throw 'The Notepad window did not become available before the task deadline.' }

        $name = $window.Current.Name
        $controlType = $window.Current.ControlType.ProgrammaticName
        [void]$trace.Add([ordered]@{ event = 'nativeWindowInspected'; application = 'Notepad'; windowName = $name; controlType = $controlType; atUtc = (Get-Date).ToUniversalTime().ToString('o') })
        return [pscustomobject]@{ Application = 'Notepad'; WindowName = $name; ControlType = $controlType; ExecutionTrace = @($trace) }
    } finally {
        if ($process -and -not $process.HasExited) { Stop-Process -Id $process.Id -Force }
    }
}

Export-ModuleMember -Function Start-DinoSupportNativeRecipe
