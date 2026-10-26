#!/bin/bash
# demo-result.sh — record and verify a PR demo run (the DEMO gate of /pr-state).
#
# Every PR demo recipe (`jb2b <topic>-try`) calls `write` at its RESULT box.
# The lead calls `check` before telling Mike a PR is merge-ready.
#
# Two records per PR (Mike 2026-09-30: DEMO = HIS approval, an agent run is only a preflight):
#   ~/.claude/demo-results/pr-<N>.json       agent preflight (lead/teammate, yes=1 or a non-Mike tmux window)
#   ~/.claude/demo-results/pr-<N>.mike.json  Mike's run + his explicit "approve" (gum confirm at the RESULT box)
#   {pr, branch, recipe, passed, failed, secs, operator, approved, dev_sha, pr_head, finished}
# Only Mike's approved clean run stamps step `demo` in /tmp/claude/pipeline-<branch>.json.
#
# Usage:
#   demo-result.sh write <pr> <recipe> <passed> <failed> <secs>
#   demo-result.sh check <pr>              # merge gate: Mike approved a fresh clean run
#   demo-result.sh check <pr> --preflight  # lead gate before handing to Mike: fresh clean agent run
#   demo-result.sh show  <pr>
set -euo pipefail

REPO=back2back-team/rescue-serverless
DIR="${DEMO_RESULT_DIR:-$HOME/.claude/demo-results}"   # override = selftest only
mkdir -p "$DIR" /tmp/claude
cmd="${1:-}"; pr="${2:-}"
[ -z "$cmd" ] || [ -z "$pr" ] && { sed -n '14,17p' "$0" >&2; exit 2; }
agent_file="$DIR/pr-$pr.json"; mike_file="$DIR/pr-$pr.mike.json"
# Key eng-<N> = workflow-engine PR #N (its build = the last successful engine-dev deploy); plain <N> = rescue-serverless.
num="$pr"; LOCAL="$HOME/code/b2b/rescue-serverless"; DEPLOY_WF="0. Backend Infrastructure Deploy"
if [[ "$pr" =~ ^eng-([0-9]+)$ ]]; then
  num="${BASH_REMATCH[1]}"; REPO=back2back-team/workflow-engine; LOCAL="$HOME/code/b2b/workflow-engine"; DEPLOY_WF="0. Deploy Backend (dev)"
fi

# Last successful dev deploy = the build the demo really exercised.
dev_sha() {
  gh run list -R "$REPO" --workflow "$DEPLOY_WF" -L 20 \
    --json headSha,conclusion,updatedAt \
    -q '[.[]|select(.conclusion=="success")]|sort_by(.updatedAt)|last|.headSha // ""' 2>/dev/null || true
}

