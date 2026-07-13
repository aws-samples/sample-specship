---
inclusion: auto
name: specship-validate
description: Use to validate a build against its contract — "validate", "check my work", "run validators", "is this done?". Derives the applicable validator set, runs each as an independent pass, collects typed verdicts, and aggregates into merge / recover / escalate.
---

# specship-validate — Validation Orchestrator

## BEFORE YOU DO ANYTHING:

1. Print this phase box (inside a fenced code block; closed 4 walls, **plain ASCII only inside** — no emoji, it breaks the right wall):
```
╔════════════════════════════════════════════╗
║ PHASE: VALIDATE                            ║
╚════════════════════════════════════════════╝
```
2. **Dispatch ALL validators in ONE `subagent` call** with every validator as a separate stage in a single `stages` array (plus the `aggregate` stage that `depends_on` them). Do NOT call the `subagent` tool once per validator — that runs them sequentially and defeats the parallelism. One call, many stages.
3. **Do NOT review the code yourself** — not even browser or design. The design/Lighthouse validator MUST be a subagent stage, not something you run as coordinator. (Browser is the ONLY one you may run yourself, and ONLY because it needs your live Playwright MCP session; if you can dispatch it, do.)
4. **gstack delegation is verifiable, not vibes.** If `~/.kiro/skills/gstack-review` exists, each validator subagent's verdict `evidence[]` MUST have as its FIRST entry: `"activated skill: <review|cso|qa-only>"`. A verdict whose first evidence line is not a gstack activation = the subagent self-reviewed = PROTOCOL VIOLATION → re-dispatch it. "Delegating to the methodology" is NOT activating the skill.
5. Do NOT write verdict JSON files yourself. Each subagent writes its own verdict.
6. **In autonomous mode: run straight through to the aggregate verdict.** Do NOT stop between validators, do NOT pause to report intermediate progress, do NOT ask "shall I continue?". If you were interrupted and are resuming, pick up at the next pending validator immediately without asking.
7. **The aggregate is the LAST step and is GATED on real files.** Produce it ONLY after every validator in `expected-validators.txt` has written its verdict file to `.specship/artifacts/verdicts/`. If you run the browser validator yourself (the one exception), its `browser.json` MUST exist on disk BEFORE you aggregate. **NEVER write an aggregate that reports a status for a validator whose verdict file does not yet exist** — claiming a PASS you haven't produced is fabrication (Learning 12). The aggregate is computed from files on disk, never from remembered or assumed results.

---

Trigger: "validate", "check my work", "run validators", "is this done?".

You orchestrate the validation squad: derive which validators apply, run each one (each is its own skill file in this Power), collect their typed verdicts, then aggregate into merge / recover / escalate.

## Execution Strategy: Parallel Subagents

Kiro's `subagent` tool runs stages with no dependencies **in parallel**. Since validators are independent by design (they don't see each other's output), run them ALL simultaneously. This cuts validation from ~6 sequential passes to ~1 pass (wall clock).

```
Use the subagent tool with this pattern:

task: "Validate build for contract <id>"
stages:
  - name: "validate-integration"
    role: kiro_default
    prompt_template: "Follow the specship-validate-integration steering. Contract: .specship/specs/<id>-<slug>/requirements.md. Output verdict JSON to .specship/artifacts/verdicts/integration.json"

  - name: "validate-code"
    role: kiro_default
    prompt_template: "Follow the specship-validate-code steering. Contract: .specship/specs/<id>-<slug>/requirements.md. Output verdict JSON to .specship/artifacts/verdicts/code.json"

  - name: "validate-security"
    role: kiro_default
    prompt_template: "Follow the specship-validate-security steering. Contract: .specship/specs/<id>-<slug>/requirements.md. Output verdict JSON to .specship/artifacts/verdicts/security.json"

  - name: "validate-browser"
    role: kiro_default
    prompt_template: "Follow the specship-validate-browser steering. Contract: .specship/specs/<id>-<slug>/requirements.md. Output verdict JSON to .specship/artifacts/verdicts/browser.json"

  - name: "validate-design"
    role: kiro_default
    prompt_template: "Follow the specship-validate-design steering. Contract: .specship/specs/<id>-<slug>/requirements.md. Output verdict JSON to .specship/artifacts/verdicts/design.json"

  - name: "validate-alignment"
    role: kiro_default
    prompt_template: "Follow the specship-validate-alignment steering. Contract: .specship/specs/<id>-<slug>/requirements.md. Output verdict JSON to .specship/artifacts/verdicts/alignment.json"

  - name: "aggregate"
    role: kiro_default
    depends_on: ["validate-integration", "validate-code", "validate-security", "validate-browser", "validate-design", "validate-alignment"]
    prompt_template: "Follow the specship-validate-aggregate steering. Read all verdicts from .specship/artifacts/verdicts/. Produce the final decision: merge / recover / escalate."
```

