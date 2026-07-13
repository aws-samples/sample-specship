---
inclusion: auto
name: specship-plan
description: Use when the user wants to plan, scope, or start a new feature/app/mission with SpecShip — e.g. "Using SpecShip, build me X", "plan this feature", "start a mission", "SpecShip auto: build me X", "build me X fully autonomous", "build me X end to end". Drives the planning pipeline and in autonomous mode chains through build → validate → ship without stopping.
---

# specship-plan — Mission Planning Orchestrator

## BEFORE YOU DO ANYTHING — execute this block:

```bash
# Create .specship/ structure FIRST (mandatory)
mkdir -p .specship/specs .specship/artifacts/traces .specship/artifacts/verdicts

# Ignore SpecShip's transient artifacts so they never get committed
# (traces/verdicts contain Lighthouse JSON + screenshots — Lighthouse output
#  contains strings that trip secret scanners like Code Defender)
cat > .specship/.gitignore << 'EOF'
state.json
state.json.tmp
state.json.bak
artifacts/traces/
artifacts/verdicts/
artifacts/expected-validators.txt
!specs/
!completed/
EOF

# Ignore build/test/tooling artifacts at the project root so the BUILD and
# VALIDATE phases can't accidentally commit them (a past run committed
# .playwright-mcp/ + server/data/*.db, and a commit was blocked by a secret
# scanner on a Lighthouse trace). Heredoc, not a shell loop — the loop form
# silently failed in zsh on a real run.
#
# Brownfield rule: NEVER overwrite an existing root .gitignore. Preserve the
# project's rules and replace only SpecShip's bounded block when re-running.
SPEC_SHIP_ROOT_IGNORE="$(cat <<'EOF'
node_modules/
dist/
build/
.playwright-mcp/
**/data/*.db
**/data/*.db-shm
**/data/*.db-wal
*.db
.env
.env.*
!.env.example
# Stray validation screenshots/traces (browser validator writes to
# .specship/artifacts/traces/, but ignore loose ones at the repo root as a
# backstop — root-anchored so real project assets like public/logo.png commit)
/*.png
/*.jpeg
.specship/artifacts/
EOF
)"
touch .gitignore
if grep -qF "# >>> SpecShip root ignores >>>" .gitignore; then
  tmp="$(mktemp)"
  awk '
    /^# >>> SpecShip root ignores >>>$/ { skip = 1; next }
    /^# <<< SpecShip root ignores <<<$/ { skip = 0; next }
    !skip { print }
  ' .gitignore > "$tmp" && mv "$tmp" .gitignore
fi
{
  printf "\n# >>> SpecShip root ignores >>>\n"
  printf "%s\n" "$SPEC_SHIP_ROOT_IGNORE"
  printf "# <<< SpecShip root ignores <<<\n"
} >> .gitignore
unset SPEC_SHIP_ROOT_IGNORE
```

**File path rules (enforced NOW):** all artifacts live in `.specship/specs/<ID>-<slug>/` — `design.md`, `requirements.md` (contract), `tasks.md` (plan), `artifacts/market-research.md`, `artifacts/reverse-engineering/`, `artifacts/test-cases.md`, `artifacts/api-contract.md`. Do NOT create `docs/plans/`, `docs/superpowers/`, `roadmap.md`, or any `*-plan.md`/`*-design.md` in the project root. When invoking `brainstorming`/`writing-plans`, explicitly tell each to save to the `.specship/specs/<ID>-<slug>/` path (they default to `docs/` — override it).

---

You are the planning orchestrator for SpecShip. SpecShip orchestrates; the methods come from the **required companion skills** (see `specship-prerequisites`) — invoke them by name, don't re-derive them:
- **Brainstorm** → the **`brainstorming`** skill (Step 1)
- **Implementation plan** → the **`writing-plans`** skill (Step 5)
- **Per-task build execution** → the **`subagent-dev`** skill + **`tdd`** per task (driven by `specship-build`)

Suggested model: a strong reasoning model (the "planner" role). Kiro routes per chat/agent, so pick that model for this chat.

## The Pipeline

```
Step 0.5: BROWNFIELD RECON → for existing code: reverse engineer current behavior + impact
Step 1:   BRAINSTORM      → understand what to build (brainstorming skill)
Step 2:   MARKET RESEARCH → study real products, define the quality bar
Step 3:   CONTRACT        → acceptance criteria + failure modes + design spec
Step 4:   TESTGEN         → pre-generate test cases (before code exists)
Step 5:   PLAN            → implementation plan (writing-plans skill)
```

