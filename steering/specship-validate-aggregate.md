---
inclusion: manual
---

# specship-validate-aggregate — Verdict Aggregator

Aggregates results from all validators and produces a final verdict. Decides whether to merge, recover, or escalate.

You combine results from every validator in the derived set (up to 7) into a single decision: merge, recover, or escalate.

Suggested model: Opus (for the completeness-critic pass and the judgment-heavy refutation reasoning).

## Inputs

Verdict files in `.specship/artifacts/verdicts/`, one per validator that ran. **Unified status vocabulary** (the only valid values): `PASS`, `FAIL`, `PARTIAL`, `INCOMPLETE`, `SKIPPED`.

1. specship-validate-integration — full-stack only
2. specship-validate-design — UI projects only
3. specship-validate-code
4. specship-validate-security
5. specship-validate-browser
6. specship-validate-alignment
7. specship-validate-load — enterprise only

Plus the **completeness critic** (see `specship-validate`) which checks whether the validator SET collectively covered every acceptance criterion.

## Decision Matrix

```
ALL PASS (or SKIPPED)                     → run COMPLETENESS CRITIC → if it names an uncovered AC: RECOVER; else MERGE
ANY NOT_RUN / INCOMPLETE (should have run)→ BLOCKED (re-dispatch the missing validator; never MERGE)
Integration FAIL                          → RECOVER (highest priority — guaranteed user-visible bug)
Design FAIL                               → REFUTE first (1 skeptic), then RECOVER on surviving findings
Code FAIL                                 → RECOVER (fix implementation)
Security FAIL (>=7/10 confidence)         → RECOVER (fix vulnerabilities)
Security FAIL (below 7/10)                → REFUTE first (1 skeptic), then RECOVER if upheld
Browser FAIL                              → RECOVER (fix broken flows)
Load FAIL                                 → RECOVER (fix performance)
Alignment FAIL / PARTIAL                  → ESCALATE TO HUMAN
3+ validators FAIL simultaneously         → ESCALATE TO HUMAN (systemic issue)
```

## Rules

