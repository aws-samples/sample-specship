---
inclusion: always
---

# SpecShip Prerequisites & Method Delegation

SpecShip is **orchestration on top of two required companion skill sets**. It does NOT re-implement the methods they own — it sequences them, adds the spec-driven artifacts (market research, sprint contract, pre-written tests, typed validator verdicts), and enforces the gates. The methods themselves live in the companions.

## Required companions (hard prerequisites)

SpecShip will not function correctly without these installed. If a delegation target below is missing, STOP and tell the user to install it (see this Power's `PREREQUISITES.md`).

| Method SpecShip needs | Delegates to | Companion |
|---|---|---|
| Brainstorming → design before code | the **`brainstorming`** skill | superpowers |
| Implementation plan (bite-sized, TDD-shaped) | the **`writing-plans`** skill | superpowers |
| Per-task build execution (fresh agent + two-stage review) | the **`subagent-dev`** skill | superpowers |
| Test-Driven Development (red→green→refactor) | the **`tdd`** skill | superpowers |
| Systematic debugging (root cause before fixes) | the **`debugging`** skill | superpowers |
| Code review | the **`review`** skill | gstack |
| Security review | the **`cso`** skill | gstack |
| Browser/QA validation (read-only) | the **`qa-only`** skill | gstack |

When a SpecShip step says "follow the brainstorming method" / "TDD this" / "review the code," that means **invoke the named companion skill** — do not paraphrase or re-derive it here.

## The non-negotiable gates SpecShip still owns

These are SpecShip's responsibility (the companions don't enforce them) and remain in force every build:

1. **TDD is mandatory** — no production code without a failing test first, via the `tdd` skill. The build TEST GATE blocks any milestone whose new behavior wasn't red-before-green.
2. **Contract before code** — define acceptance criteria + failure modes + design spec first (`specship-contract`).
3. **Validate against the contract, not vibes** — independent adversarial validators with typed verdicts; never self-evaluate.
4. **Browser proof for UI**, **no AI slop**, **surgical changes** — see `specship-guardrails`.

## Surface note

These companions are installed as **Kiro skills** (`~/.kiro/skills/`, invoked by name). SpecShip ships on two surfaces — the Kiro IDE Power and the Kiro CLI skills — and delegates to the same companion skills from either. See `PREREQUISITES.md` for install steps.
