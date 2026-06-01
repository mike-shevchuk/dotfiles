#!/bin/sh
# tmux status helper — cross-platform (Linux + macOS), POSIX sh only.
#
# Usage: .tmux-status.sh <segment> [args]
#
# Two kinds of segments:
#   * "refresh-*" — side-effect only. Compute values ONCE and stash them in
#     tmux user-options (@cpu, @pane_git, …). The status format strings then
#     read #{@cpu} etc. with ZERO subprocesses per redraw. This is the same
#     pattern gpakosz's base config uses for @battery_percentage.
#   * value segments (cpu, ram, …) — print a value to stdout. Kept for direct
#     testing and ad-hoc use; the live config no longer calls them per redraw.
#
# Segments:
#   refresh-global            → set @cpu @ram @claude @sessions @aws @kube
#   refresh-pane [cwd]        → set @pane_git @pane_python @pane_pr @pane_path
#   pane-meta <pane_id> <cwd> → one pre-formatted pane-border string (1 call/pane)
#   cpu ram claude sessions   → print a single global value
#   claude-state <pane_id>    → working | waiting | none
#   claude-uptime <pane_id>   → human elapsed time of the claude process
#   pane-git <cwd>            → branch (+ [wt:name] for worktrees)
#   pane-python <cwd>         → python version (mise → pyenv), empty if none
#   pr <cwd>                  → 🔀 PR#N <icon> for the branch (gh, cached 90s)
#   short-path <cwd>          → ~/d/.c/w/tmux  (fish-style compact path)

# ─── value helpers ───────────────────────────────────────────────────────────

get_cpu() {
    # Linux: "load average: 0.52, 0.58, 0.59"
    # macOS: "load averages: 2.41 2.43 2.12"  (plural, space-separated)
    # Strip everything up to the label, then keep the first number only.
    uptime | sed -E 's/.*load averages?:[[:space:]]*//; s/[, ].*//'
}

get_ram() {
    if command -v free >/dev/null 2>&1; then
        free | awk '/Mem:/ {printf "%.0f%%", $3/$2*100}'
    elif command -v vm_stat >/dev/null 2>&1; then
        # macOS: parse vm_stat pages (page size 16384 on ARM, 4096 on Intel)
        page_size=$(sysctl -n hw.pagesize 2>/dev/null || echo 4096)
        total=$(sysctl -n hw.memsize 2>/dev/null || echo 0)
        [ "$total" -eq 0 ] 2>/dev/null && { printf "?"; return; }
        # one vm_stat call: sum free + inactive pages in a single awk pass
        free_pages=$(vm_stat | awk '
            /Pages free/     {gsub(/\./,"",$3); f=$3}
            /Pages inactive/ {gsub(/\./,"",$3); i=$3}
            END {print f + i}')
        free_bytes=$(( ${free_pages:-0} * page_size ))
        awk "BEGIN {printf \"%.0f%%\", (1 - $free_bytes/$total) * 100}"
    else
        printf "?"
    fi
}

get_claude() {
    # Running claude processes (exact match to avoid false positives)
    count=$(pgrep -x claude 2>/dev/null | wc -l | tr -d ' ')
    [ "${count:-0}" -gt 0 ] || return 0
    # Append 5h usage from cache when available: "2|5h:45%"
    cache="/tmp/claude/statusline-usage-cache.json"
    if [ -f "$cache" ] && command -v jq >/dev/null 2>&1; then
        pct=$(jq -r '.five_hour.utilization // empty' "$cache" 2>/dev/null)
        if [ -n "$pct" ] && [ "$pct" != "null" ]; then
            printf "%s|5h:%.0f%%" "$count" "$pct"
            return 0
        fi
    fi
    printf "%s" "$count"
}

get_sessions() {
    tmux list-sessions 2>/dev/null | wc -l | tr -d ' '
}

get_aws() {
    # tmux server env — same scope as the previous #(printenv AWS_PROFILE)
    printf "%s" "${AWS_PROFILE:-}"
}

get_kube() {
    command -v kubectl >/dev/null 2>&1 || return 0
    kubectl config current-context 2>/dev/null
}

get_claude_state() {
    # working / waiting / none for a specific pane
    pane_id="$1"
    [ -z "$pane_id" ] && { printf "none"; return; }
    fg=$(tmux display-message -t "$pane_id" -p '#{pane_current_command}' 2>/dev/null)
    if [ "$fg" != "claude" ]; then
        printf "none"; return
    fi
    # Look at the last few lines for the input prompt (❯ or >)
    last=$(tmux capture-pane -t "$pane_id" -p -S -3 -E -1 2>/dev/null)
    case "$last" in
        *❯*) printf "waiting" ;;
        *)   printf "working" ;;
    esac
}

