---
inclusion: manual
---

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
