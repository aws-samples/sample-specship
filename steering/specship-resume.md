---
inclusion: auto
name: specship-resume
description: Use to resume an interrupted SpecShip mission after a crash, timeout, or context exhaustion — "specship resume", "resume mission", "where was I", "continue mission", "pick up where I left off". Reads mission state from disk and continues from the exact phase and task where execution stopped.
---

# specship-resume — Mission Resume

Resume a SpecShip mission that was interrupted. Reads the mission state file from disk and continues from the exact phase and task where execution stopped.

Resume a SpecShip mission after a session crash, timeout, or context exhaustion. Reads mission state from disk and continues from where it left off.

This steering file is invoked manually. Reach for it when you mean any of: "specship resume", "resume mission", "where was I", "continue mission", "pick up where I left off".

## When to Use

- Session crashed or timed out mid-mission
- Context window was exhausted and a new session started
- User left and came back later
- User types "where was I?" or "continue"

## Process

### Step 1: Find Mission State

Look for the mission-state file at `.specship/state.json` (the conceptual mission-state file — the single record of where the mission stands).

If no state file exists:
> "No active mission found. Start a new one with the specship-plan steering."

STOP.

### Step 2: Read State

Read `.specship/state.json`. It follows the **canonical schema** defined in the shared `context-management.md` reference (in this Power's `steering/shared/`) — that is the single source of truth for field names. Example:

```json
{
  "mission_id": "001",
  "contract_id": "001",
  "contract_slug": "user-profile-api",
  "branch": "specship/mission-001-user-profile-api",
  "phase": "build",
  "phase_status": "in_progress",
  "started_at": "2026-05-28T10:00:00Z",
  "updated_at": "2026-05-28T10:35:00Z",
  "plan_file": ".specship/specs/001-user-profile-api/tasks.md",
  "tasks_total": 5,
  "tasks_completed": 3,
  "last_completed_task": "Task 3: Input validation",
  "next_task": "Task 4: Authorization logic",
  "milestones_total": 0,
  "milestones_completed": 0,
  "current_milestone": 0,
  "current_milestone_name": "",
  "recovery_attempts": 0,
  "validation_results": {},
  "last_commit": "abc1234",
  "handoff_notes": {
    "done": ["auth middleware", "input validation", "404 handling"],
    "next": ["email redaction logic for non-admin users"],
    "blocked": []
  }
}
```

Keep these fields and their meanings intact even if you don't insist on a particular bash writer producing them:

- `mission_id` / `contract_id` / `contract_slug` — identity of the mission and its contract.
- `branch` — the mission branch to check out before resuming.
- `phase` — which pipeline phase the mission is in (plan / build / validate / recover / escalate / ship). This drives Step 5.
- `phase_status` — e.g. `in_progress`.
- `started_at` / `updated_at` — timestamps; use `started_at` to compute elapsed time.
- `plan_file` — the plan to re-read on resume.
- `tasks_total` / `tasks_completed` — flat task progress.
- `last_completed_task` / `next_task` — the task boundary to resume across.
- `milestones_total` / `milestones_completed` / `current_milestone` / `current_milestone_name` — milestone-level progress.
- `recovery_attempts` — how many recovery rounds have run; the single source of truth shared with specship-recover.
- `validation_results` — per-validator outcomes.
- `last_commit` — the commit recorded at the last state write (used for the stale-state cross-check in Step 2.5).
- `handoff_notes` — the typed `{done, next, blocked}` bridge from the previous session.

**`milestones_completed` is an integer count** (never an array), so the milestone comparison in Step 5 is a valid numeric test.

### Step 2.5: Detect a Stale State File (cross-check against git)

`state.json` is written by an LLM that may have crashed or forgotten the final write. Before trusting its counters, cross-check against git — the objective record.

Read the recorded commit from `state.json`'s `last_commit` field and compare it against the current `HEAD` (`git rev-parse HEAD`). If the recorded commit is non-empty and differs from HEAD, that means commits happened after the last recorded state write — so `state.json` may be behind. Surface this as a warning, naming both the recorded commit and HEAD, and show the commits in between:

```bash
git log --oneline <recorded_last_commit>..HEAD | head -20
```

**If the recorded commit is behind HEAD:** the state file is likely stale. Do NOT silently trust its counters. Show the user the commits since the last recorded write (above) and the milestone trace (below), then prefer git + trace over `state.json` when they disagree.

To see what milestones actually landed, consult the build's emitted milestone trace and the git history (build records `milestone_complete` events to the mission's trace log, and commits the milestones):

```bash
git log --oneline --grep='\[specship\] milestone' | head -5
```

Also check the most recent `milestone_complete` events in the mission's trace log (e.g. `.specship/artifacts/traces/current.jsonl`) — the last few entries tell you which milestone genuinely finished.

This is a WARN-and-reconcile, not a silent override — per the "human confirms before continuing" principle below.

### Step 3: Display Status

Present a clear summary to the user:

