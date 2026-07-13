---
inclusion: auto
name: specship-contract
description: Use when defining what "done" means for a unit of work — a sprint contract with acceptance criteria, failure modes, design spec, and API contract. Triggered during planning or directly via "sprint contract", "define done", "acceptance criteria".
---

# specship-contract — Sprint Contract Generation

Trigger: "sprint contract", "define done", "acceptance criteria", "specship contract".

You are generating a **Sprint Contract** — a formal definition of what "done" looks like for a unit of work. This contract will be used by adversarial validators to judge whether the implementation is correct. The contract must be specific enough that a separate, independent reviewer (with no knowledge of the implementation) can determine pass/fail.

Suggested model: Opus when the goal is nuanced or the acceptance criteria need careful adversarial framing; Sonnet for straightforward, well-scoped contracts. (Kiro routes per chat or per custom-agent, not per steering file — pick the model when you start the session.)

> Kiro-native note: SpecShip (Claude Code) emitted machine traces to JSONL files at the start/end of this skill. Kiro has no such trace harness. Where the source recorded a "start" and a "complete" trace, just keep an observable record of what you produced (the saved contract file is itself the record). The rule that matters survives: the contract is the durable artifact every later phase reads from.

## When to Use

- Before writing any implementation code
- After brainstorming/design is complete
- When a goal is clear but success criteria are not formalized
- When the orchestrator enters the PLAN phase

Save the contract to `.specship/specs/<ID>-<slug>/requirements.md`. It is the source of truth that the design and task breakdown are derived from. Do NOT save to `.kiro/specs/` or `docs/`.

## Process

### Step 1: Understand the Goal

Read the available context:
- User's stated goal or prompt
- Design document (if one exists from brainstorming)
- Existing codebase context (if modifying existing code)
- Brownfield reconnaissance, especially `artifacts/reverse-engineering/brownfield-contract-inputs.md` (if modifying existing code)

If the goal is ambiguous, ask ONE clarifying question. Do not proceed with assumptions.

### Step 2: Generate the Contract

Use the sprint contract template (see "Output Format" below for the full structure). Fill in every section with concrete, verifiable content.

**Acceptance Criteria rules:**
- Each criterion must be independently testable
- Use "When X, then Y" format
- Include both happy path and edge cases
- Minimum 3 criteria for simple tasks, 10-15+ for production apps
- Never write vague criteria like "works correctly" or "handles errors properly"

**Failure Modes rules:**
- Describe specific broken states the validators should catch
- Include user-visible failures (not just internal errors)
- Think adversarially: "what would a lazy implementation get wrong?"
- For brownfield work, include regressions of existing behavior from `preserved-behaviors.md` / `brownfield-contract-inputs.md`
- For full-stack projects, ALWAYS include these failure modes:
  - "Frontend expects wrapped response (data.items) but backend returns plain array"
  - "Create operation succeeds (API returns 201) but new item doesn't appear in list without page refresh"
  - "Frontend calls an endpoint path that doesn't match the backend route definition"

**Scope rules:**
- Explicitly list what is OUT of scope
- This prevents scope creep during implementation
- When in doubt, exclude it
- For brownfield work, list files/areas to avoid touching and compatibility behavior that must remain unchanged

**Non-Functional Requirements (for enterprise/production builds):**
- If the goal is a production service or customer-facing application, INCLUDE the NFR section
- Define: performance targets, security requirements, testing expectations, observability needs
- These become validator criteria — the security validator checks security NFRs, the code validator checks test coverage
- For simple/internal tools, NFRs can be minimal or omitted

### Step 3: Determine Contract ID

Contracts live under `.specship/specs/`. Create that directory if it does not exist. Assign the next sequential, zero-padded three-digit ID (e.g. `001`, `002`, `003`) by counting how many `*.md` contract files already exist in `.specship/specs/` and adding one. (In the original Claude Code skill this was a small shell snippet that counted the files and `printf`-padded the number — the mechanism is unimportant; the rule is: monotonically increasing, zero-padded to three digits.)

### Step 4: Save and Commit

