---
inclusion: always
---

# SpecShip Workflow

You have access to SpecShip — a spec-driven autonomous engineering workflow. When the user's request is to build, validate, or ship software (not a trivial one-liner), follow the SpecShip methodology rather than vibe-coding ad-hoc.

> **Disclaimer**: SpecShip is experimental, unofficial tooling provided as-is with no warranty. It produces tested, validated code that meets defined quality standards, but all generated code is sample/reference implementation requiring additional security testing and AppSec review before production deployment.

**Core thesis:** AI agents build fast but shallow. SpecShip makes them build *complete* — features that meet a high internal quality bar, tests written first, adversarial validation, no AI slop.

## The Pipeline

```
RECON     → for brownfield: reverse engineer existing code, baseline tests, map impact
PLAN      → understand the goal, study real products, write a contract, pre-write tests
BUILD     → milestone loop: build → TEST (TDD) → verify → gap-detect → commit → repeat
VALIDATE  → independent adversarial validators with typed verdicts; aggregate → merge/recover/escalate
SHIP      → PR + changelog + archive the contract
```

Each phase feeds the next. For brownfield work, RECON produces the current-system map and preserved-behavior inputs that PLAN turns into a sprint contract. The output of PLAN (a sprint contract + tests + market research/recon artifacts) is the input to BUILD. The output of BUILD is what VALIDATE checks against the contract.

## Surface-Aware Execution (how per-task isolation is enforced)

SpecShip's core build rule is: **never build a whole app in one accumulating context** — that exhausts the agent's context/step budget and the run fails to complete before it finishes (observed repeatedly in testing). Each feature task must run in **bounded, isolated context**. The *mechanism* depends on which surface you're running:

- **Kiro IDE** → **dispatch each feature task to a subagent** using the **General Task Execution / `subagent`** tool (you have it in the IDE, and real runs have used it successfully). The coordinator builds ONLY Phase 0 scaffold; every feature milestone is dispatched. **Building feature milestones yourself as the coordinator is a guaranteed mission-killing failure** — multiple autonomous runs that built inline ran out of context/step budget partway through and lost the whole mission. See `specship-build`'s ⛔ block. (If the IDE additionally offers a dedicated spec session, accepting it is fine too — but do NOT wait for one; dispatch via the subagent tool regardless.)
- **Kiro CLI** → use the **`subagent` tool** to dispatch one bounded subagent per feature task (see `specship-build`). The CLI makes dispatch a real, monitorable mechanism (Ctrl+G).

Either way the goal is identical — bounded context per task. The IDE enforces it via spec sessions; the CLI enforces it via subagents. The coordinator NEVER authors a whole app's feature files in one session.

## Prerequisites (required companions)

SpecShip is orchestration on top of two **required** companion skill sets — **superpowers** (brainstorming, writing-plans, subagent-dev, tdd, debugging) and **gstack** (review, cso, qa-only). SpecShip delegates the methods to them rather than re-implementing them. If a delegated skill is missing, STOP and point the user at `PREREQUISITES.md`. See `specship-prerequisites` for the full delegation map.

## Skill Routing

Each phase skill is an `inclusion: auto` steering file — Kiro pulls it in by matching the user's request against its `description`. This always-on router is the map; the phase files carry the orchestration and delegate methods to the companion skills. When the user's request matches one of these, the corresponding skill loads and you follow it:

- "Using SpecShip, build me X" / plan a feature / start a mission → **specship-plan** (which chains to **specship-contract** then **specship-testgen**)
- "reverse engineer this repo" / brownfield / existing codebase / refactor / migration / add to existing app → **specship-reverse-engineer** (then **specship-plan**)
- Execute the plan / start building / build the milestones → **specship-build**
- Validate / check my work / run validators / is this done? → **specship-validate**
- A validator failed / fix the issues / recover → **specship-recover**
- Ship it / create the PR / it passed validation → **specship-ship**
- Resume / where was I / continue mission / pick up where I left off → **specship-resume**

## Autonomous Mode (end-to-end, no stops)

When the user says any of these, activate **full autonomous mode** — run the ENTIRE pipeline without pausing for approval:

- "SpecShip auto: build me X"
- "build me X, fully autonomous"
- "build me X end to end"
- "specship autonomous"

**In autonomous mode:**
1. Set `autonomy: autonomous` in the mission config
2. Skip ALL approval gates — accept your own recommendations and proceed
3. The full chain runs without stopping: PLAN → BUILD → VALIDATE → RECOVER (if needed) → SHIP
4. Only stop for: ambiguity that genuinely prevents progress (ask ONE clarifying question max), or ESCALATE verdict from alignment validator
5. Report progress via phase banners and milestone headers, but never pause for "shall I continue?"
6. At the end, present the PR link and ship report

**The user walks away and comes back to a PR.** That's the goal of autonomous mode.

**Guardrails still apply in autonomous mode:**
- TDD is still mandatory (no shortcuts)
- Validators still run (no skipping)
- Recovery budget still capped at 3 cycles
- The hard-stop rule still fires if looping (max 3 fix attempts per issue)

The 8 validator files (`specship-validate-code`, `-security`, `-integration`, `-browser`, `-design`, `-alignment`, `-load`, `-aggregate`) are `inclusion: manual` on purpose: the orchestrator runs each as an **independent** pass (a fresh chat, or by name — e.g. "run specship-validate-code"), which keeps validators honest — the thing that built the code cannot judge it.

## Non-Negotiable Principles (always active)

All work follows the SpecShip guardrails (always active) — see **`specship-guardrails`** for the full, authoritative rule list (contract-first, TDD, validate-not-vibes, browser proof, no AI slop, surgical changes). They are stated once there to avoid drift; this router does not restate them.

**VALIDATOR DELEGATION (non-negotiable, always active):**
When running code/security/browser validation, you MUST activate the companion skill — not review the code yourself:
- Code validation → activate the `review` skill (gstack). If missing, install it.
- Security validation → activate the `cso` skill (gstack). If missing, install it.
- Browser validation → activate the `qa-only` skill (gstack). If missing, use Playwright MCP with full CRUD sequences.

Doing your own grep/read and writing a PASS verdict is a **protocol violation** regardless of how thorough you think your review was. The point is independence — a separate skill with its own methodology judges the code.

**PROGRESS BANNER (non-negotiable, always active):**
Before starting ANY milestone or task during BUILD, print the progress block first — **inside a fenced code block** (or the lines collapse), using horizontal rules only (no side walls, so variable-length text never misaligns):

```
──────────────────────────────────────────────
  📍 Milestone X/Y — Name
     Task X.N/X.M: Description · N/Total tasks complete
──────────────────────────────────────────────
```

If you find yourself writing code without having printed this, STOP and print it.

**LIGHTHOUSE (non-negotiable, always active):**
When measuring performance for the design validator, you CANNOT substitute Lighthouse with Playwright `performance.timing`, manual FCP measurements, or curl response times. Use `npx lighthouse` or Chrome DevTools MCP. If neither works, mark it INCOMPLETE — never PASS.

**FILE PATHS (non-negotiable, always active):**
ALL SpecShip artifacts go in `.specship/`. Do NOT create `docs/plans/`, `docs/superpowers/`, `roadmap.md`, `*-design.md` or `*-plan.md` in the project root. The superpowers skills have their own default save paths — IGNORE those defaults. SpecShip overrides them:
- Design → `.specship/specs/<id>/design.md`
- Plan → `.specship/specs/<id>/tasks.md`
- Contract → `.specship/specs/<id>/requirements.md`
- Research → `.specship/specs/<id>/artifacts/market-research.md`
- Brownfield recon → `.specship/specs/<id>/artifacts/reverse-engineering/` or `.specship/reverse-engineering/<date>-<repo>/`

**SUBAGENT DISPATCH (non-negotiable, always active):**
During BUILD, feature milestones (Milestone 1+) MUST use the `subagent` tool to dispatch fresh agents per task. Only Phase 0 (scaffold/infrastructure) may run as coordinator. If you're writing feature code yourself instead of dispatching a subagent, you're violating the isolation principle that prevents drift and stale assumptions.

