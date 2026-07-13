# SpecShip Threat Model — Remediation Record

**Source:** `THREAT-MODEL-REPORT.pdf` (STRIDE, 12 threats T1–T12, 12 mitigations M1–M12)
**Scope:** SpecShip Kiro Power — steering files + shell installer (no runtime service).
**This document maps every threat to the concrete control now in the codebase**, so the
next threat-modeling pass finds each risk *addressed* rather than *open*.

## How to verify (living evidence)

```bash
# 1. Static: both scripts parse cleanly
bash -n install.sh && bash -n specship-verify.sh

# 2. Dynamic: install into a throwaway root, then prove integrity monitoring works.
#    (HOME override keeps ~/.kiro reads/writes inside the sandbox; answer n / N at the prompts.)
printf 'n\nN\n' | SPECSHIP_SKIP_PREREQ=1 HOME=/tmp/ss-demo ./install.sh /tmp/ss-demo/.kiro/steering
HOME=/tmp/ss-demo ./specship-verify.sh /tmp/ss-demo/.kiro/steering    # -> PASS (exit 0)

# a) modified file is detected
echo "tamper" >> /tmp/ss-demo/.kiro/steering/specship-guardrails.md
HOME=/tmp/ss-demo ./specship-verify.sh /tmp/ss-demo/.kiro/steering    # -> INTEGRITY FAILURE (exit 1)

# b) injected always-on file (no manifest entry) is detected  [the T4 blind spot]
echo "malicious" > /tmp/ss-demo/.kiro/steering/zz-inject.md
HOME=/tmp/ss-demo ./specship-verify.sh /tmp/ss-demo/.kiro/steering    # -> UNEXPECTED file (exit 1)

# c) empty/corrupt manifest fails closed (no false green PASS)
: > /tmp/ss-demo/.kiro/steering/.specship-manifest.sha256
HOME=/tmp/ss-demo ./specship-verify.sh /tmp/ss-demo/.kiro/steering    # -> cannot attest (exit 2)

rm -rf /tmp/ss-demo
```

## Mitigation status summary

| # | Mitigation | Report status → Now | Where |
|---|------------|---------------------|-------|
| M1 | Pin git refs | Partial → **Implemented** (verify-on-pin, loud unpinned warning, provenance log) | `install.sh` |
| M2 | Cryptographic verification of cloned repos | Missing → **Implemented** (SHA pin fails closed on mismatch + integrity manifest) | `install.sh`, `specship-verify.sh` |
| M3 | Separate clone from execute | Partial → **Implemented + default** (review-first: `./setup` never runs without opt-in; `--review-only` / `--run-setup`) | `install.sh` |
| M4 | NPM version pinning / integrity | Partial → **Implemented** (committed lockfile + `npm ci --ignore-scripts` fails closed on hash mismatch; pinned `npx` fallback) | `settings/mcp/package-lock.json`, `install.sh` |
| M5 | File integrity monitoring | Missing → **Implemented** (`specship-verify.sh` + manifest) | `specship-verify.sh`, `install.sh` |
| M6 | Restrictive file permissions | Missing → **Implemented** (`umask 077`, `chmod 700/600`) | `install.sh` |
| M7 | Hooks disabled by default | Resolved → **Maintained** (`"enabled": false` on all 3) | `hooks/*.kiro.hook` |
| M8 | Backup-before-overwrite | Resolved → **Maintained** (`copy_with_backup`) | `install.sh` |
| M9 | Network egress controls | Missing → **Implemented** (guardrail rule 18 + plan Step 2) + documented | `specship-guardrails.md`, `specship-plan.md`, `SECURITY.md` |
| M10 | SSH clone + host-key verification | Missing → **Implemented** (`--ssh` / `SPECSHIP_GIT_SCHEME`) + VPN guidance | `install.sh`, `SECURITY.md` |
| M11 | Human review before push | Partial → **Implemented** (guardrail rule 17 + ship Step 5 confirmation gate) | `specship-guardrails.md`, `specship-ship.md` |
| M12 | MCP server sandboxing | Missing → **Implemented** (default `--isolated` throwaway browser profile) + container/firejail guidance for deeper isolation | `install.sh`, `settings/mcp.json`, `SECURITY.md` |

