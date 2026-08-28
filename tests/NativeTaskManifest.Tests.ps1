$module = Join-Path $PSScriptRoot '..' 'runner' 'TaskManifest.psm1'
Import-Module $module -Force

Describe 'Native task manifest scope' {
    BeforeAll {
        $rsa = [Security.Cryptography.RSACryptoServiceProvider]::new(2048)
        $keyPath = Join-Path $TestDrive 'public.xml'
        $rsa.ToXmlString($false) | Set-Content -LiteralPath $keyPath -Encoding UTF8
        function New-NativeManifest([hashtable]$Task) {
            $payload = [Text.Encoding]::UTF8.GetBytes(($Task | ConvertTo-Json -Compress -Depth 5))
            @{ schemaVersion = 1; payload = [Convert]::ToBase64String($payload); signature = @{ algorithm = 'RS256'; value = [Convert]::ToBase64String($rsa.SignData($payload, 'SHA256')) } } | ConvertTo-Json -Compress -Depth 5
        }
        $nativeTask = @{ taskId = '4e0f3182-8aa1-43b7-a980-6e4e1f2d0fe5'; requester = 'DinoSupport Support'; allowedApps = @('Notepad'); allowedDomains = @('local.native'); actions = @(@{ type = 'inspectNotepadWindow' }); requestedEvidence = @('uiAutomationTrace'); expiresAtUtc = '2030-01-01T00:00:00Z'; maxRuntimeSeconds = 10; uploadDestinationId = 'ticket-123' }
    }
    AfterAll { $rsa.Dispose() }
    It 'accepts the fixed Notepad inspection recipe' {
        $path = Join-Path $TestDrive 'notepad.json'; New-NativeManifest $nativeTask | Set-Content $path
        $actual = Read-DinoSupportTaskManifest $path $keyPath ([datetime]'2029-01-01T00:00:00Z')
        $actual.ExecutorKind | Should -Be 'native'
        $actual.ActionType | Should -Be 'inspectNotepadWindow'
        $actual.Url | Should -BeNullOrEmpty
    }
    It 'rejects broadened native recipes' {
        foreach ($change in @(
            @{ allowedApps = @('Notepad', 'Chrome') },
            @{ requestedEvidence = @('consoleErrors') },
            @{ requestedEvidence = @('uiAutomationTrace', 'consoleErrors') },
            @{ actions = @(@{ type = 'inspectNotepadWindow'; text = 'untrusted input' }) }
        )) {
            $task = @{} + $nativeTask; foreach ($name in $change.Keys) { $task[$name] = $change[$name] }
            $path = Join-Path $TestDrive ([guid]::NewGuid().ToString() + '.json'); New-NativeManifest $task | Set-Content $path
            { Read-DinoSupportTaskManifest $path $keyPath ([datetime]'2029-01-01T00:00:00Z') } | Should -Throw
        }
    }
}
