#!/bin/sh
# tmux status-right helper — cross-platform (Linux + macOS)
# Usage: .tmux-status.sh <segment>
# Segments: cpu, ram, claude, sessions

case "$1" in
cpu)
    load=$(uptime | awk -F'load average: ' '{print $2}' | cut -d, -f1 | tr -d ' ')
    printf "%s" "$load"
    ;;
ram)
    if command -v free >/dev/null 2>&1; then
        free | awk '/Mem:/ {printf "%.0f%%", $3/$2*100}'
    elif command -v vm_stat >/dev/null 2>&1; then
        # macOS: parse vm_stat pages (page size 16384 on ARM, 4096 on Intel)
        page_size=$(sysctl -n hw.pagesize 2>/dev/null || echo 4096)
        total=$(sysctl -n hw.memsize 2>/dev/null || echo 0)
        free_pages=$(vm_stat | awk '/Pages free/ {gsub(/\./,"",$3); print $3}')
        inactive_pages=$(vm_stat | awk '/Pages inactive/ {gsub(/\./,"",$3); print $3}')
        free_bytes=$(( (${free_pages:-0} + ${inactive_pages:-0}) * page_size ))
        used_pct=$(awk "BEGIN {printf \"%.0f%%\", (1 - $free_bytes/$total) * 100}")
        printf "%s" "$used_pct"
    else
        printf "?"
    fi
    ;;
claude)
    # Running claude processes (exact match to avoid false positives)
    count=$(pgrep -x claude 2>/dev/null | wc -l | tr -d ' ')
    if [ "$count" -gt 0 ]; then
        # 5h usage from cache
        cache="/tmp/claude/statusline-usage-cache.json"
        if [ -f "$cache" ]; then
            pct=$(jq -r '.five_hour.utilization // empty' "$cache" 2>/dev/null)
            if [ -n "$pct" ] && [ "$pct" != "null" ]; then
                pct_fmt=$(printf "%.0f" "$pct")
                printf "%s|5h:%s%%" "$count" "$pct_fmt"
                exit 0
            fi
        fi
        printf "%s" "$count"
    fi
    ;;
sessions)
    tmux list-sessions 2>/dev/null | wc -l | tr -d ' '
    ;;
claude-state)
    # Detect claude state in a specific pane: working / waiting / none
    # Usage: .tmux-status.sh claude-state %<pane_id>
    pane_id="$2"
    [ -z "$pane_id" ] && printf "none" && exit 0

    fg=$(tmux display-message -t "$pane_id" -p '#{pane_current_command}' 2>/dev/null)
    if [ "$fg" != "claude" ]; then
        printf "none"
        exit 0
    fi

    # Capture last 3 lines — look for the input prompt (❯ or >)
    last=$(tmux capture-pane -t "$pane_id" -p -S -3 -E -1 2>/dev/null)
    case "$last" in
        *❯*|*\>*) printf "waiting" ;;
        *)         printf "working" ;;
    esac
    ;;
claude-uptime)
    # Session duration of claude process in a pane
    # Usage: .tmux-status.sh claude-uptime %<pane_id>
    pane_id="$2"
    [ -z "$pane_id" ] && exit 0

    pane_pid=$(tmux display-message -t "$pane_id" -p '#{pane_pid}' 2>/dev/null)
    [ -z "$pane_pid" ] && exit 0

    claude_pid=$(pgrep -P "$pane_pid" -x claude 2>/dev/null | head -1)
    [ -z "$claude_pid" ] && exit 0

    # Cross-platform elapsed time
    if elapsed=$(ps -o etimes= -p "$claude_pid" 2>/dev/null | tr -d ' '); then
        : # Linux: etimes gives seconds
    elif etime=$(ps -o etime= -p "$claude_pid" 2>/dev/null | tr -d ' '); then
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
        exit 0
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
    ;;
pane-git)
    # Git branch + worktree info for a pane's cwd
    # Usage: .tmux-status.sh pane-git <cwd>
    cwd="$2"
    [ -z "$cwd" ] && exit 0

    branch=$(git -C "$cwd" --no-optional-locks branch --show-current 2>/dev/null)
    [ -z "$branch" ] && exit 0

    # Detect worktree
    git_dir=$(git -C "$cwd" --no-optional-locks rev-parse --git-dir 2>/dev/null)
    common_dir=$(git -C "$cwd" --no-optional-locks rev-parse --git-common-dir 2>/dev/null)
    wt=""
    if [ -n "$git_dir" ] && [ -n "$common_dir" ] && [ "$git_dir" != "$common_dir" ]; then
        wt_name=$(basename "$cwd")
        wt=" [wt:$wt_name]"
    fi

    printf "%s%s" "$branch" "$wt"
    ;;
esac
