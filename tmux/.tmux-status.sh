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
        free_bytes=$(( (free_pages + inactive_pages) * page_size ))
        used_pct=$(awk "BEGIN {printf \"%.0f%%\", (1 - $free_bytes/$total) * 100}")
        printf "%s" "$used_pct"
    else
        printf "?"
    fi
    ;;
claude)
    # Running claude processes
    count=$(pgrep -f "claude" 2>/dev/null | wc -l | tr -d ' ')
    if [ "$count" -gt 0 ]; then
        # 5h usage from cache
        cache="/tmp/claude/statusline-usage-cache.json"
        if [ -f "$cache" ]; then
            pct=$(jq -r '.five_hour.utilization // empty' "$cache" 2>/dev/null)
            if [ -n "$pct" ] && [ "$pct" != "null" ]; then
                pct_fmt=$(printf "%.0f" "$pct")
                printf "%s|%s%%" "$count" "$pct_fmt"
                exit 0
            fi
        fi
        printf "%s" "$count"
    fi
    ;;
sessions)
    tmux list-sessions 2>/dev/null | wc -l | tr -d ' '
    ;;
esac
