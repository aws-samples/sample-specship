---
inclusion: manual
---

# Architecture Guidance for SpecShip Workers

When building software that follows enterprise patterns, workers must follow these patterns. This file is included in worker context for complex builds.

## Technology Selection Principle: Boring Over Clever

Choose the most BORING, PROVEN technology that meets the requirements:

| Prefer | Over | Why |
|--------|------|-----|
| Vite + React | React CDN + htm | Vite has proper HMR, bundling, no module conflicts |
| Express + EJS | Custom SSR | EJS just works, no hydration issues |
| PostgreSQL | Custom file-based DB | Widely-used, migrations exist |
| bcrypt | Custom crypto | Never roll your own crypto |
| Established ORMs | Raw SQL everywhere | Migrations, types, query safety |
| npm/yarn | curl-installed binaries | Reproducible, lockfiles, auditable |

**The rule:** If a technology choice requires "clever" workarounds to function (CDN imports, manual module resolution, custom build scripts), it's the WRONG choice for production. Pick the boring alternative that just works.

## Project Structure Principles

### Separation of Concerns
```
src/
├── api/          # HTTP handlers (thin — validate input, call service, format response)
├── services/     # Business logic (testable, no HTTP knowledge)
├── models/       # Data structures and validation
├── database/     # Persistence layer (repositories)
├── middleware/   # Cross-cutting concerns (auth, logging, error handling)
├── config/       # Environment-based configuration
└── utils/        # Pure functions, helpers
```

### The Rules
1. **API handlers are thin.** They validate input, call a service, and format the response. No business logic.
2. **Services are pure business logic.** They don't know about HTTP, databases, or frameworks. They accept data and return data.
3. **Database access is a separate layer.** Services call repositories, not SQL directly.
4. **Configuration is environment-based.** No hardcoded values. Use env vars with sensible defaults.
5. **Error handling is centralized.** One error middleware catches everything. Services throw typed errors.

## Code Quality Standards

### Every file must:
- Have a single responsibility (if you can't describe it in one sentence, split it)
- Export a clear interface (what goes in, what comes out)
- Handle errors explicitly (no silent swallowing)
- Be under 200 lines (strong signal to split if exceeding)

### Every API endpoint must:
- Validate all input (types, ranges, required fields)
- Return consistent error format: `{ "error": "message", "code": "ERROR_CODE" }`
- Use appropriate HTTP status codes
- Log the request (method, path, status, duration)

### Every database interaction must:
- Use parameterized queries (never string interpolation)
- Handle connection failures gracefully
- Include indexes for queried columns
- Have a migration path (not just CREATE TABLE IF NOT EXISTS for production)

## Security Baseline (always applied)

- Input validation on ALL user-provided data
- Output encoding for any data rendered in HTML
- No secrets in source code (use environment variables)
- Dependencies pinned to exact versions in lockfile
- CORS configured explicitly (not `*` in production)
- Rate limiting on public endpoints
- Helmet.js (or equivalent) for HTTP headers

## Testing Standards

- Every service function has unit tests
- Every API endpoint has integration tests
- Tests use fixtures/factories, not production data
- Test database is separate from dev database
- CI runs tests before any merge

## Scalability Patterns

- Stateless server (no in-memory sessions — use Redis/DB for state)
- Connection pooling for databases
- Pagination on all list endpoints (never return unbounded results)
- Async operations for anything > 100ms (email, file processing, external APIs)
- Health check endpoint (`GET /health`) returning service status
