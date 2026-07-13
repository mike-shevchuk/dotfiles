#!/bin/bash
# pipeline-stamp.sh — read/write the per-branch PR-pipeline state file that the
# `/pr-state` command builds and the statusline renders as compact badges.
#
# State lives at /tmp/codex/pipeline-<sanitized-branch>.json (matches the
# statusline's /tmp/codex cache convention). Keyed by git BRANCH, so every
# worktree on the same branch shares one state file.
#
# Schema:
#   { "branch": "card-zone-clamp", "pr": 1535, "updated": "<iso>",
#     "steps": { "code-review": {"done": true, "ts": "<iso>", "src": "marker"},
#                "simplify":    {"done": true, "ts": "<iso>", "src": "commit:abc"},
#                ... } }
#
# Known steps (badge order on the statusline): brainstorm code-review simplify
# review-pr just-test pr-summary merged
#
# Usage:
#   pipeline-stamp.sh stamp <step> [src] [pr]   # mark step done = now
#   pipeline-stamp.sh unstamp <step>            # clear a step
#   pipeline-stamp.sh set-pr <pr>               # record the PR number
#   pipeline-stamp.sh refresh-pr                # force-refresh the statusline PR/bugbot cache (no TTL)
#   pipeline-stamp.sh path                      # print the state file path
#   pipeline-stamp.sh show                      # cat the JSON (pretty)
#   pipeline-stamp.sh branch                    # print the resolved branch
#
# `src` is a free-text provenance tag (marker | commit:<sha> | pr-comment | heuristic).
set -euo pipefail

cmd="${1:-show}"
step="${2:-}"
arg3="${3:-}"
arg4="${4:-}"

# Resolve the current git branch (worktree-aware) and sanitize for a filename.
branch=$(git -C "$PWD" --no-optional-locks branch --show-current 2>/dev/null || true)
[ -z "$branch" ] && branch="_detached"
safe_branch="${branch//\//-}"

dir="/tmp/codex"
mkdir -p "$dir"
file="$dir/pipeline-${safe_branch}.json"

iso_now() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

ensure_file() {
  if [ ! -f "$file" ]; then
    printf '{"branch":"%s","pr":null,"updated":"%s","steps":{}}\n' \
      "$branch" "$(iso_now)" > "$file"
  fi
}

