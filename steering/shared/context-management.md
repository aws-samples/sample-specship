---
inclusion: manual
---
# Context Management for Long-Running Missions

SpecShip missions can run for hours. The chat/agent's context window will fill up. This document defines how to handle that.

## The Problem

A model's context window is finite (~200K tokens). In a 4-hour mission:
- The plan file uses ~5K tokens
- Each task pass + review uses ~30K tokens
- After 5-6 tasks, context is half full
- After 10+ tasks, compaction happens (lossy summarization)

## Strategy: Externalize State, Minimize Context

### What MUST be in context (keep)
- Current task being executed (the immediate work)
- Sprint contract (what "done" looks like)
- The orchestrator instructions (how to proceed)

### What should be externalized (on disk, read when needed)
- Completed task results (they're committed to git)
- Previous validator outputs (in traces/)
- The full plan file (read the current milestone's tasks only)
- Architecture guidance (read once at start, not per-task)

### What can be forgotten (compacted safely)
- Brainstorming conversation (design doc captures the decisions)
- Previous milestone execution details (commits capture the code)
- Error messages from tasks that were successfully fixed

## Practical Rules for the Orchestrator

### Rule 1: One Milestone in Context at a Time
Don't load the entire 40-task plan. Load only the current milestone's tasks. After milestone completes, you can forget the task details (they're in git).

### Rule 2: State.json is Your External Brain
After every significant event, write to the mission-state file (`.specship/state.json`). If context is compacted, you can re-read it to know exactly where you are.

## State Schema (Canonical — single source of truth)

`state.json` is the conceptual mission-state file that persists across sessions. **All parts of the workflow MUST use these exact field names.** Three phases write `state.json` (plan, build, recover) and one reads it back across sessions (resume). If they disagree on field names, resume silently mis-recovers. This schema is the contract between them. You don't need any specific writer mechanism — just keep the fields and their meanings exactly as below.

```json
{
  "mission_id": "001",
  "contract_id": "001",
  "contract_slug": "user-profile-api",
  "branch": "specship/mission-001-user-profile-api",
  "phase": "plan | build | validate | recover | escalate | ship",
  "phase_status": "in_progress | pending | complete | blocked",
  "planning_step": "recon | brainstorm | contract | testgen | plan | complete",
  "recon_artifact_path": ".specship/specs/001-user-profile-api/artifacts/reverse-engineering/brownfield-contract-inputs.md",
  "started_at": "<ISO timestamp>",
  "updated_at": "<ISO timestamp>",
  "plan_file": "<path>",

  "tasks_total": 0,
  "tasks_completed": 0,
  "last_completed_task": "",
  "next_task": "",

  "milestones_total": 0,
  "milestones_completed": 0,
  "current_milestone": 0,
  "current_milestone_name": "",

  "recovery_attempts": 0,
  "validation_results": {},
  "last_commit": "<git rev-parse HEAD at the last state write>",
  "handoff_notes": { "done": [], "next": [], "blocked": [] }
}
```

**Field rules (non-negotiable):**
- `milestones_completed` is an **integer count**, NEVER an array. `current_milestone` is the milestone currently in progress (= `milestones_completed + 1`).
- `planning_step` is only meaningful while `phase` is `plan`. It records the planning sub-step so brownfield recon can resume cleanly instead of jumping straight to brainstorm.
- `recon_artifact_path` points to `brownfield-contract-inputs.md` for brownfield missions, either mission-scoped or standalone. Leave it empty for greenfield missions.
- `next_task` is the resume entry point. There is no `next_action` field.
- `last_commit` records `git rev-parse HEAD` at each write so resume can detect a stale state file (commits exist after the last recorded write → trust git + trace over state.json).
- `handoff_notes` is a typed object `{done[], next[], blocked[]}`, not free text. Resume gates "Continue" on `next` being non-empty.

**FORBIDDEN legacy names (must appear nowhere in the mission state):**
`milestone_current`, `milestone_total`, `next_action`, `planning_phase`, and `milestones_completed` as an array literal `[`.

### Atomic writes (prevents the corruption that breaks resume)

`state.json` is written with a temp-file-and-rename so a crash mid-write never leaves a truncated, unparseable file — the exact crash the resume workflow exists to recover from. All writers MUST use this pattern: write the new state to a temp file, validate that it is well-formed JSON, keep a `.bak` copy of the previous good state, then do an atomic rename of the temp file into place. Concretely:

1. Write the full JSON to a temporary file (e.g. `.specship/state.json.tmp`).
2. Validate it parses as JSON (use whatever is available — `jq`, `python3`, or `node`); if it does not parse, abort the write, delete the temp file, and report the failure — do NOT overwrite the existing state.
3. Copy the current `.specship/state.json` to `.specship/state.json.bak` (if one exists).
4. Atomically rename the temp file over `.specship/state.json` (a rename is atomic on the same filesystem, so readers never see a half-written file).

If a write fails validation, the previous `state.json` (and `.bak`) are left intact — resume always has a parseable file to fall back to.

### Rule 3: Handoff Notes are Compression
The `handoff_notes` field in state.json is a human-readable summary of "what's done and what's next." Write it as if you're explaining to a colleague who just sat down with zero context. This is what you (or a new session/chat) will read after compaction.

### Rule 4: Git Log is History
If you need to know what was done in previous milestones, read git log. Don't keep it in conversation memory. Kiro has git, so run it directly:

```bash
git log --oneline --grep="\[specship\]" | head -20
```

### Rule 5: Don't Re-Read What You've Already Committed
If a file was created in milestone 1 and you're now in milestone 4, don't read it unless the current task specifically needs to modify or reference it.

## When Compaction Happens

If you notice context being summarized (conversation getting compressed):
1. Immediately update state.json with current progress
2. Write detailed handoff_notes
3. Commit any uncommitted work (even as WIP)
4. The next action will have less context — state.json and git are your lifeline

## Milestone Health (observable signals — not wall-clock)

The orchestrator cannot reliably observe wall-clock minutes, so milestone health is judged by facts on disk, not a stopwatch (see the Stuck Detector in the build phase):

**Health signals (observable):**
- A milestone committed with **no new tests** when its type requires them → suspicious (the work skipped the test gate).
- A milestone with **no new commit** and its acceptance check still failing → stuck (re-run the focused pass once, then BLOCK).
- A milestone that **exhausts its `dispatch_budget`** without a passing check → unhealthy → commit partial progress, mark BLOCKED, move on.

**Autonomous action on stall:** Commit whatever exists, mark the milestone BLOCKED in state.json, continue to the next non-dependent milestone. Validation will catch gaps. (The planning-time sizing guidance — "~15-45 min per milestone" — is for decomposing the plan, not a runtime gate.)

## Critical Transition: Build → Validate

If context compacts BETWEEN build completion and validation start, the orchestrator must still trigger validation. This is guaranteed by state.json:

**When build completes, state.json says:**
```json
{
  "phase": "validate",
  "phase_status": "pending",
  "handoff_notes": "All tasks complete. Ready for validation."
}
```

**When the next action reads state.json and sees `phase: validate, phase_status: pending`:**
→ Run the validate workflow immediately. Do NOT re-run the build.

This means validation happens even if:
- Context was compacted and the orchestrator "forgot" it was supposed to validate
- The session crashed between build and validate
- The user resumed the mission in a new chat/window

The `phase` field is the single source of truth for "what happens next." If it says `validate` + `pending`, validate. Always.

## Session Handoff (crash / new session)

When a new session/chat starts (via the resume workflow):
1. Read state.json (knows: phase, milestone, task, what's next)
2. Read sprint contract (knows: what "done" means)
3. Read git log (knows: what's already built)
4. Read the plan file's CURRENT MILESTONE ONLY
5. Continue from the exact task

**Phase-specific resume behavior:**
- `phase: build, phase_status: in_progress` → continue from `next_task`
- `phase: validate, phase_status: pending` → run validation (build is done)
- `phase: recover, phase_status: in_progress` → continue recovery attempt
- `phase: escalate, phase_status: blocked` → report to user, wait for guidance

The new session does NOT need:
- Previous conversation history
- How decisions were made
- What was tried and failed (unless it's in state.json's handoff_notes)
