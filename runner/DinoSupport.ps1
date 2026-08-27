[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ManifestPath,

    [Parameter(Mandatory)]
    [string]$PublicKeyPath,

    [string]$OutputPath = (Join-Path (Get-Location) 'dinosupport-result.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'TaskManifest.psm1') -Force

function Find-Browser([string]$RequestedBrowser) {
    $candidates = if ($RequestedBrowser -eq 'Chrome') {
        @(
            (Join-Path $env:ProgramFiles 'Google\\Chrome\\Application\\chrome.exe'),
            (Join-Path ${env:ProgramFiles(x86)} 'Google\\Chrome\\Application\\chrome.exe'),
            (Join-Path $env:LOCALAPPDATA 'Google\\Chrome\\Application\\chrome.exe')
        )
    } else {
        @(
            (Join-Path $env:ProgramFiles 'Microsoft\\Edge\\Application\\msedge.exe'),
            (Join-Path ${env:ProgramFiles(x86)} 'Microsoft\\Edge\\Application\\msedge.exe'),
            (Join-Path $env:LOCALAPPDATA 'Microsoft\\Edge\\Application\\msedge.exe')
        )
    }

    return $candidates | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
}

function Get-FreeTcpPort {
    $listener = [System.Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
    $listener.Start()
    $port = ([Net.IPEndPoint]$listener.LocalEndpoint).Port
    $listener.Stop()
    return $port
}

function Receive-CdpMessage([System.Net.WebSockets.ClientWebSocket]$Socket, [int]$TimeoutMs) {
    $buffer = New-Object byte[] 65536
    $segment = [ArraySegment[byte]]::new($buffer)
    $task = $Socket.ReceiveAsync($segment, [Threading.CancellationToken]::None)
    if (-not $task.Wait($TimeoutMs)) { return $null }
    $result = $task.Result
    if ($result.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) { throw 'Browser closed the DevTools connection.' }
    return ([Text.Encoding]::UTF8.GetString($buffer, 0, $result.Count) | ConvertFrom-Json)
}

function Send-CdpCommand([System.Net.WebSockets.ClientWebSocket]$Socket, [int]$Id, [string]$Method, [hashtable]$Params, [System.Collections.ArrayList]$Events) {
    $message = @{ id = $Id; method = $Method; params = $Params } | ConvertTo-Json -Compress -Depth 10
    $bytes = [Text.Encoding]::UTF8.GetBytes($message)
    $Socket.SendAsync([ArraySegment[byte]]::new($bytes), [System.Net.WebSockets.WebSocketMessageType]::Text, $true, [Threading.CancellationToken]::None).GetAwaiter().GetResult()
    do {
        $reply = Receive-CdpMessage $Socket 5000
        if ($null -eq $reply) { throw "Timed out waiting for CDP response to $Method." }
        if ($reply.PSObject.Properties.Name -contains 'method') { [void]$Events.Add($reply) }
    } while ($reply.id -ne $Id)
    if ($reply.PSObject.Properties.Name -contains 'error') { throw "CDP $Method failed: $($reply.error.message)" }
    return $reply
}

$task = $null
$task = Read-DinoSupportTaskManifest -ManifestPath $ManifestPath -PublicKeyPath $PublicKeyPath
$Browser = @($task.AllowedApps)[0]
$Url = $task.Url
$executionDeadline = (Get-Date).AddSeconds($task.MaxRuntimeSeconds)

$browserExe = Find-Browser $Browser
if (-not $browserExe) { throw "$Browser was not found in a standard installation location." }

$port = Get-FreeTcpPort
$profileDirectory = Join-Path ([IO.Path]::GetTempPath()) ("DinoSupport-" + [guid]::NewGuid())
$events = [System.Collections.ArrayList]::new()
$consoleErrors = [System.Collections.ArrayList]::new()
$browserProcess = $null
$socket = [System.Net.WebSockets.ClientWebSocket]::new()

try {
    $browserProcess = Start-Process -FilePath $browserExe -ArgumentList @("--remote-debugging-port=$port", "--user-data-dir=$profileDirectory", '--no-first-run', '--no-default-browser-check', 'about:blank') -PassThru
    $deadline = (Get-Date).AddSeconds(15)
    if ($deadline -gt $executionDeadline) { $deadline = $executionDeadline }
    do {
        try { $targets = Invoke-RestMethod -Uri "http://127.0.0.1:$port/json/list" -TimeoutSec 2 } catch { Start-Sleep -Milliseconds 250; continue }
        $page = $targets | Where-Object { $_.type -eq 'page' } | Select-Object -First 1
        if ($page) { break }
    } while ((Get-Date) -lt $deadline)
    if (-not $page) { throw 'DevTools endpoint did not become available within 15 seconds.' }

    $socket.ConnectAsync([uri]$page.webSocketDebuggerUrl, [Threading.CancellationToken]::None).GetAwaiter().GetResult()
    $id = 1
    Send-CdpCommand $socket $id 'Runtime.enable' @{} $events | Out-Null; $id++
    Send-CdpCommand $socket $id 'Log.enable' @{} $events | Out-Null; $id++
    Send-CdpCommand $socket $id 'Page.enable' @{} $events | Out-Null; $id++
    Send-CdpCommand $socket $id 'Page.navigate' @{ url = $Url } $events | Out-Null

    $captureUntil = $executionDeadline
    while ((Get-Date) -lt $captureUntil) {
        $event = Receive-CdpMessage $socket 250
        if ($null -eq $event) { continue }
        if ($event.method -eq 'Runtime.exceptionThrown') {
            [void]$consoleErrors.Add([ordered]@{ kind = 'exception'; text = $event.params.exceptionDetails.text; url = $event.params.exceptionDetails.url; line = $event.params.exceptionDetails.lineNumber; column = $event.params.exceptionDetails.columnNumber })
        } elseif ($event.method -eq 'Log.entryAdded' -and $event.params.entry.level -in @('error', 'warning')) {
            [void]$consoleErrors.Add([ordered]@{ kind = $event.params.entry.level; text = $event.params.entry.text; url = $event.params.entry.url; line = $event.params.entry.lineNumber })
        }
    }

    $result = [ordered]@{
        schemaVersion = 1
        status = 'completed'
        taskId = $task.TaskId
        browser = $Browser
        browserPath = $browserExe
        requestedUrl = $Url
        startedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
        maxRuntimeSeconds = $task.MaxRuntimeSeconds
        consoleErrors = @($consoleErrors)
    }
} catch {
    $result = [ordered]@{
        schemaVersion = 1
        status = 'failed'
        taskId = if ($task) { $task.TaskId } else { $null }
        browser = $Browser
        requestedUrl = $Url
        error = $_.Exception.Message
        failedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
        consoleErrors = @($consoleErrors)
    }
} finally {
    if ($socket) { $socket.Dispose() }
    if ($browserProcess -and -not $browserProcess.HasExited) { Stop-Process -Id $browserProcess.Id -Force }
    if (Test-Path -LiteralPath $profileDirectory) { Remove-Item -LiteralPath $profileDirectory -Recurse -Force }
}

$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
if ($result.status -ne 'completed') { exit 1 }
