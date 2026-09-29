#!/bin/bash
# gsd-zettel-sync.sh — the WRITE/READ bridge between GSD's in-repo .planning/ and
# Mike's Obsidian second brain. GSD's .planning/ is ephemeral scaffolding; the vault
# is the durable brain. This bridge mirrors only *curated, useful knowledge* —
# LEARNINGS (decisions/lessons/patterns/surprises) + milestone summaries + roadmap —
# converted to Obsidian format (frontmatter + tags + wikilinks). Build scaffolding
# (raw PLAN/SUMMARY/VERIFICATION) is intentionally NOT synced.
#
# Vault layout (isolated — synced knowledge lives under gsd/knowledge/, kept
# separate from gsd/design/ and gsd/guides/):
#                $VAULT/gsd/knowledge/<milestone>/<phase>/<NN>-LEARNINGS.md
#                $VAULT/gsd/knowledge/<milestone>/MILESTONE_SUMMARY.md
#                $VAULT/gsd/knowledge/<milestone>/ROADMAP.md
#
# Usage (run from a project root that has .planning/):
#   gsd-zettel-sync.sh sync            # convert + write curated knowledge → vault
#   gsd-zettel-sync.sh dry             # show what WOULD be written, write nothing
#   gsd-zettel-sync.sh context <kw...> # READ side: find vault notes matching keywords
#   gsd-zettel-sync.sh path            # print the vault gsd/ dir for this project
#   gsd-zettel-sync.sh help
#
# Per Mike's prefs: logs + progress to stderr, prints each file it writes, duration.
set -uo pipefail

VAULT="${GSD_ZETTEL_VAULT:-$HOME/zettelkasten/claude_code/rescue-serverless}"
PROJECT_DIR="$PWD"
PLANNING="$PROJECT_DIR/.planning"

START=$(date +%s)
trap 'echo "⏱  took $(( $(date +%s) - START ))s" >&2' EXIT

cmd="${1:-sync}"; shift || true

log()  { echo "$@" >&2; }
today() { date +%Y-%m-%d; }

# milestone version from STATE.md / ROADMAP (best-effort), default v1.0
detect_milestone() {
  local v=""
  [ -f "$PLANNING/STATE.md" ] && v=$(grep -ioE 'milestone[_ ]?(version)?:?[ ]*v?[0-9.]+' "$PLANNING/STATE.md" 2>/dev/null | grep -oE 'v?[0-9.]+' | head -1)
  [ -z "$v" ] && [ -f "$PLANNING/ROADMAP.md" ] && v=$(grep -oE 'v[0-9]+\.[0-9]+' "$PLANNING/ROADMAP.md" 2>/dev/null | head -1)
  [ -z "$v" ] && v="v1.0"
  case "$v" in v*) echo "$v" ;; *) echo "v$v" ;; esac
}

# Strip a leading YAML frontmatter block (--- ... ---) if present, emit the body only.
strip_frontmatter() {
  awk 'NR==1 && $0=="---" {fm=1; next} fm==1 && $0=="---" {fm=0; next} fm!=1 {print}' "$1"
}

# Write an Obsidian note: new frontmatter (tags/created/updated/source) + a synced
# callout + the original GSD body (frontmatter stripped). Idempotent (overwrite).
write_note() {
  local src="$1" dest="$2" tags="$3" milestone="$4" phase="$5"
  local rel="${src#"$PROJECT_DIR"/}"
  if [ "$DRY" = "1" ]; then
    log "  would write → ${dest/#$HOME/~}  [tags: $tags]"
    return 0
  fi
  mkdir -p "$(dirname "$dest")"
  local created; created=$(today)
  # preserve original created: if the dest already exists, keep its created date
  if [ -f "$dest" ]; then
    local old; old=$(grep -m1 '^created:' "$dest" 2>/dev/null | sed 's/created:[[:space:]]*//')
    [ -n "$old" ] && created="$old"
  fi
  {
    echo "---"
    echo "tags:"
    local t; IFS=',' read -ra T <<< "$tags"
    for t in "${T[@]}"; do echo "  - $(echo "$t" | tr -d ' ')"; done
    echo "created: $created"
    echo "updated: $(today)"
    echo "gsd_source: $rel"
    echo "gsd_milestone: $milestone"
    [ -n "$phase" ] && echo "gsd_phase: $phase"
    echo "---"
    echo
    echo "> [!info] Synced from GSD by \`gsd-zettel-sync\` — source: \`$rel\`"
    echo "> Durable knowledge mirror; the working copy lives in the repo's \`.planning/\`."
    echo
    strip_frontmatter "$src"
    echo
    echo "---"
    echo "Related: [[MOC - Rescue Serverless]] · [[2026-06-16-gsd-pr-state-second-brain-design]]"
  } > "$dest"
  log "  ✓ wrote → ${dest/#$HOME/~}"
}

