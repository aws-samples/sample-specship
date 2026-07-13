#!/bin/bash
# Generate the Kiro CLI-skills build of SpecShip from this IDE Power's steering files.
# One source of truth (steering/*.md) → two surfaces (IDE Power + CLI skills).
# Re-run after editing any steering file to keep the CLI surface in sync.
#
# Produces:
#   ~/.kiro/skills/specship-<name>/SKILL.md         (one per phase skill + validator)
#   ~/.kiro/steering/specship/specship-methodology.md   (always-on bootstrap/router)
#
# Usage: ./build-cli-skills.sh            # install into ~/.kiro
#        ./build-cli-skills.sh <root>     # install into <root>/.kiro (for testing)

set -e

POWER_DIR="$(cd "$(dirname "$0")" && pwd)"
KIRO_ROOT="${1:-$HOME}"
SKILLS="$KIRO_ROOT/.kiro/skills"
STEER="$KIRO_ROOT/.kiro/steering/specship"

echo "→ Generating SpecShip CLI skills into $SKILLS ..."
mkdir -p "$SKILLS" "$STEER"

# strip_frontmatter <file> — echo the body after the first --- ... --- block.
strip_frontmatter() {
  awk 'BEGIN{c=0} /^---[[:space:]]*$/{c++; next} c>=2{print}' "$1"
}

# emit_skill <source-steering-file> <cli-name> <description>
# Writes ~/.kiro/skills/<cli-name>/SKILL.md = CLI frontmatter (name+desc) + source body.
emit_skill() {
  local src="$1" name="$2" desc="$3"
  local dir="$SKILLS/$name"
  mkdir -p "$dir"
  {
    printf -- "---\n"
    printf -- "name: %s\n" "$name"
    # Block scalar (|) so descriptions with colons, quotes, apostrophes, ?, /,
    # arrows etc. never break YAML frontmatter parsing (matches gstack's format).
    printf -- "description: |\n  %s\n" "$desc"
    printf -- "---\n\n"
    printf -- "<!-- GENERATED from kiro-power-specship/steering/%s by build-cli-skills.sh — edit the source, not this file. -->\n\n" "$(basename "$src")"
    strip_frontmatter "$src"
  } > "$dir/SKILL.md"
  echo "  ✓ skill: $name"
}

# Phase skills: reuse the name+description already in each source file's frontmatter.
for src in "$POWER_DIR"/steering/specship-reverse-engineer.md \
           "$POWER_DIR"/steering/specship-plan.md \
           "$POWER_DIR"/steering/specship-contract.md \
           "$POWER_DIR"/steering/specship-testgen.md \
           "$POWER_DIR"/steering/specship-build.md \
           "$POWER_DIR"/steering/specship-validate.md \
           "$POWER_DIR"/steering/specship-recover.md \
           "$POWER_DIR"/steering/specship-ship.md \
           "$POWER_DIR"/steering/specship-resume.md; do
  name=$(awk -F': *' '/^name:/{print $2; exit}' "$src")
  desc=$(awk '/^description:/{sub(/^description: */,""); print; exit}' "$src")
  emit_skill "$src" "$name" "$desc"
done

# Validator sub-skills: source files are `manual` with no name/desc — synthesize them.
emit_skill "$POWER_DIR/steering/specship-validate-code.md"        "specship-validate-code"        "Code-correctness validator: checks each acceptance criterion + failure mode, runs the test suite (non-zero exit = FAIL), flags scope drift. Delegates to the gstack review skill. Run as an independent pass."
emit_skill "$POWER_DIR/steering/specship-validate-security.md"    "specship-validate-security"    "Security validator (attacker view): injection, auth bypass, secrets, boundary/negative inputs. Delegates to the gstack cso skill. CRITICAL/HIGH = FAIL."
emit_skill "$POWER_DIR/steering/specship-validate-integration.md" "specship-validate-integration" "Integration validator: frontend↔backend response-shape match vs the API contract (the data.items vs plain-array bug class). Run first for full-stack."
emit_skill "$POWER_DIR/steering/specship-validate-browser.md"     "specship-validate-browser"     "Browser validator: real interactive CRUD lifecycle (create→verify→edit→duplicate→delete-copy) via Playwright MCP or the gstack qa-only skill. Screenshot-only = INCOMPLETE."
emit_skill "$POWER_DIR/steering/specship-validate-design.md"      "specship-validate-design"      "Design/anti-slop validator: 15-item checklist, feature depth across 5 states, reference patterns, measured Lighthouse >=90."
emit_skill "$POWER_DIR/steering/specship-validate-alignment.md"   "specship-validate-alignment"   "Alignment validator: does the build match the user's intent, not just 'code exists'? Surprises / missing / over-built. FAIL/PARTIAL escalates."
emit_skill "$POWER_DIR/steering/specship-validate-load.md"        "specship-validate-load"        "Load validator: performance under concurrent load (k6/artillery) vs the contract NFR. Enterprise only."
emit_skill "$POWER_DIR/steering/specship-validate-aggregate.md"   "specship-validate-aggregate"   "Validation aggregator: turns the validators' typed verdicts into a decision — merge / recover / escalate. Runs the completeness critic."

# Always-on bootstrap: fold the three `always` steering files into one CLI steering file.
# (CLI skills are description-matched on demand; this always-on file is the router + rules
#  + the companion delegation map, mirroring how superpowers registers in the CLI.)
echo "  ✓ steering: specship/specship-methodology.md (always-on)"
{
  printf -- "---\ninclusion: always\n---\n\n"
  printf -- "<!-- GENERATED by kiro-power-specship/build-cli-skills.sh — edit the source steering files, not this. -->\n\n"
  printf -- "# SpecShip (CLI) — Workflow, Guardrails, Prerequisites\n\n"
  printf -- "This is the always-on bootstrap for SpecShip running as Kiro CLI skills. The phase skills (specship-plan, -contract, -testgen, -build, -validate, -recover, -ship, -resume) and the 8 validators are installed under ~/.kiro/skills/ and invoked by name.\n\n---\n\n"
  strip_frontmatter "$POWER_DIR/steering/specship-workflow.md"
  printf -- "\n\n---\n\n"
  strip_frontmatter "$POWER_DIR/steering/specship-guardrails.md"
  printf -- "\n\n---\n\n"
  strip_frontmatter "$POWER_DIR/steering/specship-prerequisites.md"
} > "$STEER/specship-methodology.md"

# Shared references: copy verbatim so skills that point to them resolve on the CLI surface too.
mkdir -p "$STEER/shared"
for f in "$POWER_DIR"/steering/shared/*.md; do
  cp "$f" "$STEER/shared/$(basename "$f")"
done
echo "  ✓ copied $(ls "$POWER_DIR"/steering/shared/*.md | wc -l | tr -d ' ') shared references to steering/specship/shared/"

# Deterministic process checker: copy the script so the VALIDATE->SHIP gate can locate
# and run it on the CLI surface (the IDE Power keeps it at the Power root). Both the
# aggregate step and the ship pre-condition discover it via `find ~/.kiro -name process-checker.js`.
if [ -f "$POWER_DIR/process-checker.js" ]; then
  cp "$POWER_DIR/process-checker.js" "$STEER/process-checker.js"
  echo "  ✓ copied process-checker.js to steering/specship/"
fi

echo ""
echo "✓ CLI skills generated. They register via your agent's resources glob"
echo "  (skill:///…/.kiro/skills/**/SKILL.md). Reload the CLI agent to pick them up."
echo "  Prerequisites (superpowers + gstack) must be installed — see PREREQUISITES.md."
