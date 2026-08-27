# DinoSupport minimal cloud control plane

This dependency-free PowerShell module is the MVP service boundary for one-time support tasks. It is intentionally in-memory: a process restart deletes task state, results, and signing keys. That avoids introducing persistence before the security and retention model is designed.

The support side calls `New-DinoSupportCloudTask`, then gives the endpoint runner the returned task ID, one-time capability token, signed task envelope, and public key. The endpoint fetches exactly one signed task with `Get-DinoSupportCloudTask` and uploads exactly one structured result through `Submit-DinoSupportCloudResult`. The control plane validates the capability, task ID, lifecycle, status, and a 1 MiB result limit; it then returns and stores an RS256-signed audit receipt containing a result SHA-256 hash.

The module is an embeddable API surface, not a network listener. Deploying an authenticated HTTPS transport, durable encrypted storage, caller identity, rate limiting, retention/deletion, and runner upload wiring are deliberately deferred.

Run the tests on Windows with Pester:

```powershell
Invoke-Pester ./tests/ControlPlane.Tests.ps1
```
