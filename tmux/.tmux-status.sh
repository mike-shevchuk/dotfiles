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
#   refresh-pane [cwd]        → set @pane_git @pane_python @pane_path
#   pane-meta <pane_id> <cwd> → one pre-formatted pane-border string (1 call/pane)
#   cpu ram claude sessions   → print a single global value
#   claude-state <pane_id>    → working | waiting | none
#   claude-uptime <pane_id>   → human elapsed time of the claude process
#   pane-git <cwd>            → branch (+ [wt:name] for worktrees)
#   pane-python <cwd>         → python version (mise → pyenv), empty if none

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
    # branch (+ [wt:name] when in a linked worktree) for a cwd
    cwd="$1"
    [ -z "$cwd" ] && return 0
    [ -d "$cwd" ] || return 0
    branch=$(git -C "$cwd" --no-optional-locks branch --show-current 2>/dev/null)
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
    cwd="$2"
    [ -z "$cwd" ] && cwd=$(tmux display-message -p '#{pane_current_path}' 2>/dev/null)
    _git=$(get_git "$cwd")
    _py=$(get_python "$cwd")
    tmux set -g @pane_git "$_git" \; \
         set -g @pane_python "$_py" \; \
         set -g @pane_path "$cwd" 2>/dev/null
    ;;
pane-meta)
    # Single pre-formatted border string per visible pane (was ~4 #() calls).
    # Output carries #[...] style escapes, which tmux interprets in #() output.
    pane_id="$2"
    cwd="$3"
    cmd=$(tmux display-message -t "$pane_id" -p '#{pane_current_command}' 2>/dev/null)
    _git=$(get_git "$cwd")
    _py=$(get_python "$cwd")
    if [ "$cmd" = "claude" ]; then
        if [ "$(get_claude_state "$pane_id")" = "waiting" ]; then
            printf '#[fg=#a6e3a1]󰚩 ready'
        else
            printf '#[fg=#f9e2af]󰚩 thinking'
        fi
        printf ' #[fg=#6c7086]│ ⏱ %s │ %s' "$(get_claude_uptime "$pane_id")" "$cwd"
    else
        printf '#[fg=#6c7086]%s │ %s' "$cmd" "$cwd"
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
esac
