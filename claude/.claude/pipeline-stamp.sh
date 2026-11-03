#!/bin/bash
# pipeline-stamp.sh — read/write the per-branch PR-pipeline state file that the
# `/pr-state` command builds and the statusline renders as compact badges.
#
# State lives at ~/.claude/pipeline-state/pipeline-<sanitized-branch>.json (durable:
# survives a reboot). Every write is mirrored to /tmp/claude/ for older readers. Keyed by
# git BRANCH, so every worktree on the same branch shares one state file.
# Override the dir with PIPELINE_STATE_DIR.
#
# Schema:
#   { "branch": "card-zone-clamp", "pr": 1535, "updated": "<iso>",
#     "steps": { "code-review": {"done": true, "ts": "<iso>", "src": "marker", "head": "<sha>"},
#                "simplify":    {"done": true, "ts": "<iso>", "src": "commit:abc", "head": "abc"},
#                ... } }
#
# Known steps (badge order on the statusline): code-review simplify review-pr just-test
# just-fe demo  (+ brainstorm pr-summary merged, not shown as badges)
#
# Usage:
#   pipeline-stamp.sh stamp <step> [src] [pr]   # mark step done = now
#   pipeline-stamp.sh unstamp <step>            # clear a step
#   pipeline-stamp.sh set-pr <pr>               # record the PR number
#   pipeline-stamp.sh detect                    # stamp code-review/simplify from commit subjects (src=heuristic)
#   pipeline-stamp.sh gates [only=N]            # /pr-state all: ONE table, one verdict per PR, 10 gates (scripts/pr-gates.py)
#   pipeline-stamp.sh fleet [days=3]            # one row per open PR of mine (both repos) + recent local-only branches
#   pipeline-stamp.sh refresh-pr                # force-refresh the statusline PR/bugbot cache (no TTL)
#   pipeline-stamp.sh migrate                   # copy /tmp/claude/pipeline-*.json into the durable dir (also runs on every call)
#   pipeline-stamp.sh path | show | branch
#
# Teammate one-liners (run in the PR worktree):
#   after /code-review:  ~/.claude/pipeline-stamp.sh stamp code-review commit:$(git rev-parse --short HEAD)
#   after /simplify:     ~/.claude/pipeline-stamp.sh stamp simplify commit:$(git rev-parse --short HEAD)
#
# `src` is a free-text provenance tag (marker | commit:<sha> | pr-comment | heuristic).
set -euo pipefail

cmd="${1:-show}"
step="${2:-}"
arg3="${3:-}"
arg4="${4:-}"

dir="${PIPELINE_STATE_DIR:-$HOME/.claude/pipeline-state}"
mirror="/tmp/claude"
mkdir -p "$dir" "$mirror"

# One-time (idempotent) rescue of state written before the durable dir existed: copy a
# /tmp file only when the durable copy is missing, so a durable stamp is never overwritten.
for f in "$mirror"/pipeline-*.json; do
  [ -f "$f" ] && [ ! -f "$dir/${f##*/}" ] && cp "$f" "$dir/"
done

# Resolve the current git branch (worktree-aware) and sanitize for a filename.
branch=$(git -C "$PWD" --no-optional-locks branch --show-current 2>/dev/null || true)
[ -z "$branch" ] && branch="_detached"
# Key = branch for rescue-serverless (legacy), "<repo>--<branch>" for any other repo: the same branch name in two repos
# (wf-alert-room: rescue #2370 + engine WE#77) used to share one file, so one repo's stamps showed on the other's PR.
repo_name() { local c; c=$(git -C "${1:-$PWD}" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || { echo ""; return; }; basename "$(dirname "$c")"; }
state_file() { local b="$1" r="${2-$(repo_name)}" k; k="${b//\//-}"; case "$r" in ""|rescue-serverless) ;; *) k="$r--$k" ;; esac; echo "$dir/pipeline-$k.json"; }
file=$(state_file "$branch")

iso_now() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

ensure_file() {
  if [ ! -f "$file" ]; then
    printf '{"branch":"%s","pr":null,"updated":"%s","steps":{}}\n' \
      "$branch" "$(iso_now)" > "$file"
  fi
}

# Atomic write from a jq filter, then mirror to /tmp for readers that still look there.
jq_write() {
  local tmp="${file}.tmp"
  jq "$@" "$file" > "$tmp" && mv "$tmp" "$file"
  cp "$file" "$mirror/"
}

