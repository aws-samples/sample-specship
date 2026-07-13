---
inclusion: manual
---

# Enterprise Production Readiness Checklist

For any project targeting production customer usage, the specship-plan skill must ensure these are addressed across milestones. Not every item applies to every project — but each must be explicitly evaluated (included or excluded with reason).

## Foundation (Milestone 1 always)

- [ ] Project scaffolding with proper structure (src/, tests/, config/)
- [ ] Dev server starts with single command
- [ ] Test infrastructure configured (framework, runner, CI)
- [ ] Linting configured (ESLint/Biome/Ruff)
- [ ] TypeScript or type checking (if applicable)
- [ ] Environment-based config (dev/test/prod)
- [ ] .env.example with all required variables documented
- [ ] Health check endpoint with dependency status

## Security (must be in early milestones, not bolted on at end)

- [ ] Authentication (JWT/session/OAuth — chosen and implemented)
- [ ] Authorization (role-based or resource-based access control)
- [ ] Input validation on ALL endpoints (not just some)
- [ ] Rate limiting on auth endpoints (prevent brute force)
- [ ] CORS configured (not wildcard in production)
- [ ] Helmet.js or equivalent HTTP security headers
- [ ] Secrets in environment variables (never committed)
- [ ] SQL injection prevention (parameterized queries verified)
- [ ] XSS prevention (output encoding, CSP headers)
- [ ] Dependency audit (`npm audit` / `pip audit` clean)

## Data Layer

- [ ] Database migrations (not just CREATE IF NOT EXISTS — proper versioned migrations)
- [ ] Connection pooling configured
- [ ] Indexes on queried columns
- [ ] Soft delete (if applicable) vs hard delete
- [ ] Data validation at model layer (not just route layer)
- [ ] Backup strategy documented

## API Design

- [ ] Consistent response format across all endpoints
- [ ] Proper HTTP status codes (not just 200 and 500)
- [ ] Pagination on all list endpoints (never unbounded)
- [ ] API versioning (if public API)
- [ ] Request/response logging (method, path, status, duration)
- [ ] OpenAPI/Swagger documentation (if public API)

## Testing (must be substantial, not token)

- [ ] Unit tests for business logic (services)
- [ ] Integration tests for API endpoints
- [ ] Auth tests (register, login, protected routes, invalid tokens)
- [ ] Edge case tests (empty input, huge input, special characters)
- [ ] Error path tests (not just happy path)
- [ ] Load/stress test (at least one: can it handle 100 concurrent requests?)
- [ ] Test coverage > 70% on business logic

## Observability

- [ ] Structured logging (JSON format, levels: error/warn/info/debug)
- [ ] Request logging middleware (method, path, status, duration)
- [ ] Error tracking (uncaught exceptions logged with context)
- [ ] Health check with dependency status (DB connected? External services reachable?)
- [ ] Metrics endpoint or logging (request count, error rate, response times)

## Reliability

- [ ] Graceful shutdown (close DB connections, finish in-flight requests)
- [ ] Error handling middleware (never crash, always respond)
- [ ] Retry logic for external service calls
- [ ] Circuit breaker pattern (if calling external APIs)
- [ ] Timeout on all external calls (never hang indefinitely)

## Deployment

- [ ] Dockerfile (multi-stage build, non-root user)
- [ ] docker-compose for local development (app + DB + any services)
- [ ] CI/CD pipeline (test → build → deploy)
- [ ] Environment separation (dev/staging/prod)
- [ ] Zero-downtime deployment strategy documented
- [ ] Rollback plan documented

## Performance

- [ ] Response time targets defined and measured
- [ ] Database queries analyzed (no N+1, indexes present)
- [ ] Caching strategy (if applicable — Redis, in-memory, HTTP cache)
- [ ] Static asset optimization (if frontend: bundling, compression, CDN)
- [ ] Connection pooling sized appropriately

## Scale Considerations

- [ ] Stateless server (no in-memory sessions)
- [ ] Horizontal scaling possible (multiple instances behind load balancer)
- [ ] Database connection limits handled
- [ ] File storage externalized (S3/GCS, not local disk)
- [ ] Background jobs for heavy processing (not blocking request handlers)

---

## How specship-plan Uses This

When generating milestones for an enterprise project:

1. **Milestone 1:** Foundation + Security basics (from Foundation + first Security items)
2. **Milestone 2-N:** Feature milestones (business logic)
3. **Milestone N+1:** Testing hardening (load tests, edge cases, coverage)
4. **Milestone N+2:** Observability + Reliability (logging, graceful shutdown, health)
5. **Final Milestone:** Deployment readiness (Dockerfile, CI/CD, env config)

Each milestone should address items from this checklist relevant to what's being built. The validator checks these at the end.

## Adaptive Application

Not every project needs every item. The specship-contract NFR section determines which apply:

- **Internal tool:** Skip deployment, scale considerations, API versioning
- **SaaS product:** All items relevant
- **Microservice:** Focus on reliability, observability, deployment. Skip frontend items.
- **CLI tool:** Skip API design, deployment (different concerns)

The contract's NFR section is the authority. This checklist is guidance, not dogma.
