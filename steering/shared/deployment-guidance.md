---
inclusion: manual
---

# Deployment Guidance for SpecShip Enterprise Builds

The final milestone of an enterprise build should produce a deployable artifact. This guidance covers what "deployment ready" means.

## Minimum Deployment Artifacts

### 1. Dockerfile (required for any server-side app)

```dockerfile
# Multi-stage build — build dependencies separate from runtime
FROM node:20-slim AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production

FROM node:20-slim
WORKDIR /app

# Non-root user (security requirement)
RUN addgroup --system app && adduser --system --group app
USER app

COPY --from=builder /app/node_modules ./node_modules
COPY . .

EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=5s CMD curl -f http://localhost:3000/health || exit 1

CMD ["node", "src/index.js"]
```

Key requirements:
- Multi-stage build (smaller image, no dev deps)
- Non-root user (never run as root)
- Health check built in
- .dockerignore excludes: node_modules, .git, .env, tests, .specship

### 2. docker-compose.yml (for local dev + CI)

```yaml
version: '3.8'
services:
  app:
    build: .
    ports:
      - "3000:3000"
    environment:
      - NODE_ENV=production
      - DB_PATH=/data/app.db
      - JWT_SECRET=${JWT_SECRET}
    volumes:
      - app-data:/data
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/health"]
      interval: 30s
      timeout: 5s
      retries: 3

volumes:
  app-data:
```

### 3. CI/CD Pipeline (.github/workflows/ci.yml)

```yaml
name: CI
on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: 'npm'
      - run: npm ci
      - run: npm test
      - run: npm audit --audit-level=moderate

  build:
    needs: test
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: docker build -t app .
      - run: docker run --rm app node -e "console.log('Container starts')"
```

### 4. Environment Configuration

Required files:
- `.env.example` — documents all required env vars with descriptions
- `src/config.js` — centralized config that reads from env with defaults

```javascript
// src/config.js
module.exports = {
  port: parseInt(process.env.PORT || '3000'),
  nodeEnv: process.env.NODE_ENV || 'development',
  db: {
    path: process.env.DB_PATH || './data/app.db',
  },
  jwt: {
    secret: process.env.JWT_SECRET,
    expiry: process.env.JWT_EXPIRY || '24h',
  },
  rateLimit: {
    windowMs: parseInt(process.env.RATE_LIMIT_WINDOW || '900000'), // 15 min
    max: parseInt(process.env.RATE_LIMIT_MAX || '100'),
  },
};

// Fail fast if required vars missing in production
if (module.exports.nodeEnv === 'production' && !module.exports.jwt.secret) {
  throw new Error('JWT_SECRET is required in production');
}
```

### 5. Graceful Shutdown

```javascript
// In src/index.js
const server = app.listen(PORT);

process.on('SIGTERM', () => {
  console.log('SIGTERM received. Shutting down gracefully...');
  server.close(() => {
    db.close();
    console.log('Server closed.');
    process.exit(0);
  });

  // Force close after 10s
  setTimeout(() => {
    console.error('Forced shutdown after timeout');
    process.exit(1);
  }, 10000);
});

process.on('SIGINT', () => process.emit('SIGTERM'));
```

## What "Deployment Ready" Means for specship-ship

Before shipping an enterprise project, verify:
1. `docker build .` succeeds
2. `docker run` starts the app and health check passes
3. All env vars documented in .env.example
4. CI pipeline exists and passes
5. Graceful shutdown works (send SIGTERM, verify clean exit)

If any of these fail, the ship phase should flag it:
> "Deployment readiness: INCOMPLETE. Missing: <list>. The app runs locally but is not production-deployable."