```markdown
## Mission Resume

**Mission:** <mission_id> — <contract_slug>
**Branch:** <branch>
**Phase:** <phase> (<phase_status>)
**Progress:** <tasks_completed>/<tasks_total> tasks complete
**Last completed:** <last_completed_task>
**Next:** <next_task>
**Time elapsed:** <calculated from started_at>

### Handoff Notes
- **Done:** <handoff_notes.done — joined list>
- **Next:** <handoff_notes.next — joined list>
- **Blocked:** <handoff_notes.blocked — joined list, or "none">

### What happened
<brief explanation of where we are in the pipeline>
```

### Step 4: Confirm and Continue

**Completeness gate:** If `handoff_notes.next` is empty (the previous session crashed before recording what's next), do NOT trust the notes — re-derive the next step from git + the plan's current milestone. Look at what was actually committed:

```bash
git log --oneline --grep='\[specship\]' | head -5
```

Then present the derived next step instead of an empty one.

Ask:
> "Resume from <next_task>? Or would you prefer to:
> 1. Continue from where we left off (recommended)
> 2. Re-run the current phase from the beginning
> 3. Skip to validation (if build is close enough)
> 4. Abort and start fresh"

**Preserve autonomy across the crash.** If the mission was running autonomously (the contract/state had `autonomy: autonomous`, or it was started with "SpecShip auto" / "fully autonomous" / "end to end"), do NOT stop to ask — announce the resume point and **continue automatically** straight through the remaining phases (build → validate → recover → ship), exactly as the original autonomous run would have. The question above is only for non-autonomous (guided) missions. A crash must not silently downgrade an autonomous mission to guided.

### Step 5: Resume Execution

**First, clear stale processes from the crashed session.** A crash often leaves dev/test servers holding their ports, which makes the resumed run fail with `EADDRINUSE` (this happened on a real resume — leftover servers on 3001/5173/5174). Free the project's ports before starting anything:

```bash
# Kill listeners on the ports this project uses (adjust to your stack)
for p in 3001 5173 5174 4173; do
  pid=$(lsof -nP -tiTCP:$p -sTCP:LISTEN 2>/dev/null) && [ -n "$pid" ] && kill $pid 2>/dev/null && echo "freed :$p"
done
```

Based on the phase in state.json:

**If phase = "plan":**
- Check `planning_step` first. Valid values: `recon`, `brainstorm`, `contract`, `testgen`, `plan`, `complete`.
- If `planning_step` is `recon`, read `recon_artifact_path` and continue brownfield handoff into brainstorming/contract generation. If the path is missing, locate the newest `.specship/reverse-engineering/*/brownfield-contract-inputs.md` or `.specship/specs/*/artifacts/reverse-engineering/brownfield-contract-inputs.md` before proceeding.
- If `planning_step` is missing in an older mission, infer progress from files: recon artifact present → brainstorm; `requirements.md` present → testgen; `artifacts/test-cases.md` present → plan; `tasks.md` present → build handoff.
- Resume from the next incomplete planning step.

**If phase = "build":**
- Checkout the mission branch
- Read state.json for milestone progress (`milestones_completed` is an integer count):
  - If `milestones_completed < milestones_total`:
    - Read the plan file
    - Skip to `current_milestone` (= `milestones_completed + 1`)
    - Within that milestone, skip to `next_task`
    - Resume execution from there
  - If no milestone tracking (legacy flat plan):
    - Skip to task N+1 where N = `tasks_completed`
- If Step 2.5 flagged the state as stale, prefer the milestone count from the trace's last `milestone_complete` event / `git log --grep='[specship] milestone'` over `state.json`.
- Resume the subagent-driven-development method directly from that point — feature milestones (Milestone 1+) run as dispatched subagents (see `specship-build`), each reading the artifacts under `.specship/specs/<id>/`. Run each remaining milestone as an isolated pass.

**If phase = "validate":**
- Re-run all validators (validation should be idempotent)
- Pick up from aggregate verdict

**If phase = "recover":**
- Read the validation failure report
- Resume recovery using the live `recovery_attempts` integer in state.json (the single source of truth shared with specship-recover — do NOT recount `[specship-fix]` commits)

**If phase = "escalate":**
- Report to user: "This mission hit an unresolvable issue. Recovery was attempted 3 times."
- Show: the blocking issues from state.json handoff_notes
- Options: fix manually and re-validate, or abort
- Do NOT auto-continue — human judgment required

**If phase = "ship":**
- Re-run ship (idempotent — won't duplicate PR)

### Step 6: Update State

After resuming, continue updating `.specship/state.json` as normal (the state-update behavior described in specship-plan / specship-build handles this — keep the same fields current as you make progress).

## Key Principles

- **Filesystem is the source of truth.** Not conversation memory, not git log — the state.json file.
- **Idempotent resume.** Resuming should never corrupt state or create duplicates.
- **Human confirms before continuing.** Never auto-resume without showing the user where they are.
- **Handoff notes are critical.** The previous session's context is gone — handoff notes bridge the gap.

---

**Suggested model:** Sonnet.