get_claude_uptime() {
    # human elapsed time of the claude process running under a pane
    pane_id="$1"
    [ -z "$pane_id" ] && return 0
    pane_pid=$(tmux display-message -t "$pane_id" -p '#{pane_pid}' 2>/dev/null)
    [ -z "$pane_pid" ] && return 0
    claude_pid=$(pgrep -P "$pane_pid" -x claude 2>/dev/null | head -1)
    [ -z "$claude_pid" ] && return 0

    if elapsed=$(ps -o etimes= -p "$claude_pid" 2>/dev/null | tr -d ' ') && [ -n "$elapsed" ]; then
        : # Linux: etimes gives seconds directly
    elif etime=$(ps -o etime= -p "$claude_pid" 2>/dev/null | tr -d ' ') && [ -n "$etime" ]; then
        # macOS: etime gives [[dd-]hh:]mm:ss — convert to seconds
        elapsed=0
        case "$etime" in
            *-*)
                days="${etime%%-*}"
                etime="${etime#*-}"
                elapsed=$((days * 86400))
                ;;
        esac
        IFS=: read -r p1 p2 p3 <<EOF
$etime
EOF
        if [ -n "$p3" ]; then
            elapsed=$((elapsed + p1 * 3600 + p2 * 60 + p3))
        else
            elapsed=$((elapsed + p1 * 60 + p2))
        fi
    else
        return 0
    fi

    if [ "$elapsed" -lt 60 ]; then
        printf "%ds" "$elapsed"
    elif [ "$elapsed" -lt 3600 ]; then
        printf "%dm" "$((elapsed / 60))"
    elif [ "$elapsed" -lt 86400 ]; then
        h=$((elapsed / 3600))
        m=$(( (elapsed % 3600) / 60 ))
        [ "$m" -gt 0 ] && printf "%dh%dm" "$h" "$m" || printf "%dh" "$h"
    else
        printf "%dd%dh" "$((elapsed / 86400))" "$(( (elapsed % 86400) / 3600 ))"
    fi
}

get_git() {
    # branch (+ [wt:name] when in a linked worktree) for a cwd.
    # Usage: get_git <cwd> [branch]   (pass branch to avoid a duplicate git call)
    cwd="$1"
    [ -z "$cwd" ] && return 0
    [ -d "$cwd" ] || return 0
    branch="$2"
    [ -z "$branch" ] && branch=$(git -C "$cwd" --no-optional-locks branch --show-current 2>/dev/null)
    [ -z "$branch" ] && return 0
    git_dir=$(git -C "$cwd" --no-optional-locks rev-parse --git-dir 2>/dev/null)
    common_dir=$(git -C "$cwd" --no-optional-locks rev-parse --git-common-dir 2>/dev/null)
    if [ -n "$git_dir" ] && [ -n "$common_dir" ] && [ "$git_dir" != "$common_dir" ]; then
        printf "%s [wt:%s]" "$branch" "$(basename "$cwd")"
    else
        printf "%s" "$branch"
    fi
}

get_python() {
    # python version for a cwd: mise (preferred) → pyenv. Empty when no
    # project tool-config is found in the ancestry (so the segment hides).
    cwd="$1"
    [ -z "$cwd" ] && return 0
    [ -d "$cwd" ] || return 0

    if command -v mise >/dev/null 2>&1; then
        d="$cwd"
        while [ -n "$d" ] && [ "$d" != "/" ]; do
            if [ -f "$d/.mise.toml" ] || [ -f "$d/mise.toml" ] || [ -f "$d/.tool-versions" ]; then
                ver=$(cd "$cwd" 2>/dev/null && mise current python 2>/dev/null | head -1 | tr -d ' ')
                [ -n "$ver" ] && { printf "%s" "$ver"; return 0; }
                break
            fi
            d=$(dirname "$d")
        done
    fi

    if command -v pyenv >/dev/null 2>&1; then
        d="$cwd"
        while [ -n "$d" ] && [ "$d" != "/" ]; do
            if [ -f "$d/.python-version" ]; then
                ver=$(cd "$cwd" 2>/dev/null && pyenv version-name 2>/dev/null)
                [ -n "$ver" ] && { printf "%s" "$ver"; return 0; }
                break
            fi
            d=$(dirname "$d")
        done
    fi
}

