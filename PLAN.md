# DinoSupport Project Plan

## Product target

A temporary support runner that can execute a narrowly scoped troubleshooting task on a user's Windows computer, collect evidence, return it to support, and clean itself up.

## Build order

### Phase 0 — Research the executor
- Evaluate OpenAdapt and Microsoft UFO².
- Confirm license compatibility.
- Identify the smallest reusable computer-control pieces.
- Decide whether to vendor code, use as a dependency, or reimplement only required interfaces.

**Exit:** one documented executor choice.

### Phase 1 — Local proof of concept
- Windows only.
- Chrome + Edge.
- Deterministic task: open URL, perform predefined steps, capture browser console errors.
- No cloud backend.
- No LLM required.

**Exit:** local command completes the workflow and writes a structured JSON result.

### Phase 2 — Evidence collection
Collect only requested evidence:
- Browser console errors
- Failed network requests
- Browser/version information
- Optional screenshot
- Task execution trace

Add redaction for obvious secrets/tokens.

**Exit:** reproducible evidence bundle.

### Phase 3 — Task manifest
Define a signed task contract containing:
- Task ID
- Allowed applications
- Allowed domains
- Ordered actions
- Requested evidence
- Expiration
- Maximum runtime
- Upload destination identifier

Reject anything outside the contract.

**Exit:** runner can execute only validated manifests.

### Phase 4 — Consent + guardrails
Before execution, show the user:
- Who requested the task
- What applications/sites will be touched
- What data will be collected
- Maximum duration

Controls:
- Approve
- Cancel
- Stop immediately

**Exit:** no task can run without explicit consent.

### Phase 5 — Cloud control plane
Minimal API:
- Create one-time task
- Fetch signed task
- Upload structured results
- Mark success/failure
- Retain audit receipt

**Exit:** support can create a task and receive results remotely.

### Phase 6 — Temporary Windows runner
Package as a small Windows executable.

Requirements:
- No background service
- No startup registration
- No persistence
- Least privilege
- Automatic temp-file cleanup
- Remove runner after completion where technically reliable; otherwise clearly instruct deletion and ensure nothing remains active

**Exit:** user downloads one executable, completes one task, and no active agent remains.

### Phase 7 — Broader desktop control
Add narrowly approved Windows UI Automation support for native applications.

Do not add unrestricted desktop control.

**Exit:** predefined native-app troubleshooting tasks work with the same manifest/security model.

### Phase 8 — Local model experiment
Only after the deterministic runner works:
- Benchmark tiny local models against deterministic execution.
- Measure RAM, disk size, latency, success rate.
- Test 1B–3B-class models or smaller specialized alternatives.

Add a local model only if it materially improves task completion.

### Phase 9 — Support-desk integration
Target workflow:

```text
Ticket → support selects troubleshooting recipe → user gets one-time link → runner executes → evidence attaches to ticket → support reviews
```

Build integrations after the core protocol is stable.

## MVP success criteria

A Windows user can:
1. Download DinoSupport.
2. Review and approve a task.
3. Let it reproduce a defined Chrome/Edge issue.
4. Return console/network evidence.
5. Stop it at any time.
6. Finish with no persistent agent running.

## Non-goals for MVP

- General autonomous desktop assistant
- Unrestricted shell access
- Silent execution
- Persistence
- Credential collection
- Arbitrary remote-control sessions
- Training a custom model before the deterministic workflow works