## Threat-by-threat

### T1 — Upstream Repository Compromise (Skill Injection) · HIGH · Tampering
**Was:** no crypto verification, clones HEAD unpinned, no post-install monitoring.
**Now:**
- `install.sh` `clone_verified()`: when `SPECSHIP_*_REF` is a full 40-char SHA it checks
  the repo out at that commit and **aborts if HEAD ≠ SHA** (`rm -rf` the clone, non-zero exit).
- Unpinned clones print the resolved SHA + a loud supply-chain warning and are logged to
  `~/.kiro/skills/.specship-provenance.txt`.
- Post-install: `.specship-manifest.sha256` records each companion `SKILL.md` hash;
  `specship-verify.sh` detects any later modification.

### T2 — Gstack Setup Script Remote Code Execution · HIGH · Tampering
**Was:** `./setup` executed automatically with no review step between clone and execute.
**Now:** review-first is the **default**. `install.sh` runs `./setup` ONLY on an explicit
opt-in — `--run-setup`, `SPECSHIP_RUN_SETUP=1`, or a "yes" at the interactive prompt (default
**No**). A piped/non-interactive install NEVER runs it (verified: setup did not execute under
non-interactive stdin). `--review-only` skips the prompt entirely. The install prints
`less <setup>` and the explicit run command so the developer reviews then runs it themselves.

### T3 — Malicious NPM Package (MCP Server Compromise) · HIGH · Tampering
**Was:** versions pinned in `mcp.json`; no integrity hashes, `npx -y` auto-confirms.
**Now:** the default install is integrity-locked. `install.sh` runs `npm ci --ignore-scripts`
against a committed `settings/mcp/package-lock.json` carrying SHA-512 integrity hashes for both
pinned packages, into `~/.kiro/settings/mcp-servers/`, and points `mcp.json` at those verified
local binaries. `npm ci` recomputes each hash and **aborts (EINTEGRITY) on mismatch** — verified:
a tampered lockfile hash caused `npm ci` to fail and install nothing. `--ignore-scripts` blocks
install-time code execution (both packages ship prebuilt). `mcp.json` is `chmod 600`. Residual:
a pinned `npx` fallback (still `--isolated`) is used only when `npm` is unavailable — documented.

### T4 — Steering File Injection · HIGH · Tampering
**Was:** only OS-default permissions; no integrity monitoring or restrictive perms.
**Now:** `install.sh` sets `umask 077` and `chmod 700` on `~/.kiro/steering/` (+ `shared/`);
`specship-verify.sh` hashes every steering file into the manifest and flags tampering and
permission drift. Documented limitation: this is detection, not a root of trust (see `SECURITY.md`).

### T5 — Malicious Agent Hooks (Persistent Code Execution) · HIGH · Elevation of Privilege
**Was:** hooks disabled by default (good) but hook dir had no restrictive perms / monitoring.
**Now:** disabled-by-default maintained; `install.sh` `chmod 700`s the project `.kiro/hooks/`
dir it writes and re-states "all ship disabled" at copy time. Hook files, being under a
700 dir owned by the user, resist injection by other local processes.

### T6 — AI Agent Backdoor Injection via Poisoned Steering · MEDIUM · Tampering
**Was:** SHIP creates PRs (implies review) but no programmatic guard against auto-push.
**Now:** **Guardrail rule 17** (always-on) forbids `git push`/merge/force-push without an
explicit in-session human "yes", and forbids pushing to/merging `main`/`master`.
`specship-ship.md` Step 5 enforces a push-confirmation gate even in autonomous mode
(walk-away deliverable is a PR, not a merge). A poisoned steering file can no longer ship a
backdoor under the developer's git identity unattended.