- SKIPPED validators do NOT count as failures (e.g., browser skipped for backend-only)
- `PARTIAL` is informational for non-alignment validators (note it, don't block); for **alignment**, PARTIAL escalates
- A `PASS` whose `evidence[]` is empty (where evidence is required) is downgraded to NOT_RUN → BLOCKED — never counts as a pass (Step 1 evidence gate)
- Alignment failures ALWAYS escalate — never auto-recover (the contract may be wrong)
- If 3+ validators FAIL simultaneously, escalate (systemic issue needs human judgment) — and SKIP refutation (the build is clearly broken)
- If 1-2 validators FAIL (not alignment), trigger recovery — start one focused fix pass per blocking issue (each fix can be done in its own fresh chat session so it stays independent)

### Refutation gate (bounded — avoids recovery churn on false positives)

Design FAIL and low-confidence Security FAIL are the hallucination-prone, judgment-heavy classes, and Design recovery is the most expensive (may rebuild the whole UI layer). Before routing EITHER to RECOVER, run **ONE** independent refutation pass per blocking finding (a fresh chat session keeps it independent from the original validator's reasoning):

> "Refute this finding with file:line or screenshot counter-evidence. The original validator claims: <finding>. Return `{finding, refuted: true|false, evidence}`. Default to refuted=false if you cannot disprove it."

- If the refuter disproves it → downgrade that finding to an advisory NOTE; do not recover on it.
- Only **surviving** findings enter recovery, and the recovery prompt must quote the surviving evidence.
- Do NOT refute Integration / Code / Browser / high-confidence Security FAILs — those carry concrete file:line evidence and rarely false-positive; refuting them just burns tokens. (Cost cap: at most one refuter per surviving design/low-confidence-security finding.)

### Completeness critic gate (catches the false-PASS hole — Learning 11)

When every validator PASSES, the build is NOT automatically done — one build passed 21 tests and still shipped 2 UI bugs no single validator owned. Before MERGE, run ONE completeness-critic pass (Suggested model: Opus; a fresh chat session keeps it independent) with all verdict files + the contract:

> "Here are all validator verdicts and the sprint contract. Which specific acceptance criteria, failure modes, or finding categories has NO validator covered? Name CONCRETE uncovered items only — not hypotheticals. Return `{uncovered_criteria: [...], reasoning}`."

- If it names a **concrete** uncovered acceptance criterion → verdict is RECOVER (dispatch a validator/fix for that gap), NOT MERGE.
- If `uncovered_criteria` is empty → MERGE.
- Word the gate to fire only on a named criterion, never open-ended "what ifs," or MERGE becomes unreachable.

## Evidence Requirements

Each validator must provide evidence to be counted as complete. A verdict without evidence is treated as NOT_RUN.

| Validator | Required Evidence | Without Evidence |
|-----------|------------------|-----------------|
| Code Review | Acceptance criteria coverage table (each criterion: PASS/PARTIAL/NOT_IMPLEMENTED) | Treated as NOT_RUN → cannot merge |
| Security | Findings table (even if empty: "0 findings at confidence >=7/10") | Treated as NOT_RUN → cannot merge |
| Browser | Screenshot file path showing rendered page + console error count | Treated as NOT_RUN → cannot merge |
| Alignment | Test case projection table (each TC: would pass YES/NO) | Treated as NOT_RUN → cannot merge |

### NOT_RUN Handling

If ANY required validator is NOT_RUN (no evidence provided):
- Verdict CANNOT be MERGE
- Output: "INCOMPLETE — validators did not provide required evidence. Re-run /specship-validate."
- This is NOT a FAIL (nothing is broken) — it's a process failure (validation didn't execute)

### Fabrication Detection

If the dispatch ledger / mission state records validation entries but no validator pass was actually run in this session, the entries are fabricated from a prior run or were recorded without dispatching. Treat as NOT_RUN.

### The Golden Rule

**No evidence = no verdict.**

You cannot merge code that hasn't been validated. You cannot validate code without proof. A PASS written to a file is not proof — a validator's structured output with artifacts is proof.

## Process

### Step 0a: Deterministic process check (RUN FIRST — mechanical gate, not vibes)

Before you read a single verdict by hand, run the deterministic process checker. It is a zero-dependency Node script that mechanically verifies the pipeline left no step behind: all tasks complete in `state.json`, every validator in `expected-validators.txt` has a verdict file, no verdict is `SKIPPED`, no verdict carries `blocking_issues`, and the plan artifacts (`requirements.md`, `design.md`, `tasks.md`) exist.

Locate and run it from the project root:

```bash
CHECKER=$(find ~/.kiro -name process-checker.js 2>/dev/null | head -1)
[ -z "$CHECKER" ] && CHECKER=$(find . -name process-checker.js 2>/dev/null | head -1)
if [ -n "$CHECKER" ]; then
  node "$CHECKER" --phase ship; echo "process-checker exit: $?"
else
  echo "process-checker.js not found — fall back to the manual Step 0b precondition below"
fi
```

- **Exit 0 (PASS):** the pipeline is mechanically complete — proceed to Step 0b and the decision matrix.
- **Exit 1 (FAIL):** the script names exactly what is missing (incomplete tasks, missing verdict file, a SKIPPED validator, or a blocking issue). Do **NOT** emit MERGE. Treat it as the authoritative cause: a missing/SKIPPED verdict → BLOCKED on that validator (re-run it); incomplete tasks → back to BUILD; a blocking issue → RECOVER. The deterministic result overrides any optimistic read of the verdicts.

This is the same set of guarantees Step 0b states in prose, computed mechanically so the aggregate can never declare MERGE while a step is silently missing (Learning 12). If the script cannot be found, do **not** skip the gate — fall through to the manual precondition in Step 0b.

### Step 0b: Precondition — ALL expected verdicts present (HARD GATE, do this FIRST)

Before producing ANY decision: read `.specship/artifacts/expected-validators.txt` and confirm a verdict file exists in `.specship/artifacts/verdicts/` for EVERY entry. If any is missing → **STOP**: do NOT emit MERGE/RECOVER/ESCALATE from partial data, and do NOT infer, assume, or claim a status for the missing validator (especially the browser validator, which the coordinator may run last). Emit `BLOCKED: <validator> has no verdict file — run it before aggregating` and wait for that file. **The aggregate is computed ONLY from verdict files that actually exist on disk — never from remembered or claimed results.** (This is the mechanical guard against the Learning-12 failure where an aggregate declared a browser PASS before the browser pass had run.)

### Step 1: Collect Results (parse JSON verdict files — do NOT grep prose)

Each validator wrote a machine-readable verdict to `.specship/artifacts/verdicts/<validator>.json` (see the Verdict Contract in `specship-validate`). Read those files mechanically — never eyeball a prose "Status line". Each file has the shape `{"validator","status","evidence":[...],"blocking_issues":[...]}`. For each file, read out the validator name, its status, its evidence count (length of `evidence`), and its blocking-issue count (length of `blocking_issues`).

**Evidence-emptiness gate (mechanical NOT_RUN detection):** For any validator whose Evidence Requirements row (table above) demands an artifact, if `status == "PASS"` but `evidence[]` is empty, **downgrade it to NOT_RUN** — a PASS with no artifact is fabrication (Learning 12), not a pass. Concretely: if the status is `PASS` and the evidence array is empty, treat the effective status as `NOT_RUN`; otherwise keep the reported status.

**Missing file = NOT_RUN (mechanical check).** `specship-validate` wrote the required set to `.specship/artifacts/expected-validators.txt`. Every expected validator MUST have a verdict file; for each expected validator listed there, if `.specship/artifacts/verdicts/<validator>.json` does not exist, that validator is `NOT_RUN: <validator> (expected, no verdict file) → BLOCKED`.

The primary source for which validators should have run is the mission state / `.specship/artifacts/expected-validators.txt`. Optionally, cross-check against the run ledger if present (`.specship/artifacts/traces/dispatches.jsonl`): if recorded runs are fewer than validators claiming PASS, the surplus PASSes are NOT_RUN (a validator that never ran cannot have passed).

### Step 2: Apply Decision Matrix

Evaluate the matrix above against the parsed statuses. Determine the action.

### Step 3: Output Final Verdict

```markdown
## Aggregate Verdict

**Contract:** <id> — <title>
**Decision:** MERGE | RECOVER | ESCALATE

### Validator Results
(Status ∈ PASS | FAIL | PARTIAL | INCOMPLETE | SKIPPED | N/A — parsed from `.specship/artifacts/verdicts/*.json`)
| Validator | Status | Blocking Issues |
|-----------|--------|-----------------|
| Integration | <status> | <count or "none"> |
| Design | <status> | <count or "none"> |
| Code Review | <status> | <count or "none"> |
| Security | <status> | <count or "none"> |
| Browser | <status> | <count or "none"> |
| Alignment | <status> | <details> |
| Load | <status> | <count or "none"> |
| Completeness critic | <uncovered count or "0"> | <named uncovered AC, if any> |

### Action
- **MERGE:** All clear. Create PR.
- **RECOVER:** [which validator(s) failed] → start fix pass with failure details.
- **ESCALATE:** [why human judgment is needed] → present findings to user.

### Recovery Instructions (if RECOVER)
The fix pass should address:
1. <specific issue from failed validator>
2. <specific issue>

### Escalation Context (if ESCALATE)
The human should decide:
- <the question that needs human judgment>
- Options: [A) fix implementation] [B) update contract] [C) ship as-is]
```

> Note on tooling: when re-running validators that need a live UI (browser/design checks), use the gstack Kiro Power validators `/qa-only`, `/cso`, `/review` if the gstack Kiro Power is installed; otherwise drive the page yourself with the Playwright or Chrome-DevTools MCP, or fall back to an adversarial review pass in a fresh chat session.

## State Management

The conceptual mission-state file is `.specship/state.json`. Keep these fields and their meaning current as aggregation proceeds (the exact writer mechanism is up to you).

**On validation start:**
```json
{
  "phase": "validate",
  "phase_status": "in_progress",
  "updated_at": "<now>"
}
```

**On validation complete:**
```json
{
  "phase": "<next phase based on verdict>",
  "phase_status": "<pending>",
  "validation_results": {
    "integration": "PASS|FAIL|PARTIAL|INCOMPLETE|SKIPPED|N/A",
    "design": "PASS|FAIL|PARTIAL|INCOMPLETE|SKIPPED|N/A",
    "code_review": "PASS|FAIL|PARTIAL|INCOMPLETE|SKIPPED",
    "security": "PASS|FAIL|PARTIAL|INCOMPLETE|SKIPPED",
    "browser": "PASS|FAIL|PARTIAL|INCOMPLETE|SKIPPED",
    "alignment": "PASS|FAIL|PARTIAL|INCOMPLETE|SKIPPED",
    "load": "PASS|FAIL|PARTIAL|INCOMPLETE|SKIPPED",
    "completeness_critic": "PASS|UNCOVERED"
  },
  "handoff_notes": "Validation complete. Verdict: <MERGE|RECOVER|ESCALATE>. <details>"
}
```
