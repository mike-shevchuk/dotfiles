#!/bin/bash
set -f # disable globbing

input=$(cat)

if [ -z "$input" ]; then
  printf "Claude"
  exit 0
fi

now_epoch=$(date +%s)

# ANSI colors matching oh-my-posh theme
blue='\033[38;2;0;153;255m'
orange='\033[38;2;255;176;85m'
green='\033[38;2;0;160;0m'
cyan='\033[38;2;46;149;153m'
red='\033[38;2;255;85;85m'
yellow='\033[38;2;230;200;0m'
white='\033[38;2;220;220;220m'
dim='\033[2m'
reset='\033[0m'

# Format token counts (e.g., 50k / 200k)
format_tokens() {
  local num=$1
  if [ "$num" -ge 1000000 ]; then
    awk "BEGIN {printf \"%.1fm\", $num / 1000000}"
  elif [ "$num" -ge 1000 ]; then
    awk "BEGIN {printf \"%.0fk\", $num / 1000}"
  else
    printf "%d" "$num"
  fi
}

# Build a colored progress bar
# Usage: build_bar <pct> <width>
build_bar() {
  local pct=$1
  local width=$2
  [ "$pct" -lt 0 ] 2>/dev/null && pct=0
  [ "$pct" -gt 100 ] 2>/dev/null && pct=100

  local filled=$((pct * width / 100))
  local empty=$((width - filled))

  # Color based on usage level
  local bar_color
  if [ "$pct" -ge 90 ]; then
    bar_color="$red"
  elif [ "$pct" -ge 70 ]; then
    bar_color="$yellow"
  elif [ "$pct" -ge 50 ]; then
    bar_color="$orange"
  else
    bar_color="$green"
  fi

  local filled_str="" empty_str=""
  for ((i = 0; i < filled; i++)); do filled_str+="●"; done
  for ((i = 0; i < empty; i++)); do empty_str+="○"; done

  printf "${bar_color}${filled_str}${dim}${empty_str}${reset}"
}

