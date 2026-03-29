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
  pr_cache_mtime=$(stat -f %m "$pr_cache_file" 2>/dev/null || stat -c %Y "$pr_cache_file" 2>/dev/null)
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
cache_max_age=60
mkdir -p /tmp/claude

needs_refresh=true
usage_data=""

if [ -f "$cache_file" ]; then
  cache_mtime=$(stat -f %m "$cache_file" 2>/dev/null || stat -c %Y "$cache_file" 2>/dev/null)
  cache_age=$((now_epoch - cache_mtime))
  if [ "$cache_age" -lt "$cache_max_age" ]; then
    needs_refresh=false
    usage_data=$(cat "$cache_file" 2>/dev/null)
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
    if [ -n "$response" ] && echo "$response" | jq . >/dev/null 2>&1; then
      usage_data="$response"
      echo "$response" >"$cache_file"
    fi
  fi
  if [ -z "$usage_data" ] && [ -f "$cache_file" ]; then
    usage_data=$(cat "$cache_file" 2>/dev/null)
  fi
fi

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

format_reset_time() {
  local iso_str="$1"
  local style="$2"
  [ -z "$iso_str" ] || [ "$iso_str" = "null" ] && return

  local epoch
  epoch=$(iso_to_epoch "$iso_str")
  [ -z "$epoch" ] && return

  case "$style" in
  time)
    date -j -r "$epoch" +"%l:%M%p" 2>/dev/null | sed 's/^ //' | tr '[:upper:]' '[:lower:]' ||
      date -d "@$epoch" +"%l:%M%P" 2>/dev/null | sed 's/^ //'
    ;;
  datetime)
    date -j -r "$epoch" +"%b %-d, %l:%M%p" 2>/dev/null | sed 's/  / /g; s/^ //' | tr '[:upper:]' '[:lower:]' ||
      date -d "@$epoch" +"%b %-d, %l:%M%P" 2>/dev/null | sed 's/  / /g; s/^ //'
    ;;
  *)
    date -j -r "$epoch" +"%b %-d" 2>/dev/null | tr '[:upper:]' '[:lower:]' ||
      date -d "@$epoch" +"%b %-d" 2>/dev/null
    ;;
  esac
}

# ===== LINE 3: 5h bar | 7d bar | 2x promo | extra =====
line3=""

if [ -n "$usage_data" ] && echo "$usage_data" | jq -e . >/dev/null 2>&1; then
  bar_width=6

  # ---- 5-hour (current) ----
  five_hour_pct=$(echo "$usage_data" | jq -r '.five_hour.utilization // 0' | awk '{printf "%.0f", $1}')
  five_hour_reset_iso=$(echo "$usage_data" | jq -r '.five_hour.resets_at // empty')
  five_hour_reset=$(format_reset_time "$five_hour_reset_iso" "time")
  five_hour_bar=$(build_bar "$five_hour_pct" "$bar_width")

  line3+="⏱ ${white}5h${reset} ${five_hour_bar} ${cyan}${five_hour_pct}%${reset}"
  [ -n "$five_hour_reset" ] && line3+=" ${dim}@${five_hour_reset}${reset}"

  # ---- 7-day (weekly) ----
  seven_day_pct=$(echo "$usage_data" | jq -r '.seven_day.utilization // 0' | awk '{printf "%.0f", $1}')
  seven_day_reset_iso=$(echo "$usage_data" | jq -r '.seven_day.resets_at // empty')
  seven_day_reset=$(format_reset_time "$seven_day_reset_iso" "datetime")
  seven_day_bar=$(build_bar "$seven_day_pct" "$bar_width")

  line3+="${sep}📅 ${white}7d${reset} ${seven_day_bar} ${cyan}${seven_day_pct}%${reset}"
  [ -n "$seven_day_reset" ] && line3+=" ${dim}@${seven_day_reset}${reset}"

  # ---- Extra usage ----
  extra_enabled=$(echo "$usage_data" | jq -r '.extra_usage.is_enabled // false')
  if [ "$extra_enabled" = "true" ]; then
    extra_pct=$(echo "$usage_data" | jq -r '.extra_usage.utilization // 0' | awk '{printf "%.0f", $1}')
    extra_used=$(echo "$usage_data" | jq -r '.extra_usage.used_credits // 0' | awk '{printf "%.2f", $1/100}')
    extra_limit=$(echo "$usage_data" | jq -r '.extra_usage.monthly_limit // 0' | awk '{printf "%.2f", $1/100}')
    extra_bar=$(build_bar "$extra_pct" "$bar_width")

    line3+="${sep}💳 ${white}extra${reset} ${extra_bar} ${cyan}\$${extra_used}/\$${extra_limit}${reset}"
  fi
fi

# Output three lines
printf "%b\n%b\n%b" "$line1" "$line2" "$line3"

exit 0
