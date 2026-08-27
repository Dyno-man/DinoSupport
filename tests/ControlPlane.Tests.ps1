BeforeAll { Import-Module "$PSScriptRoot/../control-plane/ControlPlane.psm1" -Force }

Describe 'DinoSupport minimal cloud control plane' {
    BeforeEach { $controlPlane = New-DinoSupportControlPlane }
    AfterEach { Remove-DinoSupportControlPlane $controlPlane }

    It 'issues one signed task and stores one verified result receipt' {
        $issued = New-DinoSupportCloudTask $controlPlane -Requester 'DinoSupport Support' -AllowedApps Chrome -AllowedDomains example.com -Url 'https://example.com/help' -ExpiresAtUtc ([datetime]::UtcNow.AddMinutes(5))
        $manifest = Get-DinoSupportCloudTask $controlPlane $issued.taskId $issued.fetchToken
        $manifest.signature.algorithm | Should -Be 'RS256'
        $result = [ordered]@{ schemaVersion = 2; status = 'completed'; taskId = $issued.taskId; consoleErrors = @() }
        $receipt = Submit-DinoSupportCloudResult $controlPlane $issued.taskId $issued.fetchToken $result
        $receipt.receipt.taskId | Should -Be $issued.taskId
        $receipt.receipt.status | Should -Be 'completed'
        (Get-DinoSupportCloudAuditReceipt $controlPlane $receipt.receipt.receiptId).signature.algorithm | Should -Be 'RS256'
        $receiptBytes = [Text.Encoding]::UTF8.GetBytes(($receipt.receipt | ConvertTo-Json -Compress))
        $controlPlane.SigningKey.VerifyData($receiptBytes, 'SHA256', [Convert]::FromBase64String($receipt.signature.value)) | Should -BeTrue
    }

    It 'rejects invalid capability, duplicate fetches, and result task mismatches' {
        $issued = New-DinoSupportCloudTask $controlPlane -Requester 'DinoSupport Support' -AllowedApps Chrome -AllowedDomains example.com -Url 'https://example.com/' -ExpiresAtUtc ([datetime]::UtcNow.AddMinutes(5))
        { Get-DinoSupportCloudTask $controlPlane $issued.taskId 'wrong' } | Should -Throw '*capability is invalid*'
        Get-DinoSupportCloudTask $controlPlane $issued.taskId $issued.fetchToken | Out-Null
        { Get-DinoSupportCloudTask $controlPlane $issued.taskId $issued.fetchToken } | Should -Throw '*already been fetched*'
        { Submit-DinoSupportCloudResult $controlPlane $issued.taskId $issued.fetchToken @{ taskId = [guid]::NewGuid().ToString(); status = 'completed' } } | Should -Throw '*does not match*'
    }
}
