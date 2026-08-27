# DinoSupport browser proof of concept

This Windows-only script executes only a signed task manifest for a fixed, visible browser recipe:

1. Start Chrome or Edge with a temporary profile.
2. Navigate to the one `http` or `https` URL permitted by the manifest.
3. Capture browser console exceptions plus DevTools log errors/warnings for a bounded interval.
4. Write a structured JSON result locally, terminate the launched browser, and delete the temporary profile.

It has no cloud service, local model, persistence, startup registration, credential access, arbitrary shell execution, or remote-control capability.

## Prerequisites

- Windows PowerShell 5.1 or PowerShell 7
- Google Chrome or Microsoft Edge installed in a standard location

## Run

From PowerShell, run:

```powershell
./runner/DinoSupport.ps1 -ManifestPath ./task.json -PublicKeyPath ./support-public-key.xml -OutputPath ./result.json
```

The runner never accepts a browser, URL, or duration as command-line task input. Those values must be in a signed manifest. It rejects unsigned, expired, malformed, unsupported, or out-of-scope tasks before launching a browser.

## Manifest format

The envelope is JSON with a base64-encoded UTF-8 JSON payload and an `RS256` signature over the decoded payload bytes. The public key is an RSA public-key XML file (`RSAKeyValue` containing `Modulus` and `Exponent`), which is supported by Windows PowerShell 5.1.

The signed payload has exactly these fields: `taskId` (UUID), `allowedApps` (`Chrome` and/or `Edge`), `allowedDomains` (exact hostnames), `actions` (exactly one `navigate` action with an `http`/`https` URL), `requestedEvidence` (currently only `consoleErrors`), `expiresAtUtc`, `maxRuntimeSeconds` (1–120), and `uploadDestinationId`. Unknown fields are rejected.

After the browser is launched, the process exits non-zero on failure and writes a result JSON document with `status`, timestamps, the requested URL, and any errors captured before the failure.

## Result shape

```json
{
  "schemaVersion": 1,
  "status": "completed",
  "browser": "Chrome",
  "requestedUrl": "https://example.com",
  "maxRuntimeSeconds": 10,
  "consoleErrors": []
}
```

`consoleErrors` contains only browser exceptions and DevTools log entries at warning/error level. This proof of concept does not collect network events, screenshots, cookies, form values, browser history, or credentials.
