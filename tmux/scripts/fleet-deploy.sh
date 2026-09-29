#!/usr/bin/env bash
# fleet-deploy.sh — poll GitHub once and cache a deploy badge per PR number:
#   🚀 deploy run in progress/queued · ❌ latest deploy failed ·
#   🟢 PR has `deploy` label + latest deploy succeeded (= what's on dev).
# Two gh calls total (not per window). Writes "<pr>\t<badge>" lines to the
# cache atomically; on any gh failure keeps the old cache. Spawned in the
# background by fleet-sync.sh when the cache is >60s old.
repo=${FLEET_REPO:-back2back-team/rescue-serverless}
out=~/.claude/fleet-board/deploy.tsv
lock=/tmp/fleet-deploy.lock
# A lock left by a SIGKILLed run would freeze badges forever → expire it after 2 min.
find "$lock" -maxdepth 0 -mmin +2 -exec rmdir {} \; 2>/dev/null
mkdir "$lock" 2>/dev/null || exit 0
trap 'rmdir "$lock"' EXIT
# On gh failure keep the old cache but bump its mtime → fleet-sync backs off 60s
# instead of respawning us every status tick while offline/logged out.
backoff() { mkdir -p "$(dirname "$out")"; touch "$out"; exit 0; }
runs=$(gh run list -R "$repo" --workflow "0. Backend Infrastructure Deploy" --limit 30 \
    --json headBranch,status,conclusion 2>/dev/null) || backoff
prs=$(gh pr list -R "$repo" --state open --limit 100 --json number,headRefName,labels 2>/dev/null) || backoff
jq -rn --argjson runs "$runs" --argjson prs "$prs" '
  $prs[] | .headRefName as $b
  | ([.labels[].name] | index("deploy")) as $lab
  # newest first; the skipped pull_request sibling is not a real deploy
  | ([$runs[] | select(.headBranch == $b and .conclusion != "skipped")][0]) as $r
  | (if $r == null then ""
     elif $r.status != "completed" then "🚀"
     elif ($r.conclusion == "failure" or $r.conclusion == "timed_out") then "❌"
     elif ($lab != null and $r.conclusion == "success") then "🟢"
     else "" end) as $badge
  | select($badge != "") | "\(.number)\t\($badge)"' > "$out.tmp" && mv "$out.tmp" "$out"
