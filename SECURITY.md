# Security

SpecShip is a set of **steering/instruction files** for an AI coding agent plus a
shell installer. It ships no runtime service and stores no credentials. Its real
attack surface is **supply chain** (the third-party companions it installs) and
**local privilege / trust boundaries** (the steering files control what the agent
does to your source code). This document describes the controls that are in place
and the residual risks you own.

A machine-readable map of each threat → the control that now addresses it lives in
[`THREAT-MODEL-REMEDIATION.md`](THREAT-MODEL-REMEDIATION.md).

## Reporting an issue

Please report security concerns **privately** via GitHub's [Private Vulnerability
Reporting](https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing-information-about-vulnerabilities/privately-reporting-a-security-vulnerability)
(this repository's **Security** tab → **Report a vulnerability**). Do not open a
public issue or post details in a shared channel until the report has been triaged.

## Trust model (read this first)

The AI agent runs with **your** privileges and has full read/write/commit
authority over the project you point it at. There is no separate agent identity
and no sandbox around the agent itself. That means:

- **Whoever controls the steering files controls what the agent does to your code.**
  Steering-file integrity is the single most important security property of the
  system — treat `~/.kiro/steering/` with the same care as a deployment script.
- **The companions run with your privileges too.** Installing them is granting
  arbitrary local code execution to their maintainers. Pin and review accordingly.
- **Generated code is sample/reference implementation.** The validators reduce, but
  do not eliminate, the need for human + AppSec review before running it anywhere
  sensitive.

## Controls in place

### Supply chain — companion clones (`install.sh`)
`install.sh` clones two third-party skill sets — `github.com/obra/superpowers` and
`github.com/garrytan/gstack` — and (unless you opt out) runs gstack's `./setup`.
The installer gives you three levels of assurance:

- **Pin + verify by content hash (strongest).** Set `SPECSHIP_SUPERPOWERS_REF` /
  `SPECSHIP_GSTACK_REF` to a **full 40-character commit SHA**. The installer checks
  the clone out at that exact commit and **aborts (fails closed) if the checked-out
  HEAD doesn't match** — this defeats both a compromised upstream branch and a
  network MITM that redirects the clone.
- **Pin by name.** Set the same vars to a branch or tag. Pins to a moving name, not
  a content hash — weaker, but reproducible.
- **Unpinned (default).** Clones upstream `HEAD`, prints the resolved SHA, and warns
  loudly. Convenient for a throwaway machine; re-run pinned for anything you keep.

Every clone is recorded with its resolved SHA and pinned/unpinned status in
`~/.kiro/skills/.specship-provenance.txt` (an audit trail).

- **Review before execute (default).** Executing gstack's `./setup` is the single
  highest-privilege step in the whole install, so the installer is **review-first by
  default**: it will **not** run `./setup` unless you explicitly opt in — via
  `--run-setup`, `SPECSHIP_RUN_SETUP=1`, or answering "yes" at the interactive prompt
  (which defaults to **No**). A piped / non-interactive install never runs it. Use
  `--review-only` (or `SPECSHIP_CLONE_ONLY=1`) to also skip the prompt entirely. Either
  way, the default is: clone, then let you inspect the code and run `./setup` yourself.
- **Transport.** HTTPS by default (TLS cert verification). `--install.sh --ssh`
  (or `SPECSHIP_GIT_SCHEME=ssh`) clones over SSH so your known-hosts host-key
  verification applies. On an untrusted network, prefer a **trusted VPN** and/or a
  pinned SHA (which is verified regardless of transport).

### Integrity monitoring (`specship-verify.sh`)
At install time the installer writes `~/.kiro/steering/.specship-manifest.sha256`
— a SHA-256 of every SpecShip steering file and companion `SKILL.md`. Run
`./specship-verify.sh` any time to re-hash those files and detect tampering,
missing files, or permission drift, and to print the clone provenance log.

> **Honest limitation:** this is integrity **detection**, not a cryptographic root
> of trust. The manifest sits next to the files it protects, so an attacker who can
> rewrite a steering file can usually also rewrite the manifest. It defeats
> accidental corruption and unsophisticated tampering and gives you an auditable
> baseline — it is **not** code signing. For a real root of trust, keep
> `~/.kiro/steering/` under version control on a trusted host, or apply OS-level
> file protection (e.g. a read-only mount, macOS SIP-style protection, or an EDR
> file-integrity monitor).

### Restrictive file permissions
The installer runs under `umask 077` and applies `chmod 700` to
`~/.kiro/steering/`, `~/.kiro/skills/`, `~/.kiro/settings/`, and any project
`.kiro/hooks/` it writes, and `chmod 600` to `mcp.json`, the manifest, and the
provenance log. This blocks other local users/processes from silently injecting
steering instructions, hooks, or MCP entries. (These are best-effort — they can't
protect against a process running as your own user or as root.)

### Agent hooks — disabled by default
Hooks can run shell commands on IDE events (file save, tool use), which is a
persistent-execution risk. All three shipped hooks have `"enabled": false` and must
be turned on deliberately in Kiro's Agent Hooks panel. Keep that a hard requirement.

### SCM boundary — no unauthorized push
SpecShip's SHIP phase **prepares and proposes**; it does not publish on its own.
Guardrail rules 17 enforce: never `git push` / merge without an explicit in-session
human "yes" for that specific action, never push to or merge `main`/`master`, never
force-push. Autonomous mode's walk-away deliverable is a **PR**, not a merge. This
prevents a poisoned steering/skill file from committing a subtle backdoor under your
git identity and shipping it unattended.

### Network egress — no context leaks
The PLAN phase does real web searches for market research; the browser/MCP
validators make outbound requests. Guardrail rule 18 enforces egress discipline:
research queries describe the product **category**, never this codebase — no source,
file paths, internal identifiers, hostnames, customer names, or `.env` contents in
any outbound request. Secrets never leave the machine.

### MCP servers — integrity-locked install + isolated browser profile
Installing enables two MCP servers (`@playwright/mcp@0.0.75`,
`chrome-devtools-mcp@1.1.1`) for browser and Lighthouse validation. Two controls
are applied by default:

- **Integrity-locked install (T3).** When `npm` is available the installer runs
  `npm ci --ignore-scripts` against a **committed lockfile with SHA-512 integrity
  hashes** (`settings/mcp/package-lock.json`) into `~/.kiro/settings/mcp-servers/`,
  then points `mcp.json` at those verified local binaries. `npm ci` recomputes each
  package's hash and **aborts (EINTEGRITY) if it doesn't match the lock**, so a package
  tampered at the registry cannot be installed — and `--ignore-scripts` blocks
  install-time code execution (both packages ship prebuilt). If `npm` is unavailable
  the installer falls back to a pinned `npx` config (versions pinned, but `npx`
  re-resolves from the registry without a lockfile integrity check — the T3 residual).
  To bump versions, regenerate the lockfile: `cd settings/mcp && npm install
  <pkg>@<version> --package-lock-only`, review the new hashes, commit.
- **Isolated browser profile (T12).** Both servers are launched with `--isolated`,
  which uses a throwaway in-memory / temporary browser profile that is cleared when the
  browser closes — so a compromised MCP server **cannot read your real Chrome profile's
  cookies, sessions, or logins**. This is the default in both the locked and the npx
  fallback configs.

### No secrets in the repo
Do not commit `.env`, tokens, or credentials. `.gitignore` excludes `.env*` (except
`.env.example`), and the PLAN bootstrap adds the same rules to the target project.

## Residual risks you own

These are known gaps that the tooling cannot fully close for you. Decide how much
they matter for your environment.

### MCP servers still run with your OS privileges
The `--isolated` profile (default) stops a compromised MCP server from reading your
**real** browser profile, and the integrity-locked install stops a **tampered
package** from being installed. But the server process itself still runs as **your OS
user** with network access — so process-level isolation remains environmental and is
not something a markdown-skills + installer Power can force. For defense in depth
beyond the isolated profile:

- **Run Kiro (and thus the MCP servers) in a container or VM** dedicated to
  development, so a compromise can't reach your real browser profile or corp network.
- **Filesystem/network confinement on Linux:** wrap the `npx` command with `firejail`
  (`firejail --net=none --private=...`) or a systemd unit with `ProtectHome`,
  `PrivateNetwork`, and a restricted `ReadWritePaths`. On macOS, run inside a
  Linux container/VM (native `sandbox-exec` is deprecated).
- **Use a throwaway browser profile** for automation — never the profile that holds
  your real logins/cookies.
- **Disable the MCP servers when you're not validating a UI** (`"disabled": true` in
  `mcp.json`), so they aren't running during unrelated work.

