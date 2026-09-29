#!/bin/bash
# demo-result.sh — record and verify a PR demo run (the DEMO gate of /pr-state).
#
# Every PR demo recipe (`jb2b <topic>-try`) calls `write` at its RESULT box.
# The lead calls `check` before telling Mike a PR is merge-ready.
#
# Result file: ~/.claude/demo-results/pr-<N>.json
#   {pr, branch, recipe, passed, failed, secs, operator, dev_sha, pr_head, finished}
# On a clean pass it also stamps step `demo` in /tmp/claude/pipeline-<branch>.json
# (anchored to the dev SHA the demo actually ran against).
#
# Usage:
#   demo-result.sh write <pr> <recipe> <passed> <failed> <secs>
#   demo-result.sh check <pr>     # exit 0 = fresh pass on the PR's current head
#   demo-result.sh show  <pr>
set -euo pipefail

REPO=back2back-team/rescue-serverless
DIR="$HOME/.claude/demo-results"
mkdir -p "$DIR" /tmp/claude
cmd="${1:-}"; pr="${2:-}"
[ -z "$cmd" ] || [ -z "$pr" ] && { sed -n '14,17p' "$0" >&2; exit 2; }
file="$DIR/pr-$pr.json"

# Last successful dev deploy = the build the demo really exercised.
dev_sha() {
  gh run list -R "$REPO" --workflow "0. Backend Infrastructure Deploy" -L 20 \
    --json headSha,conclusion,updatedAt \
    -q '[.[]|select(.conclusion=="success")]|sort_by(.updatedAt)|last|.headSha // ""' 2>/dev/null || true
}

case "$cmd" in
  write)
    recipe="${3:?recipe}"; passed="${4:?passed}"; failed="${5:?failed}"; secs="${6:-0}"
    meta=$(gh pr view "$pr" -R "$REPO" --json headRefName,headRefOid 2>/dev/null || echo '{}')
    branch=$(jq -r '.headRefName // ""' <<<"$meta"); head=$(jq -r '.headRefOid // ""' <<<"$meta")
    win=$(tmux display -p '#W' 2>/dev/null || echo "?")
    case "$win" in *mike*) operator=mike ;; *) operator=agent ;; esac
    operator="${DEMO_OPERATOR:-$operator}"
    dsha=$(dev_sha)
    jq -n --arg pr "$pr" --arg b "$branch" --arg r "$recipe" --arg p "$passed" --arg f "$failed" \
      --arg s "$secs" --arg o "$operator" --arg d "$dsha" --arg h "$head" \
      --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      '{pr:($pr|tonumber),branch:$b,recipe:$r,passed:($p|tonumber),failed:($f|tonumber),secs:($s|tonumber),
        operator:$o,dev_sha:$d,pr_head:$h,finished:$t}' > "$file"
    echo "━━━ demo-result ━━━  PR #$pr · $recipe · $passed passed / $failed failed · operator=$operator · dev=${dsha:0:9} → $file" >&2
    if [ "$failed" = "0" ] && [ -n "$branch" ]; then
      pf="/tmp/claude/pipeline-${branch//\//-}.json"
      [ -f "$pf" ] || printf '{"branch":"%s","pr":%s,"updated":"","steps":{}}\n' "$branch" "$pr" > "$pf"
      jq --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg src "demo:$recipe:$operator" --arg h "${dsha:0:9}" \
        '.steps.demo={done:true,ts:$ts,src:$src,head:$h} | .updated=$ts' "$pf" > "$pf.tmp" && mv "$pf.tmp" "$pf"
      echo "  ✓ stamped DEMO on $branch (head ${dsha:0:9})" >&2
    else
      echo "  ✗ DEMO not stamped (failed=$failed)" >&2
    fi
    ;;
  show)
    [ -f "$file" ] && jq . "$file" || { echo "no demo result for PR #$pr" >&2; exit 1; }
    ;;
  check)
    [ -f "$file" ] || { echo "✗ DEMO: no run recorded for PR #$pr — run its jb2b <topic>-try" >&2; exit 1; }
    failed=$(jq -r .failed "$file"); dsha=$(jq -r .dev_sha "$file")
    [ "$failed" = "0" ] || { echo "✗ DEMO: last run failed ($failed)" >&2; exit 1; }
    now=$(gh pr view "$pr" -R "$REPO" --json headRefOid -q .headRefOid)
    # Fresh = no non-merge commits between the demoed build and the PR head.
    ahead=$(gh api "repos/$REPO/compare/$dsha...$now" -q '[.commits[]|select(.parents|length==1)]|length' 2>/dev/null || echo "?")
    if [ "$ahead" = "0" ]; then
      echo "✓ DEMO: $(jq -r '"\(.passed) passed · \(.operator) · \(.finished) · dev \(.dev_sha[0:9])"' "$file")" >&2
    else
      echo "✗ DEMO stale: $ahead non-merge commit(s) after the demoed build ${dsha:0:9} — re-run the demo" >&2; exit 1
    fi
    ;;
  *) sed -n '14,17p' "$0" >&2; exit 2 ;;
esac
