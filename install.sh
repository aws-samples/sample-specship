#!/bin/bash
# SpecShip Power Installer for Kiro
# Installs SpecShip steering files (the workflow + TDD discipline) into your Kiro environment.
#
# Usage:
#   ./install.sh                     # install GLOBALLY into ~/.kiro/steering (applies to every Kiro project)
#   ./install.sh ./.kiro/steering    # install into a single project's steering dir (scoped)
#   ./install.sh <any-dir>           # install into an explicit steering dir
#
# Flags (supply-chain hardening):
#   --review-only   Clone the third-party companions but do NOT run gstack's ./setup.
#                   Review the code first, then run ./setup yourself. (Also: SPECSHIP_CLONE_ONLY=1)
#   --run-setup     Opt in to running gstack's ./setup automatically. By DEFAULT setup is
#                   NOT run without consent — review-first is the default. (Also: SPECSHIP_RUN_SETUP=1)
#   --ssh           Clone over SSH (git@github.com:...) so host-key verification applies,
#                   instead of HTTPS. (Also: SPECSHIP_GIT_SCHEME=ssh)
#   --unpinned      Explicitly ALLOW cloning an unpinned companion at upstream HEAD.
#                   By DEFAULT the installer now FAILS CLOSED on an unpinned clone —
#                   you must pin a SHA/ref or pass this flag to accept live-HEAD risk.
#                   (Also: SPECSHIP_ALLOW_UNPINNED=1)
#   --allow-npx-fallback
#                   Explicitly ALLOW the integrity-UNCHECKED npx MCP config when the
#                   locked 'npm ci' install is unavailable. By DEFAULT the installer will
#                   NOT silently downgrade to npx. (Also: SPECSHIP_ALLOW_NPX_FALLBACK=1)
#   --help          Show this help.
#
# Review-first default: gstack's ./setup executes third-party code with your privileges.
# The installer will NOT run it unless you opt in (--run-setup / SPECSHIP_RUN_SETUP=1) or
# answer "yes" at the interactive prompt (which defaults to No). Piped installs never run it.
#
# Supply-chain pinning (REQUIRED by default for any install):
#   SPECSHIP_SUPERPOWERS_REF / SPECSHIP_GSTACK_REF
#     • Set to a full 40-char commit SHA  → the installer VERIFIES the checked-out HEAD
#       matches that SHA and ABORTS the clone on mismatch (defeats tampering / MITM).
#     • Set to a branch/tag name          → pins to that ref (name, not content hash).
#     • Unset                             → the installer ABORTS (fail-closed) unless you
#       pass --unpinned / SPECSHIP_ALLOW_UNPINNED=1 to explicitly accept live-HEAD risk.

set -e
# Defense in depth: every file/dir this installer creates is user-only by default.
umask 077

# --- Flag parsing (keep the single positional steering-dir arg intact) ---------
CLONE_ONLY="${SPECSHIP_CLONE_ONLY:+yes}"
# Review-first by default (T2/T9): gstack's ./setup executes third-party code with
# your privileges, so it does NOT run unless you explicitly opt in — via --run-setup,
# SPECSHIP_RUN_SETUP=1, or an interactive "yes" at the prompt. Default is clone-only.
RUN_SETUP="${SPECSHIP_RUN_SETUP:+yes}"
GIT_SCHEME="${SPECSHIP_GIT_SCHEME:-https}"
# Fail-closed on unpinned clones (T1/T2 default-unpinned gap): an unpinned clone is
# refused unless the operator explicitly accepts live-HEAD risk via --unpinned or
# SPECSHIP_ALLOW_UNPINNED=1. Pinning a SHA/ref is the intended default.
ALLOW_UNPINNED="${SPECSHIP_ALLOW_UNPINNED:+yes}"
# The npx MCP fallback re-resolves packages from the registry with NO lockfile integrity
# check (T3 residual). It is no longer taken silently — require an explicit opt-in.
ALLOW_NPX_FALLBACK="${SPECSHIP_ALLOW_NPX_FALLBACK:+yes}"
STEERING_ARG=""
for arg in "$@"; do
  case "$arg" in
    --review-only|--clone-only) CLONE_ONLY="yes" ;;
    --run-setup)                RUN_SETUP="yes" ;;
    --ssh)                      GIT_SCHEME="ssh" ;;
    --unpinned)                 ALLOW_UNPINNED="yes" ;;
    --allow-npx-fallback)       ALLOW_NPX_FALLBACK="yes" ;;
    --help|-h)
      sed -n '2,37p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    -*) echo "Unknown flag: $arg (see ./install.sh --help)"; exit 2 ;;
    *)  STEERING_ARG="$arg" ;;
  esac
