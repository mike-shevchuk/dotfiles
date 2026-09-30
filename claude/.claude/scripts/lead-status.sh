#!/bin/bash
# lead-status.sh — collect live fleet state as ONE JSON for the /lead-status report (format A1).
# Read-only: gh, tmux, reminders, df/swap, demo-result. No writes anywhere.
#
# Usage: lead-status.sh [session=b2b]   → JSON on stdout, progress to stderr
set -uo pipefail

SESSION="${1:-b2b}"
REPO=back2back-team/rescue-serverless
STEPS=(code-review simplify dev just-test demo merge)
echo "→ collecting fleet state (session=$SESSION)…" >&2

now=$(date +%H:%M)
disk=$(df -h / | awk 'NR==2{print $4}')
swap=$(sysctl -n vm.swapusage | awk '{print $6"/"$3}')
dev_holder=$(gh pr list -R "$REPO" --label deploy --json number -q '[.[].number]|join(",")' 2>/dev/null)
last_deploy=$(gh run list -R "$REPO" --workflow "0. Backend Infrastructure Deploy" -L 5 \
  --json headSha,headBranch,status,conclusion,updatedAt \
  -q '[.[]|select(.headBranch|endswith("-review")|not)][0]|"\(.headSha[0:9]) \(.headBranch) \(.status) \(.conclusion // "") \(.updatedAt)"' 2>/dev/null)

# ── teammate windows ────────────────────────────────────────────────────
windows="[]"
while IFS='|' read -r idx name; do
  pane=$(tmux capture-pane -p -J -t "$SESSION:$idx" -S -60 2>/dev/null)
  busy=$(tmux capture-pane -p -t "$SESSION:$idx" 2>/dev/null | grep -cE '…\s*\(|Running|running PreToolUse' || true)
  last=$(grep -E '^⏺ ' <<<"$pane" | tail -1 | cut -c5-220)
  signal=$(grep -vE '^\s*❯' <<<"$pane" | grep -oE '(🙋 (LEAD|MIKE)|STATUS:).*' | tail -1 | cut -c1-220)
  done_at=$(grep -oE 'done [0-9]{1,2}:[0-9]{2} [AP]M' <<<"$pane" | tail -1 | sed 's/done //')
  pr=$(grep -oE '#[0-9]{4}' <<<"$name" | head -1 | tr -d '#')
  windows=$(jq -c --arg i "$idx" --arg n "$name" --arg b "$busy" --arg l "$last" --arg s "$signal" --arg d "$done_at" --arg p "$pr" \
    '. + [{win:($i|tonumber), name:$n, busy:(($b|tonumber)>0), last:$l, signal:$s, idle_since:$d, pr:($p|if .=="" then null else tonumber end)}]' <<<"$windows")
done < <(tmux list-windows -t "$SESSION" -F '#I|#W' 2>/dev/null | grep -vE '\|(⚪lead|⌨️mike|📊fleet)')

# ── open PRs (mine) with pipeline stamps, JT, demo gate ─────────────────
prs="[]"
while IFS='|' read -r num branch draft mergeable title; do
  [ -z "$num" ] && continue
  pf="/tmp/claude/pipeline-${branch//\//-}.json"
  stamps=$( [ -f "$pf" ] && jq -c '[.steps|to_entries[]|select(.value.done)|.key]' "$pf" || echo '[]')
  jt=$(gh pr view "$num" -R "$REPO" --json comments -q '[.comments[].body|select(test("End-to-end smoke trace|API for the frontend"))]|length' 2>/dev/null || echo 0)
  demo=$(~/.claude/demo-result.sh check "$num" 2>&1 | head -1)
  labels=$(gh pr view "$num" -R "$REPO" --json labels -q '[.labels[].name]|join(",")' 2>/dev/null)
  prs=$(jq -c --arg n "$num" --arg b "$branch" --arg d "$draft" --arg m "$mergeable" --arg t "$title" \
    --argjson s "$stamps" --arg j "$jt" --arg demo "$demo" --arg lb "$labels" '
    . + [{pr:($n|tonumber), branch:$b, title:$t, draft:($d=="true"), mergeable:$m, labels:$lb,
          cr:($s|index("code-review")!=null), smp:($s|index("simplify")!=null),
          jt:(($j|tonumber)>0 or ($s|index("just-test")!=null)),
          demo_ok:($demo|startswith("✓")), demo:$demo,
          linear:(($t|scan("PUN-[0-9]+")) // null)}]' <<<"$prs")
done < <(gh pr list -R "$REPO" --author @me --state open --json number,headRefName,isDraft,mergeable,title \
          -q '.[]|"\(.number)|\(.headRefName)|\(.isDraft)|\(.mergeable)|\(.title)"' 2>/dev/null)

reminders=$(~/.claude/reminders.sh list 2>/dev/null | jq -R -s -c 'split("\n")|map(select(length>0))')
queue=$(cat ~/.claude/fleet-board/dev-queue.md 2>/dev/null | jq -R -s -c .)

jq -n --arg now "$now" --arg disk "$disk" --arg swap "$swap" --arg dev "$dev_holder" --arg deploy "$last_deploy" \
  --argjson w "$windows" --argjson p "$prs" --argjson r "$reminders" --argjson q "$queue" \
  '{now:$now, dev_holder:$dev, last_deploy:$deploy, disk:$disk, swap:$swap, windows:$w, prs:$p, reminders:$r, dev_queue:$q}'
echo "  OK ($(jq length <<<"$prs") PRs, $(jq length <<<"$windows") windows)" >&2
