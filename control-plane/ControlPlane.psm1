Set-StrictMode -Version Latest

function ConvertTo-DinoSupportSha256Hex([byte[]]$Bytes) {
    return ([BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant()
}

function Test-DinoSupportSecret([string]$ExpectedHash, [string]$PresentedSecret) {
    if ([string]::IsNullOrWhiteSpace($PresentedSecret)) { return $false }
    $actual = [Text.Encoding]::UTF8.GetBytes((ConvertTo-DinoSupportSha256Hex ([Text.Encoding]::UTF8.GetBytes($PresentedSecret))))
    $expected = [Text.Encoding]::UTF8.GetBytes($ExpectedHash)
    if ($actual.Length -ne $expected.Length) { return $false }
    # Windows PowerShell 5.1 targets .NET Framework, which lacks CryptographicOperations.
    $difference = 0
    for ($index = 0; $index -lt $actual.Length; $index++) { $difference = $difference -bor ($actual[$index] -bxor $expected[$index]) }
    return $difference -eq 0
}

function New-DinoSupportControlPlane {
    [CmdletBinding()]
    param()

    $rsa = [Security.Cryptography.RSACryptoServiceProvider]::new(2048)
    return [pscustomobject]@{
        SigningKey = $rsa
        PublicKeyXml = $rsa.ToXmlString($false)
        Tasks = [Collections.Generic.Dictionary[string, object]]::new()
        AuditReceipts = [Collections.Generic.Dictionary[string, object]]::new()
    }
}

function New-DinoSupportCloudTask {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object]$ControlPlane,
        [Parameter(Mandatory)] [string]$Requester,
        [Parameter(Mandatory)] [ValidateSet('Chrome', 'Edge')] [string[]]$AllowedApps,
        [Parameter(Mandatory)] [string[]]$AllowedDomains,
        [Parameter(Mandatory)] [uri]$Url,
        [Parameter(Mandatory)] [datetime]$ExpiresAtUtc,
        [ValidateRange(1, 120)] [int]$MaxRuntimeSeconds = 30,
        [string]$UploadDestinationId = 'dinosupport-control-plane'
    )

    if ([string]::IsNullOrWhiteSpace($Requester) -or $Requester.Length -gt 128) { throw 'requester is invalid.' }
    if ($ExpiresAtUtc.ToUniversalTime() -le [datetime]::UtcNow) { throw 'expiresAtUtc must be in the future.' }
    if ($Url.Scheme -notin @('http', 'https') -or $Url.Host -notin $AllowedDomains) { throw 'The URL must use an allowed http or https domain.' }
    if (@($AllowedDomains | Where-Object { $_ -notmatch '^(?=.{1,253}$)([A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}$' }).Count) { throw 'allowedDomains contains an invalid domain.' }

    $taskId = [guid]::NewGuid().ToString()
    $payload = [ordered]@{
        taskId = $taskId; requester = $Requester; allowedApps = @($AllowedApps); allowedDomains = @($AllowedDomains)
        actions = @([ordered]@{ type = 'navigate'; url = $Url.AbsoluteUri })
        requestedEvidence = @('consoleErrors'); expiresAtUtc = $ExpiresAtUtc.ToUniversalTime().ToString('o')
        maxRuntimeSeconds = $MaxRuntimeSeconds; uploadDestinationId = $UploadDestinationId
    }
    $payloadBytes = [Text.Encoding]::UTF8.GetBytes(($payload | ConvertTo-Json -Compress -Depth 8))
    $envelope = [ordered]@{
        schemaVersion = 1; payload = [Convert]::ToBase64String($payloadBytes)
        signature = [ordered]@{ algorithm = 'RS256'; value = [Convert]::ToBase64String($ControlPlane.SigningKey.SignData($payloadBytes, 'SHA256')) }
    }
    $fetchTokenBytes = New-Object byte[] 32
    [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($fetchTokenBytes)
    $fetchToken = [Convert]::ToBase64String($fetchTokenBytes)
    $ControlPlane.Tasks[$taskId] = [pscustomobject]@{
        FetchTokenHash = ConvertTo-DinoSupportSha256Hex ([Text.Encoding]::UTF8.GetBytes($fetchToken)); Envelope = $envelope
        ExpiresAtUtc = $ExpiresAtUtc.ToUniversalTime(); State = 'issued'; Result = $null; ReceiptId = $null
    }
    return [pscustomobject]@{ taskId = $taskId; fetchToken = $fetchToken; signedTask = $envelope; publicKeyXml = $ControlPlane.PublicKeyXml }
}

function Get-DinoSupportCloudTask {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [object]$ControlPlane, [Parameter(Mandatory)] [string]$TaskId, [Parameter(Mandatory)] [string]$FetchToken)
    if (-not $ControlPlane.Tasks.ContainsKey($TaskId)) { throw 'Task was not found.' }
    $task = $ControlPlane.Tasks[$TaskId]
    if (-not (Test-DinoSupportSecret $task.FetchTokenHash $FetchToken)) { throw 'Task capability is invalid.' }
    if ($task.ExpiresAtUtc -le [datetime]::UtcNow) { $task.State = 'expired'; throw 'Task has expired.' }
    if ($task.State -ne 'issued') { throw 'Task has already been fetched or completed.' }
    $task.State = 'fetched'
    return $task.Envelope
}

