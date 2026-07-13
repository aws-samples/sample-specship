#!/bin/bash
# SpecShip Power Uninstaller for Kiro
# Removes exactly the files install.sh added — nothing else in your steering dir is touched.
#
# Usage:
#   ./uninstall.sh                 # remove from the GLOBAL ~/.kiro/steering
#   ./uninstall.sh <steering-dir>  # remove from an explicit steering dir (match your install)

set -e

POWER_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -n "$1" ]; then
  KIRO_STEERING_DIR="$(cd "$1" && pwd)"
else
  KIRO_STEERING_DIR="$HOME/.kiro/steering"
fi

echo "→ Removing SpecShip steering files from $KIRO_STEERING_DIR ..."

removed=0
remove_one() {
  local target="$1"
  if [ -f "$target" ]; then
    rm -f "$target"
    echo "  ✗ removed $(basename "$target")"
    removed=$((removed + 1))
  fi
  # also clear any backup we created on update (rm -f is a no-op if absent;
  # never let this line return non-zero under `set -e`)
  rm -f "$target.bak"
}

# Top-level skills — remove only files this Power ships.
for file in "$POWER_DIR"/steering/*.md; do
  [ -f "$file" ] && remove_one "$KIRO_STEERING_DIR/$(basename "$file")"
done

# Shared references.
for file in "$POWER_DIR"/steering/shared/*.md; do
  [ -f "$file" ] && remove_one "$KIRO_STEERING_DIR/shared/$(basename "$file")"
done
# Remove the shared dir only if we emptied it.
[ -d "$KIRO_STEERING_DIR/shared" ] && rmdir "$KIRO_STEERING_DIR/shared" 2>/dev/null && echo "  ✗ removed empty shared/"

# The POWER.md reference copy.
remove_one "$KIRO_STEERING_DIR/specship-power.md"

# The integrity manifest install.sh generates (and the empty steering dir hint).
if [ -f "$KIRO_STEERING_DIR/.specship-manifest.sha256" ]; then
  rm -f "$KIRO_STEERING_DIR/.specship-manifest.sha256"
  echo "  ✗ removed .specship-manifest.sha256"
fi

echo ""
echo "Removed $removed SpecShip steering files."
echo "Note: any hooks copied into a project's .kiro/hooks/ and MCP entries in"
echo "~/.kiro/settings/mcp.json are left in place — remove those by hand if you want them gone."
echo "The companion skills (~/.kiro/skills/superpowers-*, gstack*) and the clone"
echo "provenance log (~/.kiro/skills/.specship-provenance.txt) are also left in place —"
echo "they may be shared with other Powers; remove them by hand if you want them gone."
echo "✓ SpecShip uninstalled."
