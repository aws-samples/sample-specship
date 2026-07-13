---
inclusion: manual
---

# Autonomous Multi-Hour Execution Model

> **Disclaimer**: SpecShip is experimental, unofficial tooling provided as-is with no warranty. This workflow produces tested, validated code that meets SpecShip's own quality standards, but all generated code is sample/reference implementation that requires additional security testing and AppSec review before any deployment. References to meeting the quality bar below mean meeting these SpecShip criteria, not a guarantee of deployment suitability.

This document defines how SpecShip runs for hours without human intervention, producing complete, tested code that meets SpecShip's internal quality criteria.

## The Problem with Single-Shot Builds

Current failure mode:
- Worker receives "build a Kanban board" → produces a working skeleton in 7 min
- Skeleton has gaps: no tests, some features missing, no error handling, no loading states
- Build is "done" but quality is 60% of the internal quality bar

## The Solution: Iterative Deepening Loop

Instead of one big build, SpecShip runs a LOOP that iterates until quality gates pass:

```
┌────────────────────────────────────────────────────────┐
│                                                        │
│   BUILD MILESTONE → TEST → VERIFY → GAP DETECT        │
│         ↑                                    │         │
│         │         (if gaps found)            │         │
│         └────────────────────────────────────┘         │
│                                                        │
│   (when ALL gates pass) → SHIP                        │
└────────────────────────────────────────────────────────┘
```

## The Milestone Loop (Core Engine)

For each milestone, run this loop:

### Phase 1: BUILD
- Run the build pass with: milestone spec + API contract + design spec + quality checklist. (In Kiro, Spec mode — requirements/design/tasks.md — is the natural home for this material; a fresh chat session keeps the build pass independent.)
- The build pass produces code and commits
- **For M1 specifically:** The build prompt must include: "After scaffolding, verify these 4 files exist and are correctly configured: index.html, vite.config (with correct root path), tailwind.config (reachable from vite root), postcss.config. Run `npx vite build` to confirm production build works before proceeding."

### Phase 2: TEST (Correctness — does the code work?)
After the build pass commits, IMMEDIATELY run:
```bash
# 1. Does it compile/build?
cd src/client && npx tsc --noEmit && npx vite build

# 2. Do existing tests pass?
npm test

# 3. Does the server start?
node src/server/index.js &
sleep 3 && curl -s http://localhost:PORT/health

# 4. Does the UI render? (Playwright)
browser_navigate(url)
browser_take_screenshot()
```

If ANY of these fail → fix immediately before moving on.

### Phase 2.5: INTERACT (UI State — do interactions produce correct state changes?)

**This is what catches "delete copy deletes original" and "archive breaks counts."** Unit tests and screenshots miss these because they test individual operations, not SEQUENCES of operations where state depends on previous actions.

For EVERY feature added in this milestone, run the CRUD lifecycle test via Playwright:

```
For each new entity/action added in this milestone:

  CREATE flow:
    1. Click the create/add button
    2. Fill the form
    3. Submit
    4. VERIFY: new item appears in the list (count increases)
    5. VERIFY: sidebar counts update correctly

  EDIT flow:
    6. Click the item
    7. Change a field
    8. Save (or wait for auto-save)
    9. VERIFY: change persists after navigating away and back

  STATE CHANGE flow (pin/archive/move/etc.):
    10. Perform the state change
    11. VERIFY: item moves to correct view
    12. VERIFY: counts update in ALL affected views (not just current)
    13. VERIFY: other items' counts are NOT affected

  DUPLICATE + DELETE flow (if duplicate exists):
    14. Duplicate the item
    15. VERIFY: original AND copy both exist (different IDs)
    16. Delete the COPY
    17. VERIFY: original STILL EXISTS
    18. VERIFY: count decreased by 1 (not 2)

  DELETE flow:
    19. Delete an item
    20. VERIFY: item gone from list
    21. VERIFY: count decreased
    22. VERIFY: other items unaffected
```

