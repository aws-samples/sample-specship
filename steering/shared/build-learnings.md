---
inclusion: manual
---

# Build Learnings (Empirical — from real builds)

This document captures what we LEARNED from building real applications with SpecShip. Each entry is backed by a specific build failure or success. Run names are generalized to app types — the lesson is what matters, not which app.

## Learning 1: API Contract in Worker Prompt → Zero Shape Mismatches
**Source:** a project-management build failed; a bookmark-manager build + a chat build succeeded
**The rule:** Every frontend worker's prompt MUST include the API contract with exact response shapes. "The backend returns plain arrays" must be EXPLICIT, not implied.
**Evidence:** the project-management build had a `data.workspaces` (wrapper vs plain-array) bug in all 3 components. After adding the API contract to prompts, the later builds had ZERO mismatches.

## Learning 2: Market Research → Table-Stakes Features
**Source:** a chat build initially delivered 4/14 features
**The rule:** The market research's table-stakes list must be EXPLICITLY included in the worker prompt as a numbered checklist with "you must implement all of these."
**Evidence:** a kanban-board build received an explicit checklist → delivered 10/10 features on first pass.

## Learning 3: Design System in Tailwind Config → Visual Consistency
**Source:** a bookmark-manager build was inline-styled garbage; a chat build matched its real-world reference.
**The rule:** Milestone 1 must set up Tailwind with exact colors/fonts/spacing from the contract's Design Spec. All subsequent workers inherit the design system automatically.
**Evidence:** the chat build's screenshot showed a dark sidebar, Inter font, compact density — because tailwind.config.ts was set up correctly in M1.

## Learning 4: SQLite First → No Docker Dependency
**Source:** a chat build's backend couldn't start because Docker wasn't available
**The rule:** Use SQLite (better-sqlite3) for all builds. It runs everywhere, zero config. Upgrade to PostgreSQL only when explicitly needed (multi-user concurrent writes).
**Evidence:** after switching to SQLite, the backend started immediately. The kanban-board build used SQLite from the start with zero issues.

## Learning 5: Drift Comes From Missing Contracts, NOT From Subagents
**Source:** a small single-pass build that worked; a multi-pass chat build that drifted; **and an autonomous full-app run that FAILED TO COMPLETE**
**The rule (CORRECTED):** Earlier we concluded "for apps under ~2000 lines, one focused coordinator pass beats splitting the work." **That conclusion was wrong for autonomous SpecShip builds and is now retired.** A single accumulating coordinator pass that builds the whole app inline blows the context window — one autonomous run created ~100 files in one context, looped on a browser test, and ran out of context/step budget before any validator ran. Subagents are MANDATORY for feature milestones precisely because they **bound the coordinator's context** and prevent that failure.
**What actually caused the chat-build drift** (a `typing:update` vs `typing:start/stop` event mismatch) was NOT "too many workers" — it was workers that didn't share the WebSocket/API contract. The fix is to inject `api-contract.md` + `ws-contract.md` into EVERY subagent (see `worker-prompt-template`), NOT to collapse into one pass.
**Do NOT cite this learning to justify building as coordinator.** "It's under 15 features / under 2000 lines / one pass is more consistent" is a forbidden rationalization — see `specship-build`'s subagent-dispatch gate.
**Evidence:** the small single-pass build worked because it was small AND short-lived. The accumulating full-app pass failed to complete. Builds that dispatched per-task subagents with the contract injected finished cleanly through VALIDATE and SHIP.

## Learning 6: Verify in Browser with Playwright → Catch Visual Bugs
**Source:** All builds — screenshots are the only way to know if the UI actually renders
**The rule:** After each UI milestone, take a Playwright screenshot. "Build succeeds" is not "app works."
**Evidence:** Every build that we screenshotted worked. The builds we didn't screenshot had invisible bugs.

