---
inclusion: auto
name: specship-testgen
description: Use to pre-generate test cases from a sprint contract BEFORE any implementation code exists, so the tests are unbiased by implementation. Runs right after the contract is written, during the PLAN-to-BUILD transition.
---

# specship-testgen — Test Case Pre-Generation

You are generating test cases from a sprint contract BEFORE any implementation code exists. This is critical: because the tests are written before the code, they are unbiased by implementation choices. The alignment validator and browser tester use these as ground truth.

Suggested model: Sonnet (Kiro routes per chat or per custom-agent, not per steering file).

## These cases are the RED seeds for TDD

testgen does NOT run tests — there is no code or framework yet, so nothing can be executed (and a test you can't watch fail proves nothing — see the `tdd` skill). What testgen produces is the **test plan**: the WHAT. BUILD then turns each case into a runnable test, watches it fail (RED), and implements until it passes (GREEN) — the HOW.

So write every case to be **red-able by construction**, because BUILD will seed its TDD loop directly from `test-cases.md`:
- **One behavior per case.** If a case needs "and" to describe it, split it.
- **Concrete input → observable output.** Never "test that it works"; always "given X, expect Y."
- **An explicit failure signal** (every template below has this field) — that's what RED looks like.

This is the division of labor: **testgen decides WHAT to test (pre-code, unbiased); the `tdd` skill decides HOW (red-first, watch-it-fail).** Together they're the SpecShip test discipline — neither replaces the other.

## When to Use

- Immediately after `/specship-contract` creates a contract
- Before any implementation begins
- When the orchestrator transitions from PLAN to EXECUTE phase

## Pre-condition

A sprint contract must exist. If none exists:
> "No sprint contract found. Run `/specship-contract` first to define what done looks like."

## Process

### Step 1: Read the Contract

Locate the contract in this order:
1. Use the path specified by the user, if provided.
2. Read `.specship/state.json` and use `contract_id` + `contract_slug` if present.
3. Locate the most recently modified `.specship/specs/*/requirements.md`.
4. As a legacy fallback only, locate the most recent `.specship/specs/*.md`.

The normal SpecShip contract path is `.specship/specs/<id>-<slug>/requirements.md`, not `.specship/specs/*.md`.

Read that contract and extract:
- All acceptance criteria (numbered list)
- All failure modes (numbered list)
- Scope boundaries (IN/OUT)
- Brownfield preserved behaviors and regression requirements from `artifacts/reverse-engineering/brownfield-contract-inputs.md` if present. If the mission has `artifacts/reverse-engineering/source.txt`, follow the referenced standalone package and read its `brownfield-contract-inputs.md`.

### Step 2: Generate Test Cases

For EACH acceptance criterion, generate:

**Unit-level test case:**
```markdown
### TC-<contract-id>-<N>: <criterion summary>

**Type:** unit
**Criterion:** <verbatim from contract>
**Setup:** <preconditions needed>
**Action:** <what to do>
**Expected:** <observable outcome>
**Failure signal:** <what you see if this fails>
```

**Integration scenario (if criterion involves multiple components):**
```markdown
### TC-<contract-id>-<N>-integration: <scenario name>

**Type:** integration
**Flow:**
1. <step 1>
2. <step 2>
3. <step 3>
**Expected at each step:** <what should be true>
**Failure signal:** <what breaks>
```

### Step 3: Generate Browser Flow Scripts (if UI exists)

For criteria involving user-visible behavior:

```markdown
### BF-<contract-id>-<N>: <flow name>

**Type:** browser
**URL:** <starting page>
**Steps:**
1. Navigate to <URL>
2. Click <element description>
3. Fill <field> with <value>
4. Verify <expected state>
**Pass condition:** <what the validator sees on success>
**Fail condition:** <what the validator sees on failure>
**Screenshot checkpoints:** <list moments to capture>
```

If the contract has no UI-facing criteria, write:
> "No browser flows needed — this contract covers backend/library work only."

### Step 3.5: Generate API Contract Tests (for full-stack projects)

If the contract involves BOTH frontend and backend (user-facing app with API):

```markdown
### ACT-<contract-id>-<N>: <endpoint> response shape verification

**Type:** api-contract
**Endpoint:** <method> <path>
**Setup:** Create necessary seed data, authenticate as test user
**Action:** Call the endpoint and inspect the response
**Verify:**
- Response is a plain array (not wrapped in `{ items: [...] }`)
- Each item has the expected keys: [list from contract]
- Status code matches contract (200 for GET, 201 for POST, etc.)
**Frontend consumption check:**
- The frontend component that calls this endpoint does: `setX(data)` not `setX(data.items)`
- If the frontend accesses `data.<property>`, that property MUST exist on the response
**Failure signal:** Frontend shows empty list or "undefined" errors despite working API
```

Generate one ACT test for EACH endpoint in the API contract. These tests are:
- Runnable without a browser (curl/fetch is sufficient)
- Verify the SHAPE of responses, not just status codes
- Explicitly check that frontend consumption code matches the actual response

**Why this exists:** 70 passing unit tests didn't catch that `data.workspaces` doesn't exist on a plain array. These tests would have caught it because they verify the shape at the consumption point.

### Step 3.6: Generate Brownfield Regression Tests (if reverse-engineering artifacts exist)

If `artifacts/reverse-engineering/brownfield-contract-inputs.md` exists, generate regression cases BEFORE new-behavior cases:

```markdown
### BRT-<contract-id>-<N>: preserve <existing behavior>

**Type:** brownfield-regression
**Preserved behavior:** <verbatim behavior from brownfield-contract-inputs.md>
**Current evidence:** <file path / route / test / baseline command>
**Setup:** <state needed to observe existing behavior>
**Action:** <what a user/system does today>
**Expected:** <current behavior that must remain unchanged>
**Failure signal:** <what regression looks like>
**Likely files touched:** <from change-impact-map.md>
```

For every file listed in `Files Likely To Change`, ensure at least one generated regression test protects the behavior attached to that file. If no regression is possible with the current test framework, write an explicit manual/browser/API check in `browser-flows.md` or `edge-cases.md`.

### Step 3.7: Generate UI State Sequence Tests (MANDATORY for CRUD apps)

For each entity type (notes, cards, transactions, etc.), generate interaction sequence tests that verify state AFTER multi-step operations:

```markdown
### UST-<contract-id>-<N>: <entity> CRUD lifecycle

**Type:** ui-state-sequence
**Entity:** <entity name>
**Tool:** Playwright MCP or gstack /qa-only

**Sequence 1: Create → Verify State**
1. Note the current count of items
2. Create a new item
3. VERIFY: count increased by 1
4. VERIFY: new item visible in list
5. VERIFY: sidebar/nav counts updated

**Sequence 2: Duplicate → Delete Copy → Verify Original Survives**
(if duplicate feature exists)
1. Select an existing item
2. Duplicate it
3. VERIFY: both original and copy exist (list shows 2)
4. VERIFY: copy has different ID than original
5. Delete the COPY (not original)
6. VERIFY: original STILL exists
7. VERIFY: count decreased by exactly 1

**Sequence 3: State Change → Verify All Views Update**
(for archive/pin/move/status changes)
1. Note counts in ALL sidebar sections (All: N, Folder A: M, Archived: K)
2. Archive/pin/move an item
3. VERIFY: item disappears from source view
4. VERIFY: item appears in target view
5. VERIFY: source count decreased by 1
6. VERIFY: target count increased by 1
7. VERIFY: other section counts UNCHANGED

**Sequence 4: Delete → Verify Isolation**
1. Note all current items and their IDs
2. Delete ONE specific item
3. VERIFY: only that item is gone
4. VERIFY: all other items still exist with same IDs
5. VERIFY: count decreased by exactly 1
```

**Why this exists:** a notes build had 21 passing API tests but 2 UI bugs:
- Archiving made ALL folder counts show 0 (state replaced, not filtered)
- Deleting a copy deleted the original (stale closure reference)

API tests can't catch these because they test individual HTTP operations, not frontend state after sequences of UI interactions. These tests MUST be executed via Playwright clicking through the actual UI.

Generate these for EVERY entity type in the contract.

### Step 4: Generate Edge Cases

From the contract's failure modes, derive edge cases:

```markdown
### EC-<contract-id>-<N>: <edge case name>

**Derived from failure mode:** <which one>
**Input:** <edge case input>
**Expected behavior:** <what should happen>
**What a broken implementation does:** <the failure the validator should catch>
```

### Step 5: Save

Create the artifacts directory at `.specship/specs/<id>-<slug>/artifacts/`.

Save files:
- `<contract-dir>/artifacts/test-cases.md` — unit + integration test cases
- `<contract-dir>/artifacts/browser-flows.md` — browser flow scripts (or "N/A" note)
- `<contract-dir>/artifacts/ui-state-sequences.md` — CRUD lifecycle interaction tests (Playwright/gstack)
- `<contract-dir>/artifacts/edge-cases.md` — edge cases from failure modes
- `<contract-dir>/artifacts/api-contract-tests.md` — API contract shape tests (full-stack only, or "N/A" for backend-only)

### Step 6: Commit

```bash
git add .specship/specs/<id>-<slug>/artifacts/
git commit -m "[specship] testgen: pre-generated test cases | contract: <id>"
```

### Step 7: Report

> "Test cases generated for contract <id>:
> - <N> unit test cases
> - <N> integration scenarios
> - <N> browser flows
> - <N> edge cases
>
> Saved to `.specship/specs/<id>-<slug>/`
>
> These will be used by the validation squad (especially the Alignment Checker) to judge whether the implementation meets the contract."

## Key Principles

- **Written before code exists.** This is the whole point. Tests written after implementation are biased by what was built, not what was needed.
- **Concrete inputs and outputs.** Never "test that it works" — always "given X input, expect Y output."
- **Adversarial edge cases.** Think like a QA engineer trying to break things, not like a developer confirming things work.
- **Browser flows are scripts, not tests.** They describe what a human would do, step by step. The browser validator (gstack /qa-only if the gstack Kiro Power is installed; else Playwright/Chrome-DevTools MCP or adversarial agent review) executes them.
- **Linked to criteria.** Every test case traces back to a specific acceptance criterion. If a criterion has no test case, that's a gap.
- **Red-able by construction.** Each case is written so BUILD can turn it straight into a failing test (RED) and then implement to green — one behavior, concrete I/O, explicit failure signal. testgen writes the plan; the `tdd` skill runs the loop.

## Mission Trace

This skill records its progress in the conceptual mission-state file (`.specship/state.json`) and trace log. At the start, note that testgen began for the current contract (`.specship/specs/<id>-<slug>/requirements.md`). At the end (after producing output), note completion with a status of PASS, FAIL, or SKIPPED and a one-line summary of the result.
