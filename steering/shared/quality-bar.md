---
inclusion: manual
---

# Internal Quality Bar

> **Note**: This document defines internal quality standards for SpecShip builds. Meeting these standards is necessary but not sufficient for deployment. All generated code is sample/reference implementation and requires additional security testing and AppSec review before any deployment.

This document defines what "meets the bar" means in SpecShip. Every build that targets this quality bar MUST meet these standards. If any section fails, the build is AI slop — not shippable.

## The Anti-Slop Checklist

AI slop has these characteristics. If your output matches ANY of these, it has FAILED:

| AI Slop Pattern | Production Standard |
|----------------|-------------------|
| Inline styles | Real design system (Tailwind, CSS modules, shadcn) |
| Generic sans-serif font | Deliberate typography hierarchy (2-3 fonts max, clear scale) |
| Blue buttons on white background | Cohesive color palette with intentional contrast ratios |
| "Lorem ipsum" or fake data | Realistic seed data that looks like a real user's account |
| Single page with a form and list | Multi-view application with navigation, states, empty states |
| No loading states | Skeleton screens, progress indicators, optimistic UI |
| No error handling in UI | Error boundaries, toast notifications, retry mechanisms |
| Desktop-only | Responsive from 320px to 2560px |
| No keyboard navigation | Full keyboard support, focus management, shortcuts |
| Generic favicon | Custom branding, proper meta tags, OG images |
| No animations | Subtle, purposeful transitions (not gratuitous) |
| Bare HTML elements | Polished components with hover/active/focus states |
| Alert() for confirmations | Modal dialogs with proper UX |
| Console.log for errors | Structured logging, error tracking |
| "Works on my machine" | Docker, env config, health checks, deployment scripts |
| No documentation | README with setup, architecture, API docs |

## Table-Stakes Enforcement (CRITICAL)

The market research identifies "table stakes" features — things users EXPECT from this category of product. The workflow MUST ensure ALL table-stakes features are built, not just the foundation + a few features.