**WHY this phase exists (from real bugs):**
- a notes build: archiving a note caused ALL folder counts to show 0 (state was replaced, not filtered)
- a notes build: deleting a duplicate deleted the original (stale closure captured wrong note ID)
- an expense-splitter build: used "refetch after mutation" pattern → ZERO stale state bugs

Both notes-build bugs ONLY manifest through multi-step UI interaction — not through API tests, not through screenshots. This phase catches them.

**Prevention pattern (from the expense-splitter build):** Tell the build pass to use "refetch after mutation" — after every create/update/delete, call fetchData() to refresh ALL state from server. Do NOT manually splice arrays or optimistically update. This is slightly slower but prevents the entire class of stale-closure bugs.

**How to execute:**
- If the gstack Kiro Power is installed: `/qa` with the flows above
- If Playwright MCP is available: execute each step with browser_click, browser_fill, browser_snapshot, verify counts in DOM
- If NEITHER available: install one (see Rule 4 in specship-validate)

**If any interaction produces unexpected state → FIX before proceeding to next milestone.**

### Phase 3: VERIFY (Feature Check)
After tests pass, check WHAT was built against WHAT was required:
```
For each acceptance criterion in the contract:
  - Is there code that implements this? (grep for key functions/routes)
  - Can we verify it works? (make an API call, click in browser)
  - Mark: DONE / PARTIAL / MISSING
```

### Phase 4: GAP DETECT
Compare implemented features against the market research:
```
Table Stakes: 12 features
Implemented: 8 features
Missing: 4 features → generate tasks for next iteration
```

If gaps found → create NEW tasks and loop back to BUILD for the next milestone.
If all features implemented and tests pass → move to final validation.

## Multi-Hour Execution Strategy

### Milestone Sizing (15-30 min each)
- Milestone 1: Foundation (scaffolding, design system, DB schema, seed) — 15 min
- Milestone 2: Core feature group A (3-4 related features WITH tests) — 30 min
- Milestone 3: Core feature group B (3-4 related features WITH tests) — 30 min
- Milestone 4: Core feature group C + remaining features — 30 min
- Milestone 5: Polish pass (loading states, error handling, empty states for ALL features) — 25 min
- Milestone 6: Test hardening (integration tests, edge cases, coverage gaps) — 25 min
- Milestone 7: Gap fill (features found missing in gap detection) — 30 min
- Milestone 8: Final polish (keyboard shortcuts, animations, responsive, a11y) — 20 min
- Milestone 9: Deployment artifacts + documentation — 15 min

Total: ~3.5 hours for a complete production app.

### Test Writing Strategy (MANDATORY — HARD GATE)

Tests are NOT a separate milestone at the end. They are a **hard prerequisite to proceed to the next milestone.** A milestone WITHOUT sufficient tests is NOT complete — it BLOCKS advancement.

**The rule:** Every milestone must produce BOTH the implementation AND its tests. If tests fail or are missing, the milestone is INCOMPLETE. You cannot commit the milestone or proceed.

**Per-milestone test requirements (MINIMUM):**

| Milestone Type | Required Tests | Minimum Count |
|----------------|----------------|---------------|
| Backend API milestone | Integration tests for every endpoint added (happy path + at least 1 error case per endpoint) | 3 tests per endpoint minimum |
| Frontend component milestone | Unit tests for every component (renders, handles props, fires callbacks) | 2 tests per component minimum |
| Frontend feature milestone | Integration tests (component + API interaction, or component + WebSocket) | 3 tests per feature minimum |
| Infrastructure milestone | Health check, DB connection, WebSocket connection | 3+ tests |
| Polish milestone | Accessibility tests, error boundary tests, edge cases | 5+ tests |

**Test categories required per milestone type:**

