# DinoSupport constrained Windows runner

This Windows-only script executes only a signed task manifest for a fixed, visible browser recipe:

1. Start Chrome or Edge with a temporary profile.
2. Navigate to one explicitly supplied `http` or `https` URL.
3. Capture browser console exceptions, failed network requests, browser/version information, and an execution trace for a bounded interval.
4. Write a structured JSON result locally, terminate the launched browser, and delete the temporary profile.

It has no cloud service, local model, persistence, startup registration, credential access, arbitrary shell execution, or remote-control capability.

## Constrained native Windows automation

The only native recipe is `inspectNotepadWindow`: it visibly launches the Windows-built-in Notepad app, waits for the window through Windows UI Automation, records its window name and control type, and then terminates only the process it launched. It does not type text, read document contents, enumerate other windows, invoke a shell, or automate arbitrary applications. A valid native manifest must allow only `Notepad`, use the `local.native` scope, request `uiAutomationTrace`, and contain exactly that action. Consent, the maximum duration, visible stop button, evidence redaction, and result trace are shared with browser runs.

## Prerequisites

- Windows PowerShell 5.1 or PowerShell 7
- Google Chrome or Microsoft Edge installed in a standard location

## Run

From PowerShell, run:

```powershell
./runner/DinoSupport.ps1 -ManifestPath ./task.json -PublicKeyPath ./support-public-key.xml -CaptureScreenshot -OutputPath ./result.json
```

The runner never accepts a browser, URL, or duration as command-line task input. Those values must be in a signed manifest. It rejects unsigned, expired, malformed, unsupported, or out-of-scope tasks before launching a browser. Before launching, it shows the requester, allowed applications/sites, requested evidence, and maximum duration; the user must select **Approve**. Selecting **Cancel** writes a `cancelled` result and starts nothing. During execution, an always-visible **Stop immediately** button stops capture, terminates the launched browser, and deletes the temporary profile.

## One-task Windows executable

On Windows, support can create a single, task-bound executable from a signed manifest and its matching public key:

```powershell
./packaging/Build-DinoSupportPackage.ps1 -ManifestPath ./task.json -PublicKeyPath ./support-public-key.xml -OutputPath ./DinoSupport-task.exe
```

The resulting `.exe` embeds only the existing runner files, that manifest, and that public key. It accepts no task details as command-line input. When the user starts it, it extracts those files to a new temporary directory, opens the existing consent UI, runs the signed task, writes `DinoSupport-task.result.json` beside the executable, and removes the temporary directory before it exits. If Windows prevents temporary cleanup, it shows the exact directory to delete. The executable does not install a service, register startup, elevate privileges, or remain active after the task ends. The user should delete the downloaded executable and its result after support has received the result; the launcher deliberately does not attempt self-deletion because Windows may keep a running executable locked.

## Manifest format

The envelope is JSON with a base64-encoded UTF-8 JSON payload and an `RS256` signature over the decoded payload bytes. The public key is an RSA public-key XML file (`RSAKeyValue` containing `Modulus` and `Exponent`), which is supported by Windows PowerShell 5.1.

The signed payload has exactly these fields: `taskId` (UUID), `requester` (the support requester shown for approval), `allowedApps`, `allowedDomains`, `actions`, `requestedEvidence`, `expiresAtUtc`, `maxRuntimeSeconds` (1–120), and `uploadDestinationId`. Unknown fields are rejected. Browser manifests allow only Chrome/Edge, exact allowed hostnames, one `navigate` action with an `http`/`https` URL, and `consoleErrors`. Native manifests allow only the fixed Notepad recipe described above.

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

`consoleErrors` contains browser exceptions and DevTools log entries at warning/error level. `failedNetworkRequests` records only failed-load metadata; it deliberately excludes request and response headers and bodies. `browserVersion` and `executionTrace` make the bundle reproducible. `-CaptureScreenshot` is opt-in and embeds a PNG in the JSON bundle.

Before writing, DinoSupport redacts obvious credentials: authorization headers, cookies, passwords, API keys, and common token names (including matching URL query values). It does not collect request/response bodies, form values, browser history, or credentials.

## Tests

With [Pester](https://pester.dev/) installed, run:

```powershell
Invoke-Pester ./tests/Evidence.Tests.ps1
Invoke-Pester ./tests/Packaging.Tests.ps1
Invoke-Pester ./tests/TaskManifest.Tests.ps1
Invoke-Pester ./tests/NativeTaskManifest.Tests.ps1
```