# Cross-platform ISO to epoch conversion
iso_to_epoch() {
  local iso_str="$1"

  local epoch
  epoch=$(date -d "${iso_str}" +%s 2>/dev/null)
  if [ -n "$epoch" ]; then
    echo "$epoch"
    return 0
  fi

  local stripped="${iso_str%%.*}"
  stripped="${stripped%%Z}"
  stripped="${stripped%%+*}"
  stripped="${stripped%%-[0-9][0-9]:[0-9][0-9]}"

  if [[ "$iso_str" == *"Z"* ]] || [[ "$iso_str" == *"+00:00"* ]] || [[ "$iso_str" == *"-00:00"* ]]; then
    epoch=$(env TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%S" "$stripped" +%s 2>/dev/null)
  else
    epoch=$(date -j -f "%Y-%m-%dT%H:%M:%S" "$stripped" +%s 2>/dev/null)
  fi

  if [ -n "$epoch" ]; then
    echo "$epoch"
    return 0
  fi

  return 1
}

# Check if a reset time (ISO string) has already passed
is_reset_past() {
  local iso_str="$1"
  [ -z "$iso_str" ] || [ "$iso_str" = "null" ] && return 1
  local epoch
  epoch=$(iso_to_epoch "$iso_str")
  [ -z "$epoch" ] && return 1
  [ "$epoch" -le "$now_epoch" ]
}

# ===== Extract data from JSON =====
model_name=$(echo "$input" | jq -r '.model.display_name // "Claude"')

# Context window
size=$(echo "$input" | jq -r '.context_window.context_window_size // 200000')
[ "$size" -eq 0 ] 2>/dev/null && size=200000

# Token usage
input_tokens=$(echo "$input" | jq -r '.context_window.current_usage.input_tokens // 0')
cache_create=$(echo "$input" | jq -r '.context_window.current_usage.cache_creation_input_tokens // 0')
cache_read=$(echo "$input" | jq -r '.context_window.current_usage.cache_read_input_tokens // 0')
current=$((input_tokens + cache_create + cache_read))

used_tokens=$(format_tokens $current)
total_tokens=$(format_tokens $size)

sep=" ${dim}|${reset} "

# ===== LINE 1: Git info (branch, remote, worktree, dirty, ahead/behind) =====
line1=""

cwd=$(echo "$input" | jq -r '.cwd // empty')
worktree_name=$(echo "$input" | jq -r '.worktree.name // empty')
if [ -n "$cwd" ]; then
  # Resolve repo name — in a worktree, toplevel is the worktree root, not the repo root
  # Use git-common-dir to find the real .git of the main repo
  toplevel=$(git -C "${cwd}" --no-optional-locks rev-parse --show-toplevel 2>/dev/null)
  common_dir=$(git -C "${cwd}" --no-optional-locks rev-parse --git-common-dir 2>/dev/null)
  if [ -n "$common_dir" ]; then
    # Resolve to absolute path (common_dir can be relative)
    abs_common_dir=$(cd "${cwd}" && cd "${common_dir}" 2>/dev/null && pwd)
    abs_git_dir=$(git -C "${cwd}" --no-optional-locks rev-parse --absolute-git-dir 2>/dev/null)
    if [ -n "$abs_common_dir" ] && [ -n "$abs_git_dir" ] && [ "$abs_common_dir" != "$abs_git_dir" ]; then
      # We're in a worktree — repo root is parent of .git common dir
      repo_root="${abs_common_dir%/.git}"
      display_dir="${repo_root##*/}"
    else
      display_dir="${toplevel##*/}"
    fi
  else
    display_dir="${toplevel##*/}"
  fi
  # Fallback
  [ -z "$display_dir" ] && display_dir="${cwd##*/}"

  local_branch=$(git -C "${cwd}" --no-optional-locks branch --show-current 2>/dev/null)
  remote_branch=$(cd "$cwd" && git --no-optional-locks rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null)
  # Reuse common_dir from above to detect worktree
  git_dir=$(git -C "${cwd}" --no-optional-locks rev-parse --git-dir 2>/dev/null)
  if [ -n "$git_dir" ] && [ -n "$common_dir" ] && [ "$git_dir" != "$common_dir" ]; then
    worktree_label=$(basename "$cwd")
  else
    worktree_label="-"
  fi

  if [ -n "$worktree_name" ]; then
    line1+="🌲 ${cyan}${display_dir}${reset}"
  else
    line1+="📁 ${cyan}${display_dir}${reset}"
  fi
  # Local branch
  if [ -n "$local_branch" ]; then
    line1+=" 🌿 ${green}${local_branch}${reset}"
  fi
  # Remote: truncate when same as local, full when different, dim dash when not pushed
  if [ -n "$remote_branch" ]; then
    remote_name="${remote_branch%%/*}"
    remote_branch_name="${remote_branch#*/}"
    if [ "$remote_branch_name" = "$local_branch" ] && [ ${#remote_branch} -gt 30 ]; then
      prefix="${remote_name}/${remote_branch_name:0:8}"
      suffix="${remote_branch_name: -8}"
      line1+=" ${dim}→${reset} ${cyan}${prefix}…${suffix}${reset}"
    else
      line1+=" ${dim}→${reset} ${cyan}${remote_branch}${reset}"
    fi
  else
    line1+=" ${dim}→ --${reset}"
  fi
  # Worktree label
  line1+=" ${dim}[wt:${reset}${orange}${worktree_label}${dim}]${reset}"

  # Git dirty indicator
  dirty_count=$(git -C "${cwd}" --no-optional-locks status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  if [ "$dirty_count" -gt 0 ]; then
    line1+=" ✏️ ${orange}${dirty_count}${reset}"
  else
    line1+=" ✅"
  fi

  # Ahead/behind remote
  ab=$(git -C "${cwd}" --no-optional-locks rev-list --left-right --count HEAD...@{upstream} 2>/dev/null)
  if [ -n "$ab" ]; then
    ahead=$(echo "$ab" | awk '{print $1}')
    behind=$(echo "$ab" | awk '{print $2}')
    if [ "$ahead" -gt 0 ] || [ "$behind" -gt 0 ]; then
      line1+=" ${green}↑${ahead}${reset} ${red}↓${behind}${reset}"
    fi
  fi

  # Last commit age
  last_commit_epoch=$(git -C "${cwd}" --no-optional-locks log -1 --format=%ct 2>/dev/null)
  if [ -n "$last_commit_epoch" ]; then
    age_secs=$((now_epoch - last_commit_epoch))
    if [ "$age_secs" -lt 60 ]; then
      commit_age="just now"
    elif [ "$age_secs" -lt 3600 ]; then
      commit_age="$((age_secs / 60))m ago"
    elif [ "$age_secs" -lt 86400 ]; then
      commit_age="$((age_secs / 3600))h ago"
    else
      commit_age="$((age_secs / 86400))d ago"
    fi
    line1+=" 🕐 ${dim}${commit_age}${reset}"
  fi
fi

# ===== Token usage cache (5h + 7d, async background refresh) =====
# Cache file has 2 lines: line1=5h count, line2=7d count
_tokens_cache="/tmp/claude/tokens-usage.txt"
_tokens_stamp="/tmp/claude/tokens-usage.stamp"
_tokens_script="/tmp/claude/tokens-usage.py"

# Write the Python scanner script once (idempotent)
mkdir -p /tmp/claude
cat > "$_tokens_script" <<'PYEOF'
import json, os, glob
from datetime import datetime, timezone, timedelta
now = datetime.now(timezone.utc)
cut5h  = now - timedelta(hours=5)
cut7d  = now - timedelta(days=7)
t5h, t7d, seen = 0, 0, set()
for path in glob.glob(os.path.expanduser('~/.claude/projects/**/*.jsonl'), recursive=True):
    try:
        with open(path) as f:
            for line in f:
                try:
                    obj = json.loads(line)
                    msg = obj.get('message', {})
                    mid, ts_str = msg.get('id', ''), obj.get('timestamp', '')
                    if not ts_str or not mid or mid in seen: continue
                    ts = datetime.fromisoformat(ts_str.replace('Z', '+00:00'))
                    if ts < cut7d: continue
                    seen.add(mid)
                    u = msg.get('usage', {})
                    toks = u.get('input_tokens', 0) + u.get('output_tokens', 0)
                    t7d += toks
                    if ts >= cut5h: t5h += toks
                except: pass
    except: pass
def fmt(n):
    if n >= 1_000_000: return f'{n/1000000:.1f}M'
    if n >= 1000: return f'{n//1000}k'
    return str(n) if n > 0 else ''
print(fmt(t5h))
print(fmt(t7d))
PYEOF

refresh_tokens_usage() {
  local now_s stamp_val stamp_age=999999
  now_s=$(date +%s)
  if [ -f "$_tokens_stamp" ]; then
    stamp_val=$(cat "$_tokens_stamp" 2>/dev/null)
    stamp_age=$(( now_s - stamp_val ))
  fi
  if [ "$stamp_age" -gt 300 ]; then
    echo "$now_s" > "$_tokens_stamp"
    # Write to tmp then rename — avoids truncating cache to 0 before Python finishes
    ( python3 "$_tokens_script" > "${_tokens_cache}.tmp" 2>/dev/null && mv "${_tokens_cache}.tmp" "$_tokens_cache" ) &
    disown $!
  fi
}

refresh_tokens_usage

# ===== LINE 2: Model | PR | tokens | thinking =====
line2=""
line2+="🤖 ${blue}${model_name}${reset}"

# PR number from git remote (cached to avoid slowdown)
pr_cache_file="/tmp/claude/pr-cache-${cwd//\//-}.txt"
mkdir -p /tmp/claude
pr_cache_max_age=120
needs_pr_refresh=true
pr_number=""
if [ -f "$pr_cache_file" ]; then
  pr_cache_mtime=$(stat -c %Y "$pr_cache_file" 2>/dev/null || stat -f %m "$pr_cache_file" 2>/dev/null)
  pr_cache_age=$((now_epoch - pr_cache_mtime))
  if [ "$pr_cache_age" -lt "$pr_cache_max_age" ]; then
    needs_pr_refresh=false
    pr_number=$(cat "$pr_cache_file" 2>/dev/null)
  fi
fi
if $needs_pr_refresh && [ -n "$cwd" ]; then
  if command -v gh >/dev/null 2>&1; then
    pr_number=$(cd "$cwd" && gh pr view --json number -q '.number' 2>/dev/null || true)
    if [ -z "$pr_number" ] || [ "$pr_number" = "null" ]; then
      pr_remote_branch=$(cd "$cwd" && git branch -r --points-at HEAD 2>/dev/null | grep -v '/HEAD' | sed 's|^ *origin/||' | head -1)
      if [ -n "$pr_remote_branch" ]; then
        pr_number=$(cd "$cwd" && gh pr view "$pr_remote_branch" --json number -q '.number' 2>/dev/null || true)
      fi
    fi
    echo "${pr_number}" > "$pr_cache_file"
  fi
fi
if [ -n "$pr_number" ] && [ "$pr_number" != "null" ]; then
  line2+="${sep}"
  line2+="🔀 ${orange}PR#${pr_number}${reset}"
fi

line2+="${sep}"
line2+="🪙 ${orange}${used_tokens}/${total_tokens}${reset}"

# 5h + 7d session token counts (from async Python cache)
if [ -f "$_tokens_cache" ]; then
  _l2_5h=$(sed -n '1p' "$_tokens_cache" 2>/dev/null | tr -d '[:space:]')
  _l2_7d=$(sed -n '2p' "$_tokens_cache" 2>/dev/null | tr -d '[:space:]')
  [ -n "$_l2_5h" ] && line2+="${sep}⏱ ${yellow}5h: ${_l2_5h}${reset}"
  [ -n "$_l2_7d" ] && line2+="${sep}📅 ${yellow}7d: ${_l2_7d}${reset}"
fi

# Subscription renewal countdown
renewal_date="2026-04-10"
renewal_epoch=$(date -d "$renewal_date" +%s 2>/dev/null || \
  date -j -f "%Y-%m-%d" "$renewal_date" +%s 2>/dev/null)
if [ -n "$renewal_epoch" ]; then
  days_left=$(( (renewal_epoch - now_epoch) / 86400 ))
  if [ "$days_left" -le 0 ]; then
    line2+="${sep}💳 ${red}renew today!${reset}"
  elif [ "$days_left" -le 3 ]; then
    line2+="${sep}💳 ${red}${days_left}d left${reset}"
  elif [ "$days_left" -le 7 ]; then
    line2+="${sep}💳 ${yellow}${days_left}d left${reset}"
  else
    line2+="${sep}💳 ${dim}${days_left}d left${reset}"
  fi
fi

# ===== Cross-platform OAuth token resolution =====
get_oauth_token() {
  local token=""

  if [ -n "$CLAUDE_CODE_OAUTH_TOKEN" ]; then
    echo "$CLAUDE_CODE_OAUTH_TOKEN"
    return 0
  fi

  if command -v security >/dev/null 2>&1; then
    local blob
    blob=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null)
    if [ -n "$blob" ]; then
      token=$(echo "$blob" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
      if [ -n "$token" ] && [ "$token" != "null" ]; then
        echo "$token"
        return 0
      fi
    fi
  fi

  local creds_file="${HOME}/.claude/.credentials.json"
  if [ -f "$creds_file" ]; then
    token=$(jq -r '.claudeAiOauth.accessToken // empty' "$creds_file" 2>/dev/null)
    if [ -n "$token" ] && [ "$token" != "null" ]; then
      echo "$token"
      return 0
    fi
  fi

  if command -v secret-tool >/dev/null 2>&1; then
    local blob
    blob=$(timeout 2 secret-tool lookup service "Claude Code-credentials" 2>/dev/null)
    if [ -n "$blob" ]; then
      token=$(echo "$blob" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
      if [ -n "$token" ] && [ "$token" != "null" ]; then
        echo "$token"
        return 0
      fi
    fi
  fi

  echo ""
}

# ===== Usage data (cached) =====
cache_file="/tmp/claude/statusline-usage-cache.json"
cache_max_age=180
mkdir -p /tmp/claude

needs_refresh=true
usage_data=""

if [ -f "$cache_file" ]; then
  cache_mtime=$(stat -c %Y "$cache_file" 2>/dev/null || stat -f %m "$cache_file" 2>/dev/null)
  cache_age=$((now_epoch - cache_mtime))
  if [ "$cache_age" -lt "$cache_max_age" ]; then
    cached_candidate=$(cat "$cache_file" 2>/dev/null)
    # Only use cache if it is valid JSON without an error field
    if echo "$cached_candidate" | jq -e 'has("error") | not' >/dev/null 2>&1; then
      # Invalidate if 5h reset time has passed (window rolled over, data is stale)
      _cached_reset=$(echo "$cached_candidate" | jq -r '.five_hour.resets_at // empty')
      if is_reset_past "$_cached_reset"; then
        needs_refresh=true
      else
        needs_refresh=false
        usage_data="$cached_candidate"
        # Record snapshot from cache for recent pace (dedup handles repeated values)
        _snap_five=$(echo "$cached_candidate" | jq -r '.five_hour.utilization // 0' | awk '{printf "%.0f", $1}')
        _snap_seven=$(echo "$cached_candidate" | jq -r '.seven_day.utilization // 0' | awk '{printf "%.0f", $1}')
        record_usage_snapshot "$_snap_five" "$_snap_seven"
      fi
    fi
  fi
fi

if $needs_refresh; then
  token=$(get_oauth_token)
  if [ -n "$token" ] && [ "$token" != "null" ]; then
    response=$(curl -s --max-time 10 \
      -H "Accept: application/json" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer $token" \
      -H "anthropic-beta: oauth-2025-04-20" \
      -H "User-Agent: claude-code/2.1.34" \
      "https://api.anthropic.com/api/oauth/usage" 2>/dev/null)
    # Only accept the response if it is valid JSON and does NOT contain an error field
    if [ -n "$response" ] && echo "$response" | jq -e 'has("error") | not' >/dev/null 2>&1; then
      usage_data="$response"
      echo "$response" >"$cache_file"
      # Record snapshot for recent pace calculation
      _snap_five=$(echo "$response" | jq -r '.five_hour.utilization // 0' | awk '{printf "%.0f", $1}')
      _snap_seven=$(echo "$response" | jq -r '.seven_day.utilization // 0' | awk '{printf "%.0f", $1}')
      record_usage_snapshot "$_snap_five" "$_snap_seven"
    fi
  fi
  if [ -z "$usage_data" ] && [ -f "$cache_file" ]; then
    # Discard a stale cache that is itself an error response
    cached=$(cat "$cache_file" 2>/dev/null)
    if echo "$cached" | jq -e 'has("error") | not' >/dev/null 2>&1; then
      usage_data="$cached"
    fi
  fi
fi


format_reset_time() {
  local iso_str="$1"
  local style="$2"
  [ -z "$iso_str" ] || [ "$iso_str" = "null" ] && return

  local epoch
  epoch=$(iso_to_epoch "$iso_str")
  [ -z "$epoch" ] && return

  case "$style" in
  time)
    (date -d "@$epoch" +"%l:%M%P" 2>/dev/null || date -r "$epoch" +"%l:%M%P" 2>/dev/null) | sed 's/^ //'
    ;;
  datetime)
    (date -d "@$epoch" +"%b %-d, %l:%M%P" 2>/dev/null || date -r "$epoch" +"%b %-d, %l:%M%P" 2>/dev/null) | sed 's/  / /g; s/^ //'
    ;;
  *)
    (date -d "@$epoch" +"%b %-d" 2>/dev/null || date -r "$epoch" +"%b %-d" 2>/dev/null)
    ;;
  esac
}

# ===== Usage snapshot history (for recent pace) =====
history_file="/tmp/claude/statusline-usage-history.txt"

# Append a snapshot; prune entries older than 24h
# Deduplicates: skip if last entry has same values and is < 60s old
record_usage_snapshot() {
  local five_pct=$1 seven_pct=$2
  if [ -f "$history_file" ]; then
    local last_line
    last_line=$(tail -1 "$history_file")
    local last_epoch last_five last_seven
    last_epoch=$(echo "$last_line" | cut -d: -f1)
    last_five=$(echo "$last_line" | cut -d: -f2)
    last_seven=$(echo "$last_line" | cut -d: -f3)
    # Skip if same values and less than 60s ago
    if [ "$last_five" = "$five_pct" ] && [ "$last_seven" = "$seven_pct" ] && \
       [ -n "$last_epoch" ] && [ $((now_epoch - last_epoch)) -lt 60 ]; then
      return
    fi
  fi
  echo "${now_epoch}:${five_pct}:${seven_pct}" >> "$history_file"
  local cutoff=$((now_epoch - 86400))
  awk -F: -v c="$cutoff" '$1 >= c' "$history_file" > "${history_file}.tmp" && \
    mv "${history_file}.tmp" "$history_file"
}

# Recent pace over a lookback window
# Usage: calc_recent_pace <current_pct> <window_secs> <lookback_secs> <col>
# col: 2=five_hour, 3=seven_day
calc_recent_pace() {
  local current_pct=$1 window_secs=$2 lookback_secs=$3 col=$4
  [ ! -f "$history_file" ] && return

  local cutoff=$((now_epoch - lookback_secs))
  local oldest_line
  oldest_line=$(awk -F: -v c="$cutoff" '$1 >= c' "$history_file" | head -1)
  [ -z "$oldest_line" ] && return

  local old_epoch old_pct
  old_epoch=$(echo "$oldest_line" | cut -d: -f1)
  old_pct=$(echo "$oldest_line" | cut -d: -f"$col")
  [ -z "$old_epoch" ] || [ -z "$old_pct" ] && return

  local time_delta=$((now_epoch - old_epoch))
  # Need at least 2 min AND 10% of lookback window for meaningful rate
  [ "$time_delta" -lt 120 ] && return
  local min_span=$((lookback_secs / 10))
  [ "$min_span" -lt 120 ] && min_span=120
  [ "$time_delta" -lt "$min_span" ] && return

  awk "BEGIN {
    delta_pct = $current_pct - $old_pct
    if (delta_pct < 0) exit  # window reset happened
    delta_elapsed_pct = ($time_delta / $window_secs) * 100
    if (delta_elapsed_pct <= 0) exit
    printf \"%.2f\", delta_pct / delta_elapsed_pct
  }"
}

# ===== Pace calculation =====
# pace = (usage% / elapsed%) where elapsed% = time_elapsed / total_window
# pace 1.0 = sustainable, >1.0 = burning fast, <1.0 = have headroom
calc_pace() {
  local pct=$1
  local reset_iso=$2
  local window_secs=$3

  [ "$pct" -eq 0 ] 2>/dev/null && echo "0.0" && return
  [ -z "$reset_iso" ] || [ "$reset_iso" = "null" ] && echo "0.0" && return

  local reset_epoch
  reset_epoch=$(iso_to_epoch "$reset_iso")
  [ -z "$reset_epoch" ] && echo "0.0" && return

  local elapsed_secs=$((window_secs - (reset_epoch - now_epoch)))
  [ "$elapsed_secs" -le 0 ] && echo "0.0" && return

  local elapsed_pct
  elapsed_pct=$(awk "BEGIN {printf \"%.4f\", ($elapsed_secs / $window_secs) * 100}")

  awk "BEGIN {
    ep = $elapsed_pct
    if (ep <= 0) { printf \"0.0\"; exit }
    printf \"%.2f\", $pct / ep
  }"
}

# Format remaining time estimate
calc_remaining() {
  local pct=$1
  local pace=$2
  local window_secs=$3
  local reset_iso=$4

  local reset_epoch
  reset_epoch=$(iso_to_epoch "$reset_iso")
  [ -z "$reset_epoch" ] && return

  local remaining_secs=$((reset_epoch - now_epoch))
  [ "$remaining_secs" -le 0 ] && return

  # At current pace, how long until 100%?
  local remaining_pct=$((100 - pct))
  [ "$remaining_pct" -le 0 ] && echo "0m" && return

  local pace_num
  pace_num=$(echo "$pace" | awk '{printf "%.2f", $1}')

  # If pace is 0 or very low, don't predict
  local is_low
  is_low=$(awk "BEGIN {print ($pace_num < 0.1) ? 1 : 0}")
  [ "$is_low" -eq 1 ] && return

  # Time to exhaust = remaining_pct / (pct / elapsed_secs)
  local elapsed_secs=$((window_secs - remaining_secs))
  [ "$elapsed_secs" -le 0 ] && return

  local exhaust_secs
  exhaust_secs=$(awk "BEGIN {
    rate = $pct / $elapsed_secs
    if (rate <= 0) { print 0; exit }
    printf \"%.0f\", $remaining_pct / rate
  }")

  if [ "$exhaust_secs" -le 0 ] 2>/dev/null; then
    echo "0m"
  elif [ "$exhaust_secs" -lt 3600 ] 2>/dev/null; then
    echo "$((exhaust_secs / 60))m"
  elif [ "$exhaust_secs" -lt 86400 ] 2>/dev/null; then
    local h=$((exhaust_secs / 3600))
    local m=$(( (exhaust_secs % 3600) / 60 ))
    if [ "$m" -gt 0 ]; then
      echo "${h}h${m}m"
    else
      echo "${h}h"
    fi
  else
    echo "$((exhaust_secs / 86400))d"
  fi
}

# Cold-to-hot color gradient for pace values
# 0.0–0.4 icy blue, 0.5–0.7 cool cyan, 0.8–1.0 green (sustainable),
# 1.1–1.5 yellow (warm), 1.6–2.0 orange (hot), 2.0+ red (burning)
pace_color_for() {
  local pace=$1
  local pace_int
  pace_int=$(echo "$pace" | awk '{printf "%.0f", $1 * 10}')

  if [ "$pace_int" -le 4 ]; then
    printf '\033[38;2;80;160;255m'    # icy blue
  elif [ "$pace_int" -le 7 ]; then
    printf '\033[38;2;46;200;200m'    # cool cyan
  elif [ "$pace_int" -le 10 ]; then
    printf '\033[38;2;0;200;80m'      # green (sustainable)
  elif [ "$pace_int" -le 15 ]; then
    printf '\033[38;2;230;200;0m'     # yellow (warm)
  elif [ "$pace_int" -le 20 ]; then
    printf '\033[38;2;255;140;40m'    # orange (hot)
  else
    printf '\033[38;2;255;60;60m'     # red (burning)
  fi
}

format_pace() {
  local pace=$1
  local remaining=$2
  local recent_pace=$3
  local pace_color
  pace_color=$(pace_color_for "$pace")

  local result="${dim}~${reset}${pace_color}${pace}x${reset}"

  # Show recent pace when available
  if [ -n "$recent_pace" ]; then
    local recent_color
    recent_color=$(pace_color_for "$recent_pace")
    result+=" ${white}⚡${reset}${recent_color}${recent_pace}x${reset}"
  fi

  # Show remaining time when pace > 1.0 (will exhaust before window ends)
  local pace_int
  pace_int=$(echo "$pace" | awk '{printf "%.0f", $1 * 10}')
  if [ -n "$remaining" ] && [ "$pace_int" -gt 10 ]; then
    result+=" ${dim}~${remaining} left${reset}"
  fi

  echo "$result"
}

# ===== LINE 3: 5h bar | 7d bar | pace | extra =====
line3=""

# Prefer the OAuth API usage_data; fall back to rate_limits from stdin JSON.
# The stdin JSON provides used_percentage (0-100) and resets_at (Unix epoch seconds).
use_oauth=false
use_stdin_limits=false

if [ -n "$usage_data" ] && echo "$usage_data" | jq -e 'has("five_hour") or has("seven_day")' >/dev/null 2>&1; then
  use_oauth=true
else
  # Check if stdin JSON has rate_limits data
  stdin_five_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
  stdin_seven_pct=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
  if [ -n "$stdin_five_pct" ] || [ -n "$stdin_seven_pct" ]; then
    use_stdin_limits=true
  fi
fi

# Convert Unix epoch seconds (from stdin rate_limits) to ISO-like string for iso_to_epoch
epoch_to_iso() {
  date -d "@$1" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || \
    date -r "$1" -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null
}

if $use_oauth; then
  bar_width=6

  # ---- 5-hour (current) ----
  five_hour_pct=$(echo "$usage_data" | jq -r '.five_hour.utilization // 0' | awk '{printf "%.0f", $1}')
  five_hour_reset_iso=$(echo "$usage_data" | jq -r '.five_hour.resets_at // empty')

  if is_reset_past "$five_hour_reset_iso"; then
    five_hour_bar=$(build_bar 0 "$bar_width")
    line3+="⏱ ${white}5h${reset} ${five_hour_bar} ${dim}↻${reset}"
  else
    five_hour_reset=$(format_reset_time "$five_hour_reset_iso" "time")
    five_hour_bar=$(build_bar "$five_hour_pct" "$bar_width")

    five_pace=$(calc_pace "$five_hour_pct" "$five_hour_reset_iso" 18000)
    five_remaining=$(calc_remaining "$five_hour_pct" "$five_pace" 18000 "$five_hour_reset_iso")
    five_recent=$(calc_recent_pace "$five_hour_pct" 18000 1800 2)
    five_pace_fmt=$(format_pace "$five_pace" "$five_remaining" "$five_recent")

    line3+="⏱ ${white}5h${reset} ${five_hour_bar} ${cyan}${five_hour_pct}%${reset} ${five_pace_fmt}"
    [ -n "$five_hour_reset" ] && line3+=" ${dim}@${five_hour_reset}${reset}"

    # Suggest throttling when recent 5h pace is very high
    if [ -n "$five_recent" ]; then
      _recent_int=$(echo "$five_recent" | awk '{printf "%.0f", $1 * 10}')
      if [ "$_recent_int" -ge 35 ]; then
        line3+=" ${yellow}💡/model sonnet${reset}"
      elif [ "$_recent_int" -ge 25 ]; then
        line3+=" ${dim}💡effort↓${reset}"
      fi
    fi
  fi

  # ---- 7-day: bar + pace ----
  seven_day_pct=$(echo "$usage_data" | jq -r '.seven_day.utilization // 0' | awk '{printf "%.0f", $1}')
  seven_day_reset_iso=$(echo "$usage_data" | jq -r '.seven_day.resets_at // empty')

  if is_reset_past "$seven_day_reset_iso"; then
    seven_day_bar=$(build_bar 0 "$bar_width")
    line3+="${sep}📅 ${white}7d${reset} ${seven_day_bar} ${dim}↻${reset}"
  else
    seven_day_reset=$(format_reset_time "$seven_day_reset_iso" "datetime")
    seven_day_bar=$(build_bar "$seven_day_pct" "$bar_width")

    seven_pace=$(calc_pace "$seven_day_pct" "$seven_day_reset_iso" 604800)
    seven_remaining=$(calc_remaining "$seven_day_pct" "$seven_pace" 604800 "$seven_day_reset_iso")
    seven_recent=$(calc_recent_pace "$seven_day_pct" 604800 60480 3)
    seven_pace_fmt=$(format_pace "$seven_pace" "$seven_remaining" "$seven_recent")

    line3+="${sep}📅 ${white}7d${reset} ${seven_day_bar} ${cyan}${seven_day_pct}%${reset} ${seven_pace_fmt}"
    [ -n "$seven_day_reset" ] && line3+=" ${dim}@${seven_day_reset}${reset}"
  fi

  # ---- Extra usage ----
  extra_enabled=$(echo "$usage_data" | jq -r '.extra_usage.is_enabled // false')
  if [ "$extra_enabled" = "true" ]; then
    extra_pct=$(echo "$usage_data" | jq -r '.extra_usage.utilization // 0' | awk '{printf "%.0f", $1}')
    extra_used=$(echo "$usage_data" | jq -r '.extra_usage.used_credits // 0' | awk '{printf "%.2f", $1/100}')
    extra_limit=$(echo "$usage_data" | jq -r '.extra_usage.monthly_limit // 0' | awk '{printf "%.2f", $1/100}')
    extra_bar=$(build_bar "$extra_pct" "$bar_width")

    line3+="${sep}💳 ${white}extra${reset} ${extra_bar} ${cyan}\$${extra_used}/\$${extra_limit}${reset}"
  fi

elif $use_stdin_limits; then
  bar_width=6

  # ---- 5-hour from stdin rate_limits ----
  if [ -n "$stdin_five_pct" ]; then
    five_hour_pct=$(printf "%.0f" "$stdin_five_pct" 2>/dev/null || echo "0")
    stdin_five_resets=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
    if [ -n "$stdin_five_resets" ]; then
      five_hour_reset_iso=$(epoch_to_iso "$stdin_five_resets")
    else
      five_hour_reset_iso=""
    fi
    five_hour_reset=$(format_reset_time "$five_hour_reset_iso" "time")
    five_hour_bar=$(build_bar "$five_hour_pct" "$bar_width")

    five_pace=$(calc_pace "$five_hour_pct" "$five_hour_reset_iso" 18000)
    five_remaining=$(calc_remaining "$five_hour_pct" "$five_pace" 18000 "$five_hour_reset_iso")
    five_recent=$(calc_recent_pace "$five_hour_pct" 18000 1800 2)
    five_pace_fmt=$(format_pace "$five_pace" "$five_remaining" "$five_recent")

    line3+="⏱ ${white}5h${reset} ${five_hour_bar} ${cyan}${five_hour_pct}%${reset} ${five_pace_fmt}"
    [ -n "$five_hour_reset" ] && line3+=" ${dim}@${five_hour_reset}${reset}"
  fi

  # ---- 7-day from stdin rate_limits ----
  if [ -n "$stdin_seven_pct" ]; then
    seven_day_pct=$(printf "%.0f" "$stdin_seven_pct" 2>/dev/null || echo "0")
    stdin_seven_resets=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')
    if [ -n "$stdin_seven_resets" ]; then
      seven_day_reset_iso=$(epoch_to_iso "$stdin_seven_resets")
    else
      seven_day_reset_iso=""
    fi
    seven_day_reset=$(format_reset_time "$seven_day_reset_iso" "datetime")
    seven_day_bar=$(build_bar "$seven_day_pct" "$bar_width")

    seven_pace=$(calc_pace "$seven_day_pct" "$seven_day_reset_iso" 604800)
    seven_remaining=$(calc_remaining "$seven_day_pct" "$seven_pace" 604800 "$seven_day_reset_iso")
    seven_recent=$(calc_recent_pace "$seven_day_pct" 604800 60480 3)
    seven_pace_fmt=$(format_pace "$seven_pace" "$seven_remaining" "$seven_recent")

    line3+="${sep}📅 ${white}7d${reset} ${seven_day_bar} ${cyan}${seven_day_pct}%${reset} ${seven_pace_fmt}"
    [ -n "$seven_day_reset" ] && line3+=" ${dim}@${seven_day_reset}${reset}"
  fi
fi

# Output three lines
printf "%b\n%b\n%b" "$line1" "$line2" "$line3"

exit 0
