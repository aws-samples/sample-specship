---
inclusion: manual
---

# Regression Recipe Catalog

This catalog turns SpecShip's empirical learnings into **per-project regression tests**. When a validator finds a bug (or `specship-recover` fixes one), the fix MUST ship with a regression test written in the **generated project's own test framework** (jest/vitest/pytest/go test/rspec — whatever the project uses). SpecShip ships no executable test runner of its own and target projects are polyglot, so these are *recipes* (the assertion to generate), not committed scripts.

**The rule (operationalizes Learning 16):** Every bug a validator finds becomes a permanent guard. The fix alone is insufficient — without a test, a future refactor reintroduces it. `specship-build`'s TEST GATE rejects a `[specship-fix]` commit that resolves a finding but adds no corresponding regression test.

Each recipe states: the finding class → the assertion to generate (framework-agnostic) → why.

---

## Recipe 1: Frontend–backend shape mismatch (Learning 1)
**Trigger:** Integration validator finds `data.items` vs backend `res.json([...])`.
**Assertion to generate:** A test that asserts the response IS the expected shape directly.
- API/integration test: `GET /api/x → expect Array.isArray(body) === true` (or `expect body.items` if the contract wraps — match `api-contract.md`).
- Why: locks the contract shape so a future handler change that re-wraps the payload fails loudly.

## Recipe 2: Negative / boundary input bypasses validation (Learning 14)
**Trigger:** Security validator finds negative amounts, integer overflow, division by zero, empty/oversized input accepted.
**Assertion to generate:** Per attack vector, a test that the boundary input is REJECTED.
- `POST /api/expense { amount: -100 } → expect 400`
- `POST /api/expense { amount: 0, split: 0 } → expect 400` (no divide-by-zero)
- `POST … { name: "<10001 chars>" } → expect 400` (length cap)
- Why: unit tests cover the happy path; these cover the attack surface that validators flagged.

## Recipe 3: Auth bypass on a new endpoint
**Trigger:** Security validator finds a route missing auth middleware.
**Assertion to generate:** `<verb> /api/protected` WITHOUT a token `→ expect 401`; with another user's token `→ expect 403`.
- Why: guards the door the validator found unlocked.

## Recipe 4: Stale-state / delete-the-wrong-item (Learning 11, 15)
**Trigger:** Browser validator finds "delete copy deletes original," "archive zeroes all counts," or any state-after-sequence bug.
**Assertion to generate:** A browser/interactive test of the FULL lifecycle, not single ops.
- create → assert appears, count +1 → duplicate → assert BOTH exist (distinct ids) → delete copy → assert original survives, count −1 (not −2).
- archive/pin/move → assert counts update in ALL affected views, others unaffected.
- Why: API tests and screenshots miss sequence-dependent state; only interactive flows catch it. Prefer the "refetch after mutation" pattern (Learning 15) in the fix.

## Recipe 5: Loading state never resets (Learning 18)
**Trigger:** Browser validator finds a form stuck on "Saving…" after submit.
**Assertion to generate:** An interactive test: fill form → submit → wait → assert the submit button returns to enabled AND (dialog closes OR success shown).
- Why: `PUT /api/x` passing says nothing about the frontend's `isSubmitting`/`.finally()` handling. Only a browser flow proves the UI state resets.

## Recipe 6: All defined UI sequences must run (Learning 17)
**Trigger:** Aggregate finds `sequences_executed < sequences_defined`.
**Assertion to generate:** Not a code test — a process check: the browser validator's verdict `evidence[]` must list every sequence in `ui-state-sequences.md`. Missing any → verdict INCOMPLETE.
- Why: each sequence (Create/Edit/Delete/Duplicate/StateChange) catches a different bug class; running a subset hides the rest.

## Recipe 7: camelCase / snake_case drift (Learning 10)
**Trigger:** Integration validator or a test finds `columnId` vs `column_id`.
**Assertion to generate:** A test asserting the response object has the EXACT keys the contract specifies (`expect Object.keys(body[0]) toContain 'column_id'`).
- Why: pins the casing convention so a future serializer change is caught.

---

## How skills use this catalog

- **`specship-recover` Step 4:** after fixing a finding, look up its class here and generate the matching assertion in the project's framework. Commit the fix + test together.
- **`specship-build` TEST GATE:** a `[specship-fix]` commit that resolves a finding but adds no new test for it is REJECTED.
- **`specship-validate` (security/browser):** when reporting a finding, the validator may name the recipe so the fixer knows exactly what test to write.

Add a new recipe whenever a real build surfaces a new durable bug class — keep this catalog in lockstep with `build-learnings.md`.
