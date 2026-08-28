Set-StrictMode -Version Latest

function Assert-DinoSupportGitHubIdentifier([string]$Value, [string]$Name) {
    if ([string]::IsNullOrWhiteSpace($Value) -or $Value -notmatch '^[A-Za-z0-9](?:[A-Za-z0-9-]{0,37}[A-Za-z0-9])?$') {
        throw "$Name is invalid."
    }
}

function ConvertFrom-DinoSupportSecureString([securestring]$Value) {
    $pointer = [IntPtr]::Zero
    try {
        $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Value)
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    } finally {
        if ($pointer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
    }
}

function Invoke-DinoSupportGitHubApi {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [ValidateSet('GET', 'POST')] [string]$Method,
        [Parameter(Mandatory)] [string]$Owner,
        [Parameter(Mandatory)] [string]$Repository,
        [Parameter(Mandatory)] [securestring]$Token,
        [Parameter(Mandatory)] [string]$Path,
        [object]$Body
    )

    Assert-DinoSupportGitHubIdentifier $Owner 'GitHub owner'
    Assert-DinoSupportGitHubIdentifier $Repository 'GitHub repository'
    $plainToken = ConvertFrom-DinoSupportSecureString $Token
    if ([string]::IsNullOrWhiteSpace($plainToken)) { throw 'GitHub token is required.' }
    try {
        $parameters = @{
            Method = $Method
            Uri = "https://api.github.com/repos/$Owner/$Repository$Path"
            Headers = @{ Accept = 'application/vnd.github+json'; Authorization = "Bearer $plainToken"; 'X-GitHub-Api-Version' = '2022-11-28'; 'User-Agent' = 'DinoSupport' }
            ErrorAction = 'Stop'
        }
        if ($Method -eq 'POST') {
            $parameters.ContentType = 'application/json'
            $parameters.Body = $Body | ConvertTo-Json -Compress -Depth 8
        }
        return Invoke-RestMethod @parameters
    } finally {
        $plainToken = $null
    }
}

function New-DinoSupportGitHubIssueTask {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object]$ControlPlane,
        [Parameter(Mandatory)] [string]$Owner,
        [Parameter(Mandatory)] [string]$Repository,
        [Parameter(Mandatory)] [ValidateRange(1, [int]::MaxValue)] [int]$IssueNumber,
        [Parameter(Mandatory)] [securestring]$GitHubToken,
        [Parameter(Mandatory)] [ValidateSet('Chrome', 'Edge')] [string[]]$AllowedApps,
        [Parameter(Mandatory)] [string[]]$AllowedDomains,
        [Parameter(Mandatory)] [uri]$Url,
        [Parameter(Mandatory)] [datetime]$ExpiresAtUtc,
        [ValidateRange(1, 120)] [int]$MaxRuntimeSeconds = 30
    )

    $issue = Invoke-DinoSupportGitHubApi -Method GET -Owner $Owner -Repository $Repository -Token $GitHubToken -Path "/issues/$IssueNumber"
    if ($issue.PSObject.Properties.Name -contains 'pull_request') { throw 'GitHub support ticket must be an issue, not a pull request.' }
    if ([string]$issue.state -ne 'open') { throw 'GitHub support ticket must be open.' }

    $issued = New-DinoSupportCloudTask -ControlPlane $ControlPlane -Requester "GitHub issue #$IssueNumber" -AllowedApps $AllowedApps -AllowedDomains $AllowedDomains -Url $Url -ExpiresAtUtc $ExpiresAtUtc -MaxRuntimeSeconds $MaxRuntimeSeconds -UploadDestinationId 'github-issues'
    $ControlPlane.Tasks[$issued.taskId] | Add-Member -NotePropertyName SupportTicket -NotePropertyValue ([pscustomobject]@{ owner = $Owner; repository = $Repository; issueNumber = $IssueNumber })
    return $issued
}

function Submit-DinoSupportGitHubIssueResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object]$ControlPlane,
        [Parameter(Mandatory)] [string]$TaskId,
        [Parameter(Mandatory)] [string]$FetchToken,
        [Parameter(Mandatory)] [object]$Result,
        [Parameter(Mandatory)] [securestring]$GitHubToken
    )

    if (-not $ControlPlane.Tasks.ContainsKey($TaskId)) { throw 'Task was not found.' }
    $task = $ControlPlane.Tasks[$TaskId]
    if (-not ($task.PSObject.Properties.Name -contains 'SupportTicket')) { throw 'Task is not associated with a GitHub support ticket.' }
    $receipt = Submit-DinoSupportCloudResult -ControlPlane $ControlPlane -TaskId $TaskId -FetchToken $FetchToken -Result $Result
    $ticket = $task.SupportTicket
    $body = "DinoSupport task $TaskId $($receipt.receipt.status). Audit receipt: $($receipt.receipt.receiptId). Result SHA-256: $($receipt.receipt.resultSha256)"
    Invoke-DinoSupportGitHubApi -Method POST -Owner $ticket.owner -Repository $ticket.repository -Token $GitHubToken -Path "/issues/$($ticket.issueNumber)/comments" -Body @{ body = $body } | Out-Null
    return $receipt
}

Export-ModuleMember -Function New-DinoSupportGitHubIssueTask,Submit-DinoSupportGitHubIssueResult