Each step feeds the next. The output is a ready-to-execute plan that produces complete, thoroughly-tested software — not AI slop.

**Autonomy (applies to all steps):** Steps 1–4 have **no approval gate** in either mode — continue automatically. The ONE gate is at Step 5, **guided mode only**: ask for plan approval before building. In `autonomous` mode there are no gates anywhere — run the entire pipeline (plan → build → validate → recover → ship) and report at phase transitions only.

## The Quality Bar (Non-Negotiable)

Read the shared `quality-bar.md` (an internal quality checklist, not a deployment certification): the anti-slop checklist, feature completeness (every feature needs empty/loading/error/etc. states), the 7/10 professional-pattern reference standard, design quality, and deployment readiness. The workflow produces complete, thoroughly-tested software or NOTHING — there is no "MVP mode" unless the user explicitly says "just make it work, I don't care about quality." All generated code still requires AppSec review and further testing before deployment.

## Enterprise Projects

If the contract has NFRs or the goal mentions "production", "enterprise", "customer-facing", or "scalable": read the shared `enterprise-checklist.md`, determine which items apply from the NFRs, and distribute them across milestones (Foundation + Security early → Features middle → Testing + Observability later → Deployment readiness final). The plan MUST address each applicable item explicitly. This yields larger plans (30–50+ tasks, 5–8 milestones). For the deployment milestone, read the shared `deployment-guidance.md` (multi-stage Dockerfile, docker-compose, CI, graceful shutdown, env config with prod fail-fast).

## Milestone Decomposition

Decompose any goal that produces >10 tasks into `## Milestone N:` units. Sizing: 1–10 tasks = single flat milestone; 10–25 = 2–3; 25+ = 3–5; 50+ = 6–10. Each milestone must: produce working, testable software on its own; be independently verifiable (own mini-AC); be committable as a coherent state; and **include sufficient tests (HARD GATE)** — no milestone advances without passing the test gate.

### Test requirements per milestone type (HARD GATE)

**Every milestone MUST include test tasks** — not a separate "test hardening" milestone at the end.

| Milestone Type | Minimum Tests |
|---|---|
| Scaffolding / Infrastructure | 3+ (health, DB, config) |
| Backend API endpoints | 3 × endpoints (success + error + edge) |
| Frontend components (library) | 2 × components (renders + interaction) |
| Frontend features (wired) | 3 × features (happy + error + real-time) |
| WebSocket / real-time | 5+ (connect, auth, broadcast, timeout) |
| Polish / accessibility | 5+ (error boundary, edge cases, a11y) |

**Interleave** implementation and tests (implement feature → write its tests → next feature), so a "run out of time, skip tests" failure can't happen. The milestone's test gate: `npm test` all pass AND new test count ≥ threshold, else fix before commit. *(Anti-pattern from a real chat build: 10 milestones, only the backend had test tasks → 37 tests, 0% frontend coverage. Every milestone now has explicit, interleaved test tasks.)*

### Milestone ordering for production UI (critical)

