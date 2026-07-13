---
inclusion: auto
name: specship-ship
description: Use after validation passes to ship — create the PR, update the changelog, and archive the contract. Triggered by "ship it", "create pr", "it passed validation", "specship ship".
---

# specship-ship — Ship to Production

Trigger: "ship it", "create pr", "specship ship".

You are the final step in the SpecShip pipeline. After validation passes, you create the PR, update documentation, and archive the contract.

Suggested model: Sonnet for the mechanical steps; Opus if you have to compose nuanced PR narrative.

## Pre-condition

The aggregate verdict must be MERGE. If not:

> "Cannot ship — aggregate verdict is not MERGE. Run validation first."

STOP.

### Deterministic process gate (run BEFORE Step 1 — no exceptions)

A MERGE verdict is necessary but not sufficient. Run the deterministic process checker as the final mechanical gate that the whole pipeline actually completed — all tasks done, every expected validator produced a verdict, none SKIPPED, none carrying blocking issues, and the plan artifacts present. This catches the case where an optimistic aggregate slipped through.

Locate and run it from the project root:

```bash
CHECKER=$(find ~/.kiro -name process-checker.js 2>/dev/null | head -1)
[ -z "$CHECKER" ] && CHECKER=$(find . -name process-checker.js 2>/dev/null | head -1)
if [ -n "$CHECKER" ]; then
  node "$CHECKER" --phase ship; echo "process-checker exit: $?"
else
  echo "process-checker.js not found — verify .specship artifacts manually before shipping"
fi
```

- **Exit 0 (PASS):** proceed to Step 1.
- **Exit 1 (FAIL):** **STOP — do not create the PR.** The script prints exactly what is missing. Route by cause: incomplete tasks → back to BUILD; a missing or SKIPPED validator verdict → back to VALIDATE for that validator; a blocking issue → RECOVER. Shipping with a failing process check is a protocol violation — the gate exists so a half-finished mission never reaches a PR.

## Process

### Step 1: Verify Branch State

- Ensure you are NOT on `main` / `master`. Use `git branch --show-current`; if it returns `main` or `master`, that is an error — you cannot ship from the trunk. Stop and branch first.
- Ensure a clean working tree. `git status --porcelain` should be empty. If there are uncommitted changes, surface them as a WARNING before continuing.
- **Check for git remote:** Run `git remote -v`. If no remote exists, note this early — the PR will be "prepared locally" with push instructions in the report. Do NOT block the ship process for a missing remote; complete all local steps (changelog, archive, CI sim) and include push instructions at the end.

### Step 2: Generate PR Content from Contract

Read the sprint contract. Generate:

**PR Title:** `[specship] <contract title>` (max 70 chars)

**PR Body:**
```markdown
## Summary

<1-3 bullet points from contract's Goal section>

## Sprint Contract

- Contract ID: <id>
- Acceptance Criteria: <count> (all PASS)
- Failure Modes: <count> (all GUARDED)
- Validation: Code ✓ | Security ✓ | Browser ✓/skipped | Alignment ✓

## Test Plan

- [ ] Pre-generated test cases verified by alignment validator
- [ ] Edge cases from contract covered
- [ ] No scope drift detected by code reviewer

## Changes

<files changed summary from git diff --stat>

---
Generated with the SpecShip workflow.
```

### Step 3: Update CHANGELOG (if exists)

If a `CHANGELOG.md` exists in the repo, update it. Prepend an entry:

```markdown
## [Unreleased]

### Added
- <from contract goal — what was built>
```

### Step 4: Archive Contract

Move the completed contract and its artifact directory out of the active contracts area into a `completed/` area (create it if needed), then commit the move:

- Create `.specship/completed/` if it does not exist.
- Move the spec directory `.specship/specs/<id>-<slug>/` → `.specship/completed/<id>-<slug>/`.
- `git add .specship/` and `git commit -m "[specship] archive spec <id> (validated + shipped)"`.

### Step 4.5: Verify CI-Readiness

Before pushing, check whether the project has CI. Look for `.github/workflows` (GitHub Actions) or `.gitlab-ci.yml` (GitLab CI).

If CI exists:
- Run the same commands CI would run LOCALLY (tests, lint, type-check, build).
- If the local CI simulation fails: FIX before pushing (don't create a red PR).
- Include in PR body: "Local CI simulation: PASS".

If no CI and this is an enterprise/production project:
- Flag in the ship report: "No CI detected. Recommended: add test workflow before merging to main."

### Step 5: Push and Create PR

**SCM boundary (guardrail rule 17 — enforce here, no exceptions):** pushing uses the developer's credentials, so it is gated on an explicit human "yes". Before any `git push`:

- Confirm you are on a **feature branch** (never `main`/`master` or a shared/protected branch — Step 1 already checked this; re-confirm).
- **Ask for confirmation of the push specifically**, showing exactly what will be published:
  > "Ready to push `<branch>` (<N commits>, <M files>) to `<remote>` and open a PR. Push now? [y/N]"
  In **guided mode**, wait for an explicit "y". In **autonomous mode**, autonomy skips *approval gates* but NOT this SCM boundary — so autonomous runs stop here too: prepare everything locally and hand the developer a one-command push, rather than pushing unattended. (If the user has explicitly pre-authorized autonomous push for this session, honor that — but never invent that authorization.)
- **NEVER** `git push --force`, and **NEVER** push directly to or merge `main`/`master`. Merging the PR is always the human's decision.

On an explicit "yes", push the current branch upstream (`git push -u origin <current branch>`), then create the PR with the `gh` CLI:

```bash
gh pr create --title "<title>" --body "<body>"
```

If confirmation is withheld, `gh` is unavailable, or there is no remote: output the PR content and the push instructions (Step 6 report) and let the user push/create it manually (Kiro's git integration can also open the PR). This is a normal, successful outcome — a prepared PR is the deliverable; publishing is the human's call.

### Step 6: Report

```markdown
## Ship Report

**Contract:** <id> — <title>
**PR:** <URL or "create manually — see push instructions below">
**Status:** SHIPPED
**Total time:** <elapsed from mission start to ship>

### Pipeline Summary
| Phase | Duration | Key output |
|-------|----------|------------|
| PLAN | <time> | contract + <N> test cases + <M>-milestone plan |
| BUILD | <time> | <N> milestones, <T> tests passing |
| VALIDATE | <time> | <V> validators PASS |
| RECOVER | <time or "none needed"> | <N> bugs fixed |
| SHIP | <time> | PR prepared |

### Bugs Caught & Fixed (the value of the pipeline)
| Bug | Found by | Phase | Fix |
|-----|----------|-------|-----|
| <description> | <which validator/gate> | <BUILD/VALIDATE> | <what was done> |

### Milestone Breakdown
| # | Name | Tasks | Tests added | Time |
|---|------|-------|-------------|------|
| 1 | Scaffold | <N> | <N> | <time> |
| 2 | ... | ... | ... | ... |

### Evidence
- Tests: <count> passing (<framework>)
- Screenshots: <count> browser proofs
- Verdicts: .specship/artifacts/verdicts/

### Branch & PR
- Branch: <branch name>
- Commits: <count>
- Files changed: <count>
- Contract: archived to .specship/completed/

To push (if no remote configured):
  git remote add origin <your-repo-url>
  git push -u origin <branch>
  gh pr create --title "[specship] <title>" --body-file .specship/completed/<id>-PR.md

### Next Mission
Ready for the next "Using SpecShip, ..." command.
```
