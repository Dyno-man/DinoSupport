# DinoSupport

Temporary, consent-based endpoint automation for Tier 1 / Tier 2 support.

## Goal

A support engineer creates a tightly scoped task. The user runs DinoSupport, sees what it will do, approves it, and the agent:

1. Executes only the approved actions.
2. Reproduces the issue.
3. Collects requested evidence.
4. Uploads a structured result.
5. Removes temporary files and exits.

The first target workflow is deliberately narrow:

> Open Chrome or Edge → reproduce a web issue → capture console/network errors → return evidence to support.

## Local proof of concept

The current proof of concept implements the deterministic browser portion of that workflow: it opens Chrome or Edge with a temporary profile, navigates to one supplied URL, collects redacted console/network evidence, browser version data, and an execution trace, then writes a local JSON result. See [`runner/README.md`](runner/README.md) for the Windows command and constraints.

For one-time distribution on Windows, [`packaging/Build-DinoSupportPackage.ps1`](packaging/Build-DinoSupportPackage.ps1) produces a task-bound `.exe` that embeds the signed manifest, public key, and runner files. It extracts only to a fresh temporary directory, preserves the existing consent and stop controls, removes its temporary files, and leaves no service or active agent behind.

## Architecture

```text
Support Desk
   ↓
Signed task manifest
   ↓
Temporary endpoint runner
   ↓
User consent
   ↓
Deterministic browser/UI actions
   ↓
Evidence collection
   ↓
Encrypted upload
   ↓
Structured support result
   ↓
Cleanup + exit
```

### Minimal cloud control plane

The first control-plane implementation is a small in-memory PowerShell API that issues a signed one-time task, allows one authenticated fetch, accepts one bounded structured result, and produces an RS256-signed audit receipt. See [`control-plane/README.md`](control-plane/README.md). It deliberately has no listener, durable storage, authentication provider, or endpoint upload wiring yet.

### MVP principle

**Cloud = reasoning. Local runner = constrained executor.**

Do not ship a local LLM in the first version. Prove the endpoint workflow first, then benchmark whether a small local model adds enough value to justify its size and risk.

## Safety model

DinoSupport is intended for authorized troubleshooting only.

- Explicit user consent before execution
- Signed, expiring task manifests
- Domain/app allowlists
- No persistence or startup registration
- No arbitrary shell execution from remote instructions
- Least privilege
- Visible stop/kill control
- Maximum runtime
- Evidence redaction before upload
- Full task/result audit record
- Fail closed on invalid or expired tasks

## Roadmap

See [`PLAN.md`](PLAN.md).

The project is intentionally built one small issue at a time so an automated coding agent can safely make incremental progress.

## License

MIT. See [`LICENSE`](LICENSE).
