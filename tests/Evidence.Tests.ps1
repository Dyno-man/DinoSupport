BeforeAll {
    Import-Module "$PSScriptRoot/../runner/Evidence.psm1" -Force
}

Describe 'Protect-DinoSupportEvidence' {
    It 'redacts sensitive object properties' {
        $actual = Protect-DinoSupportEvidence ([ordered]@{ authorization = 'Bearer abc'; Cookie = 'sid=abc'; safe = 'ok' })
        $actual.authorization | Should -Be '[REDACTED]'
        $actual.Cookie | Should -Be '[REDACTED]'
        $actual.safe | Should -Be 'ok'
    }

    It 'redacts token and password values embedded in text and URLs' {
        $actual = Protect-DinoSupportEvidence 'https://example.test/?access_token=abc123&mode=debug password=hunter2'
        $actual | Should -Not -Match 'abc123|hunter2'
        $actual | Should -Match 'access_token=\[REDACTED\]'
    }

    It 'redacts values when whitespace surrounds a sensitive separator' {
        $actual = Protect-DinoSupportEvidence 'Authorization : Bearer abc123'
        $actual | Should -Not -Match 'abc123'
        $actual | Should -Be 'Authorization : [REDACTED]'
    }

    It 'redacts nested values without changing non-sensitive evidence' {
        $actual = Protect-DinoSupportEvidence @([ordered]@{ url = 'https://test/?token=abc'; status = 500 })
        $actual[0].url | Should -Not -Match 'abc'
        $actual[0].status | Should -Be 500
    }
}
