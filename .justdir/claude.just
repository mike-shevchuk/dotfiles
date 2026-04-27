# =============================================================================
# claude.just — Claude Code statusline & token usage management
# =============================================================================
#
# HOW THE STATUSLINE CACHES WORK
# ═══════════════════════════════
# The statusline (statusline.sh) fires on every shell prompt.  To avoid
# blocking the prompt it reads from two independent cache layers:
#
#  Layer 1  OAuth API  →  /tmp/claude/statusline-usage-cache.json
#    Calls api.anthropic.com/api/oauth/usage with your Bearer token.
#    Returns 5h/7d utilization %, reset timestamps, and extra-credit usage.
#    Refreshed every 3 minutes (cache_max_age=180s).
#
#  Layer 2  JSONL scanner  →  /tmp/claude/tokens-usage.txt
#    Python script scans ~/.claude/projects/**/*.jsonl and sums
#    input_tokens + output_tokens per message (deduped by message ID).
#    Runs in the background every 5 minutes; writes two lines:
#      line 1 = 5h token count   (e.g. "51k")
#      line 2 = 7d token count   (e.g. "838k")
#    Window boundaries are read from /tmp/claude/tokens-windows.txt
#    (written by statusline after each OAuth fetch) so the "5h: 51k"
#    number covers the exact same period as the "5h ██░░░░ 11%" bar.
#
# HOOKS
# ═════
# Claude Code fires lifecycle events that invoke TypeScript hook scripts.
# Scripts live in ~/.claude/hooks/  ·  wired in ~/.claude/settings.json.
#
#   Notification   → hooks/notification.ts
#     Fires when Claude needs to alert you (rate-limited, waiting for input,
#     any Claude-triggered notification).  Plays notification.wav + desktop pop.
#
#   Stop           → hooks/stop.ts  +  hooks/cost-logger.ts
#     Fires when a session ends.  stop.ts sends a preview notification.
#     cost-logger.ts reads the session JSONL, sums tokens, estimates USD cost
#     ($3/MTok input · $15/MTok output), appends to ~/.claude/session-costs.log
#     and writes a markdown summary to ~/.claude/sessions/YYYY-MM-DD-HH.md.
#
#   SubagentStop   → hooks/subagent_stop.ts
#     Fires when a sub-agent finishes.  Plays subagent_stop.wav + notification.
#
#   PreToolUse     → hooks/danger-guard.ts  (matcher: Bash)
#     Scans every Bash command for dangerous patterns (rm -rf, git reset --hard,
#     git push --force, DROP TABLE, chmod -R 777, etc.) and sends a desktop
#     notification.  Never blocks — only warns.
#
#   PostToolUse    → hooks/format.ts  (matcher: Edit|Write)
#     Auto-formats edited files: ruff check --fix + ruff format (.py),
#     eslint --fix (.ts/.js), stylua (.lua).  Runs silently in background.
#
#   shared.ts provides:  readInput<T>(), notify(title, msg, soundFile)
#   Sound files: ~/.claude/sounds/{notification,stop,subagent_stop}.wav
#
# RECIPES
# ═══════
#   just tokens            print current 5h/7d counts (cache or live)
#   just tokens-refresh    force immediate rescan of all JSONL files
#   just statusline-test   preview all 3 statusline lines without a session
#   just statusline-debug  inspect cache files + parsed values
#   just cache-clear       wipe all caches → full refresh on next prompt
#   just logs [n]          tail last N events from the newest session file
#   just sessions          list JSONL files sorted by size (biggest first)
#   just costs             show session cost log (token counts + USD estimate)
#   just cost-sessions     list hourly session summary markdown files
#   just hooks-status      show hook files, sounds, and registered events
#   just article-new       create a new EN+UK article pair from template
# =============================================================================

