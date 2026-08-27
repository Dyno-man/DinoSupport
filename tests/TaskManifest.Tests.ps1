$module = Join-Path $PSScriptRoot '..' 'runner' 'TaskManifest.psm1'
Import-Module $module -Force

Describe 'Read-DinoSupportTaskManifest' {
    BeforeAll {
        $rsa = [Security.Cryptography.RSACryptoServiceProvider]::new(2048)
        $keyPath = Join-Path $TestDrive 'public.xml'
        $rsa.ToXmlString($false) | Set-Content -LiteralPath $keyPath -Encoding UTF8
        function New-Manifest([hashtable]$Task, [switch]$Tamper) {
            $payload = [Text.Encoding]::UTF8.GetBytes(($Task | ConvertTo-Json -Compress -Depth 5))
            $signature = $rsa.SignData($payload, 'SHA256')
            if ($Tamper) { $payload[0] = $payload[0] -bxor 1 }
            @{ schemaVersion = 1; payload = [Convert]::ToBase64String($payload); signature = @{ algorithm = 'RS256'; value = [Convert]::ToBase64String($signature) } } | ConvertTo-Json -Compress -Depth 5
        }
        $validTask = @{ taskId = '4e0f3182-8aa1-43b7-a980-6e4e1f2d0fe5'; allowedApps = @('Chrome'); allowedDomains = @('example.com'); actions = @(@{ type = 'navigate'; url = 'https://example.com/help' }); requestedEvidence = @('consoleErrors'); expiresAtUtc = '2030-01-01T00:00:00Z'; maxRuntimeSeconds = 10; uploadDestinationId = 'ticket-123' }
    }
    AfterAll { $rsa.Dispose() }
    It 'accepts a valid signed in-scope manifest' {
        $path = Join-Path $TestDrive 'valid.json'; New-Manifest $validTask | Set-Content $path
        $task = Read-DinoSupportTaskManifest $path $keyPath ([datetime]'2029-01-01T00:00:00Z')
        $task.Url | Should -Be 'https://example.com/help'
    }
    It 'rejects an invalid signature' {
        $path = Join-Path $TestDrive 'tampered.json'; New-Manifest $validTask -Tamper | Set-Content $path
        { Read-DinoSupportTaskManifest $path $keyPath } | Should -Throw '*signature is invalid*'
    }
    It 'rejects unsigned and malformed envelopes' {
        $unsignedPath = Join-Path $TestDrive 'unsigned.json'
        @{ schemaVersion = 1; payload = 'e30=' } | ConvertTo-Json -Compress | Set-Content $unsignedPath
        { Read-DinoSupportTaskManifest $unsignedPath $keyPath } | Should -Throw

        $malformedPath = Join-Path $TestDrive 'malformed.json'
        $task = @{} + $validTask; $task.extra = 'not permitted'
        New-Manifest $task | Set-Content $malformedPath
        { Read-DinoSupportTaskManifest $malformedPath $keyPath } | Should -Throw '*missing or unsupported fields*'
    }
    It 'rejects expired, out-of-scope, and unsupported-evidence manifests' {
        $cases = @(
            @{ expiresAtUtc = '2020-01-01T00:00:00Z' },
            @{ actions = @(@{ type = 'navigate'; url = 'https://not-example.com/' }) },
            @{ requestedEvidence = @('screenshot') }
        )
        foreach ($change in $cases) {
            $task = @{} + $validTask; foreach ($name in $change.Keys) { $task[$name] = $change[$name] }
            $path = Join-Path $TestDrive ([guid]::NewGuid().ToString() + '.json'); New-Manifest $task | Set-Content $path
            { Read-DinoSupportTaskManifest $path $keyPath ([datetime]'2029-01-01T00:00:00Z') } | Should -Throw
        }
    }
}
