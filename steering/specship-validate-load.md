---
inclusion: manual
---

# specship-validate-load — Load Testing Validator

Suggested model: a capable reasoning model (Kiro routes models per chat or per custom-agent, so pick one in your chat/agent settings).

You verify that the application performs under load. Enterprise software must handle concurrent users without degradation, crashes, or data corruption.

Run this validator as a focused pass — a fresh chat/session keeps it independent from the build work that produced the code.

## When to Run

- After all functional milestones complete (before ship)
- When contract NFRs specify performance targets
- When the contract mentions "scalable", "production", or "enterprise"
- Skip for: CLI tools, libraries, internal scripts

This validator exists for enterprise / performance NFRs only. If the contract has no performance target and does not follow enterprise/high-scale patterns, skip it (see "When to Skip").

## Pre-conditions

- App must be running (dev server or production build)
- At least one API endpoint exists
- Test data seeded (database not empty)

## Process

### Step 1: Identify Load Test Targets

From the contract (the NFR section in `.specship/specs/...`), identify the most critical endpoints:
- Authentication endpoints (highest traffic)
- Main data listing endpoints (most common query)
- Write endpoints (data integrity under concurrent writes)

Pick 3-5 endpoints maximum.

### Step 2: Create Load Test Script

You can drive load with an industry tool (k6 or artillery) or a simple self-contained Node.js script — both are valid. The key is to hit the chosen targets concurrently and capture req/sec, percentiles, and error rate.

If you use **k6**, a minimal script looks like:

```javascript
// load-test.k6.js — run with: k6 run load-test.k6.js
import http from 'k6/http';
import { check } from 'k6';

export const options = {
  vus: 50,            // 50 concurrent virtual users
  duration: '10s',    // 10 seconds
  thresholds: {
    http_req_duration: ['p(95)<500'],   // p95 under 500ms
    http_req_failed: ['rate<0.01'],     // less than 1% errors
  },
};

const BASE_URL = 'http://localhost:3000';

export default function () {
  // Add targets from the contract NFR
  const res = http.get(`${BASE_URL}/api/endpoint`, {
    headers: { Authorization: 'Bearer <token>' },
  });
  check(res, { 'status < 500': (r) => r.status < 500 });
}
```

If you use **artillery**, a minimal config looks like:

```yaml
# load-test.artillery.yml — run with: artillery run load-test.artillery.yml
config:
  target: "http://localhost:3000"
  phases:
    - duration: 10        # 10 seconds
      arrivalRate: 50     # 50 new virtual users per second
  ensure:
    p95: 500              # p95 under 500ms
    maxErrorRate: 1       # less than 1% errors
scenarios:
  - flow:
      - get:
          url: "/health"
      - get:
          url: "/api/endpoint"
          headers:
            Authorization: "Bearer <token>"
```

If neither k6 nor artillery is available, a self-contained Node.js script needs no external tools:

```javascript
// load-test.js — Simple concurrent request tester
const http = require('http');

const TARGETS = [
  { method: 'GET', path: '/health' },
  { method: 'GET', path: '/api/endpoint', headers: { Authorization: 'Bearer <token>' } },
  // Add targets from contract
];

const CONCURRENCY = 50;    // simultaneous requests
const DURATION_MS = 10000; // 10 seconds
const BASE_URL = 'http://localhost:3000';

async function makeRequest(target) {
  return new Promise((resolve) => {
    const start = Date.now();
    const options = {
      hostname: 'localhost',
      port: 3000,
      path: target.path,
      method: target.method,
      headers: target.headers || {},
    };

    const req = http.request(options, (res) => {
      let data = '';
      res.on('data', (chunk) => data += chunk);
      res.on('end', () => {
        resolve({
          status: res.statusCode,
          duration: Date.now() - start,
          success: res.statusCode < 500,
        });
      });
    });

    req.on('error', () => resolve({ status: 0, duration: Date.now() - start, success: false }));
    req.setTimeout(5000, () => { req.destroy(); resolve({ status: 0, duration: 5000, success: false }); });
    req.end();
  });
}

async function runLoadTest() {
  const results = [];
  const endTime = Date.now() + DURATION_MS;

  console.log(`Load test: ${CONCURRENCY} concurrent, ${DURATION_MS/1000}s duration`);

  while (Date.now() < endTime) {
    const batch = [];
    for (let i = 0; i < CONCURRENCY; i++) {
      const target = TARGETS[Math.floor(Math.random() * TARGETS.length)];
      batch.push(makeRequest(target));
    }
    const batchResults = await Promise.all(batch);
    results.push(...batchResults);
  }

  // Analyze
  const total = results.length;
  const successes = results.filter(r => r.success).length;
  const failures = total - successes;
  const durations = results.map(r => r.duration).sort((a, b) => a - b);
  const p50 = durations[Math.floor(total * 0.5)];
  const p95 = durations[Math.floor(total * 0.95)];
  const p99 = durations[Math.floor(total * 0.99)];
  const avg = durations.reduce((a, b) => a + b, 0) / total;

  console.log(`\nResults:`);
  console.log(`  Total requests: ${total}`);
  console.log(`  Successes: ${successes} (${(successes/total*100).toFixed(1)}%)`);
  console.log(`  Failures: ${failures}`);
  console.log(`  Avg response: ${avg.toFixed(0)}ms`);
  console.log(`  p50: ${p50}ms`);
  console.log(`  p95: ${p95}ms`);
  console.log(`  p99: ${p99}ms`);
  console.log(`  Requests/sec: ${(total / (DURATION_MS/1000)).toFixed(0)}`);

  // Pass/Fail criteria
  const passed = successes/total >= 0.99 && p95 < 500;
  console.log(`\nVerdict: ${passed ? 'PASS' : 'FAIL'}`);
  if (!passed) {
    if (successes/total < 0.99) console.log(`  FAIL: Success rate ${(successes/total*100).toFixed(1)}% < 99%`);
    if (p95 >= 500) console.log(`  FAIL: p95 ${p95}ms >= 500ms target`);
  }

  process.exit(passed ? 0 : 1);
}

runLoadTest();
```

