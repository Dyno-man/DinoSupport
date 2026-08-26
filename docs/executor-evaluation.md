# Executor evaluation

**Decision date:** 2026-08-26  
**Phase covered:** Phase 1 local browser proof of concept

## Decision

Use **Microsoft Playwright through the `playwright-core` Node.js package as a pinned dependency**. Build a small DinoSupport-owned, deterministic recipe executor over its public API.

Do not vendor Playwright, OpenAdapt, or UFO². Do not reimplement the Chrome DevTools Protocol. Do not use a desktop/vision agent for Phase 1.

This is deliberately a browser-only choice. Native Windows UI Automation remains outside Phase 1 and requires a separate decision when Phase 7 begins.

## Phase 1 requirements

The executor must:

- run visibly on Windows and let the user stop it;
- drive an installed stable Google Chrome or Microsoft Edge;
- perform a predefined sequence without an LLM or cloud control plane;
- collect browser console errors and write a structured local result;
- use least privilege, an isolated temporary browser profile, and no persistence; and
- avoid exposing a general shell, JavaScript evaluator, CDP session, or unrestricted desktop-control surface.

The comparison prioritizes that narrow contract rather than general agent capability.

## Comparison

| Criterion | OpenAdapt | Microsoft UFO² | `playwright-core` |
| --- | --- | --- | --- |
| Intended abstraction | Demonstration compiler and governed GUI workflow runtime | Natural-language, multimodal Windows agent framework | Browser automation library |
| Windows support | Browser backend plus optional native Windows support; Python 3.10–3.12 | Windows 10+ with UIA, Win32, WinCOM, and visual fallback | Current official support is Windows 11+ and Windows Server 2019+ |
| Chrome/Edge control | Its browser backend is implemented on Playwright and Chromium | Generic desktop UI control; its current web client explicitly leaves click, type, wait, screenshot, and JavaScript browser automation unimplemented | First-class DOM, accessibility locator, navigation, popup, console, request, response, and screenshot APIs; explicit installed `chrome` and `msedge` channels |
| Deterministic without an LLM | Yes for compiled healthy runs; governed repair and the broader compile/runtime model exceed Phase 1 | No practical fit: HostAgent/AppAgent use ReAct and model configuration; LLM-driven planning is central | Yes; calls execute an authored sequence with explicit waits, assertions, and timeouts |
| Dependency indicator, not total installed size | `openadapt` directly pulls `openadapt-flow[browser,hosted]`; Flow adds NumPy, OpenCV, RapidOCR/ONNX Runtime, Pillow, cryptography, Playwright, keyring, and other packages | 40 direct requirement entries, including LangChain, OpenAI/Anthropic clients, FAISS, sentence-transformers, Azure SDKs, Flask/FastAPI, UIA libraries, and image/data packages | npm metadata for 1.62.1 reports 13,442,086 bytes unpacked and no declared npm runtime dependencies; Node and an installed browser remain external requirements |
| License | MIT | MIT | Apache-2.0 |
| Phase 1 fit | Capable but duplicates Playwright behind a substantially broader runtime | Poor: broad authority, model dependence, and incomplete browser-native control | Best: smallest reviewed authority and direct support for the required evidence |

Package metadata changes over time. The table records the cited upstream state on the decision date; the Phase 1 implementation must pin and lock the version it actually validates.

## Candidate findings

### OpenAdapt

OpenAdapt now supports deterministic replay with zero model calls on healthy runs and has safety concepts that align with DinoSupport, including explicit verification and fail-closed outcomes. It is not the smallest Phase 1 base:

- the public package depends on `openadapt-flow[browser,hosted]`;
- the Flow browser extra depends on Playwright, so DinoSupport would still inherit Playwright indirectly;
- Flow core also brings OCR, computer-vision, cryptography, policy, hosted-token-storage, and workflow-compilation concerns that Phase 1 does not need; and
- its Playwright backend includes visual/coordinate actuation and a fixed viewport in addition to structural browser control, increasing the authority and review surface.

**Disposition:** do not depend on or vendor it for Phase 1. Reusing only its browser subset would amount to maintaining a fork around an existing Playwright dependency. Its workflow verification ideas may inform later design, but no OpenAdapt code is needed for the proof of concept.

### Microsoft UFO²

UFO² has the strongest native Windows breadth in this comparison: UIA, Win32, WinCOM, visual detection, and multi-application coordination. That breadth is contrary to the least-authority browser proof of concept.

Its normal execution model uses HostAgent/AppAgent ReAct loops, multimodal models, prompts, RAG, and model credentials. More importantly for this project, the current `WebReceiver` fetches page HTML over HTTP but returns “Browser automation not available” for browser click, type, scroll, wait, screenshot, and JavaScript operations. Chrome or Edge can still be manipulated as desktop windows, but that is less deterministic and does not provide browser-native console/network evidence.

Its requirements also pull model clients, vector retrieval, web servers, cloud identity/storage, desktop automation, and data-science packages. Extracting a lower-level UIA subset would create a security-sensitive fork without solving the browser evidence requirement.

**Disposition:** reject both dependency and vendoring for Phase 1. Reconsider only for a future, narrowly allowlisted native-application evaluation; do not adopt its agent loop or broad executor.

### Playwright

Playwright directly matches the target surface:

- `channel: "chrome"` and `channel: "msedge"` launch installed branded browsers;
- locators and explicit assertions support deterministic authored steps without visual clicking or a model;
- page events expose console messages, failed requests, and responses; and
- browser contexts provide isolated, non-persistent sessions without attaching to the user's normal profile.