done
# --review-only always wins over an opt-in to run setup.
[ -n "$CLONE_ONLY" ] && RUN_SETUP=""

# git is required for the companion clones.
if ! command -v git >/dev/null 2>&1; then
  echo "✗ git not found — required to install the companion skills. Install git and re-run."
  exit 1
fi

# --- Checksum tool (for the post-install integrity manifest, T1/T4) ------------
if command -v shasum >/dev/null 2>&1; then
  SHA256="shasum -a 256"
elif command -v sha256sum >/dev/null 2>&1; then
  SHA256="sha256sum"
else
  SHA256=""   # manifest generation will be skipped with a notice
fi

SKILLS_DIR="$HOME/.kiro/skills"
PROVENANCE="$SKILLS_DIR/.specship-provenance.txt"

# --- Supply-chain clone helpers (T1 tampering, T7 MITM) ------------------------

# repo_url <owner/repo> — build the clone URL for the chosen transport.
repo_url() {
  case "$GIT_SCHEME" in
    ssh) printf 'git@github.com:%s.git' "$1" ;;
    *)   printf 'https://github.com/%s.git' "$1" ;;
  esac
}

# is_sha <ref> — true only for a full 40-char hex commit SHA.
is_sha() { printf '%s' "$1" | grep -Eq '^[0-9a-f]{40}$'; }

# provenance_record <owner/repo> <sha> <status> — append an audit line (T11 repudiation).
provenance_record() {
  mkdir -p "$SKILLS_DIR"
  printf '%s\t%s\t%s\t%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown-time)" "$1" "$2" "$3" >> "$PROVENANCE"
  chmod 600 "$PROVENANCE" 2>/dev/null || true
}

# clone_verified <owner/repo> <ref-or-empty> <dest-dir>
# Clones the repo. When <ref> is a full commit SHA it checks the repo out at that
# exact commit and FAILS CLOSED if HEAD doesn't match (integrity verification).
# Returns non-zero on clone failure OR verification mismatch — never leaves
# unverified code behind on mismatch.
clone_verified() {
  local slug="$1" ref="$2" dest="$3"
  local url; url="$(repo_url "$slug")"
  local head=""

  if [ -n "$ref" ] && is_sha "$ref"; then
    # Pin by content: full clone (a shallow clone can't reliably reach an arbitrary
    # commit across git versions), checkout the exact SHA, then verify HEAD.
    if ! git clone --quiet "$url" "$dest" 2>/dev/null; then
      return 1
    fi
    if ! git -C "$dest" checkout --quiet "$ref" 2>/dev/null; then
      echo "  ✗ pinned commit $ref not found in $slug — refusing to use unverified code."
      rm -rf "$dest"
      provenance_record "$slug" "$ref" "PIN-NOT-FOUND"
      return 1
    fi
    head="$(git -C "$dest" rev-parse HEAD 2>/dev/null)"
    if [ "$head" != "$ref" ]; then
      echo "  ✗ INTEGRITY FAILURE: $slug HEAD ($head) != pinned ref ($ref). Aborting clone."
      rm -rf "$dest"
      provenance_record "$slug" "$head" "PIN-MISMATCH(expected:$ref)"
      return 1
    fi
    echo "  ✓ $slug pinned + integrity-verified at $ref"
    provenance_record "$slug" "$head" "pinned-sha-verified"

  elif [ -n "$ref" ]; then
    # Named branch/tag — pins to a name, not a content hash.
    if ! git clone --quiet --depth 1 --branch "$ref" "$url" "$dest" 2>/dev/null; then
      return 1
    fi
    head="$(git -C "$dest" rev-parse HEAD 2>/dev/null)"
    echo "  ✓ $slug cloned at ref '$ref' ($head)"
    echo "    ⓘ '$ref' is a branch/tag. Set a 40-char commit SHA to pin + verify by content hash."
    provenance_record "$slug" "$head" "pinned-ref:$ref"

  elif [ -n "$ALLOW_UNPINNED" ]; then
    # Unpinned, EXPLICITLY allowed (--unpinned / SPECSHIP_ALLOW_UNPINNED=1) — trust
    # upstream HEAD. Record the SHA and warn loudly.
    if ! git clone --quiet --depth 1 "$url" "$dest" 2>/dev/null; then
      return 1
    fi
    head="$(git -C "$dest" rev-parse HEAD 2>/dev/null)"
    echo "  ⚠ $slug cloned UNPINNED at $head (upstream HEAD) — you passed --unpinned."
    echo "    Supply-chain risk (T1): you are trusting whatever is on the default branch right now."
    echo "    To pin + verify next time, re-run with the SHA above, e.g.:"
    echo "      SPECSHIP_${4:-REF}=$head ./install.sh"
    provenance_record "$slug" "$head" "UNPINNED-head(explicit)"

  else
    # Unpinned and NOT explicitly allowed — FAIL CLOSED (T1/T2 default-unpinned gap).
    # We refuse to clone live HEAD without a pin, so the typical install no longer
    # silently trusts whatever is on the default branch.
    echo "  ✗ REFUSING to clone $slug UNPINNED (fail-closed, T1/T2)."
    echo "    No SPECSHIP_${4:-REF} is set, so there is no content hash to verify against."
    echo "    Choose one:"
    echo "      • Pin + verify (recommended):  SPECSHIP_${4:-REF}=<40-char-SHA> ./install.sh"
    echo "      • Pin to a branch/tag:         SPECSHIP_${4:-REF}=<branch-or-tag> ./install.sh"
    echo "      • Accept live-HEAD risk:       ./install.sh --unpinned   (or SPECSHIP_ALLOW_UNPINNED=1)"
    provenance_record "$slug" "unpinned" "REFUSED-unpinned(fail-closed)"
    return 1
  fi
  return 0
}