**Only include stages for validators in the derived set** (Step 1). If the project has no UI, omit `validate-browser` and `validate-design`. If no load NFR, omit `validate-load`.

**The aggregate stage depends on ALL validator stages** — it only runs after every validator has produced its verdict. This is the fan-out/fan-in pattern: validators run in parallel, aggregate waits for all.

**Independence is structural, not just a rule.** Each subagent gets fresh context — it cannot see what the builder did or what other validators found. This is exactly the adversarial independence SpecShip requires.

## Step 1 — Derive the validator set (don't hand-count to a magic number)

Build the list from the project shape, then run EVERY entry. You cannot "forget one" because the list is derived from facts, not remembered:

- **code, security, alignment** → ALWAYS.
- **integration** → iff frontend AND backend both exist (e.g. `src/client` + `src/server`, or a UI plus routes that return JSON).
- **browser, design** → iff there is a UI.
- **load** → iff the contract has a performance/concurrency NFR.

So: backend-only API → 4 validators (code, security, alignment, +load if NFR). Full-stack UI app → 7 (or 6 without a perf NFR). Write the derived list to a file (`.specship/artifacts/expected-validators.txt`) so the aggregator can cross-check that each one actually produced a verdict.

## Step 2 — The 7 validators (each is its own skill file in this Power)

Each validator runs as a **parallel subagent** (see execution strategy above). Each follows its dedicated steering file — do NOT inline-evaluate them here:

| Validator | Skill file | What it checks (lens) |
|-----------|-----------|------------------------|
| Integration | `specship-validate-integration` | Frontend↔backend shape match vs the API contract (the `data.items` vs plain-array bug class). **Run FIRST for full-stack** — its failures are guaranteed user-visible bugs. |
| Code | `specship-validate-code` | Correctness vs each acceptance criterion + failure modes; **runs the test suite** (non-zero exit = auto FAIL); scope drift. |
| Security | `specship-validate-security` | Attacker view: injection, auth bypass, secrets, boundary/negative inputs; confidence ≥7/10 gate; CRITICAL/HIGH = FAIL. |
| Browser | `specship-validate-browser` | Real-browser interactive CRUD lifecycle via Playwright MCP (create→verify→edit→duplicate→delete-copy→delete); screenshots as evidence. Screenshot-only with no interaction → INCOMPLETE. |
| Design | `specship-validate-design` | 15-item anti-slop checklist (13+/15), feature depth across 5 states (4+/5), reference patterns (7+/10), **measured** Lighthouse ≥90. |
| Alignment | `specship-validate-alignment` | Does it match the user's *intent*, not just "code exists"? Surprises / missing / over-built. FAIL/PARTIAL → escalate (never auto-recover). |
| Load | `specship-validate-load` | Performance under concurrent load (k6/artillery) vs the contract NFR. Enterprise only. |

