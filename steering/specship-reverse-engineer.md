---
inclusion: auto
name: specship-reverse-engineer
description: Use before planning brownfield work against an existing codebase: reverse engineer repository structure, technology stack, business flows, APIs, data models, conventions, tests, and change impact. Triggered by "reverse engineer", "brownfield", "existing codebase", "understand this repo", "add to existing app", "refactor", "migration".
---

# specship-reverse-engineer - Brownfield Reconnaissance

Trigger: "reverse engineer this codebase", "brownfield", "existing app", "add a feature to this repo", "refactor", "migration", "understand the current system".

You are running SpecShip's **read-only brownfield reconnaissance** phase. This happens before the sprint contract for any existing codebase where the implementation must preserve current behavior, follow local conventions, or avoid breaking production workflows.

This skill is inspired by AI-DLC v2's reverse-engineering stage, but it is SpecShip-native:
- Artifacts live under `.specship/`.
- The output feeds SpecShip's `requirements.md`, `design.md`, `tasks.md`, testgen, build, validators, and recovery.
- The analysis is tactical. It exists to make the next change safe to ship, not to produce an academic system inventory.

## Non-Negotiables

1. **Read-only.** Do not edit source code, config, tests, generated files, lockfiles, migrations, or docs while reverse engineering. If a command wants to write, do not run it.
2. **No hallucinated architecture.** Every component, route, entity, event, convention, and test claim must cite a real file path or command output.
3. **Scope first.** Reverse engineer the parts relevant to the intent. Do not spend hours cataloguing unrelated subsystems unless the change crosses them.
4. **Baseline before change.** Identify the existing test/build commands and run safe read-only checks when possible. Record failures as baseline facts, not as new bugs caused by SpecShip.
5. **Preserve behavior.** Capture current user-visible behavior and compatibility constraints before creating new acceptance criteria.
6. **Contract handoff.** End with a brownfield contract input file that the planning phase can directly consume.

## When To Use

Use this skill before `specship-plan` or during `specship-plan` Step 0.5 when:
- The request modifies an existing app, service, CLI, workflow, or infrastructure repo.
- The user says "refactor", "migration", "bug fix", "add to this codebase", "existing", "legacy", or "brownfield".
- The repository has established conventions that new work must follow.
- The feature touches frontend/backend integration, persistence, auth, events, or external systems.
- The change spans multiple packages or repos.

Skip or keep very short when:
- The task is truly trivial and localized, e.g. typo, one-line copy change, or obvious null check.
- A fresh, current reverse-engineering artifact already exists for the affected area.
- The user explicitly asks to skip reconnaissance and accepts the risk.

## Output Location

Prefer a mission-scoped location when a SpecShip spec exists:

```text
.specship/specs/<ID>-<slug>/artifacts/reverse-engineering/
```

If no mission/spec exists yet, create a standalone reconnaissance package:

```text
.specship/reverse-engineering/<YYYYMMDD>-<repo-slug>/
```

When `specship-plan` later creates the mission directory, copy or reference the standalone package from:

```text
.specship/specs/<ID>-<slug>/artifacts/reverse-engineering/source.txt
```

Never write reverse-engineering artifacts to `docs/`, `.kiro/specs/`, or the project root.

## Adaptive Depth

Pick the smallest artifact set that makes the change safe. Brownfield recon is a safety phase, not paperwork.

| Mode | Use When | Required Files |
|---|---|---|
| Tiny | Typo, one-file bug fix, obvious localized helper, or under 50 files with a narrow target | `brownfield-contract-inputs.md`, `change-impact-map.md`, `test-baseline.md`, `preserved-behaviors.md` |
| Focused | Existing-app feature/refactor touching one package, route, service, or workflow | Tiny files plus the applicable domain files only: APIs, data models, UI patterns, dependencies, quality assessment |
| Full | Multi-package, persistence/auth/API/event changes, migration, dependency upgrade, unclear ownership, or 200+ files | Full artifact set below, chunked by business flow or package |

If you select Tiny or Focused mode, state the mode and why in `brownfield-contract-inputs.md`. Do not create 18 empty inventory files for a tiny change just to satisfy a checklist.

## Process

### Step 1: Classify Scope

Capture:
- User intent and desired change.
- Repo(s) in scope.
- Branch and git status.
- Areas likely affected.
- Whether this is a bug fix, feature addition, refactor, migration, integration change, or dependency upgrade.
- Whether existing reverse-engineering artifacts can be reused.

If scope is unclear, ask one question:
> "Which existing flow or area should I reverse engineer first?"

After choosing the recon output directory, record the pre-recon dirty state so validation can distinguish user changes from recon mistakes:

```bash
mkdir -p "$RECON_DIR"
git status --short --untracked-files=all \
  | awk 'substr($0, 4, 10) != ".specship/" && substr($0, 4) != ".specship" { print }' \
  > "$RECON_DIR/status-before.txt"
```

### Step 2: Inventory The Repo

Run fast, read-only discovery:

