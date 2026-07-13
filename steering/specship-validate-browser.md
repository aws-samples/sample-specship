---
inclusion: manual
---

# specship-validate-browser — Browser Testing Validator

<HARD-GATE>
STOP. Before doing ANYTHING else in this validator:
- If gstack is installed (check: does ~/.kiro/skills/gstack-qa-only exist?), you MUST activate the `qa-only` skill and let IT run the browser QA. Do NOT manually click through the app yourself.
- If gstack is NOT installed: install it now (`git clone --depth 1 https://github.com/garrytan/gstack.git ~/.kiro/skills/gstack && mkdir -p ~/.kiro/skills/gstack-qa-only && cp ~/.kiro/skills/gstack/qa-only/SKILL.md ~/.kiro/skills/gstack-qa-only/SKILL.md`), then activate the `qa-only` skill.
- Taking a single screenshot and writing "looks good, PASS" is a PROTOCOL VIOLATION. You must run the full CRUD interaction sequences.
- PROOF OF ACTIVATION: when gstack is installed, the FIRST entry in your verdict's `evidence[]` MUST be `"activated skill: qa-only"`. (If gstack is absent and you ran Playwright MCP directly, the first entry must be `"Playwright MCP, no gstack"` — never a bare PASS.)
</HARD-GATE>

You verify the implementation by testing it in a real browser — clicking through flows, filling forms, checking states, capturing screenshots. Test like a real user, not a developer. **Every assertion needs a screenshot.**

Suggested model: Sonnet (or Auto). In Kiro, browser actions run through **Playwright MCP**; if the **gstack Kiro Power** is installed, prefer its `/qa-only` which automates this.

## Inputs

1. Sprint contract — what was built.
2. Browser flows — the pre-generated flow scripts for this contract (e.g. `browser-flows.md`).
3. Running app URL — provided or auto-detected.

## Pre-conditions

### UI Detection (determines if browser validation is mandatory)

Read the contract and test cases. Check:
1. Does the contract mention ANY user-visible behavior? (page, UI, form, button, click, display, show, render, view)
2. Do the browser flows say "No browser flows needed"?
3. Is this purely a library/CLI/backend-only with no HTML rendering?

**Decision:**
- Browser flows explicitly say "No browser flows needed" AND the contract has ZERO user-visible criteria → SKIP allowed.
- Contract mentions ANY user-facing behavior (even if flows say N/A) → browser validation is MANDATORY.
- App serves HTML on any route → browser validation is MANDATORY.

### The "curl is not browser" Rule

An HTTP 200 from curl proves the server responds. It does NOT prove the page renders visually, JavaScript executes without errors, components mount, or the user sees what was intended.

If the contract has UI criteria, you MUST: (1) navigate to the app in a real browser, (2) screenshot as proof of rendering, (3) check the console for JS errors, (4) verify at least ONE interactive element works. A curl 200 with no screenshot = FAIL for UI contracts.

### Evidence Required

Your verdict MUST include:
- At least 1 screenshot file path showing the rendered page. **Write ALL screenshots to `.specship/artifacts/traces/` (gitignored) — e.g. `.specship/artifacts/traces/m8-dashboard.png`. Do NOT write screenshots to the repo root or any source dir; they will be committed as stray binaries and pollute the PR (this happened on a real run).**
- Console error count (0 = clean, >0 = listed).
- Interactive test result (at least 1 click or form fill attempted).
- A **CREATE → VERIFY** flow: create a resource, verify it appears without refresh.

Without these artifacts, the verdict is INCOMPLETE regardless of what you believe about the code.

### The "Create → Verify Appears" Rule (MANDATORY)

For any CRUD app, test at least one complete cycle:
1. Navigate to the list view.
2. Verify initial state (empty or existing items).
3. Create a new item via the UI (fill form, click submit).
4. **WITHOUT refreshing**, verify the new item APPEARS in the list.
5. If it doesn't appear → **FAIL** — a guaranteed user-visible bug.

This single test catches the entire "API works but frontend doesn't show results" class. **Why it exists:** SpecShip built a full-stack app with 70 passing tests that looked correct in code review — but creating a workspace didn't show it, because the frontend expected `data.workspaces` while the API returned `data` directly. This test catches it in 10 seconds.

## Process

### Step 1: Detect the app URL

Try common dev ports (3000, 4000, 5173, 8080, 8000); use the first that responds 200/301/302. If none, ask: "What URL should I test against?"

### Step 2: Select the browser tool

