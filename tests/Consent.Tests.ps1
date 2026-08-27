$module = Join-Path $PSScriptRoot '..' 'runner' 'Consent.psm1'
Import-Module $module -Force

Describe 'Get-DinoSupportConsentSummary' {
    It 'shows only manifest-derived task details before approval' {
        $task = [pscustomobject]@{ Requester = 'DinoSupport Support'; AllowedApps = @('Chrome', 'Edge'); AllowedDomains = @('example.com'); RequestedEvidence = @('consoleErrors'); MaxRuntimeSeconds = 45 }

        $summary = Get-DinoSupportConsentSummary $task

        $summary.Requester | Should -Be 'DinoSupport Support'
        $summary.Applications | Should -Be 'Chrome, Edge'
        $summary.Sites | Should -Be 'example.com'
        $summary.DataCollected | Should -Be 'consoleErrors'
        $summary.MaximumDuration | Should -Be '45 seconds'
    }
}