```bash
git status --short --branch
git remote -v
# File inventory — prefer ripgrep, but fall back so this works without rg installed
# (rg is NOT present by default on macOS). git ls-files covers tracked files;
# find covers untracked/non-git trees.
if command -v rg >/dev/null 2>&1; then
  rg --files
elif git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git ls-files
else
  find . -type f -not -path '*/node_modules/*' -not -path '*/.git/*'
fi
find . -maxdepth 3 -type f \( -name 'package.json' -o -name 'pyproject.toml' -o -name 'go.mod' -o -name 'pom.xml' -o -name 'build.gradle' -o -name 'Cargo.toml' -o -name 'requirements.txt' -o -name 'Dockerfile' -o -name 'docker-compose*.yml' \)
```

Then inspect only relevant manifests, routes, entrypoints, tests, schemas, and config. Prefer `rg` for content search when it is installed; otherwise `git grep` / `grep -rn` are fine — do not block recon on a missing tool.

### Step 3: Establish Baseline

Determine safe baseline commands from the repo itself:
- Install command, if dependencies are already present or install is explicitly safe.
- Typecheck/lint/test/build commands.
- App start command and health/browser flow, if applicable.

Run baseline checks only when they are safe and bounded. Record:
- Command.
- Exit code.
- Important output.
- Whether failure is pre-existing.
- Whether the failure blocks the requested work.

Do not "fix" baseline failures during reverse engineering.

### Step 4: Chunk The Analysis

Do not analyze a large repo in one accumulating pass.

| Codebase size | Chunking |
|---|---|
| Small, under 50 files | Single pass is acceptable |
| Medium, 50-200 files | One chunk per major package, bounded context, or app layer |
| Large, 200+ files | One chunk per business flow relevant to the requested change |
| Multi-repo | One reconnaissance package per repo, plus a cross-repo impact map |

For medium/large repos, write `chunks/<chunk-name>.md` first, then assemble the unified artifacts. Independent chunks may run in parallel subagents if the surface supports it.

### Step 5: Produce Recon Artifacts

Write the files required by the selected adaptive-depth mode. In Full mode, write the following files when applicable. If a Full-mode file is not applicable, create it with a one-line `Not applicable` note and the reason.

```text
repo-map.md
technology-stack.md
code-structure.md
component-inventory.md
component-dependencies.md
business-flows.md
api-contracts.md
data-models.md
event-catalog.md
external-dependencies.md
cross-cutting-concerns.md
ui-patterns.md
test-baseline.md
code-quality-assessment.md
change-impact-map.md
preserved-behaviors.md
brownfield-contract-inputs.md
open-questions.md
chunks/<chunk-name>.md
```

Artifact expectations:

- **repo-map.md** - top-level structure, entrypoints, packages, deployment shape.
- **technology-stack.md** - actual languages, frameworks, versions, package managers, build tools, runtime services from manifests and lockfiles.
- **code-structure.md** - naming conventions, module boundaries, where files of each kind live.
- **component-inventory.md** - components/services/modules with purpose, owner files, public interfaces.
- **component-dependencies.md** - dependency table and call/event/data flow between components.
- **business-flows.md** - current user/system flows relevant to the requested change.
- **api-contracts.md** - existing HTTP/RPC/GraphQL contracts, exact request/response shapes, error format.
- **data-models.md** - entities, tables, schemas, migrations, relationships, ownership.
- **event-catalog.md** - async events, WebSocket messages, queues, pub/sub topics, payload shapes.
- **external-dependencies.md** - third-party services, AWS resources, env vars, secrets references, network calls.
- **cross-cutting-concerns.md** - auth, validation, error handling, logging, observability, caching, rate limiting, feature flags.
- **ui-patterns.md** - design system, component library, routing, state management, existing screens, responsive behavior.
- **test-baseline.md** - discovered test frameworks, baseline command results, coverage signals, missing regression areas.
- **code-quality-assessment.md** - risky files, large files, duplication, missing tests, unclear ownership, tech debt that affects the requested change.
- **change-impact-map.md** - files likely to change, files that must not change, downstream effects, migration/backcompat risks.
- **preserved-behaviors.md** - existing behaviors that must remain unchanged, including edge cases and compatibility constraints.
- **brownfield-contract-inputs.md** - concise handoff into `specship-contract` and `specship-testgen`.
- **open-questions.md** - only questions that materially affect safe implementation.

### Step 6: Brownfield Contract Handoff

`brownfield-contract-inputs.md` is the most important output. It must contain:

```markdown
# Brownfield Contract Inputs

## Scope Classification
- Type: bugfix | feature-addition | refactor | migration | dependency-upgrade | integration-change
- Repo(s):
- Affected components:

## Existing Behavior To Preserve
1. When ..., the current system ...

## New Or Changed Behavior
1. When ..., the changed system should ...

## Regression Tests To Generate
1. Existing behavior regression:
2. New behavior test:
3. Integration/API shape test:

## Files Likely To Change
| File | Why | Risk | Required tests |
|---|---|---|---|

## Files To Avoid Touching
| File/Area | Reason |
|---|---|

## Local Conventions Workers Must Follow
- ...

## Baseline Commands
| Command | Current result | Notes |
|---|---|---|

## Open Questions Blocking Contract
- ...
```

