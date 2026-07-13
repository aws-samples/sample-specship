#!/bin/bash
# SpecShip integrity verifier  (mitigation M5 — file integrity monitoring)
#
# Re-hashes every steering file and companion SKILL.md recorded in the manifest
# that install.sh generated, and reports any file that changed, went missing, or
# appeared unexpectedly. This makes steering-file / skill tampering (threats T1,
# T4) DETECTABLE after install — the agent's whole authority over your source
# code flows through these files, so silent modification is the highest-impact
# local attack.
#
# It also flags permission drift (dirs that should be owner-only, 700/600) and
# prints the clone provenance log so you can see exactly which upstream commits
# the companion skills came from.
#
# Usage:
#   ./specship-verify.sh                    # verify the GLOBAL ~/.kiro/steering install
#   ./specship-verify.sh <steering-dir>     # verify an explicit steering dir (match your install)
#
# Exit codes:  0 = all files intact   1 = tampering/missing detected   2 = no manifest (run install.sh)
#
# LIMITATION (stated honestly): this is integrity DETECTION, not a root of trust.
# The manifest lives next to the files it protects; an attacker who can rewrite a
# steering file can usually also rewrite the manifest. It defeats accidental
# corruption and unsophisticated tampering, and gives you an auditable baseline —
# it is not a substitute for OS-level file protection or code signing. See SECURITY.md.

set -u

if [ -n "${1:-}" ]; then
  KIRO_STEERING_DIR="$(cd "$1" 2>/dev/null && pwd || echo "$1")"
else
  KIRO_STEERING_DIR="$HOME/.kiro/steering"
fi
SKILLS_DIR="$HOME/.kiro/skills"
MANIFEST="$KIRO_STEERING_DIR/.specship-manifest.sha256"
PROVENANCE="$SKILLS_DIR/.specship-provenance.txt"

# Pick a checksum tool that matches what install.sh used.
if command -v shasum >/dev/null 2>&1; then
  SHA_CHECK="shasum -a 256 -c"
  SHA_GEN="shasum -a 256"
elif command -v sha256sum >/dev/null 2>&1; then
  SHA_CHECK="sha256sum -c"
  SHA_GEN="sha256sum"
else
  echo "✗ Neither shasum nor sha256sum found — cannot verify integrity. Install one and re-run."
  exit 2
fi

echo "→ SpecShip integrity check"
echo "  steering dir: $KIRO_STEERING_DIR"
echo ""

if [ ! -f "$MANIFEST" ]; then
  echo "✗ No integrity manifest at $MANIFEST"
  echo "  Run ./install.sh${1:+ $1} first — it generates the manifest at install time."
  exit 2
fi

# --- Guard: a manifest with no verifiable entries must FAIL CLOSED --------------
# GNU sha256sum -c returns 0 on an empty file ("all zero lines passed"), which would
# otherwise report a green "0 files verified" PASS while every steering file could be
# attacker-controlled. Treat "no valid checksum lines" as an error, not a pass.
if ! grep -Eq '^[0-9a-fA-F]{64}[ *]' "$MANIFEST"; then
  echo "  ✗ Manifest contains no verifiable checksum lines (empty or corrupt): $MANIFEST"
  echo "    Cannot attest integrity. Re-run ./install.sh${1:+ $1} to regenerate it."
  exit 2
fi

# --- Root-digest check: defeats manifest shared-fate (T4) ----------------------
# The per-file check below only proves the files match the manifest. But a same-UID
# attacker who edits a steering file can also rewrite the manifest to match it — the
# manifest and the files it protects share fate. To break that, install.sh printed a
# ROOT DIGEST (SHA-256 of the manifest) for the operator to record OFF the machine.
# If SPECSHIP_ROOT_DIGEST is provided, recompute the manifest's digest and compare.
# A tampered manifest yields a different digest than the value the operator holds, so
# steering+manifest can no longer be rewritten silently. Absent the env var we can only
# warn — the check is opt-in because the trusted value lives off-box by design.
ROOT_FAIL=0
if [ -n "${SPECSHIP_ROOT_DIGEST:-}" ]; then
  actual_root="$($SHA_GEN "$MANIFEST" 2>/dev/null | awk '{print $1}')"
  expected_root="$(printf '%s' "$SPECSHIP_ROOT_DIGEST" | tr 'A-F' 'a-f' | tr -d '[:space:]')"
  if [ "$actual_root" = "$expected_root" ]; then
    echo "  ✓ Root digest matches the off-box value — manifest itself is authentic (T4 defended)."
  else
    echo "  ✗ ROOT DIGEST MISMATCH — the manifest does not match the value you recorded off-box."
    echo "      expected: $expected_root"
    echo "      actual:   $actual_root"
    echo "    The manifest (and likely the steering files) may have been rewritten by a same-UID"
    echo "    attacker. Do NOT run SpecShip. Restore from a trusted source and re-run ./install.sh."
    ROOT_FAIL=1
  fi
  echo ""
else
  echo "  ⓘ No SPECSHIP_ROOT_DIGEST provided — skipping the off-box root-digest check (T4 residual)."
  echo "    For same-UID tamper resistance, re-run with the digest install.sh printed:"
  echo "      SPECSHIP_ROOT_DIGEST=<digest> $0${1:+ $1}"
  echo ""