## Learning 7: Seed Data Must Be Realistic → Exposes Design Issues
**Source:** a kanban-board build's seed data showed the board working with real content
**The rule:** Seed data should look like a real user's account (8-15 items, varied states, realistic names). Not "Test 1, Test 2, Test 3."
**Evidence:** the kanban seed had realistic tasks ("Setup authentication system", "Fix login redirect bug") with varied priorities and assignees.

## Learning 8: Empty States Are Required → Not Optional
**Source:** a chat build's DM channel showed "No messages yet" — this is professional
**The rule:** Every list/collection view MUST have an empty state with helpful messaging.
**Evidence:** both the chat and kanban-board builds showed empty states when appropriate.

## How to Apply These

When you generate a build pass (the prompt/spec the worker follows), it should:
1. Include the API contract (Learning 1)
2. Include the table-stakes checklist (Learning 2)
3. Reference the Tailwind config (Learning 3)
4. Use SQLite (Learning 4)
5. Dispatch a per-task subagent with the API/WS contract injected (Learning 5 — never one accumulating pass)
6. Screenshot after each milestone (Learning 6)
7. Include realistic seed data instructions (Learning 7)
8. Explicitly require empty states (Learning 8)

## Learning 9: Self-Healing Test Loop Works
**Source:** a kanban-board build — tests found 3 bugs (wrong field names), fixed iteratively until green
**The rule:** After writing tests, RUN them immediately. If they fail, read the error, fix the cause, re-run. Max 3 iterations before moving on.
**Evidence:** the tests went from 3 failures → 1 failure → 0 failures in 3 iterations. All bugs were field name mismatches (columnId vs column_id) — exactly the kind the integration validator catches.

## Learning 10: Worker Prompt Field Names Must Match API
**Source:** both a kanban-board build's tests and a chat build's integration had camelCase vs snake_case issues
**The rule:** The API contract should explicitly state whether the API uses camelCase or snake_case. Workers must use the SAME convention throughout. Mixing = guaranteed bugs.
**Evidence:** a backend used camelCase in request bodies (columnId) but snake_case in DB responses (column_id). Tests exposed this inconsistency immediately.

## Learning 11: UI State Bugs Require Interactive Testing (not API tests or screenshots)
**Source:** a notes build — 2 bugs shipped despite 21 passing tests
**Bug 1:** Clicking "Archived" made all folder counts show 0 (state replaced instead of filtered for sidebar)
**Bug 2:** Deleting a duplicated note deleted the original (stale closure captured wrong note ID)

**Why tests didn't catch it:** API tests verify individual HTTP operations work. They don't test SEQUENCES where frontend state depends on previous actions. Screenshots verify rendering, not interaction behavior.

**The rule:** For every CRUD feature, the browser validator must test the FULL LIFECYCLE:
- Create → verify appears → count increases
- Duplicate → verify both exist → delete copy → verify original survives
- Archive/pin/move → verify counts update in ALL views (not just current)
- Delete → verify gone → verify others unaffected

