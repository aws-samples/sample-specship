---
inclusion: manual
---

# Worker Prompt Template

Use this template when running an implementation task as a focused pass — a fresh Kiro chat session, or a task in a Kiro Spec task wave. The quality of the worker's output depends entirely on the quality of its prompt.

## Template

```
You are implementing a task for the SpecShip workflow.

## Your Task

[PASTE FULL TASK TEXT FROM PLAN — every step, every file path, every code block]

## Context

Project: [project name and one-line description]
Tech stack: [language, framework, database, key dependencies]
Current milestone: [N of M] — [milestone name]
Previous milestones delivered: [brief list of what's already working]

## Architecture Rules

- Thin handlers: validate input → call service → format response
- Services are pure business logic (no HTTP, no database knowledge)
- Database access through repository functions only
- Input validation on ALL user-provided data
- Consistent error format: { "error": "message" }
- Files under 200 lines (split if larger)
- Parameterized queries only (never string interpolation in SQL)

## Before You Begin

If anything is unclear about the task, ASK. Do not guess.
If you think the task is wrong or impossible, say so with reasoning.

## Your Deliverables

1. Implement exactly what the task specifies
2. Write tests (following TDD if task says to)
3. Verify: run tests, check for errors
4. Commit with message format: [specship] <description> | contract: <id>
5. Self-review: did you handle edge cases? Input validation? Error paths?

## Report Format

When done, report:
- Status: DONE | DONE_WITH_CONCERNS | BLOCKED | NEEDS_CONTEXT
- What you implemented
- What you tested (command + result)
- Files changed
- Concerns (if any)
```

## Full-Stack Projects: API Contract in Worker Context (MANDATORY)

For projects with both frontend and backend, workers that touch frontend API calls MUST receive the API contract. Without it, they will guess response shapes — and guess wrong.

**When dispatching a frontend worker, add this section to the prompt:**

```
## API Contract (source of truth for response shapes)

These are the EXACT response formats returned by the backend. Your frontend code MUST consume them exactly as shown — do not wrap, rename, or restructure.

| Endpoint | Method | Response Shape |
|----------|--------|---------------|
| GET /api/workspaces | GET | Array<{ id, name, owner_id, created_at }> (plain array, NOT wrapped in object) |
| POST /api/workspaces | POST | { id, name, owner_id, created_at } (single object) |
| GET /api/workspaces/:id/projects | GET | Array<{ id, name, workspace_id, created_at }> (plain array) |
| ... | ... | ... |

CRITICAL: If the backend returns a plain array, your frontend MUST handle a plain array:
  ✅ setWorkspaces(data)  — correct (data IS the array)
  ❌ setWorkspaces(data.workspaces)  — WRONG (data has no .workspaces property)

If you are unsure about a response shape, read the backend route file and check the res.json() call. Do NOT assume a wrapper object exists.
```

**How the orchestrator gets the contract:**
1. If `.specship/specs/<id>/api-contract.md` exists → paste it directly
2. If not, read the backend route files and extract `res.json(...)` calls to build the table
3. For POST/PUT responses: note whether they return the created/updated object or just `{ success: true }`

**The rule:** A frontend worker without the API contract is like a developer without API documentation. They will write code that "looks right" but fails at runtime.

## Guidelines for the Orchestrator

When constructing the prompt:
- ALWAYS paste the full task text (don't make the worker read files)
- ALWAYS include tech stack context (the worker doesn't know the project)
- ALWAYS include what milestones are already done (so it doesn't rebuild existing work)
- ALWAYS include API contract for frontend workers (see above)
- NEVER include other tasks (the worker only needs its own task)
- NEVER include conversation history (fresh context is the point)
- If the project has specific conventions (naming, file structure), include them briefly