Priority order in Kiro:
1. **gstack `/qa-only <URL>`** — if the gstack Kiro Power is installed (best: automated, finds bugs, generates regression tests; use `/qa-only` for validation so it doesn't change code).
2. **Playwright MCP** — the default in Kiro. Wire it in `.kiro/settings/mcp.json`. Real browser, scripted clicks.
3. **Chrome DevTools MCP** — last resort.

**Never fall back to "an agent reads the code and imagines the UI."** That is NOT browser validation. Browser validation = real browser, real clicks, real screenshots.

If no browser tool is available → install Playwright MCP (add it to `.kiro/settings/mcp.json`). If nothing works → verdict is **INCOMPLETE** (blocks shipping). For UI contracts, **SKIPPED is not valid** — the options are PASS (with screenshots), FAIL (tested, found issues), or INCOMPLETE (tool unavailable). The only acceptable SKIP is a contract with ZERO UI criteria.

### Step 3: Interactive flows — NOT just screenshots

A screenshot only proves the page renders. It does NOT prove clicking does the right thing, state updates correctly across a sequence, counts/badges update, deleting a copy spares the original, or archiving doesn't break other views.

Setup: navigate to the app, screenshot the initial state, check console messages for JS errors. Then run the FULL CRUD lifecycle below.

### Step 3.5: CRUD Interaction Sequences (MANDATORY for any CRUD app)

For EVERY entity type, test the full lifecycle (screenshot at every numbered step — each screenshot is evidence):

```
# CREATE → VERIFY
1. Click Create/Add/New
2. Fill the form with test data
3. Submit
4. VERIFY: the new item appears in the list

# EDIT → VERIFY
5. Click the item you created
6. Change a field
7. Save
8. VERIFY: the change persists (navigate away and back)

# DUPLICATE → DELETE COPY → VERIFY ORIGINAL SURVIVES
9.  Duplicate the item (if the feature exists)
10. VERIFY: both original and copy exist (different IDs)
11. Delete the COPY
12. VERIFY: the ORIGINAL still exists

# DELETE → VERIFY GONE
13. Delete the original
14. VERIFY: it's gone from the list

# STATE CHANGES → VERIFY COUNTS
15. Archive/pin/move an item
16. VERIFY: sidebar counts update correctly
17. VERIFY: item appears/disappears from the correct view
```

This catches the EXACT class of bugs unit tests miss:
- "Delete copy deletes original" (stale state reference)
- "Archive makes all counts show 0" (filtered data used for counts)
- "Create doesn't appear without refresh" (missing optimistic update / no refetch)

**ALL sequences must run — not a subset.** If the flows define 5 sequences, run all 5. Running 2/5 and claiming PASS is a protocol violation — each sequence catches a different bug class:
- Create → "doesn't appear" bugs
- Edit → "loading state never resets" bugs (INVISIBLE to API tests)
- Delete → "wrong item deleted" bugs
- Duplicate → "stale closure" bugs
- State change → "counts don't update" bugs

Count `sequences_executed / sequences_defined`; if < 100% → INCOMPLETE (blocks shipping).

**Form submit sequences specifically:** for EVERY form/dialog, test fill → submit → verify the button returns to normal (not stuck on "Saving…") + the dialog closes or shows success. A permanently disabled submit button is a user-blocking bug API tests cannot detect.

### Step 4: Custom browser flows

For each flow defined for this contract: navigate to the start URL, execute each step with the browser tool, verify expected state at checkpoints (screenshot each checkpoint), capture evidence.

### Step 5: Output verdict

```markdown
## Browser Testing Verdict
**Contract:** <id> — <title>
**Status:** PASS | FAIL | INCOMPLETE | SKIPPED

### Flow Results
| Flow | Steps | Result | Evidence |
|------|-------|--------|----------|
| <flow> | N/N completed | PASS/FAIL | <screenshot path> |

### Console Errors
- [JS errors observed]

### Blocking Issues
- [broken flows that must be fixed]
```

Record the verdict (and its screenshots) where the aggregator can read it. If the browser tool is missing, install Playwright MCP via `.kiro/settings/mcp.json` rather than skipping.

### Required machine-readable verdict (MUST be the last thing in your response)

```json
{
  "validator": "browser",
  "status": "PASS | FAIL | INCOMPLETE | SKIPPED",
  "evidence": [
    { "claim": "create→appears→duplicate→delete-copy→original survives", "artifact": "flow-crud.png" }
  ],
  "blocking_issues": [
    { "summary": "delete copy removed original", "file": "src/client/...", "line": 0, "expected": "original survives", "actual": "both deleted" }
  ],
  "sequences_executed": 5,
  "sequences_defined": 5
}
```
Rules: `status: "PASS"` is INVALID without at least one screenshot artifact AND `sequences_executed == sequences_defined`. Screenshot-only with no interaction → INCOMPLETE, never PASS.

## Decision Rules

- "No browser flows needed" + zero UI criteria → SKIPPED.
- App not running and can't be started → INCOMPLETE (install/start it; not a silent pass).
- All flows pass AND all defined sequences executed → PASS.
- Any flow fails → FAIL.
- No browser tool available → INCOMPLETE (with install guidance) — never PASS.