```
M1: Scaffolding + Design System Setup (Tailwind config, shared-component skeleton)
M2: Shared Component Library (Button, Input, Avatar, Badge, Dialog, Popover, Tooltip)
M3: Layout Shell (Sidebar + Main + Panel, responsive breakpoints, navigation)
M4: Backend API + WebSocket infrastructure
M5: API Contract definition (after backend shapes are known)
M6+: Feature milestones (each builds on shared components + layout shell)
```
Shared components (M2) and layout shell (M3) come BEFORE features so every feature reuses the same building blocks; backend (M4) before the API contract (M5) before frontend features (M6+) so workers know exact shapes. **Tightly-coupled UI goes in the SAME milestone** (e.g. message list + grouping + hover actions; a typing indicator's backend event + frontend component) — never split work that can't be verified without its sibling.

### Cross-cutting concerns (real-time, dark mode, a11y)

Set up the mechanism in an early infrastructure milestone (WebSocket client, theme tokens, ARIA patterns), then each feature milestone integrates it as part of its own tasks (e.g. "connect to WebSocket"). NEVER a separate "add real-time to everything at the end" milestone — that's integration hell. Each feature is real-time/themed from birth.

### Milestone 1 is ALWAYS "Scaffolding + Verify It Runs"

For any UI/server project, M1 = project setup + a minimal app that renders + **verify in browser (or curl for pure APIs) that it actually loads** + test infra configured with one passing test. This catches "blank page" bugs before 30+ tasks are built on a broken foundation. Each milestone ends with: run its verification command → if pass, commit `[specship] milestone N complete: <name>` + update state → if fail, STOP and fix before the next (don't accumulate debt). A 4-hour build is really 5–8 validated 30-min builds.

### Full-stack: API Contract First (HARD GATE)

For projects with BOTH frontend and backend, the plan MUST define a **committed** API contract file at `.specship/specs/<id>-<slug>/artifacts/api-contract.md` BEFORE any frontend/backend feature code. It is the source of truth for backend workers, frontend workers, the integration validator, and the spec reviewer. Format: a table of `Endpoint | Method | Request | Response (exact shape) | Status`. **Response shape rules in the file:** plain arrays returned directly (NOT wrapped in `{items:[...]}`/`{workspaces:[...]}`); single objects direct (NOT `{data:{...}}`); errors always `{error:"message"}`; no pagination unless stated.

Enforcement: no frontend API-call task may precede the committed contract; every frontend task references it ("response is a plain array, NOT wrapped"); the spec reviewer checks frontend code against it; a backend worker changing a shape updates the contract in the same commit. This prevents the #1 full-stack bug (frontend reads `data.items`, backend returns a bare array).

### Real-time: WebSocket Event Contract

For realtime features, define `.specship/specs/<id>-<slug>/artifacts/ws-contract.md` alongside the API contract — Client→Server and Server→Client event tables (`Event Type | Payload | When`). Same enforcement as the API contract: injected into worker prompts, checked by the integration validator (backend emits match frontend listeners). This prevents the event-name/payload mismatch class (e.g. `typing:update` vs `typing:start/stop`).

## Process

### Step 0: Initialize + read config
Run the bootstrap block above (creates `.specship/` + gitignores). Determine the next contract ID: `printf "%03d" $(( $(ls .specship/specs/ 2>/dev/null | wc -l) + 1 ))` (slug decided after brainstorming). Load `.specship/config.yaml` if present, else defaults: `autonomy: guided`, `model_routing.planner`: strong reasoning model, `model_routing.worker`: fast capable model.

### Step 0.5: Brownfield Recon (follow specship-reverse-engineer when modifying existing code)
If the request mentions an existing codebase/app/service, bug fix, refactor, migration, dependency upgrade, or "add this to the current repo", brownfield recon MUST happen before brainstorming/contract — but FIRST run **deterministic recon discovery** so you reuse a fresh recon instead of wastefully re-running it (and so a new session reliably finds recon a prior session produced):

```bash
# Find the most recently modified brownfield handoff anywhere under .specship/
RECON=$(find .specship -type f -name brownfield-contract-inputs.md 2>/dev/null \
  | while read -r f; do printf '%s\t%s\n' "$(git log -1 --format=%ct -- "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null || echo 0)" "$f"; done \
  | sort -rn | head -1 | cut -f2-)
if [ -n "$RECON" ]; then
  echo "FOUND existing recon handoff: $RECON"
  echo "recon dir: $(dirname "$RECON")"
else
  echo "NO existing recon — run specship-reverse-engineer now"
fi
```

Decide from the result:
- **Recon found and still current** (covers the area you're about to change; no major source churn since it was written) → **reuse it**. Do NOT re-run recon. Record its path in `state.json` as `recon_artifact_path` and inject it into the phases below.
- **Recon found but stale or for a different area** → run **`specship-reverse-engineer`** to refresh the affected slice, then proceed.
- **No recon found** → run **`specship-reverse-engineer`** now.

Existing recon may live under a *different* mission's directory (e.g. a prior `001-*` that already shipped). Reusing it as INPUT is correct — but the new change is a NEW mission: create your own `<ID>-<slug>` and point to the source via `.specship/specs/<ID>-<slug>/artifacts/reverse-engineering/source.txt` rather than editing the old mission's files.

If the mission slug is not known yet, run recon as a standalone package first:
`.specship/reverse-engineering/<YYYYMMDD>-<repo-slug>/`. After brainstorming creates `<ID>-<slug>`, either copy the key files into `.specship/specs/<ID>-<slug>/artifacts/reverse-engineering/` or create `.specship/specs/<ID>-<slug>/artifacts/reverse-engineering/source.txt` pointing to the standalone package. Do not invent a slug just to satisfy the path.

Required handoff file: `.specship/specs/<ID>-<slug>/artifacts/reverse-engineering/brownfield-contract-inputs.md` (or a referenced standalone `.specship/reverse-engineering/<date>-<repo>/brownfield-contract-inputs.md`). Feed it into:
- Brainstorming: preserve current behavior and local conventions.
- Contract: acceptance criteria must include existing behavior that must not regress.
- Testgen: generate regression tests for preserved behavior before new behavior.
- Plan: tasks must name likely files, files to avoid, baseline commands, and local conventions.

Skip only for truly trivial edits or if the user explicitly accepts the risk.

### Step 1: Brainstorm (invoke the `brainstorming` skill)
Invoke **`brainstorming`** to understand the goal — its HARD-GATE (no implementation before an approved design), one-question-at-a-time dialogue, 2–3 approaches with trade-offs, and design self-review are the method. **Tell it explicitly** to save the design to `.specship/specs/<ID>-<slug>/design.md` (it defaults to `docs/`). If the goal is genuinely trivial you may skip to Step 2 — but "too simple" is usually where unexamined assumptions bite; when in doubt do the short version.

### Step 2: Market Research (MANDATORY for any product with real-world equivalents)
Research what already exists, judge what each product does well/badly, and use that to set the quality bar and avoid AI slop. **This requires REAL web research — do NOT rely on training data** (products evolve). Identify the category and its real products, then execute **at least 5 web searches** across: feature discovery, design/UX patterns, user expectations/complaints, and technical implementation.

**Egress discipline (guardrail rule 18 — enforce on every query):** web search is an outbound door. Queries describe the product **category**, NEVER this codebase. Do not put source code, file paths, internal identifiers, hostnames, customer names, `.env` contents, or anything repo-specific into a search — search "Kanban board drag-and-drop UX patterns", never a snippet of the user's code. If a query would only make sense to someone who has already seen this repo, it leaks project context — rewrite it generically or, if you genuinely need domain specifics, ask the user first. Extract: complete feature list, exact UX patterns (loading/error/empty handling), concrete design specifics (real colors/sizes/spacing), keyboard shortcuts, recent additions, and common complaints (these become quality requirements).

Synthesize into `.specship/specs/<id>-<slug>/artifacts/market-research.md` with these sections: **Research Sources** (≥5, cited) · **Reference Products** · **What's Good / What's Bad** (per product, concrete + sourced — the guidance core: adopt the good, avoid the bad) · **Table Stakes Features** (sourced; if 3 products have it, it's table stakes) · **Professional UX Patterns** (specific, e.g. "groups messages from same user within 5min: 2px gap, no repeated avatar") · **Design Reference** (density/color/type/layout with measurements) · **Keyboard Shortcuts** · **Common Complaints** · **Our Target** (must-have / nice-to-have / explicitly-skip / quality bar).

Quality check before proceeding: ≥5 searches executed, table-stakes sourced (not from memory), ≥1 concrete UX measurement, concrete design details, shortcuts populated, complaints identified. If any unchecked, keep researching — a shallow brief produces a shallow app. *Skip only for:* pure backend with no equivalent, a bugfix/addition to an existing app, infra/DevOps, or the user saying "I don't care about design."

**If you legitimately skip market research, record it** so the deterministic PLAN→BUILD gate (`process-checker.js --phase plan`) does not fail by design. Write a one-line reason:
```bash
mkdir -p .specship/artifacts
echo "skipped: <reason — e.g. pure backend service, no real-world UI equivalent>" > .specship/artifacts/market-research-skipped.txt
```
Either `market-research.md` OR this marker must exist before BUILD. Do not write the marker to dodge real research — only for the genuine skip cases above.

### Step 3: Sprint Contract (informed by research — follow specship-contract)
Generate the contract from the approved design + research: **10–15 acceptance criteria minimum** for a production app ("When X, then Y") including UX-quality, design (all interactive elements have hover/active/focus/disabled), and responsive criteria; failure modes (adversarial — "what would a lazy impl get wrong?", incl. inline-styles and happy-path-only); scope (IN + OUT); and a **Design Spec** (system, palette hex, type scale, component library, icon set). Save to `requirements.md` + `design.md`, commit.

**Table-stakes → AC mapping (HARD GATE):** every item in the research's Table-Stakes list MUST have ≥1 acceptance criterion. 12 table-stakes features → ≥12 AC. This prevents the "infrastructure only" trap (auth + CRUD shipped, the 8 features users care about skipped). When running a whole-app build worker, include the table-stakes list verbatim as a "You MUST implement these" checklist in the prompt — don't assume the worker infers features.

### Step 4: Test Generation (follow specship-testgen)
From the contract: one unit test case per AC, integration scenarios (multi-step flows), browser flow scripts (or N/A for backend), edge cases (from failure modes). Save to `.specship/specs/<id>-<slug>/artifacts/` and commit.

### Step 5: Implementation Plan — invoke the `writing-plans` skill
Invoke **`writing-plans`** to turn the contract + pre-written tests into a bite-sized, TDD-shaped breakdown. **Tell it explicitly** to save to `.specship/specs/<ID>-<slug>/tasks.md` (it defaults to `docs/`). Rules for `tasks.md`: use `## Milestone N: <name>` headers (the build loop iterates on them); tasks as `### Task N.M:`; update `state.json.plan_file`. Each task must be contract-referenced, bite-sized (2–5 min), TDD-shaped (write test → RED → implement → GREEN → commit, seeded from `test-cases.md`), with exact file paths and complete code (no placeholders).

**Gate (guided only):** "Plan ready. Review and approve before building?" — wait for confirmation. This is the one gate guided mode keeps. In autonomous mode, report completion and hand off to build.

### Step 6: Execute
**Autonomous:** chain directly `specship-plan → specship-build → specship-validate → specship-recover (if needed) → specship-ship`, reporting at phase transitions, never pausing. The user walks away and comes back to a PR. **Guided:** after Step 5 approval, chain into specship-build (no extra confirmation between plan and build).

## Adaptive Depth

| Goal | Brainstorm | Contract | Testgen | Plan |
|---|---|---|---|---|
| Bug fix (obvious) | short recon if brownfield | 3 criteria incl. preserved behavior | regression + unit | short |
| Simple feature | 1–2 Qs | 3–5 criteria | unit + edge | standard |
| Complex feature | full (5+ Qs) | 5–10 criteria | full | detailed |
| Existing-app feature/refactor | recon + 1–2 Qs | 5–10 criteria incl. compatibility | regression + integration | focused milestones |
| System/migration | recon + full approaches | 7–10 criteria | full + migration | multi-task |

Don't apply heavyweight process to a 10-line bug fix.

## Key Principles
- Each step feeds the next; hard gates prevent premature advancement (no plan without a contract, no contract without understanding).
- The contract is the source of truth — everything downstream validates against it.
- Adaptive, not rigid.

## State Management

Update the mission-state file at each step — a conceptual `.specship/state.json` (canonical schema below, atomic write: temp file → validate → atomic move; never append in place). The writer mechanism is up to you; the fields and meanings are fixed:

```json
{
  "mission_id": "<id>", "contract_id": "<id>", "contract_slug": "<slug>",
  "branch": "<branch or main>", "phase": "plan", "phase_status": "in_progress|pending|complete|blocked",
  "planning_step": "recon|brainstorm|contract|testgen|plan|complete",
  "recon_artifact_path": "<path to brownfield-contract-inputs.md or empty>",
  "started_at": "<ISO>", "updated_at": "<ISO>", "plan_file": "<path>",
  "tasks_total": 0, "tasks_completed": 0, "last_completed_task": "", "next_task": "",
  "milestones_total": 0, "milestones_completed": 0, "current_milestone": 0, "current_milestone_name": "",
  "recovery_attempts": 0, "validation_results": {}, "last_commit": "<git rev-parse HEAD or none>",
  "handoff_notes": { "done": [], "next": ["<next step>"], "blocked": [] }
}
```

Field names are canonical: `milestones_completed` is an integer; `handoff_notes` is a typed `{done,next,blocked}` object. Keep `phase_status` as lifecycle status and advance `planning_step` at each planning gate (recon→brainstorm→contract→testgen→plan→complete), filling `recon_artifact_path`, `contract_id`, `contract_slug`, and `plan_file` as they're produced. This enables specship-resume to pick up exactly where the session left off.