case "$cmd" in
  write)
    recipe="${3:?recipe}"; passed="${4:?passed}"; failed="${5:?failed}"; secs="${6:-0}"
    # jb2b <try> step=N / steps=A-B: a partial run is never a preflight nor an approval (lead 2026-10-14)
    if [ -n "${TRY_PART_ACTIVE:-}" ]; then echo "━━━ demo-result ━━━  PR #$num · $recipe · окремі кроки (${TRY_PART_SEL:-?}) → НЕ записано: часткова проба — не апрув" >&2; exit 0; fi
    meta=$(gh pr view "$num" -R "$REPO" --json headRefName,headRefOid 2>/dev/null || echo '{}')
    branch=$(jq -r '.headRefName // ""' <<<"$meta"); head=$(jq -r '.headRefOid // ""' <<<"$meta")
    # Mike = outside tmux or in his ⌨️mike window, with a terminal; yes=1 / any other window = agent.
    operator=mike
    if [ -n "${TMUX_PANE:-}" ]; then
      case "$(tmux display -p -t "$TMUX_PANE" '#W' 2>/dev/null)" in *mike*) ;; *) operator=agent ;; esac
    fi
    [ -n "${TRY_YES:-}" ] && [ "${TRY_YES}" != 0 ] && operator=agent
    { : </dev/tty; } 2>/dev/null || operator=agent
    operator="${DEMO_OPERATOR:-$operator}"
    # unproven Pn "…" mike: a step only Mike can prove — an agent preflight records it apart (mike_pending), Mike's run must prove it (lead 2026-10-15)
    mp="${TRY_MIKE_PENDING:-0}"; [ "$operator" = agent ] && [ "$mp" -gt 0 ] 2>/dev/null && failed=$(( failed > mp ? failed - mp : 0 ))
    [ "$operator" = mike ] && mp=0
    approved=false
    if [ "$operator" = mike ] && [ "$failed" = "0" ]; then
      # stray focus/ESC bytes in the tty buffer made gum cancel instantly → approved=false without Mike answering (2026-10-13)
      perl -MPOSIX -e 'POSIX::tcflush(0, POSIX::TCIFLUSH)' </dev/tty 2>/dev/null || true
      printf "\n  👉 Enter = Так (апрув) · n = Ні\n" >/dev/tty
      gum confirm --default=true --affirmative "Так (Enter)" --negative "Ні (n)" "Апрув #$pr: демо пройшло і ти перевірив — можна мерджити?" </dev/tty >/dev/tty 2>/dev/tty; grc=$?
      if [ $grc -eq 0 ]; then approved=true
      elif [ $grc -ne 1 ]; then   # cancelled / error, not «Ні» → ask once more, plain read
        read -r -p "  Апрув #$pr? [Enter = так · n = ні] " ans </dev/tty >/dev/tty 2>&1; case "$ans" in n|N|ні|Ні) ;; *) approved=true ;; esac
      fi
    fi
    file=$agent_file; [ "$operator" = mike ] && file=$mike_file
    dsha=$(dev_sha)
    jq -n --arg pr "$pr" --arg b "$branch" --arg r "$recipe" --arg p "$passed" --arg f "$failed" \
      --arg s "$secs" --arg mp "${mp:-0}" --arg o "$operator" --arg d "$dsha" --arg h "$head" --arg k "${TRY_KIND:-gate}" \
      --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --argjson a "$approved" \
      '{pr:($pr|tonumber? // $pr),branch:$b,recipe:$r,passed:($p|tonumber),failed:($f|tonumber),mike_pending:($mp|tonumber),secs:($s|tonumber),
        operator:$o,approved:$a,kind:$k,dev_sha:$d,pr_head:$h,finished:$t}' > "$file"
    echo "━━━ demo-result ━━━  PR #$pr · $recipe · $passed passed / $failed failed$([ "${mp:-0}" -gt 0 ] && echo " · чекає Mike: $mp") · operator=$operator · dev=${dsha:0:9} → $file" >&2
    if [ "$operator" = agent ]; then
      echo "  ℹ preflight recorded (agent) — DEMO waits for Mike's own run + approve" >&2
    elif [ "$approved" = true ] && [ -n "$branch" ]; then
      pf="/tmp/claude/pipeline-${branch//\//-}.json"
      [ -f "$pf" ] || printf '{"branch":"%s","pr":%s,"updated":"","steps":{}}\n' "$branch" "$num" > "$pf"
      jq --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg src "demo:$recipe:$operator" --arg h "${dsha:0:9}" \
        '.steps.demo={done:true,ts:$ts,src:$src,head:$h} | .updated=$ts' "$pf" > "$pf.tmp" && mv "$pf.tmp" "$pf"
      echo "  ✓ stamped DEMO on $branch (head ${dsha:0:9})" >&2
    else
      echo "  ✗ DEMO not stamped (failed=$failed, approved=$approved)" >&2
    fi
    ;;
  show)
    for f in "$agent_file" "$mike_file"; do [ -f "$f" ] && jq -c . "$f"; done
    [ -f "$agent_file" ] || [ -f "$mike_file" ] || { echo "no demo result for PR #$pr" >&2; exit 1; }
    ;;
  check)
    if [ "${3:-}" = --preflight ]; then file=$agent_file; who="preflight"; else file=$mike_file; who="DEMO (Mike)"; fi
    [ -f "$file" ] || { echo "✗ $who: no run recorded for PR #$pr — $( [ "$file" = "$mike_file" ] && echo "Mike runs jb2b <topic>-try and approves" || echo "run <topic>-try yes=1")" >&2; exit 1; }
    failed=$(jq -r .failed "$file"); dsha=$(jq -r .dev_sha "$file")
    [ "$file" = "$mike_file" ] && [ "$(jq -r '.approved // false' "$file")" != true ] && [ "$failed" = 0 ] && { echo "✗ $who: ran clean but not approved — re-run and answer «так» at the end" >&2; exit 1; }
    [ "$failed" = "0" ] || { echo "✗ $who: last run failed ($failed)" >&2; exit 1; }
    now=$(gh pr view "$num" -R "$REPO" --json headRefOid -q .headRefOid)
    # Fresh = no non-merge commits between the demoed build and the PR head.
    # only the PR's own non-merge commits after the demoed build — commits that arrived via a main merge don't count
    git -C "$LOCAL" fetch -q origin 2>/dev/null
    ahead=$(git -C "$LOCAL" rev-list --no-merges --count "$dsha..$now" --not origin/main 2>/dev/null || echo "?")
    if [ "$ahead" = "0" ]; then
      echo "✓ $who: $(jq -r '"\(.passed) passed · \(.operator) · kind \(.kind // "gate")\(if (.mike_pending // 0) > 0 then " · чекає Mike: \(.mike_pending)" else "" end) · \(.finished) · dev \(.dev_sha[0:9])"' "$file")" >&2
    else
      echo "✗ $who stale: $ahead non-merge commit(s) after the demoed build ${dsha:0:9} — re-run the demo" >&2; exit 1
    fi
    ;;
  *) sed -n '14,17p' "$0" >&2; exit 2 ;;
esac
