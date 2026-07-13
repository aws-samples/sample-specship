# SpecShip

A [Kiro Power](https://kiro.dev) autonomous engineering workflow that orchestrates AI agents through a complete **recon → plan → build → validate → ship** pipeline — with brownfield reverse engineering, TDD, parallel execution, adversarial validation, and spec-driven quality gates.

## Architecture

![SpecShip architecture](docs/architecture-diagram.png)

Editable source: [`docs/architecture-diagram.svg`](docs/architecture-diagram.svg)

## The 4 Phases (+ Brownfield Recon)

| Phase | What happens | Output |
|-------|-------------|--------|
| **RECON** *(brownfield only)* | Reverse engineer existing code before planning: repo map, technology stack, components, APIs, data models, business flows, baseline tests, preserved behavior, and change impact. | `.specship/.../artifacts/reverse-engineering/` |
| **PLAN** | Brainstorm → market research (real web search, minimum 5 queries) → sprint contract → pre-generate test cases → implementation plan. Each step feeds the next. | `requirements.md` + `design.md` + `tasks.md` + artifacts |
| **BUILD** | Execute tasks.md milestone-by-milestone. Parallel batches for independent tasks. Every behavior follows Test-Driven Development (write failing test → watch it fail → implement → pass → commit). Hard gate blocks each milestone until typecheck + tests + build pass. | Tested, committed code per milestone |
| **VALIDATE** | Up to 7 adversarial validators run in parallel as independent subagents, each delegating to its gstack specialist skill (code→review, security→cso, browser→qa-only). Code, Security, Integration, Browser, Design, Alignment (always) + Load (if performance NFR exists). Each produces a typed verdict with evidence. Aggregate decides: merge / recover / escalate. | Typed verdicts → merge or recover |
| **SHIP** | PR + changelog + archive. Ship report with timing, bugs caught, milestone breakdown. If no git remote, prepares locally with push instructions. | PR ready to merge |

## Why SpecShip?

AI agents build fast but shallow — working skeleton in 7 minutes, 60% of features missing, no tests, no error handling. SpecShip fixes this:

| Principle | What it means |
|-----------|--------------|
| **Test-Driven Development** | No production code without a failing test first. The build gate blocks every milestone until typecheck + tests + build all pass. Catches bugs within minutes, not hours. |
| **Parallel execution** | Independent tasks run simultaneously. All validators fire in parallel as independent subagents. An hour of sequential work finishes in minutes. |
| **Adversarial validation** | The agent that built the code CANNOT judge it. Independent validators produce typed verdicts with evidence. A separate skill with its own methodology judges the code. |
| **Self-healing recovery** | When a validator finds a bug, a fresh agent fixes it surgically — one fix per issue, regression test first, max 3 cycles. Parallel fixes when touching different files. |
| **Contract-first** | Every build starts with acceptance criteria + failure modes + design spec — defined before any code and stored in `.specship/specs/<id>/requirements.md` + `design.md`. Validators judge against the contract, not vibes. |
| **Brownfield-safe** | Existing code gets reverse-engineered before planning. The contract includes preserved behavior, local conventions, baseline tests, files likely to change, and files to avoid. |
| **Market research** | Conducts real web searches (minimum 5 queries) to study existing products in the same category. Sets the quality bar from what exists — not from training data or tutorials. Research is saved to `.specship/specs/<id>/artifacts/market-research.md`. |

## Install

```bash
./install.sh
```

That's it. The installer automatically:
- Detects and installs missing dependencies (superpowers + gstack)
- Copies SpecShip steering files into `~/.kiro/steering/`
- Detects if Playwright MCP is configured — if not, sets it up (including Node.js guidance if missing)

One command, everything set up.

> By default installs globally (`~/.kiro/steering/`). To scope to a single project: `./install.sh ./.kiro/steering`

## Use

Just talk to Kiro — the `auto` skills match your intent:

```
Using SpecShip, build me a Kanban board
reverse engineer this repo before adding billing
start building
validate
ship it
where was I?            ← resumes an interrupted mission
```

Want to force a specific skill? Type its slash command (`/specship-plan`, `/specship-validate`) or `#`-reference it (`#specship-plan`).

## What's in it

```
kiro-power-specship/
├── power.json                          # Power manifest
├── POWER.md                            # Full documentation (shown on Try power)
├── PREREQUISITES.md                    # Required companions (superpowers + gstack) + Playwright MCP
├── SECURITY.md                         # Supply-chain notes + how to report an issue
├── install.sh                          # Installer (auto-installs dependencies + Playwright MCP)
├── uninstall.sh                        # Removes exactly what install.sh added
├── build-cli-skills.sh                 # Generates CLI skills from steering files
├── settings/mcp.json                   # Playwright + Chrome DevTools MCP config (--isolated)
├── settings/mcp/                        # Pinned MCP servers + integrity lockfile (npm ci)
├── specship-verify.sh                   # Integrity verifier (detects tampered steering/skills)
├── hooks/                              # Kiro agent hooks (opt-in, disabled by default)
├── templates/specship-gitignore        # .gitignore template for .specship/ folder
├── docs/                               # Architecture diagrams (PNG + SVG + Mermaid source)
└── steering/
    ├── specship-workflow.md            # [always] pipeline + routing + enforcement rules
    ├── specship-guardrails.md          # [always] 19 non-negotiable rules
    ├── specship-prerequisites.md       # [always] companion delegation map
    ├── specship-reverse-engineer.md    # [auto] brownfield repo reconnaissance
    ├── specship-plan.md                # [auto] plan pipeline orchestrator
    ├── specship-contract.md            # [auto] sprint contract generation
    ├── specship-testgen.md             # [auto] pre-write tests before code
    ├── specship-build.md               # [auto] milestone loop + parallel batches
    ├── specship-validate.md            # [auto] validation orchestrator (parallel subagents)
    ├── specship-recover.md             # [auto] surgical fixes, regression-test-first
    ├── specship-ship.md                # [auto] PR + changelog + archive
    ├── specship-resume.md              # [auto] resume interrupted missions
    ├── specship-validate-*.md (×8)     # [manual] individual validator skills
    └── shared/ (×12)                   # [manual] reference docs pulled on demand
```

## Modes

| Mode | Trigger | Behavior |
|------|---------|----------|
| **Guided** (default) | `Using SpecShip, build me X` | Runs the pipeline, pauses for plan approval before building |
| **Autonomous** | `SpecShip auto: build me X` or `build me X, fully autonomous` | Runs the entire pipeline end-to-end without stopping. You come back to a PR. |

## Customize

Treat SpecShip as a baseline and build your own workflow on top of it. To update, re-run `./install.sh` (it backs up any files you've edited before overwriting). To remove everything, run `./uninstall.sh`.

Experimental and unofficial. SpecShip has not undergone external security review and is provided as-is, with no warranty — use at your own risk. All generated code is sample/reference implementation requiring AppSec review before production use. Licensed under the [MIT License](LICENSE).