shorten_path() {
    # Compact a path for the status bar without making it cryptic: $HOME → ~,
    # keep full directory NAMES, and only elide the MIDDLE when the path is long
    # (more than 3 components after ~/root), keeping the parent + current dir:
    #   /Users/me/dotfiles/.claude/worktrees/tmux → ~/…/worktrees/tmux
    #   ~/dotfiles/foo                            → ~/dotfiles/foo   (left as-is)
    #   /usr/local/bin                            → /usr/local/bin   (left as-is)
    p="$1"
    [ -z "$p" ] && return 0
    [ "$p" = "/" ] && { printf '/'; return 0; }
    case "$p" in
        "$HOME")    printf '~'; return 0 ;;
        "$HOME"/*)  p="~/${p#"$HOME"/}" ;;
    esac
    case "$p" in
        '~/'*) pfx='~/'; body="${p#'~/'}" ;;
        /*)    pfx='/';  body="${p#/}" ;;   # absolute, non-home
        *)     pfx='';   body="$p" ;;       # relative
    esac
    # Short enough (≤3 components) → leave it readable in full.
    n=$(printf '%s\n' "$body" | tr '/' '\n' | grep -c .)
    if [ "${n:-0}" -le 3 ]; then
        printf '%s' "$p"
        return 0
    fi
    # Long → keep the last two components, elide the rest with …
    last1="${body##*/}"
    rest="${body%/*}"
    last2="${rest##*/}"
    printf '%s…/%s/%s' "$pfx" "$last2" "$last1"
}

