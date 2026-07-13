---
name: "specship"
displayName: "SpecShip"
description: "Spec-driven autonomous engineering: recon → plan → build → validate → ship."
keywords: ["specship", "spec-driven", "brownfield", "reverse-engineering", "existing-codebase", "tdd", "test-driven-development", "red-green-refactor", "plan", "build", "validate", "ship", "sprint contract", "market research", "anti-slop", "design quality", "api contract", "adversarial validation", "milestone", "autonomous", "workflow", "orchestration"]
author: "YungJun0112"
---

# SpecShip

> **Note**: SpecShip is experimental, unofficial tooling for development workflows. SpecShip itself has not undergone external security review and is provided as-is with no warranty. All code it generates is sample/reference implementation that requires AppSec review and further testing before any production use.

A Kiro Power wrapping **SpecShip** — a spec-driven autonomous engineering workflow that makes AI agents build *complete*, thoroughly-tested software instead of fast-but-shallow demos.

## What is SpecShip?

AI coding agents have two failure modes: **fast but shallow** (working skeleton, 60% of features missing, no tests) and **correct but ugly** (works, but looks like a tutorial). SpecShip fixes both with a disciplined pipeline:

```
RECON → PLAN → BUILD → VALIDATE → SHIP
```

- **RECON** — for brownfield work, reverse-engineer the existing repo first: current architecture, technology stack, APIs, data models, business flows, local conventions, baseline tests, preserved behavior, and change impact.
- **PLAN** — study real products (market research), write a sprint contract (acceptance criteria + failure modes + design spec + API contract), pre-write the tests.
- **BUILD** — an iterative milestone loop with **TDD baked in** (red → green → refactor): build → test → interactive-verify → gap-detect → commit → repeat.
- **VALIDATE** — independent, adversarial validators (code, security, integration, browser, design, alignment, load), each returning a **typed verdict** with evidence; aggregate → merge / recover / escalate.
- **SHIP** — PR + changelog + archive the contract.

# Onboarding

Run these checks the first time SpecShip is used in a workspace. SpecShip is orchestration on top of two **required** companion skill sets — if either is missing, STOP and install it (see `PREREQUISITES.md`) before running any mission.

## Step 1: Validate the required companions

```bash
# superpowers (expect 5: brainstorming, writing-plans, subagent-dev, tdd, debugging)
ls -d ~/.kiro/skills/superpowers-* 2>/dev/null | wc -l
# gstack validators (expect review, cso, qa-only present)
for s in review cso qa-only; do
  [ -d ~/.kiro/skills/gstack-$s ] && echo "ok gstack-$s" || echo "MISSING gstack-$s"
done
```

If superpowers shows fewer than 5, or any gstack skill is MISSING:
> "SpecShip needs its companions first. Install superpowers + gstack (see PREREQUISITES.md), then re-run." — and STOP.

## Step 2: Validate browser tooling (for UI projects)

Browser/interactive validation needs **Playwright MCP** wired in `.kiro/settings/mcp.json`. If it's absent and the mission has a UI, install it before the VALIDATE phase (the design validator also needs Lighthouse / Chrome DevTools MCP, measured — never asserted).

## Step 3: Proceed

Once companions are present, route the request: "build me X" / "plan this" → `specship-plan`. All mission artifacts will be created under `.specship/specs/<id>/`.

## Prerequisites (required)

SpecShip is **orchestration on top of two required companion skill sets** — it sequences them and adds the spec-driven artifacts (market research, sprint contract, pre-written tests, typed validator verdicts). Install these as Kiro skills **before** SpecShip (see `PREREQUISITES.md`):

- **superpowers** — provides `brainstorming`, `writing-plans`, `subagent-dev`, `tdd`, `debugging`.
- **gstack** — provides `review`, `cso`, `qa-only` (and more).

SpecShip delegates each method to the named companion skill rather than re-implementing it. TDD, for example, runs via the `tdd` skill — SpecShip owns *when* it fires (the mandatory test gate: no production code without a failing test first, watch it fail), the companion owns *how*.

## Skills

All skills are markdown steering files, loaded by Kiro's `inclusion:` modes. The **`always`** files (`specship-workflow`, `specship-guardrails`, `specship-prerequisites`) are in context every turn. The **`auto`** phase skills load automatically when your request matches their description — so natural language ("build me X", "validate") routes itself. The **`manual`** validator sub-skills and shared references load on demand.

| Skill | Mode | When | What it does |
|-------|------|------|-------------|
| **specship-workflow** | `always` | every turn | Routes requests to the right skill; states the pipeline |
| **specship-guardrails** | `always` | every turn | 19 non-negotiable rules (contract-first, TDD, no slop, browser proof, surgical, no-unauthorized-push, egress discipline, anti-prompt-injection) |
| **specship-prerequisites** | `always` | every turn | The delegation map: which method comes from which required companion skill |
| **specship-reverse-engineer** | `auto` | brownfield / existing codebase / refactor / migration | Read-only repo reconnaissance: current behavior, stack, components, APIs, baseline tests, preserved behavior, change impact |
| **specship-plan** | `auto` | "build me X" / plan | Orchestrates the plan pipeline: brainstorm → market research → contract → tests → plan |
| **specship-contract** | `auto` | "define done" | Acceptance criteria + failure modes + design spec + API contract |
| **specship-testgen** | `auto` | after the contract | Pre-write tests before any implementation code exists (RED seeds for TDD) |
| **specship-build** | `auto` | "start building" | Milestone loop, per-task isolation + two-stage review, TDD test gate, gap detection |
| **specship-validate** | `auto` | "validate" / "is this done?" | Derive + run adversarial validators with typed verdicts; aggregate; completeness critic |
| **specship-recover** | `auto` | a validator failed | One surgical fix per issue, regression-test-first, budget-bounded, prevent-the-class |
| **specship-ship** | `auto` | "ship it" | PR + changelog + archive the contract |
| **specship-resume** | `auto` | "where was I?" | Reads mission state, continues from the exact stopped phase/task |
| **specship-validate-** *(×8)* | `manual` | run by the orchestrator | code / security / integration / browser / design / alignment / load / aggregate |

> Brainstorming, writing-plans, subagent-dev, and TDD are **not** SpecShip files — they're the required superpowers skills SpecShip delegates to.

## How it runs in Kiro

SpecShip reaches its capabilities through Kiro's native primitives — **steering files** (the skills), the **required companion skills** (the methods), and **MCP servers** (the tools). All mission artifacts (recon, contract, design, plan, tests, verdicts) live under **`.specship/specs/<id>/`** — not in `.kiro/specs/` or `docs/`:

- **Brainstorm / plan / TDD / execution** → the required **superpowers** skills (`brainstorming`, `writing-plans`, `tdd`, `subagent-dev`).
- **Code review / security / QA** → the required **gstack** skills (`review`, `cso`, `qa-only` — read-only so a validator never edits the code it judges).
- **Browser / QA validation** → **Playwright MCP** (wire it in `.kiro/settings/mcp.json`).
- **Performance** → **Lighthouse / Chrome DevTools MCP** (`lighthouse_audit`) — measured, not asserted.

## Customize

These are just markdown files in `~/.kiro/steering/`. Edit them. Treat SpecShip as a baseline and tune the contract template, quality bar, or validator set to your stack.

---

Wrapped as a Kiro Power from the SpecShip workflow. Licensed under the [MIT License](LICENSE).