stamp_step() {  # stamp_step <step> <src> [pr]
  local s="$1" src="$2" pr="${3:-}" anchor
  ensure_file
  # Anchor commit for staleness ("how many commits ago was this check?").
  # src=commit:<sha> pins the anchor to that sha; otherwise anchor = HEAD now.
  case "$src" in
    commit:*|heuristic:commit:*) anchor="${src##*commit:}" ;;
    *)        anchor=$(git -C "$PWD" --no-optional-locks rev-parse --short HEAD 2>/dev/null || true) ;;
  esac
  jq_write --arg s "$s" --arg ts "$(iso_now)" --arg src "$src" --arg pr "$pr" --arg head "$anchor" '
     .steps[$s] = {done: true, ts: $ts, src: $src, head: $head}
     | .updated = $ts
     | (if ($pr != "") then .pr = ($pr|tonumber) else . end)'
  echo "✓ stamped '$s' (src=$src head=$anchor) → $file" >&2
}

# ── fleet helpers ──────────────────────────────────────────────────────────────
# Local clone for each GitHub repo (worktrees of a clone share its objects).
repo_root() {
  case "$1" in
    back2back-team/rescue-serverless) echo "$HOME/code/b2b/rescue-serverless" ;;
    back2back-team/workflow-engine)   echo "$HOME/code/b2b/workflow-engine" ;;
  esac
}

linear_id() {  # PUN-1872 from the title, else from the branch (pun-1872-…)
  local t
  t=$(grep -oE '[A-Z]{2,5}-[0-9]+' <<<"$1" | head -1 || true)
  [ -z "$t" ] && t=$(grep -oiE '(pun|eng)-[0-9]+' <<<"$2" | head -1 | tr '[:lower:]' '[:upper:]' || true)
  echo "${t:--}"
}

# Fields are never empty: bash `read` with IFS=$'\t' collapses empty TSV fields and shifts columns.
# Badge for one step: ✓ fresh · ✓-N stale by N commits · · pending · ✓? anchor unknown locally.
badge() {  # badge <state file> <step> <label> <repo root> <head sha>
  local f="$1" s="$2" label="$3" root="$4" head="$5" is_done anchor ago
  is_done=$( [ -f "$f" ] && jq -r --arg s "$s" '.steps[$s].done // false' "$f" || echo false)
  [ "$is_done" != true ] && { printf '%s·' "$label"; return; }
  anchor=$(jq -r --arg s "$s" '.steps[$s].head // ""' "$f")
  ago=""
  # Own commits only: merging main into the branch does not make a check stale.
  [ -n "$anchor" ] && [ -n "$head" ] && ago=$(git -C "$root" rev-list --count --first-parent --no-merges "${anchor}..${head}" 2>/dev/null || true)
  # Anchor gone (rebased / force-pushed / other clone): count own commits newer than the stamp time instead.
  if [ -z "$ago" ] && [ -n "$head" ]; then
    local ts; ts=$(jq -r --arg s "$s" '.steps[$s].ts // ""' "$f")
    [ -n "$ts" ] && ago=$(git -C "$root" rev-list --count --first-parent --no-merges --since="$ts" "$head" 2>/dev/null || true)
  fi
  if [ -z "$ago" ]; then printf '%s✓?' "$label"
  elif [ "$ago" -gt 0 ]; then printf '%s✓-%s' "$label" "$ago"
  else printf '%s✓' "$label"; fi
}

# GitHub computes mergeability lazily: the first read after a push/merge returns UNKNOWN and triggers the job.
mergeable_retry() {  # mergeable_retry <repo> <pr> <current> → settled value (or UNKNOWN after 3 tries)
  local repo="$1" pr="$2" m="$3" i
  for i in 1 2 3; do
    case "$m" in UNKNOWN|"?"|"") ;; *) break ;; esac
    sleep 2
    m=$(gh pr view "$pr" -R "$repo" --json mergeable -q .mergeable 2>/dev/null || echo UNKNOWN)
  done
  echo "${m:-?}"
}