`specship-contract` must use this file when creating brownfield acceptance criteria and failure modes. `specship-testgen` must generate preserved-behavior regression tests from it before build starts.

### Step 7: Deterministic Recon Validation

Before handoff, run a bounded validation check against the recon directory. Set `RECON_DIR` to the mission-scoped or standalone reverse-engineering directory:

```bash
test -n "$RECON_DIR" || { echo "RECON_DIR is required"; exit 1; }

required="brownfield-contract-inputs.md change-impact-map.md test-baseline.md preserved-behaviors.md"
for f in $required; do
  test -s "$RECON_DIR/$f" || { echo "missing or empty: $RECON_DIR/$f"; exit 1; }
done

git status --short --untracked-files=all \
  | awk 'substr($0, 4, 10) != ".specship/" && substr($0, 4) != ".specship" { print }' \
  > /tmp/specship-recon-status-current.txt
if test -f "$RECON_DIR/status-before.txt"; then
  diff -u "$RECON_DIR/status-before.txt" /tmp/specship-recon-status-current.txt >/tmp/specship-recon-status-diff.txt \
    || { echo "non-.specship working-tree state changed during recon:"; cat /tmp/specship-recon-status-diff.txt; exit 1; }
else
  test ! -s /tmp/specship-recon-status-current.txt \
    || { echo "non-.specship changes exist and no status-before.txt baseline was recorded:"; cat /tmp/specship-recon-status-current.txt; exit 1; }
fi

rg -n '(/|\\.)[A-Za-z0-9._/-]+|`[^`]+`' "$RECON_DIR" >/tmp/specship-recon-evidence.txt 2>/dev/null \
  || grep -rnE '(/|\.)[A-Za-z0-9._/-]+|`[^`]+`' "$RECON_DIR" >/tmp/specship-recon-evidence.txt 2>/dev/null \
  || true
test -s /tmp/specship-recon-evidence.txt || { echo "no obvious file/command evidence citations found"; exit 1; }

echo "SpecShip recon validation passed: $RECON_DIR"
```

### Step 8: Record Recon Location (so planning can discover it across sessions)

So a later `specship-plan` session reliably reuses this recon instead of re-running it, record the handoff path. The filesystem glob in `specship-plan` Step 0.5 is the primary discovery mechanism; this state.json marker is the durable secondary signal that survives into `specship-resume`.

If a `.specship/state.json` already exists, update its `recon_artifact_path` using an atomic write (temp → validate JSON → rename), without disturbing other fields:

```bash
STATE=".specship/state.json"
HANDOFF="$RECON_DIR/brownfield-contract-inputs.md"
if [ -f "$STATE" ] && command -v node >/dev/null 2>&1; then
  node -e '
    const fs=require("fs"); const p=process.argv[1], v=process.argv[2];
    const s=JSON.parse(fs.readFileSync(p,"utf8"));
    s.recon_artifact_path=v; s.updated_at=new Date().toISOString();
    const tmp=p+".tmp"; fs.writeFileSync(tmp, JSON.stringify(s,null,2));
    JSON.parse(fs.readFileSync(tmp,"utf8"));        // validate
    fs.copyFileSync(p, p+".bak"); fs.renameSync(tmp, p);
  ' "$STATE" "$HANDOFF" && echo "recorded recon_artifact_path → $HANDOFF"
else
  echo "no state.json yet — planning will discover this recon via the Step 0.5 filesystem glob"
fi
```

If no `state.json` exists (recon ran standalone before any mission), do not fabricate one — print the handoff path clearly so the next phase can pick it up, and rely on the plan-side glob.

## Validation Checklist

Before declaring reverse engineering complete:

- [ ] All artifacts are under `.specship/`.
- [ ] No source/config/test/code files were modified.
- [ ] Every architectural claim cites a real file path or command.
- [ ] Technology versions come from manifests/lockfiles, not guesses.
- [ ] Existing APIs/events/data models include exact shapes where discoverable.
- [ ] Baseline commands and current failures are recorded.
- [ ] `change-impact-map.md` names the files likely to change.
- [ ] `preserved-behaviors.md` names current behavior that must not regress.
- [ ] `brownfield-contract-inputs.md` is concrete enough for contract/test generation.
- [ ] The deterministic recon validation command passed, or any failure is recorded as a blocker.
- [ ] Recon location recorded in `state.json` (`recon_artifact_path`) when a mission state exists.

## Hand-Off

After completion:

- For planning: continue to `specship-plan`, but inject `brownfield-contract-inputs.md` into brainstorming, contract, testgen, and implementation planning.
- For direct contract generation: continue to `specship-contract` and tell it this is a brownfield mission.
- For tiny fixes: produce a short contract directly from `brownfield-contract-inputs.md`, then run `specship-testgen` for regression tests.

## Key Principle

Greenfield asks "what should we build?"

Brownfield asks "what exists, what must not break, and where is the safe place to cut?"

Answer that before writing the contract.