**How to apply:** The INTERACT phase (Phase 2.5 in the autonomous-execution reference — see the shared autonomous-execution reference in this Power's steering/shared/) runs these sequences DURING the build — not just at final validation — via Playwright, or via gstack `/qa` if the gstack Kiro Power is installed (else the Playwright/Chrome-DevTools MCP, or adversarial agent review). This catches state bugs within minutes of introduction.

## Learning 12: "PASS" Without Evidence is Fabrication
**Source:** a build reported "ALL GATES: PASS" without running the browser validator or gstack
**The rule:** A verdict of PASS requires EVIDENCE from an actually-executed validation pass. If you didn't run it, the status is NOT_RUN which BLOCKS shipping. Never substitute your own judgment for a real validation pass.
**How to apply:** Rule 5 in the specship-validate steering enforces this. The aggregate step checks all validators actually returned before producing a verdict.

## Learning 13: Vite/Build Config Breakage is the #1 "Blank Page" Cause
**Source:** an expense-splitter build — missing index.html, wrong vite root, missing postcss/tailwind configs, `border-border` class error
**The rule:** When a single focused pass builds an entire app, it often creates files that reference configs in the wrong locations. Milestone 1 MUST verify: `index.html` exists, `vite.config` points to correct root, `tailwind.config` is reachable from vite's root, and `postcss.config` is present. These 4 files must be verified BEFORE any component code runs.
**How to apply:** After M1, run `npx vite build` (not just `npx vite` dev mode). If the production build fails, the foundation is broken — fix before M2.

## Learning 14: Security Validator Finds REAL Vulnerabilities (Not Just Style Issues)
**Source:** an expense-splitter build — the security validator found negative split amounts (balance manipulation), integer overflow, division by zero. These are actual exploitable bugs, not theoretical concerns.
**The rule:** The security validator is NOT optional "nice to have." It finds bugs that unit tests don't test for (boundary conditions, negative values, extreme inputs). It should generate test cases for the bugs it finds — not just report them.
**How to apply:** After a security fix, add a regression test that specifically tests the attack vector. E.g., "POST expense with negative split → expect 400."

## Learning 15: "Refetch After Mutation" Pattern Prevents Stale State Bugs
**Source:** an expense-splitter build used `fetchData()` after every create/edit/delete. This is why it passed the interactive state sequences (unlike an earlier notes build that had stale-state bugs).
**The rule:** For CRUD apps, the safest pattern is: mutation → refetch ALL related data (not optimistic update with manual state manipulation). It's slightly slower but prevents the entire class of "stale closure" bugs.
**How to apply:** Worker prompts for CRUD apps should specify: "After every create/update/delete, call fetchData() to refresh ALL state. Do NOT manually splice arrays or optimistically update — refetch from server."

## Learning 16: Validator-Found Issues Should Become Regression Tests
**Source:** an expense-splitter build — the security validator found a negative-splits bug, we fixed it, but didn't add a TEST for it
**The rule:** Every bug found by a validator should result in a NEW test that prevents regression. The fix alone isn't enough — without a test, a future refactor could reintroduce it.
**How to apply:** Now operationalized — see the shared regression-recipes reference (in this Power's steering/shared/) for the assertion to generate per finding class. The specship-recover steering's Step 4 mandates the test; the specship-build steering's TEST GATE REJECTS a `[specship-fix]` commit that resolves a finding but adds no regression test. Tests are written in the generated project's own framework (jest/vitest/pytest/etc.), not a SpecShip-side script.

## Learning 17: ALL UI State Sequences Must Be Executed — Not a Subset
**Source:** an expense-splitter build — the Edit flow stuck on "Saving..." because the Playwright test only ran Create + Delete sequences, skipped the Edit sequence
**The rule:** When the ui-state-sequences reference defines N sequences, ALL N must be executed. You cannot "run 2 out of 5 and call it done." Each sequence catches a different class of bugs. The Edit flow catches loading-state-never-reset bugs that Create and Delete don't.
**How to apply:** After executing interactive flows, CHECK: "Did I run all N sequences from the shared ui-state-sequences reference (in this Power's steering/shared/)? If not, I am NOT done." The aggregate should count: sequences_defined vs sequences_executed. If executed < defined → verdict is INCOMPLETE.

## Learning 18: Loading State Bugs Are Invisible to API Tests
**Source:** an expense-splitter build — `PUT /api/expenses/:id` works perfectly (test passes). But the frontend form's loading state got stuck because the promise handler had a bug (missing `.finally()` or a catch that doesn't reset isSubmitting).
**The rule:** API tests prove the backend works. They say NOTHING about whether the frontend's UI state (loading spinners, disabled buttons, error messages) behaves correctly. This is ONLY testable via interactive browser flows that click Submit → wait → verify the button resets.
**How to apply:** For every form in the app, the browser validator must test: fill form → submit → verify button returns to enabled state + dialog closes (or shows success). A permanently stuck "Saving..." button is a guaranteed user-visible bug.