**Delegation is MANDATORY when gstack is installed** (check: `ls ~/.kiro/skills/gstack-review ~/.kiro/skills/gstack-cso ~/.kiro/skills/gstack-qa-only 2>/dev/null`). If those directories exist:
- Code validator → MUST activate the `review` skill. Do NOT self-review.
- Security validator → MUST activate the `cso` skill. Do NOT self-review.
- Browser validator → MUST activate the `qa-only` skill. Do NOT just take screenshots.

**This is the #1 protocol violation in SpecShip builds.** The agent "forgets" to delegate and writes its own "PASS" verdict. Each validator file has a HARD-GATE at the top that blocks this — but if you're the orchestrator dispatching subagents, include the delegation instruction in each subagent's prompt:

```
"If ~/.kiro/skills/gstack-review exists, activate the review skill. Do NOT self-review."
```

> **`review`/`cso`/`qa-only` are markdown skills — there are NO binaries or telemetry preamble to run.** "I'll apply the skill's method myself because the gstack tooling/binaries aren't present" is a FALSE excuse and a self-review violation. Activating the skill just means following its method as a fresh, independent pass — which is exactly the point. There is nothing to install at validation time beyond the skill files themselves.

Never substitute "I read it and it's fine" for an actual validator pass.

## Step 3 — The verdict contract (every validator emits this)

There is no tool-layer schema enforcement in a markdown system, so each validator ends its pass with a fenced JSON block that the aggregator parses — never grep a prose "Status:" line:

```json
{
  "validator": "code | security | integration | browser | design | alignment | load",
  "status": "PASS | FAIL | PARTIAL | INCOMPLETE | SKIPPED",
  "independent": true,
  "method": "fresh chat session + activated gstack `review` skill",
  "evidence": [ { "claim": "what was checked", "artifact": "file:line | screenshot | test name | curl output" } ],
  "blocking_issues": [ { "summary": "...", "file": "...", "line": 0, "expected": "...", "actual": "..." } ]
}
```

Rules: a `PASS` with empty `evidence[]` is downgraded to NOT_RUN (a pass with no artifact is fabrication — Learning 12). Tool missing / app not running → INCOMPLETE, never PASS. Status vocabulary is exactly PASS | FAIL | PARTIAL | INCOMPLETE | SKIPPED. Save each verdict where the aggregator can read it (`.specship/artifacts/verdicts/<validator>.json`).

**Independence attestation is REQUIRED (T18).** Every verdict MUST carry `"independent": true` and a non-empty `"method"` describing HOW independence was achieved — the fresh-session/subagent context plus the activated companion skill (e.g. `"fresh subagent + gstack cso skill"`). The deterministic ship gate is STRICT by default and FAILS any verdict missing this attestation, because a verdict the builder wrote for its own work is not adversarial validation. `"method"` must be truthful: if you could not run it independently, the honest status is `INCOMPLETE`, not a fabricated `independent:true`.

## Step 4 — Aggregate

Follow **`specship-validate-aggregate`** to turn the verdicts into a decision (merge / recover / escalate). In short:
- Any NOT_RUN / INCOMPLETE that should have run → BLOCKED (re-run it).
- Integration / Code / Browser / Load FAIL → RECOVER. Design FAIL or low-confidence Security FAIL → refute with ONE skeptic first, then RECOVER on survivors. Alignment FAIL/PARTIAL → ESCALATE. 3+ FAIL → ESCALATE.
- All PASS → run the **completeness critic** (names any uncovered acceptance criterion); a named gap → RECOVER, else → MERGE.

## Enforcement (why this exists)

- **NOT_RUN = BLOCKED.** A validator you didn't run cannot be "PASS." If you catch yourself thinking "I'll run the important ones" / "given context I'll focus on…" / "I already checked that manually" — STOP, that's skipping with a nicer name. Run the whole derived set.
- **Independence.** No validator sees another's output. The builder cannot self-evaluate. Fresh passes produce honest assessments.
- **Evidence or it didn't pass.** Every PASS needs an artifact (screenshot, test name, file:line, curl output).

## Hand-off

MERGE → **specship-ship**. RECOVER → **specship-recover**. ESCALATE → present findings to the user and stop.