POWER_DIR="$(cd "$(dirname "$0")" && pwd)"

# Target steering dir: positional arg if given, else the global user-level dir.
if [ -n "$STEERING_ARG" ]; then
  KIRO_STEERING_DIR="$(mkdir -p "$STEERING_ARG" && cd "$STEERING_ARG" && pwd)"
  SCOPE="project-scoped ($KIRO_STEERING_DIR)"
else
  KIRO_STEERING_DIR="$HOME/.kiro/steering"
  SCOPE="GLOBAL — applies to every Kiro workspace"
fi

echo "╔══════════════════════════════════════════╗"
echo "║  SpecShip Power Installer for Kiro       ║"
echo "╚══════════════════════════════════════════╝"
echo ""
echo "Target: $KIRO_STEERING_DIR"
echo "Scope:  $SCOPE"
echo "Transport: $GIT_SCHEME${CLONE_ONLY:+  |  --review-only (gstack ./setup will NOT run)}"
echo ""

# Step 0: Prerequisite check — SpecShip delegates its methods to the required
# companion skills (superpowers + gstack). Refuse to install without them.
echo "→ Checking required companions (superpowers + gstack)..."
MISSING=""

sp_ok="yes"
for s in brainstorming writing-plans subagent-dev tdd debugging; do
  if [ ! -d "$SKILLS_DIR/superpowers-$s" ]; then
    echo "  ✗ superpowers-$s NOT found"
    sp_ok=""
    MISSING="yes"
  fi
done
[ -n "$sp_ok" ] && echo "  ✓ superpowers (brainstorming, writing-plans, subagent-dev, tdd, debugging found)"

gstack_ok="yes"
for s in review cso qa-only; do
  if [ ! -d "$SKILLS_DIR/gstack-$s" ]; then
    echo "  ✗ gstack-$s NOT found"
    gstack_ok=""
    MISSING="yes"
  fi
done
[ -n "$gstack_ok" ] && echo "  ✓ gstack (review, cso, qa-only found)"

