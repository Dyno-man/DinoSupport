$scriptPath = Join-Path $PSScriptRoot '..' 'packaging' 'Build-DinoSupportPackage.ps1'
$script = Get-Content -LiteralPath $scriptPath -Raw -Encoding UTF8

Describe 'DinoSupport temporary package' {
    It 'embeds only the approved runner inputs' {
        $script | Should -Match "\$runnerFiles = @\('DinoSupport.ps1', 'Consent.psm1', 'Evidence.psm1', 'TaskManifest.psm1'\)"
        $script | Should -Match "'task.json'"
        $script | Should -Match "'support-public-key.xml'"
    }

    It 'uses a fresh temporary directory and deletes it on exit' {
        $script | Should -Match 'DinoSupport-package-'
        $script | Should -Match 'DinoSupport-" \+ Guid.NewGuid'
        $script | Should -Match 'Directory.Delete\(temporaryDirectory, true\)'
        $script | Should -Match 'DinoSupport cleanup needed'
    }

    It 'does not allow task input through launcher command-line arguments' {
        $script | Should -Match '-ManifestPath \\"" \+ manifest'
        $script | Should -Match '-PublicKeyPath \\"" \+ publicKey'
        $script | Should -Not -Match 'ExecutionPolicy Bypass'
    }
}
