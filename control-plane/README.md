# DinoSupport minimal cloud control plane

This dependency-free PowerShell module is the MVP service boundary for one-time support tasks. It is intentionally in-memory: a process restart deletes task state, results, and signing keys. That avoids introducing persistence before the security and retention model is designed.

The support side calls `New-DinoSupportCloudTask`, then gives the endpoint runner the returned task ID, one-time capability token, signed task envelope, and public key. The endpoint fetches exactly one signed task with `Get-DinoSupportCloudTask` and uploads exactly one structured result through `Submit-DinoSupportCloudResult`. The control plane validates the capability, task ID, lifecycle, status, and a 1 MiB result limit; it then returns and stores an RS256-signed audit receipt containing a result SHA-256 hash.

The module is an embeddable API surface, not a network listener. Deploying an authenticated HTTPS transport, durable encrypted storage, caller identity, rate limiting, retention/deletion, and runner upload wiring are deliberately deferred.

## GitHub Issues support-desk integration

`GitHubSupportDesk.psm1` provides the first support-desk adapter. An operator supplies a GitHub fine-grained token with **Issues: read and write** access to one repository, creates a task from one open GitHub Issue, gives the returned one-time task bundle to the endpoint through the approved task-delivery channel, and submits the runner result through `Submit-DinoSupportGitHubIssueResult`.

The adapter verifies that the ticket is an open Issue (not a pull request), binds the task to that ticket in the in-memory control plane, and posts only status, receipt ID, and the result hash back to the Issue. It never posts the evidence payload or stores the GitHub token. The control-plane process must remain available until the result is submitted; durable delivery, authentication, and retry/retention policies remain deliberately out of scope.

Run the tests on Windows with Pester:

```powershell
Invoke-Pester ./tests/ControlPlane.Tests.ps1
Invoke-Pester ./tests/GitHubSupportDesk.Tests.ps1
```