if [ -n "$MISSING" ]; then
  echo ""
  echo "╔══════════════════════════════════════════╗"
  echo "║  ✗ Prerequisites missing                 ║"
  echo "╚══════════════════════════════════════════╝"
  echo ""
  echo "SpecShip orchestrates the superpowers + gstack skills; it won't work without them."
  echo ""
  echo "  ⓘ Supply-chain notice — if you continue, this installer will:"
  echo "      • git clone $(repo_url obra/superpowers)   (skills copied into ~/.kiro/skills)"
  if [ -n "$CLONE_ONLY" ]; then
    echo "      • git clone $(repo_url garrytan/gstack)    (--review-only: ./setup will NOT be run)"
  elif [ -n "$RUN_SETUP" ]; then
    echo "      • git clone $(repo_url garrytan/gstack)    AND run its ./setup script (--run-setup opt-in)"
  else
    echo "      • git clone $(repo_url garrytan/gstack)    (./setup is NOT run automatically — review-first)"
  fi
  echo "    Pinning (REQUIRED by default): set SPECSHIP_SUPERPOWERS_REF / SPECSHIP_GSTACK_REF to a full"
  echo "    commit SHA and the installer verifies the checked-out code matches it (fails closed on mismatch)."
  echo "    Unset = the installer ABORTS unless you pass --unpinned / SPECSHIP_ALLOW_UNPINNED=1 to accept HEAD."
  echo "    Review-first (default): gstack ./setup runs third-party code with your privileges, so it is"
  echo "    NOT executed unless you opt in (--run-setup / SPECSHIP_RUN_SETUP=1 or 'yes' at the prompt)."
  echo "    Use --review-only to also skip the prompt. Or install both manually (see PREREQUISITES.md)."
  echo ""
  printf "  Install missing prerequisites automatically? [Y/n] "
  read -r ans
  if [ "$ans" = "n" ] || [ "$ans" = "N" ]; then
    echo ""
    echo "  Skipped. Install them manually (see PREREQUISITES.md) and re-run ./install.sh."
    [ -z "$SPECSHIP_SKIP_PREREQ" ] && exit 1
  else
    echo ""
    mkdir -p "$SKILLS_DIR"
    chmod 700 "$SKILLS_DIR" 2>/dev/null || true
    # Install superpowers if missing
    if [ -z "$sp_ok" ]; then
      echo "→ Installing superpowers skills from $(repo_url obra/superpowers)..."
      SUPERPOWERS_TMP=$(mktemp -d)
      # Clone into a fresh leaf INSIDE the 0700 mktemp dir (don't rmdir + reuse the
      # name — that opens a TOCTOU window where a local attacker could pre-create the
      # path as a symlink and feed us attacker-controlled skills). git creates the leaf.
      if clone_verified "obra/superpowers" "$SPECSHIP_SUPERPOWERS_REF" "$SUPERPOWERS_TMP/repo" SUPERPOWERS_REF; then
        for skill_dir in "$SUPERPOWERS_TMP"/repo/skills/brainstorming \
                         "$SUPERPOWERS_TMP"/repo/skills/writing-plans \
                         "$SUPERPOWERS_TMP"/repo/skills/subagent-driven-development \
                         "$SUPERPOWERS_TMP"/repo/skills/test-driven-development \
                         "$SUPERPOWERS_TMP"/repo/skills/systematic-debugging; do
          if [ -d "$skill_dir" ] && [ -f "$skill_dir/SKILL.md" ]; then
            src_name=$(basename "$skill_dir")
            case "$src_name" in
              subagent-driven-development) kiro_name="superpowers-subagent-dev" ;;
              test-driven-development)     kiro_name="superpowers-tdd" ;;
              systematic-debugging)        kiro_name="superpowers-debugging" ;;
              *)                           kiro_name="superpowers-$src_name" ;;
            esac
            mkdir -p "$SKILLS_DIR/$kiro_name"
            cp "$skill_dir/SKILL.md" "$SKILLS_DIR/$kiro_name/SKILL.md"
            # Copy supporting files (prompts, references) alongside the SKILL.md
            find "$skill_dir" -maxdepth 1 -name "*.md" ! -name "SKILL.md" -exec cp {} "$SKILLS_DIR/$kiro_name/" \;
            echo "  ✓ $kiro_name"
          fi
        done
      else
        echo "  ✗ Failed to clone/verify superpowers repo. Check your network/ref and try again."
        echo "    Manual: git clone $(repo_url obra/superpowers)"
      fi
      rm -rf "$SUPERPOWERS_TMP"
    fi

    # Install gstack if missing
    if [ -z "$gstack_ok" ]; then
      echo "→ Installing gstack from $(repo_url garrytan/gstack)..."
      echo "  (gstack is ~52MB and requires bun to build its browser binary)"
      if clone_verified "garrytan/gstack" "$SPECSHIP_GSTACK_REF" "$SKILLS_DIR/gstack" GSTACK_REF; then
        echo "  ✓ gstack cloned to $SKILLS_DIR/gstack"
        # Running gstack's ./setup is the highest-privilege step in the install (T2/T9):
        # it executes third-party code with your privileges. REVIEW-FIRST IS THE DEFAULT —
        # ./setup runs ONLY on an explicit opt-in (--run-setup / SPECSHIP_RUN_SETUP=1) or a
        # "yes" at the prompt below (which defaults to No). A piped/non-interactive install
        # NEVER auto-executes it; the developer runs it after reviewing.
        run_setup_now=""
        if [ -n "$CLONE_ONLY" ]; then
          run_setup_now=""
        elif [ -n "$RUN_SETUP" ]; then
          run_setup_now="yes"   # explicit opt-in via flag / env
        elif [ -t 0 ]; then
          # Interactive: ask, default No. The developer is trusting gstack's setup at THIS moment.
          echo "  ⚠ gstack's ./setup runs third-party code with your privileges (supply-chain risk T2)."
          echo "    Review it first:  less \"$SKILLS_DIR/gstack/setup\""
          printf "  Run gstack ./setup now? [y/N] "
          read -r setup_ans
          [ "$setup_ans" = "y" ] || [ "$setup_ans" = "Y" ] && run_setup_now="yes"
        fi

        if [ -z "$run_setup_now" ]; then
          echo "  ⓘ gstack cloned but ./setup was NOT run (review-first default)."
          echo "    Review, then run it yourself to enable browser features:"
          echo "      less \"$SKILLS_DIR/gstack/setup\"          # inspect the script first"
          echo "      (cd \"$SKILLS_DIR/gstack\" && ./setup)      # then build the browser binary"
          echo "    (Or re-run the installer with --run-setup to opt in.)"
        elif command -v bun >/dev/null 2>&1; then
          echo "  → Running gstack setup (you opted in)..."
          # Capture setup's real exit status (pipefail off globally → pipe would mask it).
          setup_out=$(cd "$SKILLS_DIR/gstack" && ./setup 2>&1); setup_rc=$?
          printf '%s\n' "$setup_out" | tail -5
          [ "$setup_rc" -ne 0 ] && echo "  ⚠ gstack ./setup exited $setup_rc — browser features may not work. Re-run: (cd $SKILLS_DIR/gstack && ./setup)"
        else
          echo "  ⚠ bun not installed — gstack browser features won't work until you run:"
          echo "    cd $SKILLS_DIR/gstack && ./setup"
          echo "    (Install bun first — download, inspect, then run:"
          echo "       curl -fsSL https://bun.sh/install -o install-bun.sh && less install-bun.sh && bash install-bun.sh)"
        fi
        # Create the individual skill directories gstack expects
        for s in review cso qa-only; do
          if [ -f "$SKILLS_DIR/gstack/$s/SKILL.md" ] && [ ! -d "$SKILLS_DIR/gstack-$s" ]; then
            mkdir -p "$SKILLS_DIR/gstack-$s"
            cp "$SKILLS_DIR/gstack/$s/SKILL.md" "$SKILLS_DIR/gstack-$s/SKILL.md"
            echo "  ✓ gstack-$s"
          fi
        done
      else
        echo "  ✗ Failed to clone/verify gstack repo. Check your network/ref and try again."
        echo "    Manual: git clone $(repo_url garrytan/gstack) ~/.kiro/skills/gstack"
      fi
    fi
    echo ""
  fi