try_of() {  # try_of <pr> → its try recipe: newest sprint preflight-map.tsv, else the last demo-result, else "no-try"
  local map r; map=$(ls -d ~/.claude/fleet-board/w*/preflight-map.tsv 2>/dev/null | sort -V | tail -1)
  [ -n "$map" ] && r=$(awk -F'\t' -v n="$1" '$1==n {print $2; exit}' "$map")
  [ -z "$r" ] || [ "$r" = "—" ] && r=$(jq -r '.recipe // empty' ~/.claude/demo-results/pr-"$1".json 2>/dev/null)
  echo "${r:-no-try}"
}

worktree_of() {  # worktree_of <repo root> <branch> → path or empty
  git -C "$1" worktree list --porcelain 2>/dev/null | awk -v b="refs/heads/$2" '
    /^worktree /{p=substr($0,10)} $0=="branch " b && !f {print p; f=1}'  # no early exit: SIGPIPE + pipefail killed fleet
}

_fleet_rows() {
  local days=3 a only=""
  for a in "$@"; do case "$a" in days=*) days="${a#days=}" ;; only=*) only="${a#only=}" ;; esac; done
  local repos="back2back-team/rescue-serverless back2back-team/workflow-engine"
  local seen=" "
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "PR" "LINEAR" "CR SMP JT FE" "BEHIND" "CI" "TRY pre/mike" "MERGEABLE" "DEPLOY" "TRAIN" "LOCAL+"
  for repo in $repos; do
    local root; root=$(repo_root "$repo")
    [ -d "$root" ] || { echo "  (no local clone for $repo — skipped)" >&2; continue; }
    git -C "$root" fetch -q origin 2>/dev/null || true   # one fetch per repo: main + every PR branch
    local prs
    # heavy query (comments + checks) hits transient GraphQL 502s → retry, never silently show "no PRs"
    local try_n
    if [ -n "$only" ]; then   # single PR (pr-state <N>): one gh call, no table-wide query
      prs=$(gh pr view "$only" -R "$repo" --json number,title,headRefName,headRefOid,mergeable,labels,statusCheckRollup,comments,state 2>/dev/null \
        | jq -c 'select(.state=="OPEN") | [.]' || true)
      [ -n "$prs" ] || prs='[]'
    else
    for try_n in 1 2 3; do
      prs=$(gh pr list -R "$repo" --author @me --state open \
        --json number,title,headRefName,headRefOid,mergeable,labels,statusCheckRollup,comments) && break
      echo "  ⚠ gh pr list -R $repo failed (try $try_n/3)" >&2; prs=""; sleep $((try_n * 3))
    done
    [ -n "$prs" ] || { echo "  FAIL gh pr list -R $repo — open PRs of this repo are MISSING from the table" >&2; prs='[]'; }
    fi
    # fd 3: commands inside the loop (demo-result.sh, git) read stdin and used to swallow the remaining rows
    while IFS=$'\t' read -r num title br head mergeable labels ci jt fe <&3; do
      [ -z "$num" ] && continue
      seen+="$br "
      mergeable=$(mergeable_retry "$repo" "$num" "$mergeable")
      local f; f=$(state_file "$br" "${repo##*/}")
      local cr smp jtb feb
      cr=$(badge "$f" code-review CR "$root" "$head"); smp=$(badge "$f" simplify SMP "$root" "$head")
      jtb=$(badge "$f" just-test JT "$root" "$head"); feb=$(badge "$f" just-fe FE "$root" "$head")
      # A posted JT / FE comment counts even when nobody stamped it.
      case "$jtb" in JT·) [ "$jt" -gt 0 ] && jtb="JT✓c" ;; esac
      case "$feb" in FE·) [ "$fe" -gt 0 ] && feb="FE✓c" ;; esac
      local behind; behind=$(git -C "$root" rev-list --count "${head}..origin/main" 2>/dev/null || echo "?")
      local demo="-/-" pre mike
      if [ "$repo" = back2back-team/rescue-serverless ]; then
        pre=$(~/.claude/demo-result.sh check "$num" --preflight >/dev/null 2>&1 && echo "✓" || echo "·")
        mike=$(~/.claude/demo-result.sh check "$num" >/dev/null 2>&1 && echo "✓" || echo "·")
        demo="$(try_of "$num") $pre/$mike"
        [ "$mike" = "✓" ] && demo="$demo merge"   # Mike approved, PR still open → the next action is the merge
      fi
      local deploy="·"; grep -qw deploy <<<"$labels" && deploy="🚀"
      local train; train=$(git -C "$root" branch -r --contains "$head" 2>/dev/null | grep -c 'origin/train' || true)
      [ "${train:-0}" -gt 0 ] && train="yes" || train="·"
      local wt local_ahead="·"; wt=$(worktree_of "$root" "$br")
      [ -n "$wt" ] && local_ahead=$(git -C "$wt" rev-list --count "origin/${br}..HEAD" 2>/dev/null || echo "?")
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "#$num ${repo##*/}" "$(linear_id "$title" "$br")" "$cr $smp $jtb $feb" "$behind" "$ci" "$demo" \
        "${mergeable:-?}" "$deploy" "$train" "$local_ahead"
    done 3< <(jq -r '.[] | [
        .number, .title, .headRefName, .headRefOid, (.mergeable // "?"),
        ([.labels[].name] | join(",") | if . == "" then "-" else . end),
        ([.statusCheckRollup[]? | (.conclusion // .state // .status // "")] as $c
          | "✓\([$c[]|select(.=="SUCCESS")]|length) ✗\([$c[]|select(.=="FAILURE" or .=="TIMED_OUT" or .=="CANCELLED")]|length) ⏳\([$c[]|select(.=="IN_PROGRESS" or .=="QUEUED" or .=="PENDING")]|length) ↷\([$c[]|select(.=="SKIPPED" or .=="NEUTRAL")]|length)"),
        ([.comments[].body | select(test("End-to-end smoke trace|/just-test|Smoke trace|smoke trace"; "i"))] | length),
        ([.comments[].body | select(test("API for the frontend|FE hand-off|/just-fe|Frontend hand-off"; "i"))] | length)
      ] | @tsv' <<<"$prs")

    [ -n "$only" ] && continue
    # Branches whose PR is already merged/closed: one query per repo → "branch<TAB>epoch of merge/close".
    local gone; gone=$(gh pr list -R "$repo" --state all -L 200 --json headRefName,state,mergedAt,closedAt \
      -q '.[] | select(.state!="OPEN") | [.headRefName, ((.mergedAt // .closedAt) | fromdateiso8601)] | @tsv' 2>/dev/null || true)
    # Local-only: worktree branches with no open PR, ahead of main, touched in the last $days days.
    local since; since=$(( $(date +%s) - days * 86400 ))
    while read -r wt wbr; do
      [ -z "$wbr" ] && continue
      case "$seen" in *" $wbr "*) continue ;; esac
      case "$wbr" in main|train-*|worktree-agent-*) continue ;; esac
      local ts; ts=$(git -C "$wt" log -1 --format=%ct 2>/dev/null || echo 0)
      # PR merged/closed and nothing committed after it → not local-only work any more
      local gts; gts=$(awk -F'\t' -v b="$wbr" '$1==b && $2>m {m=$2} END{print m+0}' <<<"$gone")
      [ "$gts" -gt 0 ] && [ "$ts" -le "$gts" ] && continue
      [ "$ts" -lt "$since" ] && continue
      local ahead; ahead=$(git -C "$wt" rev-list --count origin/main..HEAD 2>/dev/null || echo 0)
      [ "$ahead" -eq 0 ] && continue
      local head f; head=$(git -C "$wt" rev-parse HEAD); f=$(state_file "$wbr" "${repo##*/}")
      local cr smp jtb feb behind upstream
      cr=$(badge "$f" code-review CR "$root" "$head"); smp=$(badge "$f" simplify SMP "$root" "$head")
      jtb=$(badge "$f" just-test JT "$root" "$head"); feb=$(badge "$f" just-fe FE "$root" "$head")
      behind=$(git -C "$wt" rev-list --count HEAD..origin/main 2>/dev/null || echo "?")
      upstream=$(git -C "$wt" rev-list --count "origin/${wbr}..HEAD" 2>/dev/null || echo "$ahead (no origin)")
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "— ${repo##*/}" "$(linear_id "" "$wbr")" "$cr $smp $jtb $feb" "$behind" "no PR" "-" "-" "·" "·" "$upstream  ($wbr)"
    done < <(git -C "$root" worktree list --porcelain 2>/dev/null | awk '/^worktree /{p=substr($0,10)} /^branch /{sub("refs/heads/","",$2); print p, $2}')
  done
}