# Print 5h and 7d token counts — reads cache if fresh, scans live if stale
tokens:
    #!/usr/bin/env bash
    # Cache file: two lines written by the background Python scanner
    #   line 1 = 5h count (matches the 5h bar window in statusline)
    #   line 2 = 7d count (matches the 7d bar window in statusline)
    cache="/tmp/claude/tokens-usage.txt"
    stamp="/tmp/claude/tokens-usage.stamp"   # epoch of last scan
    script="$HOME/.claude/tokens-usage.py"   # stowed copy; /tmp fallback below

    green='\033[32m'; cyan='\033[36m'; dim='\033[2m'; reset='\033[0m'

    # Measure how old the stamp is (age > 300s = stale)
    if [ -f "$stamp" ]; then
        stamp_val=$(cat "$stamp")
        stamp_age=$(( $(date +%s) - stamp_val ))
    else
        stamp_age=999999
    fi

    if [ -f "$cache" ] && [ "$stamp_age" -lt 300 ]; then
        # Cache is fresh — read it directly (no Python startup cost)
        t5h=$(sed -n '1p' "$cache" | tr -d '[:space:]')
        t7d=$(sed -n '2p' "$cache" | tr -d '[:space:]')
        age_label="${dim}(cached ${stamp_age}s ago)${reset}"
    else
        # Cache is stale or missing — run the scanner synchronously
        printf "${dim}scanning JSONL files...${reset}\n"
        result=$(python3 "$script" 2>/dev/null \
              || python3 /tmp/claude/tokens-usage.py 2>/dev/null)
        t5h=$(echo "$result" | sed -n '1p' | tr -d '[:space:]')
        t7d=$(echo "$result" | sed -n '2p' | tr -d '[:space:]')
        age_label="${dim}(live)${reset}"
    fi

    printf "\n"
    printf "  ${cyan}⏱  5h window:${reset}  ${green}${t5h:-0}${reset} tokens  $age_label\n"
    printf "  ${cyan}📅 7d window:${reset}  ${green}${t7d:-0}${reset} tokens\n"
    printf "\n"

# Force immediate rescan of all JSONL files and rebuild the token cache
tokens-refresh:
    #!/usr/bin/env bash
    # Wipe stamp + cache so both this recipe AND the statusline start fresh.
    # Unlike the normal background refresh (every 5 min), this runs Python
    # synchronously so results are ready before the recipe exits.
    rm -f /tmp/claude/tokens-usage.stamp \
          /tmp/claude/tokens-usage.txt \
          /tmp/claude/tokens-usage.txt.tmp
    mkdir -p /tmp/claude

    printf "Scanning JSONL files... "
    python3 /tmp/claude/tokens-usage.py > /tmp/claude/tokens-usage.txt 2>/dev/null \
        || python3 ~/.claude/tokens-usage.py > /tmp/claude/tokens-usage.txt 2>/dev/null
    echo "$(date +%s)" > /tmp/claude/tokens-usage.stamp
    printf "done\n"
    just tokens          # print the freshly written counts

# Render all 3 statusline lines using a fake session payload (no Claude needed)
statusline-test:
    #!/usr/bin/env bash
    # Injects a minimal JSON payload so statusline.sh can run without an
    # active Claude Code session.  Useful after editing statusline.sh to
    # preview colours, bars, pace labels, and token counts immediately.
    #
    # Payload simulates:
    #   model        = claude-sonnet-4-6
    #   context used = 12 345 input + 5 000 cache-read  (out of 200k)
    #   cwd          = current directory
    script="$HOME/.claude/statusline.sh"
    if [ ! -f "$script" ]; then
        printf "ERROR: statusline.sh not found at %s\n" "$script"
        printf "Run 'just claude' to stow it.\n"
        exit 1
    fi
    echo '{"model":{"display_name":"claude-sonnet-4-6"},"context_window":{"context_window_size":200000,"current_usage":{"input_tokens":12345,"cache_creation_input_tokens":0,"cache_read_input_tokens":5000}},"cwd":"'"$(pwd)"'"}' \
        | bash "$script"
    printf "\n"