Note: the pass thresholds in the script (99% success, p95 < 500ms) are defaults. If the contract NFR specifies different targets (e.g. p95 < 200ms, or a required req/sec floor), tie the thresholds to the contract — the contract NFR wins.

### Step 3: Run Load Test

```bash
# Start app in background
node src/index.js &
APP_PID=$!
sleep 2

# Run load test (use the tool you chose in Step 2)
node load-test.js
# or: k6 run load-test.k6.js
# or: artillery run load-test.artillery.yml
LOAD_EXIT=$?

# Cleanup
kill $APP_PID 2>/dev/null

exit $LOAD_EXIT
```

If the app under test is a web UI rather than a raw API and you need to confirm it stays responsive after the load run, you can sanity-check it with Playwright MCP (e.g. browser_navigate / browser_take_screenshot / browser_snapshot) — if the browser tool is missing, install Playwright MCP via `.kiro/settings/mcp.json`.

### Step 4: Produce Evidence

```markdown
## Load Test Verdict

**Status:** PASS | FAIL

### Results
| Metric | Value | Target | Status |
|--------|-------|--------|--------|
| Total requests | N | - | - |
| Success rate | N% | >= 99% | PASS/FAIL |
| Avg response | Nms | - | - |
| p50 | Nms | - | - |
| p95 | Nms | < 500ms | PASS/FAIL |
| p99 | Nms | - | - |
| Requests/sec | N | - | - |
| Concurrency | 50 | - | - |
| Duration | 10s | - | - |

### Failures (if any)
- [list failed requests with status codes]
```

## Pass Criteria

- Success rate >= 99% (less than 1% errors under load)
- p95 response time < 500ms (95% of requests respond within 500ms) — or whatever the contract NFR specifies
- No crashes (server stays running throughout)
- No data corruption (spot-check data integrity after load test)

## Verdict Rules

- Both criteria met → PASS
- Success rate < 99% → FAIL (app crashes under load)
- p95 > 500ms → FAIL (app too slow under load — may indicate connection pool exhaustion, missing indexes, or synchronous blocking)
- Server crashes during test → FAIL

## When to Skip

- Contract explicitly says "internal tool" or "low traffic"
- No HTTP endpoints exist (library, CLI)
- Load test infra not available and contract doesn't require it

When skipping, output: "Load test skipped: <reason>. For production use, add load testing before deployment."

## Independent Review

If a deeper performance or correctness-under-load review is warranted, run it via gstack /qa-only, /cso, or /review if the gstack Kiro Power is installed; otherwise use Playwright/Chrome-DevTools MCP directly (or adversarial agent review for code/security). To inspect what changed since main, `git diff origin/main...HEAD`.

## Recording the Verdict

Record the verdict for this validator (conceptually under `.specship/artifacts/verdicts/...`, with run traces under `.specship/artifacts/traces/...`). If the browser tool is missing, install Playwright MCP via `.kiro/settings/mcp.json`. The machine-readable verdict you must emit is below.

```json
{
  "validator": "load",
  "status": "PASS | FAIL | PARTIAL | INCOMPLETE | SKIPPED",
  "evidence": [ { "claim": "what was checked", "artifact": "<N> req/s, <p95>ms p95, <err>% errors" } ],
  "blocking_issues": [ { "summary": "...", "file": "...", "line": 0, "expected": "...", "actual": "..." } ]
}
```