fleet() {
  _fleet_rows "$@" | column -t -s $'\t'
  echo
  echo "legend: ✓ fresh · ✓-N N own commits after the check · ✓c comment posted, not stamped · ✓? anchor not in the local clone · · pending" >&2
  echo "        CI ✓ ok ✗ failed/cancelled ⏳ running ↷ skipped" >&2
  echo "        TRY pre/mike = try recipe · agent preflight / Mike's approval (demo-result.sh check [--preflight]) · LOCAL+ = local commits not on origin" >&2
}

case "$cmd" in
  path)    echo "$file" ;;
  branch)  echo "$branch" ;;
  migrate) ls "$dir"/pipeline-*.json 2>/dev/null | wc -l | xargs -I{} echo "✓ {} state file(s) in $dir" >&2 ;;
  show)
    [ -f "$file" ] && jq '.' "$file" 2>/dev/null || echo "{}  (no pipeline state for branch '$branch')"
    ;;
  stamp)
    [ -z "$step" ] && { echo "usage: pipeline-stamp.sh stamp <step> [src] [pr]" >&2; exit 2; }
    stamp_step "$step" "${arg3:-marker}" "$arg4"
    ;;
  unstamp)
    [ -z "$step" ] && { echo "usage: pipeline-stamp.sh unstamp <step>" >&2; exit 2; }
    ensure_file
    jq_write --arg s "$step" --arg up "$(iso_now)" 'del(.steps[$s]) | .updated = $up'
    echo "✓ cleared '$step'" >&2
    ;;
  set-pr)
    ensure_file
    pr="${2:-}"
    [ -z "$pr" ] && { echo "usage: pipeline-stamp.sh set-pr <pr>" >&2; exit 2; }
    jq_write --arg pr "$pr" --arg up "$(iso_now)" '.pr = ($pr|tonumber) | .updated = $up'
    echo "✓ pr=$pr" >&2
    ;;
  detect)
    # Heuristic stamps from commit subjects on origin/main..HEAD (newest match wins). Never
    # overwrites a manual/evidence stamp that is at least as recent as the matched commit.
    shopt -s nocasematch
    for s in simplify code-review; do
      case "$s" in
        simplify)    rx='^(refactor|simplify)|simplif' ;;
        code-review) rx='review fixes|from code-review|code-review|review-fix|^fix[^:]*: .*review' ;;
      esac
      sha=""
      while IFS=$'\t' read -r h subj; do
        [[ "$subj" =~ ^Merge ]] && continue
        [[ "$subj" =~ $rx ]] && { sha="$h"; break; }
      done < <(git -C "$PWD" --no-optional-locks log --format='%h%x09%s' origin/main..HEAD 2>/dev/null)
      [ -z "$sha" ] && { echo "· $s: no matching commit subject" >&2; continue; }
      cur=$( [ -f "$file" ] && jq -r --arg s "$s" '.steps[$s].head // ""' "$file" || true)
      cur_src=$( [ -f "$file" ] && jq -r --arg s "$s" '.steps[$s].src // ""' "$file" || true)
      # A real stamp (command / commit: / pr-comment) always beats a guess; a heuristic one is only
      # replaced by a newer match.
      if [ -n "$cur_src" ] && [[ "$cur_src" != heuristic:* ]]; then
        echo "· $s: stamped by evidence (src=$cur_src) — heuristic skipped" >&2; continue
      fi
      if [ -n "$cur" ] && git -C "$PWD" merge-base --is-ancestor "$sha" "$cur" 2>/dev/null; then
        echo "· $s: already stamped at $cur (newer or equal)" >&2; continue
      fi
      stamp_step "$s" "heuristic:commit:$sha"
    done
    shopt -u nocasematch
    ;;
  fleet) shift; fleet "$@" ;;
  gates) shift; _fleet_rows "$@" | python3 ~/.claude/scripts/pr-gates.py ;;   # /pr-state all: one verdict per PR (pr-gates.py)
  try) shift; try_of "$1" ;;
  pr-state)  # pr-state [all|<PR>] [--compact]   (--compact: ≤3 plain lines, silent on any failure → safe for try-doc)
    shift; ps_arg=""; compact=""
    for a in "$@"; do case "$a" in --compact) compact=1 ;; *) ps_arg="$a" ;; esac; done
    if [ -n "$compact" ]; then exec 2>/dev/null; command -v gh >/dev/null 2>&1 || exit 0; fi
    if [ -z "$ps_arg" ] || [ "$ps_arg" = all ]; then fleet; exit 0; fi
    ps_arg="${ps_arg#\#}"
    row=$(_fleet_rows "only=$ps_arg" 2>/dev/null | sed -n '2p' || true)
    if [ -z "$row" ]; then
      st=$(gh pr view "$ps_arg" -R back2back-team/rescue-serverless --json state -q .state 2>/dev/null || true)
      [ -n "$compact" ] && { [ -n "$st" ] && echo "🧭 PR #$ps_arg: $st — nothing to track"; exit 0; }
      echo "PR #$ps_arg: ${st:-not found (or gh unavailable)} — not an open PR of mine"; exit 0
    fi
    IFS=$'\t' read -r c_pr c_lin c_bdg c_beh c_ci c_demo c_mrg c_dep c_trn c_loc <<<"$row"
    # next actions, most urgent first, max 3
    todo=()
    [ "$c_mrg" = CONFLICTING ] && todo+=("conflict with main → merge origin/main, resolve, re-run checks")
    case "$c_ci" in *"✗0"*) ;; *) todo+=("CI has failures → open the PR checks and fix") ;; esac
    case "$c_bdg" in *CR·*|*CR✓-*|*CR✓\?*) todo+=("/code-review (${c_bdg%% *})") ;; esac
    case "$c_bdg" in *SMP·*|*SMP✓-*) todo+=("/simplify") ;; esac
    case "$c_bdg" in *JT·*|*JT✓-*) todo+=("/just-test (JT stale or missing)") ;; esac
    case "$c_bdg" in *FE·*|*FE✓-*) todo+=("/just-fe if the FE needs this API") ;; esac
    case "$c_demo" in "✓/✓"*) ;; "✓/·"*) todo+=("preflight ✓ → Mike runs the try, then merge") ;; *) todo+=("try/preflight not done → jb2b <topic>-try") ;; esac
    [ "${c_beh:-0}" != "?" ] && [ "${c_beh:-0}" -gt 20 ] 2>/dev/null && todo+=("${c_beh} behind main → jb2b pull-main")
    if [ -n "$compact" ]; then
      echo "🧭 $c_pr $c_lin · $c_bdg · behind $c_beh · CI $c_ci · DEMO $c_demo · $c_mrg"
      [ ${#todo[@]} -gt 0 ] && echo "   → ${todo[0]}${todo[1]:+ · ${todo[1]}}" || echo "   → nothing pending"
      exit 0
    fi
    { printf '%s\n' "PR|LINEAR|CR SMP JT FE|BEHIND|CI|DEMO pre/mike|MERGEABLE"; printf '%s\n' "$c_pr|$c_lin|$c_bdg|$c_beh|$c_ci|$c_demo|$c_mrg"; } | column -t -s '|'
    echo; echo "what to do:"
    if [ ${#todo[@]} -eq 0 ]; then echo "  • nothing pending — all gates fresh"; else
      for i in 0 1 2; do [ -n "${todo[$i]:-}" ] && echo "  • ${todo[$i]}"; done; fi
    ;;
  refresh-pr)
    # Force-refresh the statusline PR/bugbot cache the SAME way statusline.sh does
    # (lines "number|state|isDraft|mirror|bugbot"), bypassing its 120s TTL. This is
    # the half /pr-state could not touch before — set-pr only writes the pipeline
    # JSON; the PR badge + 🐛 count live in /tmp/claude/pr-cache-<cwd>.txt.
    if ! command -v gh >/dev/null 2>&1; then
      echo "refresh-pr: gh not found — skipped" >&2; exit 0
    fi
    rp_cwd="${2:-$PWD}"
    git -C "$rp_cwd" fetch -q origin 2>/dev/null || true   # fresh origin/* so anchors and "behind" are current
    pr_number=""; pr_state=""; pr_isdraft=""; pr_mirror=""; pr_bugbot=""; pr_bugsha=""; pr_bugurl=""; pr_nwo=""; pr_mergeable=""
    pr_json=$(cd "$rp_cwd" && gh pr view --json number,state,isDraft,mergeable 2>/dev/null || true)
    if [ -z "$pr_json" ]; then
      rb=$(cd "$rp_cwd" && git branch -r --points-at HEAD 2>/dev/null | grep -v '/HEAD' | sed 's|^ *origin/||' | head -1)
      [ -n "$rb" ] && pr_json=$(cd "$rp_cwd" && gh pr view "$rb" --json number,state,isDraft,mergeable 2>/dev/null || true)
    fi
    if [ -n "$pr_json" ]; then
      pr_number=$(echo "$pr_json" | jq -r '.number // ""')
      pr_state=$(echo "$pr_json" | jq -r '.state // ""')
      pr_isdraft=$(echo "$pr_json" | jq -r '.isDraft // false')
      pr_mergeable=$(echo "$pr_json" | jq -r '.mergeable // ""')
      if [ "$pr_state" = OPEN ] && [ -n "$pr_number" ]; then
        pr_mergeable=$(cd "$rp_cwd" && mergeable_retry "$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)" "$pr_number" "$pr_mergeable")
      fi
      if [ -n "$pr_number" ] && [ "$pr_number" != "null" ]; then
        pr_nwo=$(cd "$rp_cwd" && gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || true)
        _nwo="$pr_nwo"
        _mt=$(cd "$rp_cwd" && gh pr view $((pr_number + 1)) --json title --jq '.title' 2>/dev/null || true)
        case "$_mt" in REVIEW:*) pr_mirror=$((pr_number + 1)) ;; esac
        if [ -n "$pr_mirror" ]; then
          if [ -n "$_nwo" ]; then
            # count of unresolved+un-reacted threads AND the newest one's commit sha
            _bb=$(cd "$rp_cwd" && gh api graphql -f query="query{repository(owner:\"${_nwo%/*}\",name:\"${_nwo#*/}\"){pullRequest(number:${pr_mirror}){reviewThreads(first:100){nodes{isResolved comments(first:1){nodes{originalCommit{abbreviatedOid} reactions(first:20){nodes{user{login}}}}}}}}}}" \
              --jq '[.data.repository.pullRequest.reviewThreads.nodes[]|select(.isResolved|not)|select([.comments.nodes[0].reactions.nodes[]?.user.login]|index("mike-shevchuk")|not)|(.comments.nodes[0].originalCommit.abbreviatedOid // "")]' 2>/dev/null || true)
            if [ -n "$_bb" ]; then
              pr_bugbot=$(echo "$_bb" | jq 'length' 2>/dev/null || true)
              pr_bugsha=$(echo "$_bb" | jq -r '.[-1] // ""' 2>/dev/null || true)
            fi
            [ -n "$pr_bugbot" ] && [ "$pr_bugbot" -gt 0 ] 2>/dev/null && pr_bugurl="https://github.com/${_nwo}/pull/${pr_mirror}"
          fi
        fi
      fi
    fi
    line="${pr_number}|${pr_state}|${pr_isdraft}|${pr_mirror}|${pr_bugbot}|${pr_bugsha}|${pr_bugurl}|${pr_nwo}|${pr_mergeable}"
    # Write the cache for this cwd AND every existing subdir cache under it, so a
    # session sitting in any subdirectory of the worktree sees the fresh value too.
    canon=$(cd "$rp_cwd" 2>/dev/null && pwd -P || echo "$rp_cwd")
    prefix="/tmp/claude/pr-cache-${canon//\//-}"
    printf '%s\n' "$line" > "${prefix}.txt"
    count=1
    for f in "${prefix}"*.txt; do
      [ "$f" = "${prefix}.txt" ] && continue
      [ -f "$f" ] && { printf '%s\n' "$line" > "$f"; count=$((count + 1)); }
    done
    # Caches regenerate on demand; drop the ones untouched >1 day (removed worktrees, merged PRs) so they stop hanging.
    pruned=0
    for f in $(find /tmp/claude -maxdepth 1 -name 'pr-cache-*.txt' -mtime +1 2>/dev/null); do rm -f "$f"; pruned=$((pruned + 1)); done
    echo "✓ pr-cache refreshed: ${line}  (${count} file(s) under ${canon}; pruned ${pruned} stale)" >&2
    ;;
  *)
    echo "unknown command: $cmd (use stamp|unstamp|set-pr|detect|fleet|refresh-pr|migrate|path|show|branch)" >&2
    exit 2
    ;;
esac