# Inspect all statusline cache files — age, size, and parsed values
statusline-debug:
    #!/usr/bin/env bash
    # Prints a table of every /tmp/claude/ cache file with:
    #   green  = present and fresh (< 10 min old)
    #   yellow = present but stale (>= 10 min old)
    #   red    = present but empty (write may have failed)
    #   dim    = missing (will be created on next prompt)
    #
    # Also prints the actual parsed values so you can see what the
    # statusline is reading right now without triggering a render.
    green='\033[32m'; yellow='\033[33m'; red='\033[31m'; dim='\033[2m'
    cyan='\033[36m'; reset='\033[0m'
    now=$(date +%s)

    show_file() {
        local path="$1" label="$2"
        if [ -f "$path" ]; then
            local mtime size age
            mtime=$(stat -c %Y "$path" 2>/dev/null || stat -f %m "$path" 2>/dev/null)
            size=$(stat -c %s "$path" 2>/dev/null || stat -f %z "$path" 2>/dev/null)
            age=$(( now - mtime ))
            if   [ "$size" -eq 0 ];   then printf "  ${red}%-42s${reset}  ${red}EMPTY${reset}  (${age}s ago)\n" "$label"
            elif [ "$age"  -gt 600 ]; then printf "  ${yellow}%-42s${reset}  ${yellow}stale${reset}  ${size}B  (${age}s ago)\n" "$label"
            else                           printf "  ${green}%-42s${reset}  ${green}ok${reset}     ${size}B  (${age}s ago)\n" "$label"
            fi
        else
            printf "  ${dim}%-42s  missing${reset}\n" "$label"
        fi
    }

    printf "\n  ${cyan}Cache files:${reset}\n\n"
    # Layer 2 — JSONL scanner (runs in background every 5 min)
    show_file "/tmp/claude/tokens-usage.txt"               "tokens cache  (5h/7d counts, 5-min TTL)"
    show_file "/tmp/claude/tokens-usage.stamp"              "tokens stamp  (tracks last scan time)"
    show_file "/tmp/claude/tokens-usage.py"                 "token scanner (auto-written by statusline)"
    show_file "/tmp/claude/tokens-windows.txt"              "window bounds (OAuth reset times for sync)"
    # Layer 1 — OAuth API (fetched every 3 min)
    show_file "/tmp/claude/statusline-usage-cache.json"     "OAuth cache   (utilization %, 3-min TTL)"
    show_file "/tmp/claude/statusline-usage-history.txt"    "pace history  (% snapshots for rate calc)"

    printf "\n  ${cyan}Parsed values:${reset}\n\n"

    # Layer 2 counts
    if [ -f /tmp/claude/tokens-usage.txt ]; then
        t5h=$(sed -n '1p' /tmp/claude/tokens-usage.txt)
        t7d=$(sed -n '2p' /tmp/claude/tokens-usage.txt)
        printf "  JSONL scanner  5h: ${green}${t5h:-empty}${reset}   7d: ${green}${t7d:-empty}${reset}\n"
    else
        printf "  JSONL scanner  ${dim}no cache — run: just tokens-refresh${reset}\n"
    fi

    # Layer 1 utilization
    if [ -f /tmp/claude/statusline-usage-cache.json ]; then
        five=$(jq -r '"  OAuth API     5h: \(.five_hour.utilization)%  resets \(.five_hour.resets_at)"' \
               /tmp/claude/statusline-usage-cache.json 2>/dev/null)
        seven=$(jq -r '"               7d: \(.seven_day.utilization)%  resets \(.seven_day.resets_at)"' \
                /tmp/claude/statusline-usage-cache.json 2>/dev/null)
        [ -n "$five" ]  && printf "%s\n" "$five"
        [ -n "$seven" ] && printf "%s\n" "$seven"
    else
        printf "  OAuth API      ${dim}no cache — will fetch on next prompt${reset}\n"
    fi
    printf "\n"

# Wipe all statusline caches so the next prompt does a full refresh
cache-clear:
    #!/usr/bin/env bash
    # Deletes every /tmp/claude/ cache file.  On the next shell prompt:
    #   - OAuth usage is re-fetched from api.anthropic.com
    #   - JSONL scanner runs in the background and rebuilds token counts
    #   - PR number is re-detected via gh pr view
    # Use when the statusline shows stale, zero, or incorrect values.
    rm -f /tmp/claude/tokens-usage.txt \
          /tmp/claude/tokens-usage.txt.tmp \
          /tmp/claude/tokens-usage.stamp \
          /tmp/claude/tokens-windows.txt \
          /tmp/claude/statusline-usage-cache.json \
          /tmp/claude/statusline-usage-history.txt \
          /tmp/claude/pr-cache-*.txt
    printf "All caches cleared. Press Enter to trigger a fresh prompt render.\n"

# Tail the last N events from the newest session JSONL file (default: 20)
logs n="20":
    #!/usr/bin/env bash
    # Each JSONL line is one conversation event (user message, assistant
    # response, tool call, tool result, etc.).  This recipe shows:
    #   HH:MM:SS  role      first 80 chars of content   [in:X out:Y] tokens
    #
    # Usage:
    #   just logs        — last 20 events
    #   just logs 50     — last 50 events (deeper history)
    #   just logs 5      — quick peek at last 5 events
    cyan='\033[36m'; dim='\033[2m'; yellow='\033[33m'; reset='\033[0m'
    n={{n}}

    # Pick the most recently modified JSONL across all project subdirs
    newest=$(find ~/.claude/projects -name '*.jsonl' -type f 2>/dev/null \
             | xargs ls -t 2>/dev/null | head -1)
    if [ -z "$newest" ]; then
        printf "No JSONL files found in ~/.claude/projects/\n"; exit 1
    fi

    printf "\n  ${dim}%s${reset}\n\n" "$newest"

    tail -"$n" "$newest" | while IFS= read -r line; do
        ts=$(echo "$line" | jq -r '.timestamp // empty' 2>/dev/null | cut -c12-19)
        role=$(echo "$line" | jq -r '.message.role // empty' 2>/dev/null)
        content=$(echo "$line" | jq -r '.message.content // empty' 2>/dev/null)
        in_tok=$(echo "$line"  | jq -r '.message.usage.input_tokens // 0' 2>/dev/null)
        out_tok=$(echo "$line" | jq -r '.message.usage.output_tokens // 0' 2>/dev/null)

        [ -z "$ts" ] && continue   # skip non-message lines (tool wrappers, etc.)

        case "$role" in
            user)      color="$yellow" ;;
            assistant) color="$cyan"   ;;
            *)         color="$dim"    ;;
        esac

        printf "  ${dim}%s${reset}  ${color}%-9s${reset}  %.80s" \
            "$ts" "${role:-event}" "$content"
        [ "$in_tok" -gt 0 ] || [ "$out_tok" -gt 0 ] && \
            printf "  ${dim}[in:%s out:%s]${reset}" "$in_tok" "$out_tok"
        printf "\n"
    done
    printf "\n"

