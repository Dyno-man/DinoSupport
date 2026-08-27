Set-StrictMode -Version Latest

function Get-DinoSupportConsentSummary {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [object]$Task)

    return [ordered]@{
        Requester = $Task.Requester
        Applications = (@($Task.AllowedApps) -join ', ')
        Sites = (@($Task.AllowedDomains) -join ', ')
        DataCollected = (@($Task.RequestedEvidence) -join ', ')
        MaximumDuration = "$($Task.MaxRuntimeSeconds) seconds"
    }
}

function Initialize-DinoSupportForms {
    if ($env:OS -ne 'Windows_NT') { throw 'The DinoSupport consent UI is supported only on Windows.' }
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
}

function Request-DinoSupportConsent {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [object]$Task)

    Initialize-DinoSupportForms
    $summary = Get-DinoSupportConsentSummary $Task
    $form = [Windows.Forms.Form]@{
        Text = 'DinoSupport approval required'; Width = 560; Height = 400
        StartPosition = 'CenterScreen'; TopMost = $true; FormBorderStyle = 'FixedDialog'
        MaximizeBox = $false; MinimizeBox = $false
    }
    $heading = [Windows.Forms.Label]@{ Text = 'Review this support task before it runs.'; Left = 20; Top = 18; Width = 510; Height = 28; Font = [Drawing.Font]::new($form.Font, [Drawing.FontStyle]::Bold) }
    $details = [Windows.Forms.TextBox]@{ Left = 20; Top = 55; Width = 510; Height = 225; Multiline = $true; ReadOnly = $true; ScrollBars = 'Vertical'; BackColor = [Drawing.SystemColors]::Window; Text = "Requester: $($summary.Requester)`r`nApplications: $($summary.Applications)`r`nSites: $($summary.Sites)`r`nData collected: $($summary.DataCollected)`r`nMaximum duration: $($summary.MaximumDuration)`r`n`r`nDinoSupport will only execute the signed task shown above. You can stop it at any time after approving." }
    $approve = [Windows.Forms.Button]@{ Text = 'Approve'; Left = 290; Top = 300; Width = 110; DialogResult = [Windows.Forms.DialogResult]::OK }
    $cancel = [Windows.Forms.Button]@{ Text = 'Cancel'; Left = 420; Top = 300; Width = 110; DialogResult = [Windows.Forms.DialogResult]::Cancel }
    $form.Controls.AddRange(@($heading, $details, $approve, $cancel)); $form.AcceptButton = $approve; $form.CancelButton = $cancel
    try { return $form.ShowDialog() -eq [Windows.Forms.DialogResult]::OK } finally { $form.Dispose() }
}

function New-DinoSupportStopControl {
    [CmdletBinding()]
    param()

    Initialize-DinoSupportForms
    $state = [pscustomobject]@{ StopRequested = $false }
    $form = [Windows.Forms.Form]@{ Text = 'DinoSupport running'; Width = 300; Height = 135; StartPosition = 'CenterScreen'; TopMost = $true; FormBorderStyle = 'FixedToolWindow'; ControlBox = $false }
    $label = [Windows.Forms.Label]@{ Text = 'Troubleshooting is in progress.'; Left = 18; Top = 15; Width = 250 }
    $stop = [Windows.Forms.Button]@{ Text = 'Stop immediately'; Left = 80; Top = 48; Width = 130 }
    $stop.Tag = $state
    $stop.Add_Click({ $this.Tag.StopRequested = $true; $this.Enabled = $false })
    $form.Controls.AddRange(@($label, $stop)); $form.Show()
    return [pscustomobject]@{ Form = $form; State = $state }
}

function Update-DinoSupportStopControl {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [object]$StopControl)

    [Windows.Forms.Application]::DoEvents()
    if ($StopControl.State.StopRequested) { throw 'DinoSupport execution was stopped by the user.' }
}

function Close-DinoSupportStopControl {
    [CmdletBinding()]
    param([object]$StopControl)

    if ($StopControl -and $StopControl.Form) { $StopControl.Form.Close(); $StopControl.Form.Dispose() }
}

Export-ModuleMember -Function Get-DinoSupportConsentSummary, Request-DinoSupportConsent, New-DinoSupportStopControl, Update-DinoSupportStopControl, Close-DinoSupportStopControl
