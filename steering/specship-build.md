---
inclusion: auto
name: specship-build
description: Use to execute a SpecShip plan — the iterative milestone loop (build → test with TDD red/green → interactive-verify → gap-detect → commit → repeat). Triggered by "start building", "execute the plan", "build the milestones", "specship build".
---

# specship-build — Mission Execution (Multi-Hour Autonomous)

## ⛔ STOP — READ THIS BEFORE YOU BUILD ANYTHING. THIS IS NOT OPTIONAL.

**In BUILD, you are a DISPATCHER, not a builder.** For every feature milestone (Milestone 1+) you dispatch the work to a fresh subagent (in the Kiro IDE: the **General Task Execution / `subagent`** tool — you have it, use it). You do NOT author feature files yourself.

**This is not a style choice or a tradeoff. Building feature milestones yourself as the coordinator is a GUARANTEED MISSION-KILLING FAILURE.** Here is the evidence — every autonomous coordinator-build of a real (multi-feature) app has failed the same way:

| Mission | What it did | Result |
|---|---|---|
| Multi-feature app A | coordinator built inline | 💥 ran out of context/step budget before any validator ran |
| Multi-feature app B | coordinator built inline | 💥 failed to complete mid-build |
| Multi-feature app C (run 1) | coordinator built inline | 💥 budget-exhausted partway through the milestones |
| Multi-feature app C (run 2) | coordinator built inline | 💥 budget-exhausted near the deployment milestone |

A coordinator build accumulates roughly one tool call per file + test + fix. A real app runs to **many hundreds or thousands of such steps in a single accumulating context**, which exhausts the agent's context/step budget — the session fails before it finishes, **losing the entire mission, with no validator, no ship, nothing recoverable in that session.** This is not specific to any one IDE or model; it is a property of any long-horizon agent running unbounded work in one context. Dispatching to subagents is the ONLY thing that keeps the coordinator's context bounded below that ceiling. **You are not the exception. Your build will fail exactly like the four above if you build it yourself.**

**THE FAILURE SIGNATURE — if your own reasoning contains ANY of these phrases, you are mid-failure right now:**
> "tightly coupled" · "keeps it coherent" · "as the coordinator" / "build as coordinator" · "for a build of this scale" · "one pass is more consistent" · "I'll build … myself" · "simpler/faster to coordinate"

Each of those exact rationalizations preceded a failure above. They feel reasonable. They are the bug. The moment you notice one in your thinking, STOP and dispatch.

**YOUR ALLOWED ACTIONS in Milestone 1+ are ONLY:** print the banner → dispatch a subagent for the task(s) → verify the test gate → commit → write state.json. **Authoring a feature file (route, component, hook, service, repo, page) with a file-write tool in Milestone 1+ is a protocol violation** — that is the subagent's job, not yours. Phase 0 (scaffold/infra) is the ONLY part you build directly.

**MANDATORY AFFIRMATION:** before the first feature milestone, output this line verbatim, then do it:
> "BUILD = DISPATCH. I am the dispatcher. I will NOT author feature files. Dispatching Milestone 1 to a subagent now."

If you cannot honestly write that line, you have already decided to fail the mission. Dispatch.

**FORBIDDEN RATIONALIZATIONS (no project size or coupling grants you authority to build features in one accumulating context):**
- ❌ "It's under 15 features / under 2000 lines, one pass is more consistent." — RETIRED advice; a single accumulating pass has repeatedly failed to complete before any validator ran.
- ❌ "It's large (58 tasks / 9 milestones), so coordinating keeps it coherent." — INVERTED LOGIC. The bigger the plan, the faster one context fills up. **The larger the build, the MORE mandatory isolation is.**
- ❌ "Subagents increase integration drift / it's tightly-coupled full-stack." — drift is prevented by injecting the contract into each task, NOT by building inline.
- ❌ "It'll be faster if I just build it as coordinator." — it ends the mission with nothing recoverable.

