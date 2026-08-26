# AGENTS.md

## Working rule

Implement **one GitHub issue at a time**.

Do not jump ahead to later phases unless the current issue explicitly requires it.

## Priorities

1. Correctness
2. Safety / least privilege
3. Small executable and dependency footprint
4. Testability
5. Simplicity

## Guardrails

- No persistence mechanisms.
- No startup registration.
- No credential harvesting.
- No unrestricted remote shell.
- No silent execution.
- No bypass of the task manifest.
- User must be able to stop execution.
- Prefer deterministic APIs / browser automation over visual clicking when possible.
- Keep cloud reasoning separate from endpoint execution in the MVP.

## PR expectations

Every implementation PR should include:
- What changed
- How it was tested
- Security implications
- Remaining limitations

Do not close an issue unless its exit criteria are met.