Use `playwright-core`, not the Playwright test runner and not a downloaded Chromium bundle. This keeps the runtime dependency to the browser-control library and uses Chrome or Edge already installed on the endpoint. It also ensures Phase 1 tests the actual supported browser channels rather than Playwright's separate Chromium build.

Tradeoffs:

- Node remains an external runtime until packaging is addressed in Phase 6.
- The currently documented Playwright support floor is Windows 11; Windows 10 is not an upstream-supported target.
- Enterprise browser policies can prevent Playwright from launching or controlling branded browsers, and upstream explicitly treats those policy combinations as outside its scope.
- Playwright is powerful enough to execute arbitrary page JavaScript, access files, and open raw CDP sessions. DinoSupport must not expose those APIs through its recipe contract.

These are bounded and testable. They are smaller risks than adopting a desktop agent or maintaining browser-protocol code.

## Dependency and license decision

### Dependency, not vendoring

Pin `playwright-core` exactly in the lockfile and consume only public APIs. A dependency preserves upstream browser compatibility and security updates. Vendoring would copy a large, fast-changing protocol implementation into DinoSupport and make patch provenance harder to audit. Reimplementing CDP would recreate navigation, target lifecycle, locator, timeout, and Chrome/Edge version-compatibility failure modes.

DinoSupport should own only the narrow adapter and recipe execution policy. That is application code, not a fork of Playwright.

### Obligations

- **Playwright:** Apache-2.0 permits use and distribution in this MIT project and includes an express patent grant. A distribution must include the Apache-2.0 license, retain applicable attribution notices, include any applicable upstream `NOTICE`, and mark modified upstream files if any are modified. The selected dependency strategy does not modify upstream files.
- **OpenAdapt and UFO²:** both are MIT. Copying substantial code would require retaining their copyright and permission notices. No code will be copied, so no distribution obligation is introduced by this evaluation.
- **Chrome and Edge:** they are installed external products, not redistributed by this strategy. Their licenses and enterprise policies remain independent deployment constraints.

Before shipping a binary, generate third-party notices from the locked dependency graph rather than relying on top-level licenses alone.

## Phase 1 integration boundaries

The implementation issue for Phase 1 should preserve these boundaries:

1. Launch a headed installed `chrome` or `msedge` channel in a fresh temporary profile. Never attach to the user's daily profile or import its cookies, passwords, extensions, or history.
2. Execute only code-defined recipe actions. Start with navigation, role/label-based click or fill, bounded waits, and assertions. Do not add arbitrary JavaScript, raw CDP, shell, upload, download, extension, or desktop-input actions.
3. Register evidence listeners before navigation. Cover every page created by the context so popups do not bypass console collection. Treat HTTP error responses separately from transport-level `requestfailed` events.
4. Apply per-action and total-runtime deadlines. A local stop signal must close the context and browser promptly and produce a canceled result.
5. Keep the proof of concept local and use a synthetic target. No cloud reasoning, model calls, background service, startup registration, or persistent browser state.
6. Validate both stable channels on supported Windows, including unavailable-browser and policy-blocked launch errors. Record the exact browser and Playwright versions in the result.

The signed manifest, consent UI, evidence redaction, and production packaging remain their own roadmap phases. The adapter must stay narrow enough for those controls to wrap later without exposing additional authority.

## Remaining validation gates

This research selects the strategy; it does not claim runtime validation. Phase 1 must verify:

- headed Chrome and Edge launch and deterministic action completion on Windows 11;
- console collection across navigation and popup pages;
- cancellation during navigation and during a wait;
- cleanup of temporary browser data after success, failure, and cancellation;
- clear failure when a browser is absent or enterprise policy blocks automation; and
- measured installed/package footprint with the chosen Node packaging approach.

If Windows 10 becomes a required supported platform, reassess the executor or explicitly validate and own that unsupported-upstream combination before claiming support.

## Sources

Accessed 2026-08-26.

- [DinoSupport project plan](../PLAN.md)
- [OpenAdapt README](https://github.com/OpenAdaptAI/OpenAdapt#readme)
- [OpenAdapt package dependencies](https://github.com/OpenAdaptAI/OpenAdapt/blob/main/pyproject.toml)
- [OpenAdapt Flow dependencies](https://github.com/OpenAdaptAI/openadapt-flow/blob/main/pyproject.toml)
- [OpenAdapt Playwright backend](https://github.com/OpenAdaptAI/openadapt-flow/blob/main/openadapt_flow/backends/playwright_backend.py)
- [OpenAdapt MIT license](https://github.com/OpenAdaptAI/OpenAdapt/blob/main/LICENSE)
- [UFO² README](https://github.com/microsoft/UFO/blob/main/ufo/README.md)
- [UFO requirements](https://github.com/microsoft/UFO/blob/main/requirements.txt)
- [UFO web client](https://github.com/microsoft/UFO/blob/main/ufo/automator/app_apis/web/webclient.py)
- [UFO MIT license](https://github.com/microsoft/UFO/blob/main/LICENSE)
- [Playwright supported browsers and branded channels](https://playwright.dev/docs/browsers)
- [Playwright system requirements](https://playwright.dev/docs/intro#system-requirements)
- [Playwright page events](https://playwright.dev/docs/api/class-page#events)
- [`playwright-core` npm metadata](https://registry.npmjs.org/playwright-core/latest)
- [Playwright Apache-2.0 license](https://github.com/microsoft/playwright/blob/main/LICENSE)