**CONTEXT-BUDGET HARD-STOP:** if you have created more than ~15 files as the coordinator in a single feature milestone, you are building inline and about to fail. STOP — in the IDE move to spec-session/subagent task execution; on the CLI dispatch the rest. The coordinator's Milestone 1+ job is to scaffold, then verify gates — NOT to author feature files.

---

## The per-milestone loop

Print the banner FIRST, before any work — the first output of each phase/milestone/task; the user must never ask "where are we?". **Always inside a fenced code block** (or the box collapses into one run-on line). The phase box is closed (4 walls) — use **plain ASCII only inside** (no emoji/em-dash; a non-ASCII glyph is a different column-width and pushes the right `║` out of line) and pad to the border:

```
╔════════════════════════════════════════════╗
║ PHASE: BUILD - <id>-<slug>                 ║
║ Milestone: 3/8 - Backend API               ║
╚════════════════════════════════════════════╝
```

For each milestone/task, print a ruled block — horizontal rules only (no side walls), so long task text and emoji never misalign:

```
──────────────────────────────────────────────
  📍 Milestone X/Y — <name>
     Task X.N/X.M: <description> · N/Total tasks complete
──────────────────────────────────────────────
```

**ONE milestone at a time — never collapse milestones.** Per milestone: banner → dispatch tasks → TEST GATE (typecheck + tests + build) → commit → write state.json → next. Do NOT batch "all backend" then "all frontend" into mega-passes — that skips the gates and lets one context accumulate a hundred-plus files until it exhausts its budget. 9 milestones = 9 banners, 9 gates, 9 commits, 9 state writes.

```
1. BUILD   dispatch milestone N's tasks (Phase 0 only: coordinator may build directly)
2. TEST    TEST GATE — typecheck + npm test + build + app renders (fix if any fail)
3. VERIFY  check features built vs contract AC (DONE/PARTIAL/MISSING)
4. COMMIT  git commit -m "[specship] M<N>: <summary>"
5. STATE   write .specship/state.json BOUND TO that commit (same step)
6. NEXT    milestones remain → loop; else → gap-detect (3.5) → validate → ship
```

**State write is BOUND to the commit (atomic, mandatory):** commit the milestone, then IMMEDIATELY write `state.json` with that commit's hash — never one without the other. If they drift, resume mis-recovers. Use the canonical field names from the shared `context-management` reference:
```bash
git commit -q -m "[specship] M<N>: <summary>"
cat > .specship/state.json << EOF
{ "phase":"build", "phase_status":"in_progress", "milestones_total":<TOTAL>,
  "milestones_completed":<N>, "current_milestone":<N+1>, "current_milestone_name":"<name>",
  "next_task":"<next>", "last_commit":"$(git rev-parse HEAD)", "updated_at":"$(date -u +%FT%TZ)" }
EOF
```
On build complete, set `"phase":"validate","phase_status":"pending"` with `handoff_notes.next:["run validation squad"]` — this is how validation still fires if context compacts (see `context-management`). `milestones_completed` is an integer count; also append a `milestone_complete` trace event so resume survives a stale state file.

**AUTONOMOUS ERROR-RESILIENCE — never halt on a transient tool error.** A failed tool call is NOT a stop condition — auto-recover and continue:
- **File-write error** (recurring: a large file fails to write) → it's too large; split into smaller modules (e.g. WS layer → `registry.ts` + `hub.ts` + `server.ts`) and write those.
- **Flaky command** (network, port in use) → retry once; if a port is busy, free it (`lsof -tiTCP:<port> -sTCP:LISTEN | xargs kill`) and retry.
- Only stop for the hard-stop rule (same fix failing >3×) or a genuine blocking ambiguity. Never pause to ask "shall I continue?" between milestones — run the loop → gap-detect → straight into VALIDATE.

## Per-task isolation — the mechanism by surface

