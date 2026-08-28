BeforeAll {
    Import-Module "$PSScriptRoot/../control-plane/ControlPlane.psm1" -Force
    Import-Module "$PSScriptRoot/../control-plane/GitHubSupportDesk.psm1" -Force
}

Describe 'DinoSupport GitHub Issues support-desk integration' {
    BeforeEach {
        $controlPlane = New-DinoSupportControlPlane
        $token = ConvertTo-SecureString 'test-token' -AsPlainText -Force
        $script:requests = @()
        Mock Invoke-RestMethod {
            param($Method, $Uri, $Headers, $Body)
            $script:requests += [pscustomobject]@{ Method = $Method; Uri = $Uri; Body = $Body; Headers = $Headers }
            if ($Method -eq 'GET') { return [pscustomobject]@{ state = 'open'; number = 42 } }
            return [pscustomobject]@{ id = 1 }
        } -ModuleName GitHubSupportDesk
    }
    AfterEach { Remove-DinoSupportControlPlane $controlPlane }

    It 'creates a one-time task from an open issue and posts only an audit summary' {
        $issued = New-DinoSupportGitHubIssueTask -ControlPlane $controlPlane -Owner 'Dyno-man' -Repository 'DinoSupport' -IssueNumber 42 -GitHubToken $token -AllowedApps Chrome -AllowedDomains example.com -Url 'https://example.com/help' -ExpiresAtUtc ([datetime]::UtcNow.AddMinutes(5))
        $manifest = Get-DinoSupportCloudTask $controlPlane $issued.taskId $issued.fetchToken
        $result = @{ schemaVersion = 2; status = 'completed'; taskId = $issued.taskId; consoleErrors = @('token=never-posted') }
        $receipt = Submit-DinoSupportGitHubIssueResult -ControlPlane $controlPlane -TaskId $issued.taskId -FetchToken $issued.fetchToken -Result $result -GitHubToken $token

        $script:requests.Count | Should -Be 2
        $script:requests[0].Uri | Should -Be 'https://api.github.com/repos/Dyno-man/DinoSupport/issues/42'
        $script:requests[1].Uri | Should -Be 'https://api.github.com/repos/Dyno-man/DinoSupport/issues/42/comments'
        $script:requests[1].Body | Should -Match $receipt.receipt.receiptId
        $script:requests[1].Body | Should -Not -Match 'never-posted'
        $script:requests[1].Headers.Authorization | Should -Be 'Bearer test-token'
    }

    It 'rejects pull requests and closed issues as support tickets' {
        Mock Invoke-RestMethod { [pscustomobject]@{ state = 'open'; pull_request = @{} } } -ModuleName GitHubSupportDesk
        { New-DinoSupportGitHubIssueTask -ControlPlane $controlPlane -Owner 'Dyno-man' -Repository 'DinoSupport' -IssueNumber 42 -GitHubToken $token -AllowedApps Chrome -AllowedDomains example.com -Url 'https://example.com/' -ExpiresAtUtc ([datetime]::UtcNow.AddMinutes(5)) } | Should -Throw '*not a pull request*'
    }

    It 'does not allow a non-GitHub task to post a ticket comment' {
        $issued = New-DinoSupportCloudTask -ControlPlane $controlPlane -Requester 'DinoSupport Support' -AllowedApps Chrome -AllowedDomains example.com -Url 'https://example.com/' -ExpiresAtUtc ([datetime]::UtcNow.AddMinutes(5))
        { Submit-DinoSupportGitHubIssueResult -ControlPlane $controlPlane -TaskId $issued.taskId -FetchToken $issued.fetchToken -Result @{ taskId = $issued.taskId; status = 'completed' } -GitHubToken $token } | Should -Throw '*not associated*'
    }
}