# Show estimated cost log — all sessions with token counts and USD cost
costs:
    #!/usr/bin/env bash
    # Written by cost-logger.ts on every session Stop event.
    # Format: timestamp  cwd=...  in=X  out=Y  cost=$0.0123
    log="$HOME/.claude/session-costs.log"
    if [ ! -f "$log" ]; then
        printf "No cost log yet — costs are written when a session ends.\n"; exit 0
    fi
    cyan='\033[36m'; green='\033[32m'; dim='\033[2m'; reset='\033[0m'
    printf "\n  ${cyan}%-19s  %-8s  %-8s  %s${reset}\n" "DATE" "INPUT" "OUTPUT" "COST"
    tail -20 "$log" | while IFS= read -r line; do
        date=$(echo "$line" | grep -oP '^\S+ \S+')
        in=$(echo "$line"   | grep -oP 'in=\K[^ ]+')
        out=$(echo "$line"  | grep -oP 'out=\K[^ ]+')
        cost=$(echo "$line" | grep -oP 'cost=\K\S+')
        printf "  ${dim}%-19s${reset}  %-8s  %-8s  ${green}%s${reset}\n" "$date" "$in" "$out" "${cost:-?}"
    done
    printf "\n  Total entries: $(wc -l < "$log")\n\n"