phase_slug() { # "01-auth-flow" → keeps as-is for dir; "phase-01" tag
  basename "$1"
}

do_sync() {
  [ -d "$PLANNING" ] || { log "✗ no .planning/ in $PROJECT_DIR — run from a GSD project root."; exit 1; }
  local milestone; milestone=$(detect_milestone)
  local mslug; mslug=$(echo "$milestone" | tr -d '.' | tr 'A-Z' 'a-z')   # v1.0 → v10
  local out_base="$VAULT/gsd/knowledge/$milestone"
  local n=0

  log "→ syncing curated GSD knowledge → ${out_base/#$HOME/~}  (milestone $milestone)"

  # 1) Per-phase LEARNINGS.md (decisions / lessons / patterns / surprises)
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    local pdir; pdir=$(basename "$(dirname "$f")")          # e.g. 01-auth-flow
    local pnum; pnum=$(echo "$pdir" | grep -oE '^[0-9]+' | head -1)
    local dest="$out_base/$pdir/$(basename "$f")"
    write_note "$f" "$dest" "gsd,learnings,rescue,$mslug,phase-${pnum:-NA}" "$milestone" "$pdir" && n=$((n+1))
  done < <(find "$PLANNING/phases" -type f \( -name '*-LEARNINGS.md' -o -name 'LEARNINGS.md' \) 2>/dev/null | sort)

  # 2) Milestone summaries
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    write_note "$f" "$out_base/$(basename "$f")" "gsd,milestone-summary,rescue,$mslug" "$milestone" "" && n=$((n+1))
  done < <(find "$PLANNING/reports" -type f -name 'MILESTONE_SUMMARY-*.md' 2>/dev/null | sort)

  # 3) Roadmap (project map of the milestone)
  if [ -f "$PLANNING/ROADMAP.md" ]; then
    write_note "$PLANNING/ROADMAP.md" "$out_base/ROADMAP.md" "gsd,roadmap,rescue,$mslug" "$milestone" "" && n=$((n+1))
  fi

  if [ "$DRY" = "1" ]; then
    log "→ DRY: $n note(s) would be synced. Nothing written."
  else
    log "✓ synced $n note(s) into the second brain."
    log "  Tags applied: gsd · learnings/milestone-summary/roadmap · rescue · $mslug · phase-NN"
  fi
}

do_context() {
  [ $# -gt 0 ] || { log "usage: gsd-zettel-sync.sh context <keyword...>"; exit 2; }
  local pat; pat=$(printf '%s|' "$@"); pat="${pat%|}"
  log "→ READ: vault notes matching: $*"
  if command -v rg >/dev/null 2>&1; then
    rg -l -i -- "$pat" "$VAULT" 2>/dev/null | head -20
  else
    grep -rilE -- "$pat" "$VAULT" 2>/dev/null | head -20
  fi
}

DRY=0
case "$cmd" in
  sync)            DRY=0; do_sync ;;
  dry|--dry|dry-run) DRY=1; do_sync ;;
  context)         do_context "$@" ;;
  path)            echo "$VAULT/gsd/knowledge/$(detect_milestone)" ;;
  help|-h|--help)
    sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
    ;;
  *) log "unknown command: $cmd (use sync|dry|context|path|help)"; exit 2 ;;
esac
