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

The current proof of concept implements the deterministic browser portion of that workflow: it opens Chrome or Edge with a temporary profile, navigates to one supplied URL, collects console exceptions and browser log errors, then writes a local JSON result. See [`runner/README.md`](runner/README.md) for the Windows command and constraints.

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
