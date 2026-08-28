# Local model benchmark decision

**Decision date:** 2026-08-28
**Phase covered:** Phase 8 local-model experiment

## Decision

Do **not** add a local model to DinoSupport.

The implemented runner accepts one signed, deterministic browser action: navigate to an allowlisted URL and collect bounded evidence. A local model cannot expand, repair, or reinterpret that action without becoming a second decision-maker on the endpoint. That would either provide no additional task-completion value or require broadening the signed manifest and local authority, neither of which is justified for the MVP.

No model package, model download, inference service, credential, startup registration, or model runtime is introduced by this decision.

## Baseline and measurement result

The current deterministic executor is the appropriate baseline for the supported task class:

| Measure | Deterministic runner | Local model addition | Decision impact |
| --- | --- | --- | --- |
| Task success rate | Defined by a signed `navigate` action and explicit failure outcomes | Cannot improve this action without selecting or altering endpoint actions | No demonstrated benefit |
| RAM | Existing PowerShell/browser process footprint only | Additional resident inference memory would be required while the task runs | Additional footprint without a supported use |
| Disk size | Runner and its task-bound package only | Model weights and inference runtime would add a large distributable asset | Conflicts with the small temporary-runner goal |
| Startup time | No model initialization | Model loading and warm-up would occur before or during a time-bounded task | Regresses task start |
| Latency | Authored actions use explicit bounded waits | Inference adds per-decision latency | No supported decision to offset it |

This is a scope-bound benchmark result, not a claim that all 1B–3B models are ineffective. The current task contract deliberately leaves a model no authorized choice to make, so the material improvement threshold cannot be met.

## Candidate scope considered

The evaluation considered the issue's requested classes:

- small general-purpose local models in the 1B–3B range; and
- smaller specialized alternatives, such as classifiers or extractors.

For the present manifest, a general-purpose model would only be able to suggest a different action, selector, URL, application, or evidence request. Each is outside the signed contract and must be rejected. A specialized model could classify already-collected evidence, but that is support-side reasoning and does not improve endpoint task completion. It belongs in the cloud control plane after its data-handling and evaluation requirements are defined.

## Reproducible admission gate for a future experiment

A future model experiment is permitted only after a new issue defines an explicitly authorized, deterministic fallback operation in the manifest. That issue must include a versioned, redacted test corpus and compare the candidate to the deterministic executor on the same Windows hardware and browser versions.

Record these measurements for every candidate and baseline run:

1. Peak process working set in MiB, measured from process launch through cleanup.
2. Model/runtime bytes added to the packaged artifact, excluding an already-required browser.
3. Cold startup time from user approval to the first authorized operation.
4. End-to-end task success rate, with success defined only by the manifest's expected observable result.
5. Per-task latency from the authorized fallback request to its completed or failed outcome.

Admit a model only if it satisfies all of the following:

- improves task success rate by at least 10 percentage points over the deterministic baseline on a held-out corpus of at least 100 tasks;
- does not cause any action, application, domain, evidence field, or runtime to exceed the signed manifest;
- preserves the existing visible consent and immediate-stop behavior;
- adds no persistence, background service, credential access, unrestricted shell, raw browser debugging interface, or network dependency; and
- fits the packaging, RAM, startup, and latency budgets defined in that future issue.

Until those conditions are met, the deterministic executor remains the shipped endpoint design. Any model-assisted evidence interpretation should run in the cloud control plane, not on the endpoint.

## Security implications

Keeping models out of the endpoint removes a substantial attack and review surface: model files, native inference dependencies, prompt-driven action selection, local data exposure to inference, and a second component that could attempt to exceed a signed task. The endpoint remains a constrained executor whose only behavior is validated manifest execution.

## Remaining limitations

This decision does not benchmark model quality on a new, approved fallback task because no such manifest capability or redacted task corpus exists. It should be revisited only through a scoped issue that supplies both and retains the current least-privilege controls.