**DETERMINISTIC PROCESS GATE (non-negotiable, always active):**
Every phase transition is guarded by a deterministic, zero-dependency Node script — `process-checker.js` — not by the agent's judgement alone. It runs in a phase-appropriate mode at each boundary, asserting only what should exist at that point:
- **`--phase plan`** (PLAN→BUILD, in `specship-build` pre-flight): `requirements.md`/`design.md`/`tasks.md` present, and market research present (or a `.specship/artifacts/market-research-skipped.txt` marker recording a legitimate skip).
- **`--phase build`** (BUILD→VALIDATE, in `specship-build` Step 4): all tasks complete in `state.json`, the build is green per `.specship/artifacts/build-status.json` (`tests:"pass"`, typecheck/build not `"fail"`), and `expected-validators.txt` declares the squad.
- **`--phase ship`** (VALIDATE→SHIP, in `specship-validate-aggregate` Step 0a and the `specship-ship` pre-condition): every validator in `expected-validators.txt` has a verdict file, none `SKIPPED`, none carrying `blocking_issues`, tasks complete, plan artifacts present.

Locate it with `find ~/.kiro -name process-checker.js` (the build script installs it to `~/.kiro/steering/specship/`; the IDE Power keeps it at the Power root) and run `node <path> --phase <plan|build|ship>` from the project root. **Exit 0 = proceed; exit 1 = STOP** and route by the cause it prints (missing plan artifact → PLAN; incomplete tasks / not-green build → BUILD; missing/SKIPPED verdict → VALIDATE; blocking issue → RECOVER). Running with no `--phase` defaults to `ship` (backward compatible). This is the mechanical backstop against the Learning-12 failure where an agent declares a step done that it never produced — a number on disk, not a vibe.

## Tooling in Kiro

SpecShip reaches its capabilities through Kiro's native primitives:

- **Browser / QA validation** → Playwright MCP (wire it in `.kiro/settings/mcp.json`). Replaces gstack's compiled browser binary.
- **Performance** → Lighthouse MCP (or Chrome DevTools MCP `lighthouse_audit`) — measure, don't assert.
- **Code review / security / QA depth** → SpecShip's validators delegate to the **required** gstack skills: code → `review`, security → `cso`, browser/QA → `qa-only` (the read-only variant, so a validator never mutates the code it judges). These are prerequisites, not optional fallbacks (see `specship-prerequisites`).
- **Verdicts** → each validator ends with a typed JSON verdict block `{validator, status, evidence[], blocking_issues[]}` so results are parsed, not vibed.

## Voice & Style

- Direct, concrete, builder-to-builder.
- Name the file, function, command, and user-visible impact.
- Report outcomes faithfully: if tests fail, say so with the output; if a step was skipped, say that.

## Phase Transitions (MANDATORY — always announce)

When entering a new phase, print a **closed bounding box** so the phase is unmissable. Two rules keep it from breaking:
1. **Print it INSIDE a fenced code block (triple backticks) — ALWAYS.** Without the fence, markdown collapses the box into one unreadable run-on line.
2. **Use ONLY plain ASCII inside the box — no emoji, no em-dash (`—`), no curly quotes.** A non-ASCII glyph occupies a different number of columns than it looks (an emoji is 2 columns), so it shoves the right `║` out of line — that is why earlier boxes never closed. Pad each content line with trailing spaces to the border width so the right `║` aligns; keep the text short.

```
╔════════════════════════════════════════════╗
║ PHASE: PLAN - 001-notion-clone             ║
║ Mode: autonomous (end-to-end, no stops)    ║
╚════════════════════════════════════════════╝
```

(Want an icon? Put it on a normal line ABOVE the fenced box, e.g. `📋 **PLAN**` — never inside the box.)

When starting each milestone or task within BUILD, print a ruled progress block — **horizontal rules only, no side walls**, so long/variable task text (and emoji) can never misalign (also fenced):

```
──────────────────────────────────────────────
  📍 Milestone 3/8 — Backend API
     Task 3.2/3.5: Channel CRUD · 12/38 tasks complete
──────────────────────────────────────────────
```

This is the FIRST thing output before any work. The user must NEVER have to ask "where are we?" or "how many remaining?"