### T7 — Git Clone Man-in-the-Middle · HIGH · Spoofing
**Was:** HTTPS only; no SSH option, no cert pinning, no post-clone checksum.
**Now:** `--ssh` / `SPECSHIP_GIT_SCHEME=ssh` clones over SSH (known-hosts host-key verification).
More importantly, a **pinned SHA is verified after clone regardless of transport** — a MITM that
redirects the clone cannot produce a repo whose HEAD matches the expected commit hash, so the
install fails closed. `SECURITY.md` recommends a trusted VPN on untrusted networks.

### T8 — Data Exfiltration via Market Research · MEDIUM · Information Disclosure
**Was:** no documentation, no egress guidance, no content filtering.
**Now:** **Guardrail rule 18** (always-on) + `specship-plan.md` Step 2 mandate that research
queries describe the product **category**, never the codebase — no source, paths, identifiers,
hostnames, customer names, or `.env` contents in any outbound request; secrets never leave the
machine; ask the user before querying anything repo-specific. Documented in `SECURITY.md`.

### T9 — Unreviewed Third-Party Code Execution During Install · MEDIUM · Elevation of Privilege
**Was:** most users answer "Y" without reviewing cloned code; no clone-only mode.
**Now:** the dangerous step (executing `./setup`) no longer happens by default — it requires an
explicit opt-in (see T2), so "just hitting Enter" clones without executing third-party code. The
prereq notice states exactly what will run and how to inspect it; the provenance log records what
was installed. The implicit "grant arbitrary execution by pressing Y" trust relationship is gone.

### T10 — Workflow Denial of Service · MEDIUM · Denial of Service
**Was:** no integrity monitoring, no schema validation for steering/hooks.
**Now:** `specship-verify.sh` detects corrupted/truncated steering files (hash mismatch) before
they can drive the agent into failure loops; the existing hard-stop rule (guardrail rule 8:
max 3 fix attempts / 5 file edits) already bounds runaway loops. Malformed-content DoS is now
**detectable pre-run**; full JSON-schema validation of hooks remains a possible future add.

### T11 — Configuration Overwrite Without Audit Trail · LOW · Repudiation
**Was:** backup-before-overwrite implemented (M8), but no record of *what* changed.
**Now:** backups maintained; additionally the clone provenance log
(`~/.kiro/skills/.specship-provenance.txt`, `chmod 600`) records each companion install with
timestamp, repo, resolved SHA, and pinned/unpinned status — an audit trail `specship-verify.sh`
prints. `.bak` copies still capture the prior steering content for diffing.

### T12 — MCP Server Browser Session Exposure · MEDIUM · Information Disclosure
**Was:** no sandboxing, no network restriction, no least-privilege applied.
**Now:** both MCP servers launch with `--isolated` by default — verified against the actual
`0.0.75`/`1.1.1` binaries: Playwright keeps the profile in memory, chrome-devtools-mcp uses a
temporary user-data-dir cleaned up on close. A compromised server therefore **cannot read the
developer's real Chrome profile cookies/sessions/logins**, which was the core of this threat.
`mcp.json` is `chmod 600`. Residual (process still runs as the OS user, network access): deeper
confinement — container/VM, `firejail --net=none`, systemd `PrivateNetwork`, disable-when-idle —
is documented in `SECURITY.md` as environmental defense in depth.

## Residual risks (accepted / environmental)

- **M3/M4/M12 are now defaults, not just options.** gstack `./setup` is opt-in (review-first
  default); MCP servers install integrity-locked via `npm ci` and run `--isolated` by default.
  The remaining residuals are narrow and environmental: the `npx` MCP fallback (only when `npm`
  is absent) lacks lockfile integrity, and MCP processes still run as the OS user (deeper
  container/firejail isolation is documented in `SECURITY.md`).
- **Integrity manifest is detection, not a root of trust** — the manifest lives beside the files
  it protects. For a real baseline, keep `~/.kiro/steering/` in version control on a trusted host
  or under OS-level file protection.
- **The agent-to-project boundary remains trust-based by design** — mitigated by branch isolation,
  version control, human diff review, and the no-auto-push guardrail rather than eliminated.
