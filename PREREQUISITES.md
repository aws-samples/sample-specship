# SpecShip Prerequisites

SpecShip is **orchestration on top of two required companion skill sets**. It sequences their methods and adds the spec-driven artifacts (market research, sprint contract, pre-written tests, typed validator verdicts) — it does **not** re-implement the methods. Install both companions as Kiro skills **before** SpecShip.

| Companion | Provides the skills | SpecShip uses them for |
|---|---|---|
| **superpowers** ([github.com/obra/superpowers](https://github.com/obra/superpowers)) | `brainstorming`, `writing-plans`, `subagent-dev`, `tdd`, `debugging` | design-before-code, the implementation plan, per-task execution + two-stage review, red-green-refactor, root-cause debugging |
| **gstack** ([github.com/garrytan/gstack](https://github.com/garrytan/gstack)) | `review`, `cso`, `qa-only` (+ many more) | code review, security review, browser/QA validation (read-only) |

For UI projects you also need **Playwright MCP** (real browser/interactive validation) wired in `.kiro/settings/mcp.json`, and Lighthouse / Chrome DevTools MCP for measured performance. `./install.sh` offers to set up Playwright MCP automatically; the companion skills above are the only hard blockers.

## Install (the proven path)

Both companions install cleanly by asking Kiro to wrap the public repo as skills. In a Kiro chat (CLI or IDE):

```
read github.com/obra/superpowers, then wrap it as Kiro skills for me to use
```
```
read github.com/garrytan/gstack, then wrap it as Kiro skills for me to use
```

Kiro clones the repo, converts each skill into a Kiro `SKILL.md`, and registers them. After this you should have:

- `~/.kiro/skills/superpowers-*` (brainstorming, writing-plans, subagent-dev, tdd, debugging)
- `~/.kiro/skills/gstack-*` (review, cso, qa-only, …)

> **Kiro CLI vs IDE:** skills registered under `~/.kiro/skills/**/SKILL.md` are picked up by the CLI agent via its `agent_config.json` `resources` glob. In the IDE, the same skills are available as `/`-commands. If the IDE shows a "SKILL.md not for skill" validation warning, it's cosmetic — the skill still loads and runs.

## Verify they're installed

```bash
# superpowers (expect 5)
ls -d ~/.kiro/skills/superpowers-* 2>/dev/null | wc -l
# gstack core skills (expect review, cso, qa-only present)
for s in review cso qa-only; do
  [ -d ~/.kiro/skills/gstack-$s ] && echo "✓ gstack-$s" || echo "✗ MISSING gstack-$s"
done
```

`./install.sh` runs this check automatically and refuses to proceed if either companion is missing.

## What if I skip them?

SpecShip's pipeline will hit a delegation point ("invoke the `tdd` skill", "run `review`", …) and the named skill won't exist. Rather than silently degrade to vibe-coding — the exact failure SpecShip exists to prevent — SpecShip is built to **stop and tell you to install the missing companion**. Install both first; it takes two messages to Kiro.