fi

# --- Core integrity check: re-hash every manifested file -----------------------
# `shasum -c` / `sha256sum -c` print "<file>: OK" or "<file>: FAILED" per line and
# exit non-zero if ANY file fails or is missing. Capture output so we can summarize.
CHECK_OUT="$($SHA_CHECK "$MANIFEST" 2>&1)"
CHECK_RC=$?

fail_lines="$(printf '%s\n' "$CHECK_OUT" | grep -E ': (FAILED|No such file|FAILED open or read)' || true)"
ok_count="$(printf '%s\n' "$CHECK_OUT" | grep -c ': OK' || true)"

if [ "$CHECK_RC" -eq 0 ]; then
  echo "  ✓ $ok_count files verified — all match the manifest."
else
  echo "  ✗ INTEGRITY FAILURE — $ok_count OK, but these changed or are missing:"
  printf '%s\n' "$fail_lines" | sed 's/^/      /'
  echo ""
  echo "    A changed steering/skill file means the AI agent's instructions may have been"
  echo "    tampered with (threat T4). Do NOT run SpecShip until you have reviewed the diff"
  echo "    (git diff if the dir is tracked, or compare against this Power's steering/*.md)"
  echo "    and re-run ./install.sh to restore + re-baseline once you trust the contents."
fi

# --- Detect UN-manifested steering files (T4: a dropped-in always-on file) ------
# The -c pass only re-hashes files IN the manifest — a brand-new steering file is
# invisible to it. But a .md with no `inclusion:` frontmatter defaults to always-on,
# so an injected file is loaded into every interaction. Enumerate what's on disk and
# flag anything the manifest doesn't cover.
TMPD="$(mktemp -d 2>/dev/null || echo /tmp/ss-verify.$$)"
mkdir -p "$TMPD" 2>/dev/null || true
# manifest paths: strip "<hash>  " or "<hash> *" prefix, keep only steering-dir .md entries
awk '{ sub(/^[0-9a-fA-F]+[ *]+/, ""); print }' "$MANIFEST" | sort -u > "$TMPD/manifested"
ls "$KIRO_STEERING_DIR"/*.md "$KIRO_STEERING_DIR"/shared/*.md 2>/dev/null | sort -u > "$TMPD/present"
extra="$(comm -13 "$TMPD/manifested" "$TMPD/present" 2>/dev/null || true)"
rm -rf "$TMPD" 2>/dev/null || true
if [ -n "$extra" ]; then
  echo "  ✗ UNEXPECTED steering files present but NOT in the manifest (possible injection, T4):"
  printf '%s\n' "$extra" | sed 's/^/      /'
  echo "    A steering .md with no 'inclusion:' frontmatter loads into EVERY interaction."
  echo "    Review these files; if legitimate (you added them), re-run ./install.sh to re-baseline."
  CHECK_RC=1
fi

# --- Permission drift (mitigation M6) ------------------------------------------
echo ""
echo "→ Permission check (owner-only expected)"
perm_warn=0
check_perm() {
  local path="$1" want="$2"
  [ -e "$path" ] || return 0
  # macOS stat -f %Lp ; GNU stat -c %a
  local mode
  mode="$(stat -f '%Lp' "$path" 2>/dev/null || stat -c '%a' "$path" 2>/dev/null || echo '???')"
  if [ "$mode" = "$want" ]; then
    echo "  ✓ $path ($mode)"
  else
    echo "  ⚠ $path is $mode, expected $want — tighten with: chmod $want \"$path\""
    perm_warn=1
  fi
}
check_perm "$KIRO_STEERING_DIR" 700
check_perm "$SKILLS_DIR" 700
check_perm "$MANIFEST" 600
check_perm "$HOME/.kiro/settings/mcp.json" 600

# --- Clone provenance (audit trail, mitigation for T1/T11) ---------------------
if [ -f "$PROVENANCE" ]; then
  echo ""
  echo "→ Companion clone provenance (time / repo / sha / status)"
  sed 's/^/  /' "$PROVENANCE"
  if grep -q 'UNPINNED' "$PROVENANCE" 2>/dev/null; then
    echo "  ⚠ One or more companions were cloned UNPINNED (upstream HEAD)."
    echo "    Re-run install.sh with SPECSHIP_SUPERPOWERS_REF / SPECSHIP_GSTACK_REF set to the"
    echo "    printed SHA to pin + integrity-verify them on the next install."
  fi
fi

echo ""
if [ "$ROOT_FAIL" -ne 0 ]; then
  echo "Result: FAIL ✗ — root-digest mismatch (see above). The manifest itself is untrusted; treat as tampering."
  exit 1
elif [ "$CHECK_RC" -eq 0 ] && [ "$perm_warn" -eq 0 ]; then
  echo "Result: PASS ✓ — files intact, permissions locked down."
  exit 0
elif [ "$CHECK_RC" -ne 0 ]; then
  echo "Result: FAIL ✗ — integrity mismatch (see above). Treat as tampering until proven otherwise."
  exit 1
else
  echo "Result: PASS with warnings — files intact, but permissions are looser than recommended."
  exit 0
fi