function Submit-DinoSupportCloudResult {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [object]$ControlPlane, [Parameter(Mandatory)] [string]$TaskId, [Parameter(Mandatory)] [string]$FetchToken, [Parameter(Mandatory)] [object]$Result)
    if (-not $ControlPlane.Tasks.ContainsKey($TaskId)) { throw 'Task was not found.' }
    $task = $ControlPlane.Tasks[$TaskId]
    if (-not (Test-DinoSupportSecret $task.FetchTokenHash $FetchToken)) { throw 'Task capability is invalid.' }
    if ($task.ExpiresAtUtc -le [datetime]::UtcNow) { $task.State = 'expired'; throw 'Task has expired.' }
    if ($task.State -ne 'fetched') { throw 'A result can only be uploaded once after the task is fetched.' }
    if ([string]$Result.taskId -ne $TaskId) { throw 'Result taskId does not match the issued task.' }
    if ([string]$Result.status -notin @('completed', 'failed', 'stopped', 'cancelled')) { throw 'Result status is unsupported.' }
    $serializedResult = $Result | ConvertTo-Json -Compress -Depth 16
    if ([Text.Encoding]::UTF8.GetByteCount($serializedResult) -gt 1048576) { throw 'Result exceeds the 1 MiB MVP limit.' }
    $receiptPayload = [ordered]@{ receiptId = [guid]::NewGuid().ToString(); taskId = $TaskId; status = [string]$Result.status; receivedAtUtc = [datetime]::UtcNow.ToString('o'); resultSha256 = ConvertTo-DinoSupportSha256Hex ([Text.Encoding]::UTF8.GetBytes($serializedResult)) }
    $receiptBytes = [Text.Encoding]::UTF8.GetBytes(($receiptPayload | ConvertTo-Json -Compress))
    $receipt = [ordered]@{ schemaVersion = 1; receipt = $receiptPayload; signature = [ordered]@{ algorithm = 'RS256'; value = [Convert]::ToBase64String($ControlPlane.SigningKey.SignData($receiptBytes, 'SHA256')) } }
    $task.Result = $Result; $task.ReceiptId = $receiptPayload.receiptId; $task.State = if ($Result.status -eq 'completed') { 'succeeded' } else { 'failed' }
    $ControlPlane.AuditReceipts[$receiptPayload.receiptId] = $receipt
    return $receipt
}

function Get-DinoSupportCloudAuditReceipt {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [object]$ControlPlane, [Parameter(Mandatory)] [string]$ReceiptId)
    if (-not $ControlPlane.AuditReceipts.ContainsKey($ReceiptId)) { throw 'Audit receipt was not found.' }
    return $ControlPlane.AuditReceipts[$ReceiptId]
}

function Remove-DinoSupportControlPlane {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [object]$ControlPlane)
    $ControlPlane.SigningKey.Dispose()
    $ControlPlane.Tasks.Clear()
    $ControlPlane.AuditReceipts.Clear()
}

Export-ModuleMember -Function New-DinoSupportControlPlane,New-DinoSupportCloudTask,Get-DinoSupportCloudTask,Submit-DinoSupportCloudResult,Get-DinoSupportCloudAuditReceipt,Remove-DinoSupportControlPlane