# Show session summaries — markdown files written at Stop, one per hour
cost-sessions:
    #!/usr/bin/env bash
    # Lists ~/.claude/sessions/*.md files (hourly session summaries).
    # Each file may contain multiple sessions if they ended in the same hour.
    dir="$HOME/.claude/sessions"
    if [ ! -d "$dir" ] || [ -z "$(ls "$dir" 2>/dev/null)" ]; then
        printf "No session summaries yet — written when a session ends.\n"; exit 0
    fi
    cyan='\033[36m'; dim='\033[2m'; reset='\033[0m'
    printf "\n  ${cyan}%-22s  %8s${reset}\n" "FILE" "SIZE"
    ls -lh "$dir"/*.md 2>/dev/null | sort -k9 -r | head -20 \
        | awk '{printf "  %-22s  %8s\n", $NF, $5}'
    printf "\n"

# List all session JSONL files sorted by size — biggest (longest) sessions first
sessions:
    #!/usr/bin/env bash
    # Large files = many conversation turns = potentially high token cost.
    # Use this to find expensive sessions or audit disk usage under
    # ~/.claude/projects/ before deleting old project logs.
    cyan='\033[36m'; reset='\033[0m'
    printf "\n  ${cyan}%-58s  %8s  %s${reset}\n" "SESSION FILE" "SIZE" "LAST MODIFIED"
    find ~/.claude/projects -name '*.jsonl' -type f -exec ls -lh {} \; 2>/dev/null \
        | sort -k5 -rh | head -20 \
        | awk '{printf "  %-58s  %8s  %s %s\n", $NF, $5, $6, $7}'
    printf "\n"

# Show Claude Code hook scripts, sound files, and registered events from settings.json
hooks-status:
    #!/usr/bin/env bash
    # Quick audit of the hooks layer:
    #   green  = file exists
    #   red    = file missing (hook will fail silently at runtime)
    # Hook scripts are TypeScript files transpiled at runtime by npx tsx.
    # Sounds are .wav files played on Linux via paplay/aplay, macOS via afplay.
    green='\033[32m'; red='\033[31m'; cyan='\033[36m'; dim='\033[2m'; reset='\033[0m'
    hooks_dir="$HOME/.claude/hooks"
    sounds_dir="$HOME/.claude/sounds"
    settings="$HOME/.claude/settings.json"

    show_file() {
        local path="$1" label="$2"
        if [ -f "$path" ]; then
            local size
            size=$(stat -c%s "$path" 2>/dev/null || stat -f%z "$path" 2>/dev/null)
            printf "  ${green}%-32s${reset}  %s bytes\n" "$label" "$size"
        else
            printf "  ${red}%-32s  MISSING${reset}\n" "$label"
        fi
    }

    printf "\n  ${cyan}Hook scripts:${reset}  %s\n\n" "$hooks_dir"
    for f in danger-guard.ts notification.ts stop.ts cost-logger.ts subagent_stop.ts format.ts shared.ts; do
        show_file "$hooks_dir/$f" "$f"
    done

    printf "\n  ${cyan}Sound files:${reset}  %s\n\n" "$sounds_dir"
    for f in notification.wav stop.wav subagent_stop.wav; do
        show_file "$sounds_dir/$f" "$f"
    done

    printf "\n  ${cyan}Registered hooks (settings.json):${reset}\n\n"
    if [ -f "$settings" ] && command -v jq &>/dev/null; then
        jq -r '.hooks | to_entries[] | "  \(.key): \(.value[0].hooks | map(.command) | join(", "))"' \
            "$settings" 2>/dev/null
        printf "\n  ${cyan}statusLine:${reset} $(jq -r '.statusLine.command // "not set"' "$settings" 2>/dev/null)\n"
    else
        printf "  ${dim}install jq for detailed output${reset}\n"
    fi
    printf "\n"

# Create a new EN+UK article pair from the standard template
# Usage:  just article-new my-slug "My Article Title"         → creates en + uk
#         just article-new my-slug "My Article Title" en      → en only
#         just article-new my-slug "My Article Title" uk      → uk only
# After running: add an entry to articles[] in ~/code/content/index.html
article-new slug title lang="both":
    #!/usr/bin/env bash
    # Creates blog/en/SLUG.html and/or blog/uk/SLUG.html from the template at
    # templates/article-template.html, substituting LANG_CODE, ARTICLE_TITLE,
    # and ARTICLE_DESCRIPTION placeholders.
    # Uses sed with | delimiter (safe for all chars except pipe in titles).
    set -euo pipefail
    SLUG="{{slug}}"
    TITLE="{{title}}"
    LANG="{{lang}}"
    CONTENT_DIR="$HOME/code/content"
    TEMPLATE="$CONTENT_DIR/templates/article-template.html"

    if [ ! -f "$TEMPLATE" ]; then
        printf "ERROR: template not found at %s\n" "$TEMPLATE"
        printf "Make sure ~/code/content/templates/article-template.html exists.\n"
        exit 1
    fi

    create_article() {
        local lang_code="$1"
        local out_dir="$CONTENT_DIR/blog/$lang_code"
        local out_file="$out_dir/$SLUG.html"
        if [ -f "$out_file" ]; then
            printf "SKIP: %s already exists\n" "$out_file"; return
        fi
        mkdir -p "$out_dir"
        sed \
            -e "s|LANG_CODE|$lang_code|g" \
            -e "s|ARTICLE_TITLE|$TITLE|g" \
            -e "s|ARTICLE_DESCRIPTION|TODO: Add description for $TITLE|g" \
            "$TEMPLATE" > "$out_file"
        printf "CREATED: %s\n" "$out_file"
    }

    case "$LANG" in
        en)   create_article en ;;
        uk)   create_article uk ;;
        both) create_article en; create_article uk ;;
        *)    printf "ERROR: lang must be en, uk, or both (got: %s)\n" "$LANG"; exit 1 ;;
    esac

    printf "\nNext: add to articles[] in ~/code/content/index.html:\n"
    printf "  {\n"
    printf "    id: \"%s\",\n" "$SLUG"
    printf "    title:       { en: \"%s\", uk: \"TODO\" },\n" "$TITLE"
    printf "    description: { en: \"TODO\", uk: \"TODO\" },\n"
    printf "    category: \"blog\",\n"
    printf "    tags: [],\n"
    printf "    status: \"draft\",\n"
    printf "    lang: [%s],\n" "$([ "$LANG" = "both" ] && printf '"en","uk"' || printf '"'"$LANG"'"')"
    printf "    url: { en: \"blog/en/%s.html\", uk: \"blog/uk/%s.html\" },\n" "$SLUG" "$SLUG"
    printf "    related: [],\n"
    printf "    price: { en: \"Free\", uk: \"Безкоштовно\" }\n"
    printf "  },\n"
