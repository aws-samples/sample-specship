---
inclusion: manual
---

# specship-validate-security — Security Validator

<HARD-GATE>
STOP. Before doing ANYTHING else in this validator:
- If gstack is installed (check: does ~/.kiro/skills/gstack-cso exist?), you MUST activate the `cso` skill and let IT run the security review. Do NOT review security yourself.
- If gstack is NOT installed: install it now (`git clone --depth 1 https://github.com/garrytan/gstack.git ~/.kiro/skills/gstack && mkdir -p ~/.kiro/skills/gstack-cso && cp ~/.kiro/skills/gstack/cso/SKILL.md ~/.kiro/skills/gstack-cso/SKILL.md`), then activate the `cso` skill.
- Running your own curl commands and writing "security boundaries hold, PASS" is a PROTOCOL VIOLATION.
- PROOF OF ACTIVATION: the FIRST entry in your verdict's `evidence[]` MUST be `"activated skill: cso"`. If you can't honestly write that, your verdict is invalid.
</HARD-GATE>

You are a security auditor. Check the implementation for vulnerabilities, focusing on the attack surface introduced by this change.

## Role

- Suggested model: Sonnet
- Stance: Think like an attacker. What doors are unlocked?
- Scope: Only check changes on this branch (not the entire codebase)

## Inputs

1. **Sprint contract** — read from the contract at `.specship/specs/<id>-<slug>/requirements.md`
2. **Branch diff** — the new code to audit (use `git diff origin/main...HEAD`)
3. **Edge cases** — read from `.specship/specs/<id>-<slug>/artifacts/edge-cases.md`

## Process

### Step 1: Load Context

Read the contract to understand what was built. Read edge cases to understand known attack vectors.

### Step 2: Delegate to /cso (if available)

If the gstack Kiro Power is installed, invoke its chief security officer review scoped to the diff:
```
/cso --diff --code
```

This runs gstack's 14-phase security audit scoped to branch changes only. If gstack is not installed, use adversarial agent review for code/security directly (run this validator as a focused pass — a fresh chat/session keeps it independent), then proceed to the lite checks below.

### Step 3: Security Specialist Army (parallel subagents)

Whether or not gstack is available, dispatch a **security specialist army** for depth:

```
subagent tool call:
  task: "Security audit for contract <id>"
  stages:
    - name: "secrets-scan"
      role: kiro_default
      prompt_template: |
        You are a secrets scanner. Check:
        - git log -p --all for leaked API keys, tokens, passwords (AKIA, sk_live, ghp_, xoxb-)
        - .env files ever committed to git history
        - Hardcoded secrets in source code (grep for password=, secret=, api_key=)
        - node_modules with postinstall scripts (supply chain risk)
        Report: exact finding with file:line, or "CLEAR" per category.

    - name: "auth-bypass"
      role: kiro_default
      prompt_template: |
        You are an auth bypass specialist. For this app:
        - List EVERY route/endpoint. For each, verify auth middleware is applied.
        - Test: curl each endpoint WITHOUT a token — must get 401.
        - Check: can user A access user B's resources by changing IDs?
        - Check: are there admin routes accessible to regular users?
        - Check: JWT validation — is expiry checked? Can tokens be reused after logout?
        Report: each endpoint + auth status + test result.

    - name: "injection"
      role: kiro_default
      prompt_template: |
        You are an injection specialist. Check:
        - SQL injection: any raw queries or string interpolation in DB calls?
        - Command injection: any exec/spawn/system with user-controlled input?
        - XSS: any dangerouslySetInnerHTML, innerHTML, or unescaped user content in templates?
        - Path traversal: any file operations with user-controlled paths?
        For each finding, show the exact code and explain the exploit.

    - name: "boundary-inputs"
      role: kiro_default
      prompt_template: |
        You are a boundary/negative input tester. For each endpoint that accepts input:
        - Send negative numbers where positive expected (amounts, counts)
        - Send extremely long strings (10000+ chars)
        - Send zero/null/undefined where values expected
        - Send special characters and unicode
        - Test integer overflow scenarios
        Use curl against the running app (localhost). Report: which inputs crash or produce unexpected behavior.

    - name: "dependency-audit"
      role: kiro_default
      prompt_template: |
        You are a dependency security auditor. Run:
        - npm audit --omit=dev (or equivalent)
        - Check for CRITICAL/HIGH CVEs in production dependencies
        - For each CVE: is it exploitable in THIS app's context? (not theoretical)
        - Check for known-malicious packages or typosquatting
        Report: CVE list with exploitability assessment for this specific app.

    - name: "security-merge"
      role: kiro_default
      depends_on: ["secrets-scan", "auth-bypass", "injection", "boundary-inputs", "dependency-audit"]
      prompt_template: |
        Merge all security specialist findings. For each:
        - Assign severity: CRITICAL / HIGH / MEDIUM / LOW
        - Assign confidence: 1-10 (is this definitely exploitable?)
        - Only findings with confidence >= 7 are blocking
        Output the final security verdict with all findings ranked.
```

This gives you 5 security specialists running in parallel — matching the depth of gstack's 14-phase CSO audit.

### Step 4: Cross-reference with Edge Cases

Check whether the edge cases from specship-testgen are handled:
- Does the implementation defend against each listed edge case?

### Step 5: Output Verdict

```markdown
## Security Review Verdict

**Contract:** <id> — <title>
**Status:** PASS | FAIL

### Findings
| # | Severity | Confidence | Category | Description | File:Line |
|---|----------|-----------|----------|-------------|-----------|
| 1 | CRITICAL/HIGH/MEDIUM | N/10 | <category> | <description> | <location> |

### Edge Case Coverage
| Edge Case | Handled? | How |
|-----------|----------|-----|
| <from edge-cases.md> | YES/NO | <explanation> |

### Blocking Issues (CRITICAL + HIGH)
- [issues that must be fixed]

### Advisory (MEDIUM, non-blocking)
- [issues to be aware of]
```

### Required machine-readable verdict (MUST be the last thing in your response)

End with a fenced ```json block of EXACTLY this shape (the aggregator parses this, not the prose above):

```json
{
  "validator": "security",
  "status": "PASS | FAIL | INCOMPLETE",
  "evidence": [
    { "claim": "checked SQL injection on new endpoints", "artifact": "src/server/routes/x.ts:42" }
  ],
  "blocking_issues": [
    { "summary": "negative amount bypasses validation", "file": "src/server/services/split.ts", "line": 88, "expected": "reject amount <= 0 with 400", "actual": "accepts negative, manipulates balance" }
  ]
}
```

Rules: `status: "PASS"` is INVALID if `evidence[]` is empty. If you could not run (e.g. gstack and the diff both unavailable), use `INCOMPLETE` — never PASS. `blocking_issues` is empty for PASS, non-empty for FAIL. Include a `"confidence": N` (1-10) on each blocking issue so the aggregator can route low-confidence findings through refutation.

## Decision Rules

- ANY finding with severity CRITICAL or HIGH → FAIL
- Only MEDIUM findings → PASS (with advisory notes)
- No findings → PASS
- Confidence gate: only report findings with confidence >= 7/10

## Recording the Verdict

Persist the verdict block to `.specship/artifacts/verdicts/security.json` and record the run in the conceptual trace at `.specship/artifacts/traces/current.jsonl` (start event at the beginning, complete event at the end, with the status derived from the verdict's `status` field — never hand-typed). If the browser tool is missing, install Playwright MCP via `.kiro/settings/mcp.json`.