get_pr() {
    # PR number + a compact status icon for a cwd's branch.
    #   🔀 PR#26 ✓   (✓ pass · ✗ fail · ● open/pending · ⊘ merged/closed)
    # Cached in /tmp/claude — same cache dir + mtime-TTL pattern the Claude Code
    # statusline uses (claude/.claude/statusline.sh). gh is ~0.7s + network +
    # rate-limited, so we only call it when the cache is older than 90s.
    #
    # CONTRACT: on a cache miss this BLOCKS for the duration of the gh call
    # (~0.7s). Call it only from background contexts (run-shell -b) — never from
    # a synchronous #() in status/pane-border-format, or it stalls the redraw.
    #
    # Usage: get_pr <cwd> [branch]   (pass branch to avoid a duplicate git call)
    cwd="$1"
    [ -z "$cwd" ] && return 0
    [ -d "$cwd" ] || return 0
    command -v gh >/dev/null 2>&1 || return 0

    branch="$2"
    [ -z "$branch" ] && branch=$(git -C "$cwd" --no-optional-locks branch --show-current 2>/dev/null)
    [ -z "$branch" ] && return 0

    dir=/tmp/claude
    mkdir -p "$dir" 2>/dev/null
    root=$(git -C "$cwd" --no-optional-locks rev-parse --show-toplevel 2>/dev/null)
    # Only fold path separators + spaces into '_'; keep ':'/'.' distinct so
    # different repos/branches can't collide onto one cache file.
    key=$(printf '%s:%s' "$root" "$branch" | tr '/ ' '__')
    cache="$dir/tmux-pr-$key.txt"

    # Fresh cache (TTL 90s) → serve without touching the network.
    if [ -f "$cache" ]; then
        mtime=$(stat -c %Y "$cache" 2>/dev/null || stat -f %m "$cache" 2>/dev/null)
        if [ -n "$mtime" ] && [ "$(( $(date +%s) - mtime ))" -lt 90 ]; then
            cat "$cache"
            return 0
        fi
    fi

    # Stale/missing → fetch once, classify, cache the formatted string. We cache
    # even an empty result so "no PR" branches don't refetch on every focus.
    json=$(cd "$cwd" 2>/dev/null && gh pr view --json number,state,statusCheckRollup,reviewDecision 2>/dev/null)
    out=""
    if [ -n "$json" ]; then
        out=$(printf '%s' "$json" | jq -r '
            if .number then
              "🔀 PR#\(.number) " +
              ( if .state != "OPEN" then "⊘"
                else
                  ( reduce (.statusCheckRollup[]? | (.conclusion // .state // "")) as $c
                      ({fail:false, pend:false, any:false};
                       { fail: (.fail or ($c == "FAILURE" or $c == "ERROR" or $c == "CANCELLED" or $c == "TIMED_OUT")),
                         pend: (.pend or ($c == "PENDING" or $c == "IN_PROGRESS" or $c == "QUEUED" or $c == "")),
                         any:  true }) ) as $s
                  | if   $s.fail then "✗"
                    elif $s.pend then "●"
                    elif $s.any  then "✓"
                    elif .reviewDecision == "APPROVED" then "✓"
                    else "●" end
                end )
            else empty end' 2>/dev/null)
    fi
    # Unique temp per process ($$) so concurrent background refreshes for the
    # same branch can't clobber a shared temp mid-write.
    tmp="$cache.$$"
    printf '%s' "$out" > "$tmp" 2>/dev/null && mv "$tmp" "$cache" 2>/dev/null
    printf '%s' "$out"
}

# ─── dispatch ────────────────────────────────────────────────────────────────

case "$1" in
refresh-global)
    # One subprocess per status-interval instead of ~10. Compute everything,
    # then push to user-options in a single tmux invocation.
    _cpu=$(get_cpu)
    _ram=$(get_ram)
    _claude=$(get_claude)
    _sessions=$(get_sessions)
    _aws=$(get_aws)
    _kube=$(get_kube)
    tmux set -g @cpu "$_cpu" \; \
         set -g @ram "$_ram" \; \
         set -g @claude "$_claude" \; \
         set -g @sessions "$_sessions" \; \
         set -g @aws "$_aws" \; \
         set -g @kube "$_kube" 2>/dev/null
    # no stdout: used as a side-effect-only #() trigger
    ;;
refresh-pane)
    # Active-pane context. Triggered by focus/select hooks, NOT every redraw.
    # get_pr only hits the network when its 90s cache is stale; this whole
    # segment runs under `run-shell -b`, so even that never blocks the UI.
    cwd="$2"
    [ -z "$cwd" ] && cwd=$(tmux display-message -p '#{pane_current_path}' 2>/dev/null)
    # Resolve the branch once and share it with get_git + get_pr.
    _branch=$(git -C "$cwd" --no-optional-locks branch --show-current 2>/dev/null)
    _git=$(get_git "$cwd" "$_branch")
    _py=$(get_python "$cwd")
    _pr=$(get_pr "$cwd" "$_branch")
    _path=$(shorten_path "$cwd")
    tmux set -g @pane_git "$_git" \; \
         set -g @pane_python "$_py" \; \
         set -g @pane_pr "$_pr" \; \
         set -g @pane_path "$_path" 2>/dev/null
    ;;
pane-meta)
    # Single pre-formatted border string per visible pane (was ~4 #() calls).
    # Output carries #[...] style escapes, which tmux interprets in #() output.
    pane_id="$2"
    cwd="$3"
    cmd=$(tmux display-message -t "$pane_id" -p '#{pane_current_command}' 2>/dev/null)
    _git=$(get_git "$cwd")
    _py=$(get_python "$cwd")
    _path=$(shorten_path "$cwd")
    if [ "$cmd" = "claude" ]; then
        if [ "$(get_claude_state "$pane_id")" = "waiting" ]; then
            printf '#[fg=#a6e3a1]󰚩 ready'
        else
            printf '#[fg=#f9e2af]󰚩 thinking'
        fi
        printf ' #[fg=#6c7086]│ ⏱ %s │ %s' "$(get_claude_uptime "$pane_id")" "$_path"
    else
        printf '#[fg=#6c7086]%s │ %s' "$cmd" "$_path"
    fi
    [ -n "$_git" ] && printf ' #[fg=#a6e3a1]🌿 %s' "$_git"
    [ -n "$_py" ] && printf ' #[fg=#f9e2af]🐍 %s' "$_py"
    printf ' '
    ;;
cpu)           get_cpu ;;
ram)           get_ram ;;
claude)        get_claude ;;
sessions)      get_sessions ;;
claude-state)  get_claude_state "$2" ;;
claude-uptime) get_claude_uptime "$2" ;;
pane-git)      get_git "$2" ;;
pane-python)   get_python "$2" ;;
pr)            get_pr "$2" ;;
short-path)    shorten_path "$2" ;;
esac