Phase 0 (scaffold/infra) → coordinator runs directly, either surface. **Milestone 1+ (feature tasks):**
- **Kiro IDE** → run in a **spec session** (accept the IDE's prompt) OR dispatch via the **`subagent`** tool. Either executes each task as its own bounded request — that IS the isolation. Do NOT decline it and build inline.
- **Kiro CLI** → use the **`subagent`** tool, one bounded subagent per task.

Both enforce the same invariant: **no feature is built in the coordinator's accumulating context.** Execution delegates to the required **`subagent-dev`** skill (superpowers) — it owns fresh-agent-per-task dispatch and the two-stage review (spec-compliance, then code-quality). Each task reads the artifacts (contract, `tasks.md`, `test-cases.md`), not chat memory, and commits before the next starts.

**Every feature task's prompt MUST include the contract** — paste `api-contract.md` (+ `ws-contract.md` if realtime) so workers consume exact shapes (this prevents drift without collapsing into one pass). Template:

```json
{ "task": "Execute Milestone <N> tasks", "mode": "blocking", "stages": [
  { "name": "task-N.1", "role": "kiro_default",
    "prompt_template": "Implement Task N.1: <name>.\n\n<FULL TASK TEXT FROM tasks.md>\n\nProject: <desc> | Tech: <stack>\n\nAPI/WS CONTRACT (consume shapes EXACTLY — do not rename/wrap):\n<PASTE api-contract.md (+ ws-contract.md)>\n\nRules: (1) TDD — failing test FIRST, watch it fail, then implement (2) run tests (3) commit when green (4) report DONE|BLOCKED|NEEDS_CONTEXT" }
] }
```
**Parallelism:** tasks touching different files → same `stages` array (run parallel); tasks sharing files → separate calls (sequential). After each parallel batch, run `npm test` to catch conflicts; if it fails, re-run those tasks sequentially.

## Per-task discipline (coordinator in Phase 0 AND every subagent)

1. **TDD is RED-FIRST.** For each behavior: write the test → RUN it, watch it FAIL for the right reason → implement → GREEN. You may NOT write implementation files then add tests at the end — a test that was never red proves nothing (guardrail #6). The test file is the FIRST file you create for a unit of behavior. Run via the required **`tdd`** skill.
2. **Files under ~200 lines — split proactively.** Plan the split before writing (e.g. WS layer → `registry.ts` + `hub.ts` + `server.ts`); oversized single-file writes fail.
3. **Dependency hygiene.** A major-version bump is not drop-in — read migration notes and ensure tests exercise the new API. Any `npm audit` finding you don't fix must be written to `.specship/artifacts/verdicts/` as an explicit dismissal with reason, so the security validator confirms the call.

## Spec location (three files, one directory)

`.specship/specs/<id>-<slug>/`: **`requirements.md`** (AC, failure modes, scope) · **`design.md`** (design spec, API contract, NFRs) · **`tasks.md`** (`## Milestone N:` execution plan). Sibling RED seeds: `test-cases.md`, `browser-flows.md`, `edge-cases.md`.

For enterprise builds, inject relevant sections of the shared `architecture-guidance` reference into worker context (thin handlers, pure services, repository pattern, 200-line limit, input validation, parameterized queries, consistent error format, health endpoint).

## Pre-conditions & pre-flight

Before building: a contract exists in `.specship/specs/`, an implementation plan exists, working tree is clean. If not → tell the user to run specship-plan, or ask how to handle a dirty tree.

Read the **Execution Config** YAML from `requirements.md` (defaults: `autonomy: guided`, `worker/validator: sonnet`, `validator_alignment: opus`). Kiro routes models per chat/agent, so treat routing as a suggestion applied when spinning up a pass. `autonomous` = execute all, auto-trigger validation, no user interaction.

**Pre-flight (Step 0.5):** check `node --version`, git clean, ≥1GB disk. If any fails → report and STOP.

**PLAN→BUILD gate (deterministic — run before any milestone):** confirm the PLAN phase left its required output before you build on it. Locate and run the process checker in `plan` mode from the project root:

```bash
CHECKER=$(find ~/.kiro -name process-checker.js 2>/dev/null | head -1)
[ -z "$CHECKER" ] && CHECKER=$(find . -name process-checker.js 2>/dev/null | head -1)
[ -n "$CHECKER" ] && { node "$CHECKER" --phase plan; echo "plan-gate exit: $?"; } || echo "process-checker.js not found — verify requirements/design/tasks + market research manually"
```

**Exit 0 = proceed. Exit 1 = STOP** and go back to `specship-plan` — it means a plan artifact (`requirements.md`/`design.md`/`tasks.md`) or market research is missing. (If market research was intentionally skipped, the plan phase must have written `.specship/artifacts/market-research-skipped.txt` with the reason; otherwise the gate fails by design.)

**After Milestone 1 (scaffold), integration pre-flight:** app starts without crashing (wait 3s), tests infra runs, and the browser actually renders content — navigate with a browser MCP, screenshot to `.specship/artifacts/traces/`, and `browser_snapshot()`; if the DOM is only `<div id="root"></div>` the page is blank (JS/hydration failed) → FIX M1 before proceeding. (No browser MCP → curl and grep for `<h1|<p|<div` content; a bare shell is a WARN for SPAs, not a hard block.) **A broken foundation wastes all later work — STOP and fix M1.**

## Step 1: Mission branch

```bash
MISSION_NUM=$(( $(git branch --list 'specship/mission-*' | wc -l | tr -d ' ') + 1 ))
printf -v MISSION_ID "%03d" $MISSION_NUM
CONTRACT=$(ls -t .specship/specs/*.md 2>/dev/null | head -1); SLUG=$(basename "$CONTRACT" .md | sed 's/^[0-9]*-//')
git checkout -b "specship/mission-${MISSION_ID}-${SLUG}"
```

## Step 2: Execute the plan (dispatch per task)

Dispatch each `tasks.md` task per the isolation rules above. Inject into each worker's prompt (read from the contract + shared refs):
- **API contract** (full-stack frontend tasks) — exact response shapes; tell the spec reviewer to verify the frontend consumes them (see shared `worker-prompt-template`).
- **Brownfield recon** (existing-code tasks) — inject `artifacts/reverse-engineering/brownfield-contract-inputs.md`, `change-impact-map.md`, `preserved-behaviors.md`, and `test-baseline.md`; workers must follow local conventions, preserve named behavior, and avoid files marked "do not touch".
- **Design spec** (any UI task) — design system (no inline styles), palette, type scale; hover/active/focus/disabled states; loading/empty/error states; responsive at 375/768/1440. **Non-negotiable for production** — a worker without design context produces inline-styled slop.
- **Market research "Professional UX Patterns"** (first frontend milestone) — match real products, not a tutorial.
- **Feature polish — three passes** (every production feature, from shared `feature-polish-checklist`): (1) core AC, (2) states (loading/error/empty/overflow/rapid-click), (3) polish (animation, keyboard, tooltip, optimistic UI, undo). Tell the spec reviewer: missing loading/error states = FAIL.

## Step 3.5: Gap Detection — computed coverage gate

The single authoritative gap check (the autonomous-execution "Feature Completeness" loop points here — do not run two mechanisms). Coverage is **computed**, not self-asserted:

```bash
BRIEF=$(ls .specship/specs/*/market-research.md 2>/dev/null | head -1)
awk '/Table Stakes Features/{f=1;next} /^##/{f=0} f && /^[0-9]+\./{print}' "$BRIEF" > .specship/table-stakes.txt
FEATURE_COUNT=$(wc -l < .specship/table-stakes.txt | tr -d ' ')
FOUND=0; MISSING=()
while IFS= read -r line; do
  KEY=$(echo "$line" | sed -E 's/^[0-9]+\.\s*//' | grep -oE '[A-Za-z]+' | head -3 | tr '\n' '|' | sed 's/|$//')
  if grep -rqiE "$KEY" src/ 2>/dev/null; then FOUND=$((FOUND+1)); else MISSING+=("$line"); fi
done < .specship/table-stakes.txt
COVERAGE=$(awk "BEGIN{ if($FEATURE_COUNT>0) printf \"%.2f\", $FOUND/$FEATURE_COUNT; else print 0 }")
echo "COVERAGE: $FOUND/$FEATURE_COUNT = $COVERAGE"; printf '  - %s\n' "${MISSING[@]}"
awk "BEGIN{ exit !($COVERAGE < 0.80) }" && echo "GATE: FAIL (<0.80)" || echo "GATE: PASS"
```

If coverage **< 0.80** or any feature is missing → generate gap-fill tasks for the named features, run a focused pass, re-test, re-run. grep is a cheap first filter (a hit means "code mentions this," not "it works") — for ambiguous hits escalate ONLY that feature to a verification/INTERACT pass, not one pass per feature. Loop until ≥0.80 with nothing missing, OR the `dispatch_budget` cap is hit — on cap, LOG the still-missing features in the aggregate verdict (never silently declare complete).

## Step 4: Trigger the FULL validation squad (MANDATORY — cannot be skipped)

After all milestones + gap-fill, run pre-ship gates then the squad. **You do NOT have authority to skip validators** — not for "tests already pass," "the screenshot looks fine," "it'll take too long," or "context constraints" (that's yours to manage). Running "focused/selected" validators is skipping with a nicer name. If compute is a real concern, tell the user and ASK — never silently skip. A build once shipped 2 UI bugs because validators were skipped.

Pre-ship gates (fix any failure before validating): typecheck (`tsc --noEmit`/`mypy`/`go vet`) · production build · tests · server health · browser render · no inline styles (`grep -r "style={{" src/`).

**Record the build result + declare the squad, then run the BUILD→VALIDATE gate (deterministic):**

1. After the pre-ship gates pass, write `.specship/artifacts/build-status.json` capturing their outcome (green = `tests:"pass"`, and `typecheck`/`build` not `"fail"`). **The gate is STRICT by default: a bare `tests:"pass"` is treated as unproven self-attestation and FAILS.** You MUST capture the actual test command AND save its output to a log file, then reference both — this is what turns "I say it passed" into "here is the evidence it passed":
   ```bash
   mkdir -p .specship/artifacts
   # Run the real test command and TEE its output to a log the gate can inspect.
   npm test > .specship/artifacts/test.log 2>&1   # (or pytest/go test — whatever this repo uses)
   cat > .specship/artifacts/build-status.json <<JSON
   { "typecheck": "pass", "tests": "pass", "build": "pass",
     "tests_command": "npm test", "tests_log": "artifacts/test.log",
     "updated_at": "$(date -u +%FT%TZ)" }
   JSON
   ```
   `tests_command` is the exact command you ran; `tests_log` is its captured output, path relative to `.specship/`. Use `"fail"` for any gate that actually failed (you must then fix it — do not write a green status you didn't earn), `"n/a"` for a gate that genuinely doesn't apply (e.g. no typecheck in a plain-JS project). (Only add `--lenient` to the gate for a genuinely-legacy repo where you cannot capture a test log — and say so.)

2. Write the validator squad you are about to run to `.specship/artifacts/expected-validators.txt` (one name per line — e.g. `code`, `security`, `integration`, `browser`, `design`, `alignment`, `load`). This is the contract the ship gate and aggregator cross-check against.

3. Run the build gate from the project root. **Run it as its OWN command — never chain it after `git commit` with `&&`.** The build artifacts (`build-status.json`, `expected-validators.txt`, `verdicts/`) are gitignored, so a commit that only touches them is a no-op that exits non-zero and would short-circuit the `&&`, making the gate silently not run and print a misleading `exit: 1`. Commit first (as its own statement), then run the gate separately:
   ```bash
   CHECKER=$(find ~/.kiro -name process-checker.js 2>/dev/null | head -1)
   [ -z "$CHECKER" ] && CHECKER=$(find . -name process-checker.js 2>/dev/null | head -1)
   [ -n "$CHECKER" ] && { node "$CHECKER" --phase build; echo "build-gate exit: $?"; } || echo "process-checker.js not found — verify tasks complete + build green + expected-validators.txt manually"
   ```
   **Exit 0 = proceed to validation. Exit 1 = STOP** — it means tasks are incomplete in `state.json`, the build isn't green, or `expected-validators.txt` is missing. Fix the cause before dispatching the squad. (A non-zero from a preceding `git commit` is NOT a gate failure — read the `build-gate exit:` line, which only reflects the checker.)

Then **actually perform** validation (do not merely suggest it — the orchestrator that built the code MUST trigger it, or it never happens):
1. emit a one-line status ("Build complete. Running validation squad…") — NOT a question
2. run ALL enabled validators as independent passes (fresh chat sessions / spec task waves so they stay honest)
3. wait for all → aggregate → FAIL triggers recovery, PASS proceeds to ship

In autonomous mode, NEVER stop at a phase boundary to ask the user — a question mark between build → gates → gap-detect → validate → recover → ship is a protocol violation.

## Validation strategy (three tiers — catch bugs early)

**Per-milestone smoke (30s):** app still starts, existing tests still pass, no new console errors.

**Per-milestone integration shape check (MANDATORY full-stack, after any milestone touching frontend API calls):** for each `fetch`/`axios` call, compare what the frontend reads (`data.workspaces`? `data`?) against what the backend actually returns (`res.json(...)`). Mismatch (backend returns a plain array, frontend reads `data.workspaces`) = guaranteed bug → FIX before the next milestone.
```bash
grep -rn "await.*\(get\|post\|fetch\)\|\.then" src/client/src/ 2>/dev/null | grep -v node_modules
grep -rn "res.json\|res.send" src/server/routes/ 2>/dev/null   # cross-reference shapes
```
*Why:* a full-stack build had 70 passing backend tests but `createWorkspace` didn't appear — API returned `[...]`, frontend read `data.workspaces`. This check catches it at the milestone it's introduced, not 6 milestones later.

**Per-milestone design spot check (production UI, 30s):** screenshot, then scan 5 red flags — inline styles (`style={{`), browser-default font, giant padding, no hierarchy, looks like a different app than last milestone. 1–2 flags → fix now; 3+ → the worker ignored the design system, rewrite the milestone with explicit constraints.

**End-of-build:** trigger specship-validate for the full adversarial squad (integration FIRST for full-stack, then code, security, browser, design, alignment).

## TEST GATE (hard requirement — blocks milestone advancement)

**The #1 rule: NO milestone proceeds without passing its gate. The gate is typecheck + tests + build** (not just tests):
```bash
npx tsc --noEmit        # broken imports/types are bugs — fix now
npm test                # zero failures — fix, never skip, never edit the test to pass
npm run build           # catches missing deps / bad imports / config
```
**Decision:** typecheck + tests + build all pass AND test count meets threshold → commit + proceed. Any fail, or count below threshold, or no tests for the milestone → GATE FAILS → fix before committing.

**Test count thresholds:** backend ≥3/endpoint (success + error + edge) · frontend component ≥2 (renders + interaction) · feature ≥3 · infra ≥3 · polish ≥5.

**TDD red-first is the Iron Law** (run via `tdd`): every test must have been RED before GREEN — "tests exist and pass" is not enough. Seed from `test-cases.md` where it covers this milestone's behaviors (see below); other behaviors still get a failing-test-first. Exceptions are only those the `tdd` skill names, and require the user's say-so.

**What counts:** unit (single function/component), integration (full request→response or component-with-hooks). Does NOT count: `console.log`, manual curl, screenshots without assertions.

**Fix commits MUST carry a regression test (Learning 16):** a `[specship-fix]` commit resolving a validator finding but adding NO new test is REJECTED. The test must exercise the bug/attack vector, not the happy path — see the shared `regression-recipes` reference for the exact assertion per finding class.

### Seeding TDD from testgen (closes the PLAN→BUILD loop)

PLAN pre-wrote unbiased test **specs** to `.specship/specs/<id>-<slug>/artifacts/test-cases.md` (+ `edge-cases.md`, `api-contract-tests.md`, `ui-state-sequences.md`). They are the RED seeds. For each case mapping to a behavior in this milestone: translate `TC-/EC-/ACT-<id>-N` into a runnable test → watch it fail for the right reason → minimal code to green → refactor. A pre-written case with no runnable test by milestone end is an uncovered AC — the gap detector and alignment validator will flag it. **testgen decides WHAT to test (pre-code); TDD decides HOW (red-first).**

## Error handling

**Stuck detector (git-based, not wall-clock):** a task is *stuck* when, after a pass, BOTH hold: no new commit since the task started AND its acceptance check still fails. → log a `stuck` trace event, re-run ONCE with a simpler prompt; if still stuck, mark BLOCKED and move to the next non-dependent task. *Progress = a new commit OR a passing check* (measured in commits, not minutes).

**Dispatch budget (the real ceiling):** bound passes per task via `dispatch_budget` in state.json (default 3). Exhausted without a passing check → BLOCKED. "No hard timeout" never means "loop forever."

**Plan adaptation (the plan itself is wrong, not just the code):** signals — same task fails 2+ times with different approaches, or a milestone fails on a fundamental assumption (e.g. "React CDN + htm" → import errors), or 3+ tasks in a milestone BLOCKED. → STOP, set `phase_status: plan_revision_needed`, log a `plan_adaptation` trace, keep completed milestones, rewrite the failing milestone with a different approach, resume. (This is course-correction, not bug-recovery.)

**Build-failure escalation:** L1 retry once with the error + failing file + spec; L2 mark BLOCKED, continue to non-dependent tasks (dependents also BLOCKED); L3 (3+ blocked) STOP, set `phase_status: blocked` with handoff notes → escalates on resume.

| Failure | Recovery |
|---|---|
| `npm install` fails | network? try `--legacy-peer-deps`, check Node version |
| TS compile error | fix pass reads error, fixes types |
| Test fails post-impl | fix the implementation, never the test |
| Port in use | kill the process or change port |
| DB connection fails | create/migrate the DB |
| Module not found | check paths / missing dep |

**"I don't know" protocol:** for anything unfamiliar — stop (don't guess), log the exact error, web-search for a known fix; apply + log the learning if found, else set `phase_status: needs_research` with a clear blocker. "I'm stuck, here's what I tried" beats 30 minutes of random fixes that worsen the codebase.

**Never:** skip a failing test to move on · modify a test to make it pass · continue past a failed `npm install` · delete error output (log it to traces) · spend >2 attempts on one error without searching · guess at fixes you don't understand.

## Key principles

- **Fresh branch per mission** (never build on main).
- **Never one giant pass** — each task gets fresh isolated context (IDE spec session / CLI subagent); the surface decides the mechanism, the isolation is the point.
- **Fail fast, fix immediately** — never accumulate broken milestones.
- **Clean handoff to validation** — build always flows into validation; no shipping without it.
- **Recovery points** — each milestone commit compiles and passes tests; roll back to the last good one if needed (`git log --oneline --grep="\[specship\] M"`).
