Set-StrictMode -Version Latest

$script:ManifestFields = @('taskId', 'allowedApps', 'allowedDomains', 'actions', 'requestedEvidence', 'expiresAtUtc', 'maxRuntimeSeconds', 'uploadDestinationId')

function Get-ObjectPropertyNames([object]$Object) {
    return @($Object.PSObject.Properties | ForEach-Object { $_.Name })
}

function Assert-ExactFields([object]$Object, [string[]]$Expected, [string]$Context) {
    if ($null -eq $Object) { throw "$Context is required." }
    $actual = Get-ObjectPropertyNames $Object
    $unexpected = @($actual | Where-Object { $_ -notin $Expected })
    $missing = @($Expected | Where-Object { $_ -notin $actual })
    if ($unexpected.Count -or $missing.Count) { throw "$Context has missing or unsupported fields." }
}

function Assert-StringArray([object]$Value, [string]$Name) {
    $items = @($Value)
    if ($items.Count -eq 0 -or @($items | Where-Object { $_ -isnot [string] -or [string]::IsNullOrWhiteSpace($_) }).Count) {
        throw "$Name must be a non-empty array of strings."
    }
    return $items
}

function Test-AllowedDomain([uri]$Uri, [string[]]$AllowedDomains) {
    if ($Uri.Scheme -notin @('http', 'https')) { return $false }
    $host = $Uri.Host.TrimEnd('.').ToLowerInvariant()
    return @($AllowedDomains | Where-Object { $host -eq $_.Trim().TrimEnd('.').ToLowerInvariant() }).Count -gt 0
}

function Import-DinoSupportPublicKey([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw 'The manifest public-key file was not found.' }
    try { [xml]$xml = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 } catch { throw 'The manifest public key is not valid XML.' }
    if ($xml.DocumentElement.Name -ne 'RSAKeyValue') { throw 'The manifest public key must be an RSAKeyValue XML public key.' }
    $modulus = $xml.RSAKeyValue.Modulus
    $exponent = $xml.RSAKeyValue.Exponent
    if ([string]::IsNullOrWhiteSpace($modulus) -or [string]::IsNullOrWhiteSpace($exponent)) { throw 'The manifest public key is incomplete.' }
    $rsa = [Security.Cryptography.RSACryptoServiceProvider]::new()
    try { $rsa.FromXmlString($xml.OuterXml) } catch { $rsa.Dispose(); throw 'The manifest public key could not be imported.' }
    return $rsa
}

function Read-DinoSupportTaskManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$ManifestPath,
        [Parameter(Mandatory)] [string]$PublicKeyPath,
        [datetime]$NowUtc = ([datetime]::UtcNow)
    )

    if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) { throw 'The task manifest file was not found.' }
    try { $envelope = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { throw 'The task manifest is not valid JSON.' }
    Assert-ExactFields $envelope @('schemaVersion', 'payload', 'signature') 'Manifest envelope'
    if ($envelope.schemaVersion -ne 1 -or $envelope.payload -isnot [string] -or [string]::IsNullOrWhiteSpace($envelope.payload)) { throw 'The manifest envelope is malformed.' }
    Assert-ExactFields $envelope.signature @('algorithm', 'value') 'Manifest signature'
    if ($envelope.signature.algorithm -ne 'RS256' -or $envelope.signature.value -isnot [string]) { throw 'The manifest signature is unsupported.' }
    try { $payloadBytes = [Convert]::FromBase64String($envelope.payload); $signatureBytes = [Convert]::FromBase64String($envelope.signature.value) } catch { throw 'The manifest payload or signature is not valid base64.' }
    $rsa = Import-DinoSupportPublicKey $PublicKeyPath
    try { $isValid = $rsa.VerifyData($payloadBytes, 'SHA256', $signatureBytes) } finally { $rsa.Dispose() }
    if (-not $isValid) { throw 'The task manifest signature is invalid.' }
    try { $task = [Text.Encoding]::UTF8.GetString($payloadBytes) | ConvertFrom-Json } catch { throw 'The signed manifest payload is not valid JSON.' }
    Assert-ExactFields $task $script:ManifestFields 'Task manifest payload'

    $taskId = [guid]::Empty
    if (-not [guid]::TryParse([string]$task.taskId, [ref]$taskId)) { throw 'taskId must be a UUID.' }
    $apps = Assert-StringArray $task.allowedApps 'allowedApps'
    if (@($apps | Where-Object { $_ -notin @('Chrome', 'Edge') }).Count) { throw 'The task requests an unsupported application.' }
    $domains = Assert-StringArray $task.allowedDomains 'allowedDomains'
    if (@($domains | Where-Object { $_ -notmatch '^(?=.{1,253}$)([A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}$' }).Count) { throw 'allowedDomains contains an invalid domain.' }
    $evidence = Assert-StringArray $task.requestedEvidence 'requestedEvidence'
    if (@($evidence | Where-Object { $_ -notin @('consoleErrors') }).Count) { throw 'The task requests unsupported evidence.' }
    if ($task.actions -is [string] -or @($task.actions).Count -ne 1) { throw 'This runner requires exactly one ordered navigate action.' }
    $action = @($task.actions)[0]
    Assert-ExactFields $action @('type', 'url') 'Task action'
    $uri = $null
    if ($action.type -ne 'navigate' -or -not [uri]::TryCreate([string]$action.url, [UriKind]::Absolute, [ref]$uri)) { throw 'The task action is malformed.' }
    if (-not (Test-AllowedDomain $uri $domains)) { throw 'The task action URL is outside allowedDomains.' }
    try { $expiresAtUtc = [datetime]::Parse([string]$task.expiresAtUtc).ToUniversalTime() } catch { throw 'expiresAtUtc is invalid.' }
    if ($expiresAtUtc -le $NowUtc.ToUniversalTime()) { throw 'The task manifest has expired.' }
    $maxRuntime = 0
    if (-not [int]::TryParse([string]$task.maxRuntimeSeconds, [ref]$maxRuntime) -or $maxRuntime -lt 1 -or $maxRuntime -gt 120) { throw 'maxRuntimeSeconds must be between 1 and 120.' }
    if ($task.uploadDestinationId -isnot [string] -or [string]::IsNullOrWhiteSpace($task.uploadDestinationId) -or $task.uploadDestinationId.Length -gt 128) { throw 'uploadDestinationId is invalid.' }

    return [pscustomobject]@{ TaskId = $taskId.ToString(); AllowedApps = $apps; AllowedDomains = $domains; Url = $uri.AbsoluteUri; RequestedEvidence = $evidence; ExpiresAtUtc = $expiresAtUtc; MaxRuntimeSeconds = $maxRuntime; UploadDestinationId = $task.uploadDestinationId }
}

Export-ModuleMember -Function Read-DinoSupportTaskManifest