**Backend milestones (API routes, DB):**
- Unit tests: individual function logic (validation, transformation)
- Integration tests: full request → response cycle via supertest
- Error case tests: invalid input, auth failures, 404s, 409s
- Example: POST /api/channels needs at minimum:
  1. Create channel successfully → 201 + correct shape
  2. Create with invalid name → 400
  3. Create duplicate name → 409
  4. Create without auth → 401

**Frontend milestones (components, pages):**
- Unit tests: component renders without crashing, displays correct content for given props
- Interaction tests: user events (click, type, submit) produce expected behavior
- Integration tests: component + hook + API mock (or real API in integration mode)
- Example: MessageInput component needs at minimum:
  1. Renders textarea and send button
  2. Typing updates the textarea value
  3. Enter key calls the send handler
  4. Empty input doesn't trigger send
  5. Shift+Enter creates newline (doesn't send)

**WebSocket milestones:**
- Connection tests: connect with valid/invalid tokens
- Event tests: emit event → verify broadcast received
- Timeout tests: typing timeout, presence timeout

**Coverage threshold (HARD GATE):**
After running tests for a milestone, check:
- New code introduced in this milestone must have >= 70% line coverage from its tests
- If coverage < 70%: milestone is INCOMPLETE. Write more tests before committing.
- Use: `npx vitest run --coverage` (configure vitest with @vitest/coverage-v8)

**How to measure per-milestone (approximate when full coverage tooling isn't set up):**
- Count: endpoints/components/features added in this milestone
- Count: tests written
- Ratio check: if you added 5 endpoints and only wrote 3 tests → FAIL (need 15+ tests: 3 per endpoint)
- Ratio check: if you added 4 components and wrote 0 tests → FAIL (need 8+ tests: 2 per component)

**Build-pass prompt addition (include in EVERY build pass):**
```
## Testing Requirement (HARD GATE — blocks next milestone)

You MUST write tests for every feature you implement in this milestone.
Tests are NOT optional. Tests are NOT "nice to have." Tests are a HARD GATE.

Requirements:
- Backend endpoints: minimum 3 tests per endpoint (success + error + edge case)
- Frontend components: minimum 2 tests per component (renders + interaction)
- Features: minimum 3 tests per feature (happy path + error + edge case)

After implementation, run ALL tests. If any fail, fix them.
Count your tests vs features: if the ratio is < 3 tests per endpoint or < 2 per component,
you MUST write more tests before the milestone is complete.

A milestone without sufficient tests is NOT complete. Period.
The build loop WILL reject your milestone if test count is insufficient.
```

**Milestone verification (expanded):**
```
After each milestone, the build loop checks:
1. `npm test` → ALL tests pass (zero failures)
2. Count new tests written in this milestone >= threshold for milestone type
3. No untested endpoints/components (every new file has a corresponding test)
4. If any check fails → milestone is NOT committed → fix before proceeding
```

This ensures that by the time the build is "complete," there are 60-100+ tests passing — not 37 discovered at the end with zero frontend coverage.

### State Persistence (Survives Context Compaction)

After EVERY milestone, record mission state in the conceptual mission-state file (`.specship/state.json`). **Use the canonical schema — defined once in the shared `context-management` reference (its "State Schema (Canonical)" section) — do not restate or fork it here.** The build-relevant fields are `phase`, `milestones_total`, `milestones_completed` (integer count, never an array), `current_milestone`(+name), `next_task`, and `last_commit` (set to `git rev-parse HEAD` after the milestone commit). The forbidden legacy names (`milestone_current`, `milestone_total`, `next_action`) and the integer-vs-array rule also live in that reference. When context compacts, read this file and you know exactly where to continue.

### Test-After-Every-Milestone Rule (Non-Negotiable — HARD GATE)

**The #1 cause of "gaps and bugs" is building without testing between milestones.** If you build 6 milestones then test at the end, you discover 15 bugs that require going back through all 6 milestones to fix.

**The test gate is a HARD REQUIREMENT — not a suggestion.** A milestone that doesn't pass the test gate is NOT committed and does NOT advance.

**After EACH milestone, the build loop MUST verify:**
1. `npm test` → ALL tests pass (zero failures) — if any fail, fix before moving on
2. **Test count check:** sufficient tests exist for this milestone's scope (see thresholds in Test Writing Strategy)
3. **No untested features:** every endpoint/component/hook added in this milestone has corresponding test(s)
4. Start the app → navigate → does it render? — if not, fix
5. Test the feature just built (via Playwright if UI, or curl if API) — if broken, fix

**If ANY of the 5 checks fail → milestone is REJECTED:**
- Do NOT commit
- Do NOT update the mission-state file
- Do NOT proceed to next milestone
- FIX the issue (write tests, fix failures, add coverage)
- Re-run all 5 checks
- Only when ALL pass → commit and advance

**Example gate failure scenarios:**
- "All 10 tests pass but I only wrote 2 tests for 5 new endpoints" → REJECTED (need 15+ tests)
- "I wrote 20 tests but 3 are failing" → REJECTED (fix the failures)
- "All tests pass but the MessageInput component has no test file" → REJECTED (write component tests)
- "Tests pass, count is sufficient, but the app shows a blank page" → REJECTED (fix rendering)

This means bugs are caught within 5 minutes of being introduced, not 2 hours later. It also means test debt does NOT accumulate across milestones.

### Self-Healing Loop

When a test fails or feature doesn't work:
1. Read the error message
2. Identify the likely cause (from the error + recent changes)
3. Run a focused fix pass with: error message + relevant file + what the code should do (a fresh chat session keeps this fix independent)
4. The fix pass makes the change
5. Re-run the test
6. If still fails → try again (max 3 attempts)
7. If 3 failures → log the issue and continue to next milestone (validation will catch it)

### Feature Completeness Enforcement

At the END of the build (after all planned milestones), run the **computed coverage gate** — this is `specship-build` Step 3.5 (Gap Detection), the single authoritative implementation. Do NOT re-implement a second gap check here; that drift is exactly what this refactor removed.

In short, Step 3.5:
1. Extracts one checklist row per table-stakes feature and asserts the count matches the brief.
2. Greps the codebase for each feature's marker terms and **computes** `found/total` coverage.
3. FAILs below 0.80, logs every missing feature by name, and loops gap-fill until coverage clears or the `dispatch_budget` cap is hit (logging anything still missing — no silent caps).

This is the "last mile" that ensures production completeness, with a number instead of a self-assessment.

## Quality Gates (ALL must pass before /specship-ship)

| Gate | Check | Tool |
|------|-------|------|
| Compiles | `tsc --noEmit` passes | Bash |
| Builds | `vite build` succeeds | Bash |
| Tests pass | `npm test` → 0 failures | Bash |
| Server starts | Health endpoint returns 200 | curl |
| UI renders | Screenshot shows real content | Playwright |
| Features complete | 80%+ table-stakes implemented | Manual check |
| No inline styles | `grep -r "style={{" src/` returns empty | Bash |
| Design system used | Tailwind config has custom tokens | File check |
| API shapes match | Integration validator PASS | Focused pass |
| Security | No secrets, parameterized queries | Focused pass |

If ANY gate fails → fix it before shipping. This is what meeting the internal quality bar means.

## How the Build Loop Uses This

The build skill (`/specship-build`) follows this loop:
1. Read the plan → determine milestones
2. For each milestone:
   a. Run the build pass
   b. After commit: run TEST phase
   c. If test fails: run self-healing (max 3 attempts)
   d. Run VERIFY phase (feature check)
   e. Update the mission-state file
   f. Commit milestone checkpoint
3. After all milestones: run GAP DETECT
4. If gaps: run one more milestone
5. Run ALL quality gates
6. If all pass → trigger /specship-validate (full squad — in Kiro, fan these out as spec task waves of independent validation tasks)
7. If validate passes → /specship-ship

This is a 3-5 hour process. It runs without human intervention.