**Anti-pattern (what happened in a chat build's first pass):**
- Market research listed 14 table-stakes features
- Build delivered: login, channels, messages, send (4/14)
- Missing: logout, profiles, DMs, threading, reactions, mentions, file upload, presence, search, typing indicators

**The fix:** The planning phase must generate one milestone per table-stakes feature group. The contract's acceptance criteria must have AT LEAST one criterion per table-stakes feature. If the market research lists 14 features, the contract needs 14+ acceptance criteria.

**Validation gate:** The alignment validator MUST compare implemented features against the market research's table-stakes list. If fewer than 80% of table-stakes features are implemented, verdict is FAIL — even if everything that IS implemented works perfectly.

"It works" is not "it's complete." A Slack clone without logout is not a Slack clone.

## Feature Completeness Standard

A production app is NOT just the "happy path." For EVERY feature, implement:

1. **Happy path** — the thing works
2. **Empty state** — what does the user see before any data exists?
3. **Loading state** — what shows while data is being fetched?
4. **Error state** — what happens when the API fails?
5. **Edge cases** — what about extremely long text? 1000 items? Unicode?
6. **Bulk operations** — can users act on multiple items at once?
7. **Undo/recovery** — can users reverse destructive actions?
8. **Persistence** — does state survive page refresh? Does URL reflect state?
9. **Accessibility** — screen reader support, keyboard navigation, ARIA labels
10. **Responsive** — works on mobile, tablet, desktop, ultrawide

## Market Comparison Standard

Before building ANY product that has real-world equivalents:

1. **Identify 2-3 real products** in the same category
2. **Document their core UX patterns** — not features, but HOW features feel
3. **List the 10 things that make them feel "professional"** vs a tutorial project
4. **Your implementation must match at least 7/10** of those professional patterns

Example for a chat app:
- Real-time message appearance (not polling)
- Typing indicators
- Read receipts / delivery status
- Message threading/replies
- File/image sharing with preview
- Emoji reactions
- Mention autocomplete (@user)
- Keyboard shortcuts (Cmd+K for search)
- Notification badges
- Presence indicators (online/away/offline)

If your "chat app" is just a text input and a list of messages, it's a tutorial — not a product.

## Design Quality Standard

### Typography
- Use a type scale (e.g., 12/14/16/20/24/32/40/48px)
- Max 2-3 font families (heading + body + optional mono)
- Line height: 1.4-1.6 for body, 1.1-1.3 for headings
- Max line width: 65-75 characters for readability

### Color
- Primary, secondary, and accent colors with 5 shades each
- Semantic colors: success, warning, error, info
- Neutral scale: 8+ shades from white to near-black
- WCAG AA contrast ratios (4.5:1 for text, 3:1 for large text)

### Spacing
- Consistent spacing scale (4px base: 4, 8, 12, 16, 24, 32, 48, 64)
- Use the scale — never arbitrary pixel values

### Components
- Every interactive element needs: default, hover, active, focus, disabled states
- Consistent border radius across the app
- Consistent shadow scale (sm, md, lg)
- Icons from a single icon family (Lucide, Heroicons, etc.)

### Layout
- Clear visual hierarchy
- Consistent page structure
- Proper use of whitespace
- Grid-based alignment

## Deployment Readiness

Meeting the deployment-readiness bar means deployable NOW — not "works in dev mode":

- **Docker:** Multi-stage build, non-root user, health check
- **Environment config:** All secrets via env vars, no hardcoded values
- **Database:** Migrations (not schema.sql), seed data for dev
- **CI/CD:** GitHub Actions or equivalent, lint + test + build + deploy
- **Monitoring:** Health endpoint, structured logs, error tracking hook
- **HTTPS:** TLS configuration or Cloudflare/Vercel automatic SSL
- **Domain:** Ready for custom domain binding
- **Performance:** Lighthouse score > 90 for web apps — **MEASURED** by the design validator via `mcp__chrome-devtools__lighthouse_audit`, not self-asserted. A score that wasn't measured is INCOMPLETE, not PASS.
- **Security:** Headers (HSTS, CSP, X-Frame-Options), rate limiting

## How This Integrates with SpecShip

1. **Planning phase:** The market research informs the contract's acceptance criteria
2. **Contract phase:** The quality bar items become explicit AC and NFRs
3. **Build phase:** Workers receive design tokens + component inventory + quality checklist in every prompt
4. **Mid-build checks:** After each UI milestone, screenshot and compare to reference density/patterns
5. **Validate phase:** Design review validator checks against this quality bar with screenshots
6. **Ship phase:** Deployment readiness is a gate before PR creation

## Worker Quality Prompt (include in EVERY frontend worker)

```
## Quality Checklist (verify before marking task done)

Before you commit this code, self-check:
[ ] Used design system components (not custom/inline styles)
[ ] All colors are from the palette (no arbitrary hex values)
[ ] All spacing is from the scale (no arbitrary px)
[ ] Interactive elements have hover/active/focus/disabled states
[ ] Loading state implemented (skeleton or spinner)
[ ] Empty state implemented (helpful message, not blank)
[ ] Error state implemented (toast or inline error)
[ ] Responsive at 375px (check layout doesn't break)
[ ] Keyboard accessible (can tab to all interactive elements)
[ ] Animation on state changes (subtle, purposeful)

If ANY box is unchecked, your task is NOT complete.
```

## Density Guidance for Chat/Dashboard UIs

AI tends to produce SPACIOUS layouts (lots of padding, large text, card-based). Real productivity tools are DENSE:

- **Messages:** 4-8px vertical padding per message, not 16-24px
- **Sidebar items:** 28-32px height per item, not 48-56px
- **Font sizes:** 13-14px for body, not 16px
- **Line height:** 1.3-1.4 for dense lists, not 1.6
- **Padding:** 8-12px in containers, not 24-32px
- **Borders:** 1px subtle separators, not heavy shadows

When building dense UIs, tell workers explicitly: "This is a COMPACT layout. Use tight spacing (4-8px between messages). Reference Slack's density, not a blog post layout."

The quality bar is NOT optional for production builds. It's not "nice to have." It's the difference between software people use and software people close immediately.

## State Management Pattern (CRUD Apps)

For apps with create/edit/delete operations, use the **"refetch after mutation"** pattern:

```typescript
// CORRECT: refetch all data after any mutation
const handleDelete = async (id) => {
  await deleteItem(id);
  await fetchData(); // refetch ALL state from server
};

// WRONG: optimistic splice (causes stale state bugs)
const handleDelete = async (id) => {
  await deleteItem(id);
  setItems(prev => prev.filter(i => i.id !== id)); // DANGEROUS: stale closures
};
```

**Why:** a notes build had stale-closure bugs (deleting a copy deleted the original) because it manually manipulated state. An expense-splitter build used refetch-after-mutation and had ZERO state bugs.

**The tradeoff:** Refetch is slightly slower (extra API call) but eliminates an entire class of frontend state bugs. For apps with < 1000 items, the performance cost is negligible.

**Worker prompt instruction:** "After every create/update/delete, call the fetch function to reload ALL data from the server. Do NOT manually filter/splice local state arrays."

## Database Strategy (Default: SQLite)

For proof builds, demos, and single-user apps: **always use SQLite (better-sqlite3)**. It requires zero infrastructure (no Docker, no PostgreSQL service, no connection strings).

**Use SQLite when:**
- Single-user or low-concurrency app
- The user doesn't have Docker
- It's a proof build or demo
- The data model is straightforward (< 10 tables)

**Use PostgreSQL when:**
- Multi-user concurrent writes
- Complex queries (JSON operators, full-text search)
- The user explicitly requests it
- Production deployment with multiple app instances

**The pattern:** Build with SQLite first, prove the app works, then upgrade to PostgreSQL later if needed. Never let "I need Docker" block a working demo.

## Worker Strategy (SpecShip: always dispatch subagents for feature work)

**In SpecShip autonomous builds, feature milestones (Milestone 1+) ALWAYS dispatch a subagent per task — regardless of app size.** Do NOT build features inline as the coordinator "because it's small." Only Phase 0 (scaffold/infra) may run as coordinator.

We previously advised "one worker for < 15 features / < 2000 lines." **That advice is retired** — it caused an autonomous run to build ~100 files in one accumulating context and run out of context/step budget before any validator ran. Subagents are mandatory because they bound the coordinator's context window; an unbounded single pass fails to complete.

The thing that "single worker" was trying to avoid (integration drift) is prevented by **injecting `api-contract.md` + `ws-contract.md` into every subagent prompt** (see `worker-prompt-template`), not by collapsing into one pass. Consistency comes from shared contracts, not shared context.