### npm supply chain for the MCP servers
The default install is now integrity-locked (`npm ci` against the committed
`settings/mcp/package-lock.json` with SHA-512 hashes), which closes the "pinned
version tampered at the registry" gap — a bad tarball fails `EINTEGRITY` and nothing
installs. Residual only applies if you fall back to the `npx` path (no `npm`
available) or bump versions. For the strictest posture:

- Keep the locked install (don't delete `~/.kiro/settings/mcp-servers/`); regenerate
  the lockfile deliberately when bumping, and review the new integrity hashes in the
  diff before committing.
- Consider a private/proxied registry (Verdaccio, CodeArtifact, Artifactory) with an
  allowlist, and `npm config set audit true`.
- Audit periodically: `npm audit`, `npm view <pkg>@<version> dist.integrity`.

### The agent-to-project boundary has no access control
By design, the agent can read/modify/commit anything in the project. Mitigate with:
work in a dedicated branch, keep the repo under version control so every agent
change is a reviewable diff, and read the diff before you push (guardrail rule 17
keeps publishing a human decision).

## Quick hardening checklist

- [ ] Pin `SPECSHIP_SUPERPOWERS_REF` / `SPECSHIP_GSTACK_REF` to reviewed commit SHAs.
- [ ] Review gstack's `./setup` before opting in (`--run-setup`) — it does NOT run by default.
- [ ] Keep the integrity-locked MCP install (don't fall back to `npx`); `--isolated` stays on by default.
- [ ] Run `./specship-verify.sh` after install and periodically (or wire it into a pre-run hook).
- [ ] Keep `~/.kiro/steering/` under version control on a trusted host for a real integrity baseline.
- [ ] For defense in depth, run Kiro + MCP servers in a container/VM; disable MCP when not validating UI.
- [ ] Never let the agent push/merge without reviewing the diff; never to `main`/`master`.
- [ ] On untrusted networks, use a trusted VPN and/or `--ssh` with pinned SHAs.

## Scope

These files instruct an autonomous agent to write, test, and validate code. Review
generated code before running it in any sensitive environment — the workflow's
validators reduce, but do not eliminate, the need for human review. SpecShip itself
has not undergone external security review and is provided as-is, with no warranty;
review it before use in any sensitive environment.
