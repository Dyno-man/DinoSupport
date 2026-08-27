Set-StrictMode -Version Latest

function Protect-DinoSupportEvidence {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [object]$Value)

    $secretPattern = '(?i)((?:authorization|proxy-authorization|cookie|set-cookie|password|passwd|secret|api[_-]?key|access[_-]?token|refresh[_-]?token|id[_-]?token|token)\s*[=:]\s*)([^\s,;&"'']+)'
    $querySecretPattern = '(?i)([?&](?:authorization|password|secret|api[_-]?key|access[_-]?token|refresh[_-]?token|id[_-]?token|token)=)([^&#\s]+)'

    if ($Value -is [string]) {
        $redacted = [regex]::Replace($Value, $secretPattern, '$1[REDACTED]')
        # Preserve the key name in URL query strings while removing its value.
        return [regex]::Replace($redacted, $querySecretPattern, '$1[REDACTED]')
    }

    if ($Value -is [System.Collections.IDictionary]) {
        $copy = [ordered]@{}
        foreach ($key in $Value.Keys) {
            if ($key -match '(?i)authorization|cookie|password|secret|token|api[_-]?key') { $copy[$key] = '[REDACTED]' }
            else { $copy[$key] = Protect-DinoSupportEvidence $Value[$key] }
        }
        return $copy
    }

    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        return @($Value | ForEach-Object { Protect-DinoSupportEvidence $_ })
    }

    return $Value
}

Export-ModuleMember -Function Protect-DinoSupportEvidence