case "$cmd" in
  path)   echo "$file" ;;
  branch) echo "$branch" ;;
  show)
    [ -f "$file" ] && jq '.' "$file" 2>/dev/null || echo "{}  (no pipeline state for branch '$branch')"
    ;;
  stamp)
    [ -z "$step" ] && { echo "usage: pipeline-stamp.sh stamp <step> [src] [pr]" >&2; exit 2; }
    ensure_file
    src="${arg3:-marker}"
    pr="${arg4:-}"
    # Anchor commit for staleness ("how many commits ago was this check?").
    # src=commit:<sha> pins the anchor to that sha; otherwise anchor = HEAD now.
    case "$src" in
      commit:*) anchor="${src#commit:}" ;;
      *)        anchor=$(git -C "$PWD" --no-optional-locks rev-parse --short HEAD 2>/dev/null || true) ;;
    esac
    tmp="${file}.tmp"
    jq --arg s "$step" --arg ts "$(iso_now)" --arg src "$src" --arg up "$(iso_now)" \
       --arg pr "$pr" --arg head "$anchor" '
       .steps[$s] = {done: true, ts: $ts, src: $src, head: $head}
       | .updated = $up
       | (if ($pr != "") then .pr = ($pr|tonumber) else . end)
    ' "$file" > "$tmp" && mv "$tmp" "$file"
    echo "✓ stamped '$step' (src=$src head=$anchor) → $file" >&2
    ;;
  unstamp)
    [ -z "$step" ] && { echo "usage: pipeline-stamp.sh unstamp <step>" >&2; exit 2; }
    ensure_file
    tmp="${file}.tmp"
    jq --arg s "$step" --arg up "$(iso_now)" 'del(.steps[$s]) | .updated = $up' \
       "$file" > "$tmp" && mv "$tmp" "$file"
    echo "✓ cleared '$step'" >&2
    ;;
  set-pr)
    ensure_file
    pr="${2:-}"
    [ -z "$pr" ] && { echo "usage: pipeline-stamp.sh set-pr <pr>" >&2; exit 2; }
    tmp="${file}.tmp"
    jq --arg pr "$pr" --arg up "$(iso_now)" '.pr = ($pr|tonumber) | .updated = $up' \
       "$file" > "$tmp" && mv "$tmp" "$file"
    echo "✓ pr=$pr" >&2
    ;;
  refresh-pr)
    # Force-refresh the statusline PR/bugbot cache the SAME way statusline.sh does
    # (lines "number|state|isDraft|mirror|bugbot"), bypassing its 120s TTL. This is
    # the half /pr-state could not touch before — set-pr only writes the pipeline
    # JSON; the PR badge + 🐛 count live in /tmp/codex/pr-cache-<cwd>.txt.
    if ! command -v gh >/dev/null 2>&1; then
      echo "refresh-pr: gh not found — skipped" >&2; exit 0
    fi
    rp_cwd="${2:-$PWD}"
    pr_number=""; pr_state=""; pr_isdraft=""; pr_mirror=""; pr_bugbot=""
    pr_json=$(cd "$rp_cwd" && gh pr view --json number,state,isDraft 2>/dev/null || true)
    if [ -z "$pr_json" ]; then
      rb=$(cd "$rp_cwd" && git branch -r --points-at HEAD 2>/dev/null | grep -v '/HEAD' | sed 's|^ *origin/||' | head -1)
      [ -n "$rb" ] && pr_json=$(cd "$rp_cwd" && gh pr view "$rb" --json number,state,isDraft 2>/dev/null || true)
    fi
    if [ -n "$pr_json" ]; then
      pr_number=$(echo "$pr_json" | jq -r '.number // ""')
      pr_state=$(echo "$pr_json" | jq -r '.state // ""')
      pr_isdraft=$(echo "$pr_json" | jq -r '.isDraft // false')
      if [ -n "$pr_number" ] && [ "$pr_number" != "null" ]; then
        _mt=$(cd "$rp_cwd" && gh pr view $((pr_number + 1)) --json title --jq '.title' 2>/dev/null || true)
        case "$_mt" in REVIEW:*) pr_mirror=$((pr_number + 1)) ;; esac
        if [ -n "$pr_mirror" ]; then
          _nwo=$(cd "$rp_cwd" && gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || true)
          [ -n "$_nwo" ] && pr_bugbot=$(cd "$rp_cwd" && gh api graphql -f query="query{repository(owner:\"${_nwo%/*}\",name:\"${_nwo#*/}\"){pullRequest(number:${pr_mirror}){reviewThreads(first:100){nodes{isResolved comments(first:1){nodes{reactions(first:20){nodes{user{login}}}}}}}}}}" \
            --jq '[.data.repository.pullRequest.reviewThreads.nodes[]|select(.isResolved|not)|select([.comments.nodes[0].reactions.nodes[]?.user.login]|index("mike-shevchuk")|not)]|length' 2>/dev/null || true)
        fi
      fi
    fi
    line="${pr_number}|${pr_state}|${pr_isdraft}|${pr_mirror}|${pr_bugbot}"
    # Write the cache for this cwd AND every existing subdir cache under it, so a
    # session sitting in any subdirectory of the worktree sees the fresh value too.
    canon=$(cd "$rp_cwd" 2>/dev/null && pwd -P || echo "$rp_cwd")
    prefix="/tmp/codex/pr-cache-${canon//\//-}"
    printf '%s\n' "$line" > "${prefix}.txt"
    count=1
    for f in "${prefix}"*.txt; do
      [ "$f" = "${prefix}.txt" ] && continue
      [ -f "$f" ] && { printf '%s\n' "$line" > "$f"; count=$((count + 1)); }
    done
    echo "✓ pr-cache refreshed: ${line}  (${count} file(s) under ${canon})" >&2
    ;;
  *)
    echo "unknown command: $cmd (use stamp|unstamp|set-pr|path|show|branch)" >&2
    exit 2
    ;;
esac
