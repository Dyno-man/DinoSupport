# DinoSupport browser proof of concept

This Windows-only script executes a fixed, visible browser recipe:

1. Start Chrome or Edge with a temporary profile.
2. Navigate to one explicitly supplied `http` or `https` URL.
3. Capture browser console exceptions plus DevTools log errors/warnings for a bounded interval.
4. Write a structured JSON result locally, terminate the launched browser, and delete the temporary profile.

It has no cloud service, local model, persistence, startup registration, credential access, arbitrary shell execution, or remote-control capability.

## Prerequisites

- Windows PowerShell 5.1 or PowerShell 7
- Google Chrome or Microsoft Edge installed in a standard location

## Run

From PowerShell, run:

```powershell
./runner/DinoSupport.ps1 -Browser Chrome -Url 'https://example.com' -CaptureSeconds 10 -OutputPath ./result.json
```

To use Edge, pass `-Browser Edge`. `CaptureSeconds` is restricted to 1–120 seconds. The URL parameter accepts only `http://` and `https://` URLs.

After the browser is launched, the process exits non-zero on failure and writes a result JSON document with `status`, timestamps, the requested URL, and any errors captured before the failure.

## Result shape

```json
{
  "schemaVersion": 1,
  "status": "completed",
  "browser": "Chrome",
  "requestedUrl": "https://example.com",
  "captureSeconds": 10,
  "consoleErrors": []
}
```

`consoleErrors` contains only browser exceptions and DevTools log entries at warning/error level. This proof of concept does not collect network events, screenshots, cookies, form values, browser history, or credentials.