Create the spec directory at `.specship/specs/<ID>-<slug>/` and save the contract as **three files** (matching Kiro's native spec structure):

- **`requirements.md`** — Goal, Acceptance Criteria, Failure Modes, Scope, Risks & Unknowns, Execution Config, Validation Results table
- **`design.md`** — Design Spec (colors, typography, layout, components), API contract (endpoint shapes), WebSocket contract (if real-time), Market Research Reference, NFRs
- **`tasks.md`** — (empty for now — filled by Step 5 when the implementation plan is written)

```bash
mkdir -p .specship/specs/<ID>-<slug>
# Write requirements.md and design.md
git add .specship/specs/
git commit -m "[specship] contract: <title> | id: <ID>"
```

### Step 5: Offer Next Steps

After saving:

> "Sprint contract saved to `.specship/specs/<ID>-<slug>/` (requirements.md + design.md). Next steps:
> 1. Pre-generate test cases from this contract (specship-testgen).
> 2. Write the implementation plan into `tasks.md` (specship-plan Step 5).
> 3. Edit the contract if anything needs adjustment."

## Output Format

The contract must follow this template **exactly**. Do not invent new sections or omit required ones. (This is the shared sprint-contract-template reference, in this Power's `steering/shared/`.)

```markdown
# Sprint Contract: {{TITLE}}

**ID:** {{NNN}}
**Created:** {{DATE}}
**Status:** draft | active | validated | archived

---

## Goal

{{One paragraph: what we are building and why it matters.}}

## Acceptance Criteria

Each criterion must be independently verifiable:

1. {{Specific, measurable criterion — "When X happens, Y should result"}}
2. {{Another criterion}}
3. {{Another criterion}}

## Failure Modes

What "broken" looks like — the evaluator checks these explicitly:

1. {{Specific failure scenario — "If X, the system should NOT Y"}}
2. {{Another failure mode}}

## Scope

**IN scope:**
- {{Explicitly included}}

**OUT of scope:**
- {{Explicitly excluded — prevents scope creep}}

## Design Spec

The visual and interaction design for this product:

- **Design system:** {{e.g., "Tailwind CSS + shadcn/ui components"}}
- **Color palette:**
  - Primary: {{hex}} / Secondary: {{hex}} / Accent: {{hex}}
  - Neutrals: {{scale from light to dark}}
  - Semantic: success={{hex}}, error={{hex}}, warning={{hex}}
- **Typography:**
  - Headings: {{font family, weights used}}
  - Body: {{font family, weights used}}
  - Scale: {{e.g., "12/14/16/20/24/32/48px"}}
- **Layout:** {{e.g., "Sidebar (240px) + main content, responsive collapse at 768px"}}
- **Component library:** {{e.g., "shadcn/ui for all interactive components"}}
- **Icon set:** {{e.g., "Lucide React"}}
- **Dark mode:** {{yes/no, how toggled}}
- **Key interactions:** {{e.g., "drag-and-drop for reorder, inline editing for titles, command palette"}}

## Market Research Reference

See: `.specship/specs/{{NNN}}-{{slug}}/market-research.md`

**Target quality:** Match {{reference product}}'s core experience. Specifically implement {{N}}/{{total}} professional UX patterns identified in the brief.

## Non-Functional Requirements (Enterprise)

For software that follows enterprise patterns, define quality attributes:

- **Performance:** {{Response time targets, e.g., "API responses < 200ms at p95, Lighthouse > 90"}}
- **Security:** {{Auth method, data encryption, input validation requirements}}
- **Scalability:** {{Concurrent users, data volume, stateless requirement}}
- **Reliability:** {{Uptime target, error handling, graceful degradation}}
- **Observability:** {{Logging, health checks, monitoring endpoints}}
- **Testing:** {{Coverage target, test types required (unit/integration/e2e)}}
- **Deployment:** {{Docker, CI/CD pipeline, environment config, health checks}}
- **Accessibility:** {{WCAG level, keyboard navigation, screen reader support}}

(Remove any that don't apply. For simple projects, this section can be minimal.)

## Risks & Unknowns

- {{Known unknowns that might affect delivery}}

## Execution Config

```yaml
model_routing:
  planner: opus
  worker: sonnet
  validator: sonnet
  alignment: opus
autonomy: guided
```

## Pre-Generated Test Cases

See: `.specship/specs/{{NNN}}-{{slug}}/test-cases.md`

## Validation Results

| Validator | Result | Details |
|-----------|--------|---------|
| Code Review | pending | |
| Security | pending | |
| Browser | pending | |
| Alignment | pending | |

**Aggregate Verdict:** pending
```

Notes on the template's Kiro-specific fields:
- **Execution Config / `model_routing`:** In Claude Code this told the orchestrator which model to assign each role. Kiro routes per chat or per custom-agent, not per steering file, so treat these as *suggested* models per role — Planner: Opus, Worker: Sonnet, Validator: Sonnet, Alignment: Opus — and pick the model when you start each session. Keep the field in the contract as the documented intent; `autonomy: guided` records the desired autonomy level for the mission.
- **Validation Results table:** This is filled in later by the validate phase; it starts as all `pending` with an `Aggregate Verdict: pending`.

## Key Principles

- **Specificity over completeness.** 5 precise criteria beat 15 vague ones.
- **Testable by a stranger.** Someone with no context should be able to read a criterion and determine pass/fail from the implementation alone.
- **Adversarial thinking.** Write failure modes as if you're trying to catch a lazy implementer cutting corners.
- **Scope is a weapon.** The OUT-of-scope list prevents 80% of scope creep.