fi
echo ""

# back_up_if_changed <dest> — if dest exists and differs from the new file, keep a .bak copy.
copy_with_backup() {
  local src="$1" dest="$2"
  if [ -f "$dest" ] && ! cmp -s "$src" "$dest"; then
    cp "$dest" "$dest.bak"
    echo "  ⟲ $(basename "$dest") changed — previous version saved to $(basename "$dest").bak"
  fi
  cp "$src" "$dest"
}

# Step 1: Install steering files (top-level skills)
echo "→ Installing steering files..."
mkdir -p "$KIRO_STEERING_DIR"
# Restrictive permissions (T4/T5): steering + hooks control the AI agent's behavior
# over your source code. Lock the dir to the owner so no other local process can
# silently inject instructions. One line, significant impact.
chmod 700 "$KIRO_STEERING_DIR" 2>/dev/null || true

for file in "$POWER_DIR"/steering/*.md; do
  if [ -f "$file" ]; then
    filename=$(basename "$file")
    copy_with_backup "$file" "$KIRO_STEERING_DIR/$filename"
    echo "  ✓ $filename"
  fi
done

# Step 1b: Install shared references (quality-bar, feature-polish,
# design-system, regression-recipes, etc.) that the skills reference.
if [ -d "$POWER_DIR/steering/shared" ]; then
  mkdir -p "$KIRO_STEERING_DIR/shared"
  chmod 700 "$KIRO_STEERING_DIR/shared" 2>/dev/null || true
  for file in "$POWER_DIR"/steering/shared/*.md; do
    if [ -f "$file" ]; then
      filename=$(basename "$file")
      copy_with_backup "$file" "$KIRO_STEERING_DIR/shared/$filename"
      echo "  ✓ shared/$filename"
    fi
  done
fi

# Step 2: Install POWER.md as an ON-DEMAND reference (NOT always-on).
# A steering file with no inclusion frontmatter defaults to 'always' and would
# bloat every interaction — so we prepend `inclusion: manual` to the copy.
{
  printf -- "---\ninclusion: manual\n---\n\n"
  cat "$POWER_DIR/POWER.md"
} > "$KIRO_STEERING_DIR/specship-power.md.tmp"
copy_with_backup "$KIRO_STEERING_DIR/specship-power.md.tmp" "$KIRO_STEERING_DIR/specship-power.md"
rm -f "$KIRO_STEERING_DIR/specship-power.md.tmp"
echo "  ✓ specship-power.md (reference, inclusion: manual)"

# Step 2.5: Generate an integrity manifest (T1 supply-chain, T4 steering injection).
# Records the SHA-256 of every steering file + companion SKILL.md so tampering is
# detectable after install. Verify any time with ./specship-verify.sh.
#
# The manifest alone is DETECTION, not a root of trust: a same-UID attacker who rewrites
# a steering file can also rewrite the co-located manifest to match (the T4 shared-fate
# gap). To break that shared fate we ALSO print a ROOT DIGEST — a SHA-256 of the manifest
# itself — for you to record OFF the machine (password manager, phone, ticket). At verify
# time, pass it back via SPECSHIP_ROOT_DIGEST and specship-verify recomputes + compares.
# Because the attacker cannot change the value you hold off-box, they can no longer rewrite
# steering + manifest silently: the root-digest check fails. See SECURITY.md.
echo ""
echo "→ Generating integrity manifest..."
if [ -n "$SHA256" ]; then
  MANIFEST="$KIRO_STEERING_DIR/.specship-manifest.sha256"
  : > "$MANIFEST"
  # SpecShip steering files + shared references
  for f in "$KIRO_STEERING_DIR"/*.md "$KIRO_STEERING_DIR"/shared/*.md; do
    [ -f "$f" ] && $SHA256 "$f" >> "$MANIFEST"
  done
  # Companion skill definitions (third-party code integrity)
  for d in "$SKILLS_DIR"/superpowers-* "$SKILLS_DIR"/gstack-* "$SKILLS_DIR"/gstack; do
    [ -f "$d/SKILL.md" ] && $SHA256 "$d/SKILL.md" >> "$MANIFEST"
  done
  chmod 600 "$MANIFEST" 2>/dev/null || true
  manifest_count=$(wc -l < "$MANIFEST" 2>/dev/null | tr -d ' '); manifest_count=${manifest_count:-0}
  echo "  ✓ $manifest_count files hashed → $MANIFEST"

  # Root digest: SHA-256 of the manifest, for off-box recording (T4 shared-fate).
  ROOT_DIGEST="$($SHA256 "$MANIFEST" 2>/dev/null | awk '{print $1}')"
  if [ -n "$ROOT_DIGEST" ]; then
    echo ""
    echo "  ┌─ ROOT DIGEST (record this OFF the machine to defeat same-UID tampering, T4) ─┐"
    echo "     $ROOT_DIGEST"
    echo "  └──────────────────────────────────────────────────────────────────────────────┘"
    echo "    Then verify with it pinned:"
    echo "      SPECSHIP_ROOT_DIGEST=$ROOT_DIGEST $POWER_DIR/specship-verify.sh${STEERING_ARG:+ $KIRO_STEERING_DIR}"
  fi
  echo "    Verify integrity any time:  $POWER_DIR/specship-verify.sh${STEERING_ARG:+ $KIRO_STEERING_DIR}"
else
  echo "  ⚠ no shasum/sha256sum found — skipping integrity manifest (install one to enable it)."
fi

# Step 3: Offer recommended Kiro agent hooks (opt-in).
echo ""
echo "→ Recommended agent hooks (opt-in, ship disabled)..."
PROJECT_KIRO=""
if [ -n "$STEERING_ARG" ]; then
  # project-scoped install: hooks dir is a sibling of the steering dir
  PROJECT_KIRO="$(dirname "$KIRO_STEERING_DIR")/hooks"
elif [ -d ".kiro" ]; then
  PROJECT_KIRO=".kiro/hooks"
fi
# validate_hook <file> — structural schema check for a .kiro.hook (T10 malformed-hook DoS).
# A malformed or unexpected hook can drive the agent into failure loops or run something
# the developer didn't intend. Before copying, require: valid JSON, an "enabled" key that
# is a boolean AND false at ship time (opt-in only), and the "when"/"then" keys present.
# Prefers jq (already used for MCP merge); falls back to a conservative grep check.
validate_hook() {
  local f="$1"
  if command -v jq >/dev/null 2>&1; then
    jq -e '
      (type=="object")
      and (has("enabled") and (.enabled|type=="boolean") and (.enabled==false))
      and (has("when") and (.when|type=="object"))
      and (has("then") and (.then|type=="object"))
    ' "$f" >/dev/null 2>&1
    return $?
  fi
  # jq-less fallback: reject if it doesn't look like an object shipping enabled:false with when/then.
  grep -q '"enabled"[[:space:]]*:[[:space:]]*false' "$f" 2>/dev/null \
    && grep -q '"when"[[:space:]]*:' "$f" 2>/dev/null \
    && grep -q '"then"[[:space:]]*:' "$f" 2>/dev/null
}

if [ -n "$PROJECT_KIRO" ] && [ -d "$POWER_DIR/hooks" ]; then
  printf "  Copy SpecShip hooks into %s? [y/N] " "$PROJECT_KIRO"
  read -r ans
  if [ "$ans" = "y" ] || [ "$ans" = "Y" ]; then
    mkdir -p "$PROJECT_KIRO"
    # Hooks can execute shell commands on IDE events (T5) — lock the dir to the owner.
    chmod 700 "$PROJECT_KIRO" 2>/dev/null || true
    for hook in "$POWER_DIR"/hooks/*.kiro.hook; do
      [ -f "$hook" ] || continue
      # T10: validate structure BEFORE copying. A malformed/unexpected hook is skipped, not installed.
      if validate_hook "$hook"; then
        copy_with_backup "$hook" "$PROJECT_KIRO/$(basename "$hook")" && echo "  ✓ $(basename "$hook") (schema-validated)"
      else
        echo "  ✗ SKIPPED $(basename "$hook") — failed hook schema check (must be valid JSON with enabled:false + when/then). Not installed."
      fi
    done
    echo "    Enable the ones you want in Kiro's Agent Hooks panel (all ship disabled)."
  else
    echo "  ℹ skipped — hooks are in $POWER_DIR/hooks/ if you want them later."
  fi
else
  echo "  ℹ no project .kiro/ here — hooks live in $POWER_DIR/hooks/ (copy into a project's .kiro/hooks/)."
fi

# Step 4: Setup Playwright MCP (required for browser validation).
echo ""
echo "→ Setting up Playwright MCP for browser validation..."
echo "  ⓘ Enables two pinned MCP servers (browser + Lighthouse validation) that run when Kiro starts:"
echo "      @playwright/mcp@0.0.75  +  chrome-devtools-mcp@1.1.1"
echo "      Hardening: launched with --isolated (throwaway in-memory browser profile — never touches"
echo "      your real cookies/sessions, T12) and, when possible, installed from a pinned lockfile with"
echo "      integrity hashes via 'npm ci' (fails closed on registry tampering, T3). See SECURITY.md to sandbox."
MCP_FILE="$HOME/.kiro/settings/mcp.json"
MCP_INSTALL_DIR="$HOME/.kiro/settings/mcp-servers"
MCP_SRC="$POWER_DIR/settings/mcp"   # ships package.json + integrity-locked package-lock.json

# generate_locked_config <dest> — write an mcp.json that runs the servers from the
# integrity-verified local install (command:node <entry>) with --isolated (T3 + T12).
generate_locked_config() {
  cat > "$1" <<EOF
{
  "mcpServers": {
    "playwright": {
      "command": "node",
      "args": ["$MCP_INSTALL_DIR/node_modules/@playwright/mcp/cli.js", "--isolated"],
      "disabled": false
    },
    "chrome-devtools": {
      "command": "node",
      "args": ["$MCP_INSTALL_DIR/node_modules/chrome-devtools-mcp/build/src/bin/chrome-devtools-mcp.js", "--isolated"],
      "disabled": false
    }
  }
}
EOF
}

# write_mcp_config <source-config-file> — install/merge the config at $MCP_FILE (with backup + 600).
write_mcp_config() {
  local src="$1"
  mkdir -p "$(dirname "$MCP_FILE")"
  chmod 700 "$(dirname "$MCP_FILE")" 2>/dev/null || true
  if [ -f "$MCP_FILE" ]; then
    cp "$MCP_FILE" "$MCP_FILE.bak"
    if command -v jq >/dev/null 2>&1; then
      jq -s '.[0] * .[1]' "$MCP_FILE" "$src" > "$MCP_FILE.merged" \
        && mv "$MCP_FILE.merged" "$MCP_FILE" \
        && echo "  ✓ MCP servers added (previous config saved to mcp.json.bak)"
    else
      cp "$src" "$MCP_FILE"
      echo "  ✓ MCP servers configured (previous config saved to mcp.json.bak)"
      echo "    ⚠ Install jq for smarter config merging: brew install jq"
    fi
  else
    cp "$src" "$MCP_FILE"
    echo "  ✓ MCP servers configured at $MCP_FILE"
  fi
  # MCP config selects which code auto-runs on IDE start — keep it owner-only.
  chmod 600 "$MCP_FILE" 2>/dev/null || true
}

if [ -f "$MCP_FILE" ] && grep -q "playwright" "$MCP_FILE" 2>/dev/null; then
  echo "  ✓ Playwright MCP already configured (left as-is; delete the entries to re-run this step)."
elif ! command -v node >/dev/null 2>&1; then
  echo "  ⚠ Node.js not found — required for the MCP servers."
  echo ""
  echo "  Install Node.js first:"
  echo "    macOS:   brew install node"
  echo "    Linux:   curl -fsSL https://deb.nodesource.com/setup_20.x -o nodesource_setup.sh  # download, inspect, then run with sudo:"
  echo "             less nodesource_setup.sh && sudo bash nodesource_setup.sh && sudo apt-get install -y nodejs"
  echo "    Windows: https://nodejs.org/en/download"
  echo "    nvm:     nvm install 20"
  echo ""
  echo "  After installing Node.js, re-run ./install.sh to complete MCP setup."
else
  echo "  ✓ Node.js found: $(node --version)"
  installed_locked=""
  # Preferred path (T3): integrity-verified install from the shipped lockfile.
  # 'npm ci' recomputes each package's hash and ABORTS if it doesn't match the lock —
  # so a package tampered at the registry cannot be installed. --ignore-scripts blocks
  # install-time code execution; both packages ship prebuilt so nothing is lost.
  if [ -f "$MCP_SRC/package-lock.json" ] && command -v npm >/dev/null 2>&1; then
    echo "  → Installing pinned MCP servers from integrity lockfile (npm ci --ignore-scripts)..."
    mkdir -p "$MCP_INSTALL_DIR"
    chmod 700 "$MCP_INSTALL_DIR" 2>/dev/null || true
    cp "$MCP_SRC/package.json" "$MCP_INSTALL_DIR/package.json"
    cp "$MCP_SRC/package-lock.json" "$MCP_INSTALL_DIR/package-lock.json"
    if (cd "$MCP_INSTALL_DIR" && npm ci --ignore-scripts >/tmp/specship-mcp-npm.log 2>&1); then
      echo "  ✓ MCP servers installed + integrity-verified in $MCP_INSTALL_DIR"
      MCP_LOCKED_CONFIG="$MCP_INSTALL_DIR/.mcp.json"
      generate_locked_config "$MCP_LOCKED_CONFIG"
      write_mcp_config "$MCP_LOCKED_CONFIG"
      installed_locked="yes"
    else
      echo "  ⚠ 'npm ci' failed (integrity mismatch or network) — see /tmp/specship-mcp-npm.log."
    fi
  fi
  # Fallback: pinned npx config (versions pinned + --isolated, but npx re-resolves from
  # the registry without a lockfile integrity check — T3 residual). This is now OPT-IN:
  # taking it silently would quietly downgrade from integrity-verified to unverified, so
  # we refuse unless the operator passed --allow-npx-fallback / SPECSHIP_ALLOW_NPX_FALLBACK=1.
  if [ -z "$installed_locked" ]; then
    if [ -n "$ALLOW_NPX_FALLBACK" ]; then
      echo "  ⚠ Using the pinned npx MCP config (--allow-npx-fallback): versions pinned + --isolated,"
      echo "    but NO lockfile integrity check (T3 residual). Prefer fixing npm so 'npm ci' can run."
      write_mcp_config "$POWER_DIR/settings/mcp.json"
    else
      echo "  ✗ MCP servers NOT configured: the integrity-locked install is unavailable"
      echo "    (npm missing, or 'npm ci' failed) and the npx fallback is integrity-unchecked (T3)."
      echo "    Choose one:"
      echo "      • Install/repair npm, then re-run ./install.sh   (integrity-locked path, recommended)"
      echo "      • Accept the unverified npx fallback:            ./install.sh --allow-npx-fallback"
      echo "        (or SPECSHIP_ALLOW_NPX_FALLBACK=1)"
      echo "    Browser/Lighthouse validation stays unavailable until one of these is done."
    fi
  fi
fi

# (Companions were already verified as a hard prerequisite in Step 0.)

# Step 5: Install .specship/.gitignore template (so ephemeral state isn't tracked).
echo ""
echo "→ .specship/.gitignore template..."
if [ -f "$POWER_DIR/templates/specship-gitignore" ]; then
  echo "  ℹ Template available at $POWER_DIR/templates/specship-gitignore"
  echo "    Copy it to your project's .specship/.gitignore when you start a mission."
fi

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║  ✓ SpecShip Power installed!             ║"
echo "╚══════════════════════════════════════════╝"
echo ""
echo "Always-on: the workflow router, guardrails, and TDD discipline are active."
echo "Auto: the phase skills (plan/build/validate/recover/ship/resume) load when your request matches."
echo ""
echo "Invoke a phase by asking Kiro naturally:"
echo "  'Using SpecShip, build me a <your app>'   — plan a full mission"
echo "  'start building'                          — run the milestone loop (TDD)"
echo "  'validate' / 'is this done?'              — run adversarial validators"
echo "  'ship it'                                 — create the PR"
echo "  'where was I?'                            — resume an interrupted mission"
echo ""
echo "To force a specific skill: type its slash command (e.g. /specship-plan) or #-reference it."
echo "TDD is baked in: no production code without a failing test first."
echo "Integrity check: ./specship-verify.sh${STEERING_ARG:+ $KIRO_STEERING_DIR}   (detects tampered steering/skill files)"
echo "To remove SpecShip: ./uninstall.sh${STEERING_ARG:+ $KIRO_STEERING_DIR}"
