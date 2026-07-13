---
inclusion: auto
name: specship-recover
description: Use when a validator returned FAIL or the user wants to fix validation failures — "recover from failure", "fix validation failure", "specship recover". Runs one surgical, regression-test-first fix per issue, budget-bounded, and prevents the failure class.
---

# specship-recover — Self-Healing Recovery

Trigger: a validator returned FAIL; "recover from failure", "fix validation failure", "specship recover".

When a validator reports FAIL, you run a fresh fixer pass — a new chat session carrying the failure context — to fix the issue. The key insight: a fresh fixer with the failure report produces better fixes than asking the original builder to "try again" — the original carries sunk-cost bias. Max 3 attempts, then escalate.

## Role

- Suggested model: Sonnet (the fix worker). Kiro routes per chat / custom-agent, not per steering file.
- Stance: Surgical — fix ONLY what the validator flagged, nothing else.
- Context: Fresh — no knowledge of the implementation decisions, only the failure report. In Kiro, run each fix as a focused pass; a fresh chat session keeps it independent from whoever built the code.

## Inputs

1. **Sprint contract** — what "done" means.
2. **Validation failure report** — what specifically failed.
3. **Current branch state** — the code to fix.

## Process

### Step 1: Check Recovery Budget (use the live counter, NOT a git-log grep)

The budget is the `recovery_attempts` field in your mission-state file — a **cycle counter**, incremented once per recovery cycle (default max is 3, configurable). Do NOT count `[specship-fix]` commits: Step 1.5 emits one fix commit *per issue*, so a single 6-issue first cycle would grep `6 >= 3` and falsely exhaust the budget before any retry. It also bleeds across contracts on the same branch. The cycle counter avoids both bugs.

Read the configured max (default 3) and the current `recovery_attempts` from the mission-state file, then compute the cycle as `recovery_attempts + 1`.

If `recovery_attempts >= max_attempts`:
> "Recovery budget exhausted (N/MAX cycles used). Escalating to human."
> Show: all attempts, what was tried, what still fails.

STOP.

Otherwise, **increment the counter at the START of this cycle** (atomic write) so a crash mid-recovery doesn't lose the count: set `recovery_attempts` to the new cycle number, `phase` to `recover`, and `phase_status` to `in_progress`, then persist the mission state. Both `specship-recover` and `specship-resume` read `recovery_attempts` from this one field — they can never disagree.

### Step 1.5: Scale Assessment — One Recovery Agent Per Issue (Surgical Precision)

Count the number of blocking issues found by the validator(s).

**Regardless of count (1 or 20), run a SEPARATE recovery pass for EACH issue.** Each pass follows the surgical precision method:
- Understands ONE specific failure.
- Reads ONLY the relevant source files.
- Makes the minimal fix for THAT issue.
- Adds a regression test for THAT issue.
- Commits with `[specship-fix] <what was wrong>`.
- Verifies existing tests still pass.

**The pattern:**

```
For each blocking issue from validators:
  1. Run a fix pass (independent issues can be parallelized; in Kiro,
     a fresh chat session per issue keeps each one independent)
     - Give it: the specific failure description, relevant file paths,
       what "correct" looks like
     - It fixes ONLY that one issue (surgical, not exploratory)
     - It commits its own fix independently
  2. After ALL fix passes complete:
     - Run the project's test suite to verify no conflicts between fixes
     - If conflicts: fix the conflict (one more surgical pass)
  3. Re-run ALL 7 validators
  4. If still failing: next recovery cycle (counts toward 3-strike max)
```

**Why individual passes, not one big pass:**
- Each fix is atomic and independently committable.
- If one fix breaks something, it's isolated and easy to revert.
- Follows the "surgical — fix ONLY what the validator flagged" principle.
- Parallel execution: 6 independent fix passes can proceed at once = faster than one sequential pass.
- Better quality: each pass focuses on ONE problem deeply rather than rushing through 6.

**Execution modes:**
- If issues are independent (no shared files): run ALL fix passes in parallel — in Kiro, fan them out as separate task waves / fresh sessions.
- If issues share files (e.g., two fixes both touch `auth.ts`): run them sequentially to avoid clobbering each other's edits.
- After all complete: a single verification pass (tests + build).

**NEVER reduce the fix scope.** If the validator found 6 issues, run 6 fix passes. Do not rationalize why some are "out of scope" or "not recovery-appropriate." The validator found them → they need fixing.

### Step 2: Understand the Failure

Read the validation failure report. Extract:
- Which validator failed (integration / code / security / browser).
- Specific blocking issues (with file:line references).
- What the expected behavior should be (from the contract).

**Integration failures get special treatment:**
Integration failures (from specship-validate-integration) are GUARANTEED user-visible bugs. They require fixing BOTH sides to align:
- If backend is correct (matches API contract): fix the frontend consumption.
- If frontend is correct (matches API contract): fix the backend response.
- If no API contract exists: fix whichever side is simpler, then create the contract.

The fix pass for integration failures MUST receive:
1. The integration validator's mismatch table (endpoint → expected → actual).
2. The relevant backend route file.
3. The relevant frontend component/API file.
4. The API contract file (if it exists).

The fix is almost always a 1-line change (e.g., `data.workspaces` → `data`) but the fix pass must also verify ALL other consumption points for the same pattern (Step 4.5 prevent-the-class).

**Design failures get special treatment:**
Design failures (from specship-validate-design) are SYSTEMIC — they often affect many files, not just one. The recovery approach differs by severity:

**Severity 1: Surface-level (anti-slop items failed, design system exists but wasn't followed)**
- Fix: Grep for inline styles / arbitrary values and replace with design tokens.
- Scope: Usually 5-20 class replacements across 3-10 files.
- Fix-pass prompt: "Replace all inline styles with Tailwind classes from the design system. Replace arbitrary hex values with palette colors."

**Severity 2: Missing states (features work but lack loading/empty/error states)**
- Fix: Add conditional rendering for each missing state.
- Scope: 2-5 components need loading skeletons and error boundaries.
- Fix-pass prompt: "Add loading skeleton, empty state, and error boundary to these components: [list]. Use the existing design system."

**Severity 3: Structural (wrong density, wrong layout, wrong design system entirely)**
- This is a REBUILD, not a fix. The UI layer needs to be rewritten.
- Escalate to the user: "The design validator found structural issues. The UI was built with wrong density/layout. Recommend: delete the UI components and rebuild M2 (shared components) with correct density specs in the build prompt."
- DO NOT attempt automated recovery for structural design issues — it's cheaper to rebuild the components correctly than to patch wrong fundamentals.

The fix pass for design failures MUST receive:
1. The design validator's anti-slop score table (which items failed).
2. The contract's Design Spec section (what "correct" looks like).
3. The specific files that need changes.
4. The feature depth table (which features are missing which states).

### Step 3: Spawn Fix Worker

The fix pass receives ONLY:
- The failure report (what's wrong).
- The contract acceptance criteria (what "right" looks like).
- The relevant source files (not the entire codebase).

The fix pass does NOT receive:
- The original implementation plan.
- The original builder's reasoning.
- The full git history.

In Kiro, this is naturally a fresh chat session scoped to the one issue — Kiro Spec mode (requirements/design/tasks.md) is the home for any fix that grows beyond a single edit.

### Step 4: Fix Worker Instructions

The fix pass must:
1. Read the failure report.
2. Read the relevant source files.
3. **Understand WHY the bug happened** (root cause, not just symptoms).
4. Make the fix that addresses the blocking issues.
5. **Add a regression test that tests the ATTACK VECTOR, not just the happy path** (MANDATORY — operationalizes Learning 16).
   - Consult the regression recipes (in Kiro, follow the test-driven-development method — write the failing test first, watch it fail, then fix until green). The recipes map each finding class to the exact assertion to generate.
   - Write the test in the GENERATED project's OWN test framework (jest/vitest/pytest/go test/rspec — whatever the project uses), not a SpecShip-side script.
   - Security finding: "negative amounts bypass validation" → test: `POST with amount: -100 → expect 400`.
   - Integration finding: "frontend expects data.items" → test: verify response IS an array directly.
   - Browser finding: "delete copy deletes original" → test: create, duplicate, delete copy, verify original exists.
   - The test must FAIL without the fix and PASS with it. This prevents future regressions.
   - **The fix commit is REJECTED if it lacks a regression test** — the build's TEST GATE (specship-build) refuses a fix commit that fixes a finding but adds no test for it. The fix alone lets a future refactor reintroduce the bug.
6. Run ALL tests to verify the fix works and nothing else broke.
7. Commit with message: `[specship-fix] <what was wrong> | contract: <id>`.

### Step 4.5: Prevent-the-Class (Enterprise Quality)

After fixing the specific instance, the fix pass asks: "Is this a one-off or a pattern?"

**If it's a pattern (same bug could occur elsewhere):**
- Search for similar code in the codebase (same anti-pattern).
- Fix all instances, not just the one the validator found.
- Example: if the bug was "missing input validation on endpoint A", check if endpoints B, C, D also lack validation.

**If it's a design flaw (the architecture invited this bug):**
- Note it in the commit message: `[specship-fix] <fix> | root-cause: <architectural issue> | contract: <id>`.
- Add a code comment at the fix site explaining the constraint (so future builders don't reintroduce it).

This transforms recovery from "patch the symptom" into "cure the disease." Enterprise code doesn't just pass validation — it prevents regression.

### Step 5: Re-validate

After the fix is committed, re-run the failed validator(s).

**HARD RULE — re-validation is INDEPENDENT, not self-certified.** You (the coordinator) just wrote the fixes, so you CANNOT judge them. Re-validation runs exactly like the first pass: **dispatch each validator as its own `subagent` (see `specship-validate`'s parallel-dispatch block). Each subagent activates its gstack companion and writes its OWN verdict JSON. You do NOT write/edit verdict files, and you do NOT "apply the review method yourself."**
- If integration failed → re-dispatch specship-validate-integration.
- If code review failed → re-dispatch specship-validate-code.
- If security failed → re-dispatch specship-validate-security.
- If browser failed → re-dispatch specship-validate-browser (the only one you may run yourself, and only because it needs the live Playwright session).

> **The "gstack needs binaries" excuse is FORBIDDEN.** `review`, `cso`, and `qa-only` are **markdown skills** — there is no binary, no telemetry preamble, nothing to install at run time. "I'll apply its method myself because the gstack tooling isn't here" = self-review = PROTOCOL VIOLATION. Activate the skill and let it run as an independent pass.

**For integration fixes:** Also run the mid-build integration shape check (the inline one from specship-build) as a quick sanity check before launching the full validator pass. This catches obvious issues in 5 seconds instead of waiting for a full re-validation.

**Decisive-cycle full re-run (prevents fix-induced regressions):** If the failed validator now re-passes AND this fix would clear the LAST blocking issue (i.e. the next aggregate would be MERGE), re-run the **FULL validator squad once** before declaring MERGE — not just the validator that failed. A security fix that loosens an input contract can silently break the integration shape; a design fix can break a browser flow.

**HOW the decisive re-run happens — re-DISPATCH the independent squad, do NOT self-verify.** This is the same dispatch as the first validation pass (see `specship-validate`): each validator runs as its own fresh `subagent` that activates its gstack companion and writes its OWN verdict; the coordinator does NOT re-check the fixes itself, does NOT hand-edit verdict/aggregate files, and does NOT mark a gate PASS by re-running a couple of tests in its own context. Re-verifying the specific fix yourself (e.g. "I re-ran the test and re-checked it in the browser, so it's MERGE") is the self-certification trap — the agent that wrote the fix cannot be the one that clears it. **"Re-run" means re-dispatch the squad**: design RE-MEASURES Lighthouse, load RE-RUNS k6, code/security/integration/browser each re-run as independent passes against the running app. You may NOT mark a previously-passing gate PASS by asserting "unaffected by my change" — an independent verdict measures it, or it is not a verdict. This costs one full-squad dispatch, paid once, only on the cycle that would otherwise ship. (Browser is the only validator the coordinator may run itself, and only because it needs the live Playwright session.)

**Verify-the-fix on security/alignment (one skeptic):** When a security or alignment validator re-passes after a fix, run ONE fresh skeptic pass (no fix context — a separate chat session keeps it independent):
> "The original failure was X. A fix was applied. Prove the fix does NOT resolve X — look specifically for swallowed exceptions, loosened/removed assertions, tests that no longer exercise the attack vector, or config that disables the check. Return `{fixHolds: yes|no, evidence: file:line, regressionRisk}`."

Accept the recovery only if `fixHolds=yes`. If the skeptic refutes, that counts as a failed cycle (increment `recovery_attempts`). Do NOT apply this to integration/code/design/browser fixes — those rely on the deterministic re-check plus prevent-the-class.

### Step 6: Report

```markdown
## Recovery Report

**Contract:** <id>
**Attempt:** N/3
**Trigger:** <which validator failed>

### What was wrong
<from the failure report>

### What was fixed
<description of the fix>

### Files changed
- <list of files modified>

### Commit
<commit hash and message>

### Re-validation Result
<PASS or still FAIL>
```

## Key Principles

- **Fresh context, not retry.** Don't ask the same builder to fix its own mistakes. It has sunk-cost bias.
- **Surgical, not rewrite.** Fix ONLY what the validator flagged. Don't refactor. Don't improve.
- **3-strike maximum.** If 3 fix attempts fail, the problem needs human intelligence, not more compute.
- **Never fix alignment failures.** Alignment failures mean the contract might be wrong. Only humans can fix that.

> If the gstack Kiro Power is installed, you can drive a re-check through `gstack /qa-only`, `/cso`, and `/review`; otherwise use Playwright / Chrome-DevTools MCP directly, or an adversarial agent review pass.

## State Management

All writes use atomic state updates and canonical field names. `recovery_attempts` is the live integer set in Step 1 — keep it in a conceptual mission-state file (the specific writer mechanism does not matter, but the fields and their meaning do).

**On recovery start** (counter already incremented in Step 1):
```json
{
  "phase": "recover",
  "phase_status": "in_progress",
  "recovery_attempts": 1,
  "updated_at": "<now>",
  "last_commit": "<git rev-parse HEAD>",
  "handoff_notes": { "done": [], "next": ["fix: <what failed>"], "blocked": [] }
}
```

**On recovery complete (re-validate):**
```json
{
  "phase": "validate",
  "phase_status": "pending",
  "last_commit": "<git rev-parse HEAD>",
  "handoff_notes": { "done": ["recovery fix applied"], "next": ["re-run validation"], "blocked": [] }
}
```

**On recovery exhausted (budget reached):**
```json
{
  "phase": "escalate",
  "phase_status": "blocked",
  "handoff_notes": { "done": [], "next": [], "blocked": ["<list of issues that failed all recovery cycles>"] }
}
```

## Trace Notes

Record a start and a complete event for this skill in your run trace (skill `recover`, with the active contract and the final status PASS / FAIL / SKIPPED) so the mission timeline stays auditable.

## Hand-off

Re-validation passes → specship-ship. Budget exhausted → escalate to the user with the full trail (all attempts, what was tried, what still fails).
