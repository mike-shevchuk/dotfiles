# =============================================================================
# global.just — shared recipes available from anywhere via `just -g <recipe>`
# =============================================================================
#
# This file is symlinked from ~/.config/just/justfile — the path that
# `just --global-justfile` (alias `-g`) resolves to. After running
# `just install-global` from ~/dotfiles, `just -g <recipe>` works from
# any directory on the machine.
#
# CONVENTIONS (per ~/CLAUDE.md justfile visibility rules)
# ═══════════════════════════════════════════════════════
# Every recipe echoes progress to stderr — `→ doing X` before work,
# `OK`/`FAIL` after. Recipes that hit the network show the curl command
# inside a `━━━ curl ... ━━━` banner so it's copy-pasteable.
#
# ZSH SHORTCUTS (defined in zsh/.zshrc)
# ═════════════════════════════════════
#   jj   = grouped fzf chooser → echoes the chosen `just -g <recipe>`,
#          then runs it (prompts for args if the recipe takes any)
#   jd   = `just -g --dry-run` (print commands without running)
#   jv   = `just -g --verbose` (echo each shell command before running)
#   jq-  = `just -g --quiet`   (suppress recipe banners — `jq` is taken)
# =============================================================================

# Default: pop the chooser (use `jjg` from zsh for the grouped preview view)
default:
    @just -g --choose

# --- Cheatsheets ------------------------------------------------------------
#
# ONE fuzzy entry point for every cheatsheet on the machine. Sources:
#   1. ~/dotfiles/README.md   — each `## …` section, split into the cache
#   2. ~/zettelkasten/IT/cheatsheet/**/*.md
#   3. ~/zettelkasten/claude_code/**/*cheatsheet*.md
# Nothing is moved: README sections are exploded into ~/.cache/cheat/readme/
# only when README is newer than the cache. fzf shows "SOURCE  title",
# previews with bat, Enter opens the full sheet in the pager.
#
#   just -g cheat            → browse everything
#   just -g cheat tmux       → pre-filter the fzf query to "tmux"
#   just -g cheat-list       → plain list of all sheets (no fzf, scriptable)
# To add a sheet: drop any *.md into ~/zettelkasten/IT/cheatsheet/ — done.

# Fuzzy-browse every cheatsheet (README sections + zettelkasten notes)
[group('cheat')]
cheat query="":
    #!/usr/bin/env bash
    set -uo pipefail
    cache="$HOME/.cache/cheat/readme"
    readme="$HOME/dotfiles/README.md"
    mkdir -p "$cache"

    # Rebuild the README split only when README changed (mtime compare)
    marker="$cache/.src-mtime"
    src_mtime=$(stat -f %m "$readme" 2>/dev/null || stat -c %Y "$readme" 2>/dev/null || echo 0)
    if [ "$(cat "$marker" 2>/dev/null || echo 0)" != "$src_mtime" ]; then
        echo "→ indexing README sections into $cache ..." >&2
        rm -f "$cache"/*.md
        awk -v dir="$cache" '
            /^## / {
                n++; title=$0; sub(/^## /,"",title)
                slug=tolower(title); gsub(/[^a-z0-9]+/,"-",slug); gsub(/^-|-$/,"",slug)
                cur=sprintf("%s/%02d-%s.md", dir, n, slug)
            }
            cur { print > cur }
        ' "$readme"
        echo "$src_mtime" > "$marker"
    fi

    # Build the index:  "SOURCE\tTITLE\tPATH"  (tab-delimited)
    build_index() {
        for f in "$cache"/*.md; do
            [ -f "$f" ] || continue
            t=$(head -1 "$f" | sed 's/^#* *//')
            printf 'README\t%s\t%s\n' "$t" "$f"
        done
        for f in "$HOME/zettelkasten/IT/cheatsheet"/**/*.md \
                 "$HOME/zettelkasten/IT/cheatsheet"/*.md; do
            [ -f "$f" ] || continue
            printf 'zettel\t%s\t%s\n' "$(basename "$f" .md)" "$f"
        done
        for f in "$HOME/zettelkasten/claude_code"/**/*cheatsheet*.md; do
            [ -f "$f" ] || continue
            printf 'claude\t%s\t%s\n' "$(basename "$(dirname "$f")")/$(basename "$f" .md)" "$f"
        done
    }

    index=$(build_index | sort -u)
    if [ -z "$index" ]; then echo "  no cheatsheets found" >&2; exit 1; fi

    # fzf: show "SOURCE  title" (fields 1-2), preview field 3 with bat.
    pick=$(printf '%s\n' "$index" | \
        fzf --query="{{query}}" --delimiter='\t' --with-nth=1,2 \
            --prompt='cheat ❯ ' --height=90% --border --ansi \
            --preview='bat --color=always --style=numbers,grid {3} 2>/dev/null || cat {3}' \
            --preview-window='right,65%,wrap')
    [ -z "$pick" ] && { echo "  (nothing selected)" >&2; exit 0; }

    path=$(printf '%s' "$pick" | cut -f3)
    bat --paging=always --style=full "$path" 2>/dev/null || less "$path"

# Plain list of all cheatsheets — scriptable, no fzf (SOURCE · title · path)
[group('cheat')]
cheat-list:
    #!/usr/bin/env bash
    set -uo pipefail
    just -g cheat >/dev/null 2>&1 &  # warm the README cache in background
    cache="$HOME/.cache/cheat/readme"
    printf "\n  %-8s  %s\n" "SOURCE" "CHEATSHEET"
    printf "  %-8s  %s\n" "------" "----------"
    for f in "$cache"/*.md; do
        [ -f "$f" ] && printf "  %-8s  %s\n" "README" "$(head -1 "$f" | sed 's/^#* *//')"
    done
    for f in "$HOME/zettelkasten/IT/cheatsheet"/*.md \
             "$HOME/zettelkasten/claude_code"/**/*cheatsheet*.md; do
        [ -f "$f" ] && printf "  %-8s  %s\n" "zettel" "$(basename "$f" .md)"
    done
    printf "\n"

# --- Git / repo sync --------------------------------------------------------

# Pull dotfiles, show status — used by night-job
[group('git')]
dotfiles-sync:
    #!/usr/bin/env bash
    set -uo pipefail
    cd "$HOME/dotfiles"
    echo "→ git -C ~/dotfiles pull --ff-only" >&2
    git pull --ff-only 2>&1 | sed 's/^/  /' >&2 || echo "  FAIL — non-fast-forward" >&2
    echo "→ git status --short" >&2
    git status --short | sed 's/^/  /' >&2 || true

# Pull zettelkasten, show status — used by night-job
[group('git')]
zettel-sync:
    #!/usr/bin/env bash
    set -uo pipefail
    zk="$HOME/zettelkasten"
    if [ ! -d "$zk/.git" ]; then
        echo "→ $zk is not a git repo — skipping" >&2; exit 0
    fi
    cd "$zk"
    echo "→ git -C ~/zettelkasten pull --ff-only" >&2
    git pull --ff-only 2>&1 | sed 's/^/  /' >&2 || echo "  FAIL — non-fast-forward" >&2
    echo "→ git status --short" >&2
    git status --short | sed 's/^/  /' >&2 || true

# Show uncommitted changes across every git repo under ~/dotfiles, ~/zettelkasten, ~/code
[group('git')]
git-status-all:
    #!/usr/bin/env bash
    set -uo pipefail
    echo "→ scanning git repos for uncommitted changes..." >&2
    dirty_count=0
    for root in "$HOME/dotfiles" "$HOME/zettelkasten" "$HOME/code"; do
        [ -d "$root" ] || continue
        while IFS= read -r dot; do
            repo="$(dirname "$dot")"
            dirty=$(git -C "$repo" status --short 2>/dev/null)
            if [ -n "$dirty" ]; then
                dirty_count=$((dirty_count + 1))
                echo ""
                echo "  ${repo/$HOME/~}:"
                echo "$dirty" | sed 's/^/    /'
            fi
        done < <(find "$root" -maxdepth 3 -type d -name .git 2>/dev/null)
    done
    echo "  OK — $dirty_count repo(s) with uncommitted changes" >&2

# --- Reddit daily digest ----------------------------------------------------

# Build today's Reddit digest (calls ~/code/reddit-digest/run.sh if present)
[group('night')]
reddit-digest:
    #!/usr/bin/env bash
    set -uo pipefail
    runner="$HOME/code/reddit-digest/run.sh"
    if [ -x "$runner" ]; then
        echo "→ $runner" >&2
        "$runner"
    else
        echo "→ reddit-digest runner not found at $runner — stub" >&2
        echo "  Create $runner and chmod +x to enable the nightly digest." >&2
        echo "  Tracked in MEMORY.md → project_reddit_digest" >&2
        exit 2   # exit-2 = SKIP (night-job differentiates SKIP from FAIL)
    fi

# --- Night job (the cron entry runs this) -----------------------------------

# Run all nightly automation jobs in sequence; box-render summary to log
[group('night')]
night-job:
    #!/usr/bin/env bash
    set -uo pipefail
    cache="$HOME/.cache/night-jobs"
    mkdir -p "$cache"
    summary="$cache/summary.log"   # one boxed entry per run (rendered)
    detail="$cache/detail.log"     # full stdout/stderr from every step

    run_step() {
        # $1=label  $2=just-target
        local label="$1" target="$2" out status one
        out=$(just -g "$target" 2>&1); status=$?
        {
            echo ""
            echo "─── $(date '+%H:%M:%S')  $label ───────────────────────────"
            echo "$out"
        } >> "$detail"
        one=$(echo "$out" | grep -v '^$' | tail -1 | sed 's/^[[:space:]]*//' | head -c 30)
        case "$status" in
            0) printf "OK   %s" "${one:-done}" ;;
            2) printf "SKIP %s" "${one:-skipped}" ;;
            *) printf "FAIL %s" "${one:-error}" ;;
        esac
    }

    start_ts=$(date +%s)
    label=$(date '+%Y-%m-%d %H:%M:%S')
    s1=$(run_step "dotfiles-sync" "dotfiles-sync")
    s2=$(run_step "zettel-sync"    "zettel-sync")
    s3=$(run_step "reddit-digest"  "reddit-digest")
    elapsed=$(( $(date +%s) - start_ts ))

    {
        printf "┌─ %s ─────────────────────────────────────┐\n" "$label"
        printf "│ [1/3] dotfiles-sync          %-30s│\n" "$s1"
        printf "│ [2/3] zettel-sync            %-30s│\n" "$s2"
        printf "│ [3/3] reddit-digest          %-30s│\n" "$s3"
        printf "│        elapsed: %-42ds│\n" "$elapsed"
        printf "└────────────────────────────────────────────────────────────┘\n"
    } | tee -a "$summary"

# Tail the boxed summary log with status colours (default 4 most recent runs)
[group('night')]
night-log n="4":
    #!/usr/bin/env bash
    [[ "{{n}}" =~ ^[0-9]+$ ]] || { echo "FAIL — n must be a positive integer, got: {{n}}" >&2; exit 1; }
    log="$HOME/.cache/night-jobs/summary.log"
    if [ ! -f "$log" ]; then
        echo "no log yet at $log — run: just -g night-job" >&2; exit 0
    fi
    # 6 lines per box → show last n*6 lines, then colourize OK/FAIL/SKIP
    lines=$(( {{n}} * 6 ))
    echo "→ tail -$lines $log (last {{n}} box(es))" >&2
    tail -"$lines" "$log" \
        | sed -E "s/OK  /$(printf '\033[32m')OK  $(printf '\033[0m')/g" \
        | sed -E "s/FAIL/$(printf '\033[31m')FAIL$(printf '\033[0m')/g" \
        | sed -E "s/SKIP/$(printf '\033[33m')SKIP$(printf '\033[0m')/g"

# Tail the full detail log (per-step stdout/stderr) — default last 100 lines
[group('night')]
night-log-detail n="100":
    #!/usr/bin/env bash
    [[ "{{n}}" =~ ^[0-9]+$ ]] || { echo "FAIL — n must be a positive integer, got: {{n}}" >&2; exit 1; }
    log="$HOME/.cache/night-jobs/detail.log"
    if [ ! -f "$log" ]; then
        echo "no detail log yet at $log — run: just -g night-job" >&2; exit 0
    fi
    echo "→ tail -{{n}} $log" >&2
    tail -{{n}} "$log"

# Install a cron entry that runs night-job at HOUR:00 daily (default 03:00)
[group('night')]
night-install hour="3":
    #!/usr/bin/env bash
    set -euo pipefail
    [[ "{{hour}}" =~ ^([0-9]|1[0-9]|2[0-3])$ ]] || { echo "FAIL — hour must be 0-23, got: {{hour}}" >&2; exit 1; }
    just_bin=$(command -v just || echo /opt/homebrew/bin/just)
    line="0 {{hour}} * * * $just_bin -g night-job >/dev/null 2>&1"
    echo "→ proposed crontab entry:" >&2
    echo "    $line" >&2
    if crontab -l 2>/dev/null | grep -qF 'just -g night-job'; then
        echo "  already installed — edit with: crontab -e" >&2; exit 0
    fi
    ( crontab -l 2>/dev/null; echo "$line" ) | crontab -
    echo "  OK — installed. Inspect with: crontab -l" >&2

# Remove the night-job cron entry
[group('night')]
night-uninstall:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! crontab -l 2>/dev/null | grep -qF 'just -g night-job'; then
        echo "→ no night-job cron entry to remove" >&2; exit 0
    fi
    crontab -l 2>/dev/null | grep -vF 'just -g night-job' | crontab -
    echo "  OK — removed." >&2

# Show currently installed cron entries
[group('night')]
cron-list:
    #!/usr/bin/env bash
    echo "→ crontab -l" >&2
    crontab -l 2>/dev/null || echo "  (no crontab installed)"

# --- Network / system info --------------------------------------------------

# Current public IP
[group('system')]
ip:
    #!/usr/bin/env bash
    echo "━━━ curl -s https://ifconfig.me ━━━" >&2
    curl -s https://ifconfig.me && echo ""

# Local weather, optional CITY arg (multi-word OK: `weather "New York"`)
[group('system')]
weather city="":
    #!/usr/bin/env bash
    # URL-encode the city so spaces / non-ASCII work
    city_enc=$(printf %s "{{city}}" | jq -sRr @uri)
    url="https://wttr.in/${city_enc}?format=3"
    echo "━━━ curl -s '$url' ━━━" >&2
    curl -s "$url"; echo

# Multi-day ASCII forecast from wttr.in. days=1|2|3 (wttr max is 3).
[group('system')]
forecast city="" days="3":
    #!/usr/bin/env bash
    city_enc=$(printf %s "{{city}}" | jq -sRr @uri)
    # ?{{days}} limits days; F=hide follow line, M=metric wind, q=no header
    url="https://wttr.in/${city_enc}?{{days}}FMq"
    echo "━━━ curl -s '$url' ━━━" >&2
    curl -s "$url"

# Compact wttr.in view — morning/noon/evening/night summary table, narrower
[group('system')]
forecast-narrow city="":
    #!/usr/bin/env bash
    city_enc=$(printf %s "{{city}}" | jq -sRr @uri)
    url="https://wttr.in/${city_enc}?nFMq"
    echo "━━━ curl -s '$url' ━━━" >&2
    curl -s "$url"

# Resolve a city (or auto-detect via ip-api) → lat<TAB>lon<TAB>name on stdout
[group('system')]
[private]
_resolve-location city="":
    #!/usr/bin/env bash
    set -uo pipefail
    if [ -z "{{city}}" ]; then
        geo_url="http://ip-api.com/json/?fields=city,lat,lon"
        echo "━━━ curl -s '$geo_url' ━━━" >&2
        curl -s "$geo_url" | jq -r '[.lat, .lon, .city] | @tsv'
    else
        city_enc=$(printf %s "{{city}}" | jq -sRr @uri)
        geo_url="https://geocoding-api.open-meteo.com/v1/search?count=1&name=${city_enc}"
        echo "━━━ curl -s '$geo_url' ━━━" >&2
        out=$(curl -s "$geo_url" | jq -r ".results[0] // empty | [.latitude, .longitude, (.name // \"{{city}}\")] | @tsv")
        [ -z "$out" ] && { echo "  FAIL — city '{{city}}' not found" >&2; exit 1; }
        printf '%s\n' "$out"
    fi

# Pretty 24h chart: Unicode temp chart + rain/precip-prob/wind bars (Open-Meteo)
[group('system')]
forecast-chart city="":
    #!/usr/bin/env bash
    set -uo pipefail
    echo "[1/2] resolving location..." >&2
    IFS=$'\t' read -r lat lon name < <(just -g _resolve-location "{{city}}")
    [ -z "$lat" ] && exit 1
    echo "[2/2] fetching 24h forecast for $name..." >&2
    url="https://api.open-meteo.com/v1/forecast?latitude=${lat}&longitude=${lon}&hourly=temperature_2m,precipitation,precipitation_probability,wind_speed_10m&forecast_hours=24&timezone=auto"
    echo "━━━ curl -s '$url' ━━━" >&2
    fc=$(curl -s "$url")
    NAME="$name" JSON="$fc" python3 - <<'PY'
    import json, sys, os, math
    data = json.loads(os.environ['JSON'])
    h = data['hourly']
    N = min(24, len(h['time']))
    times  = h['time'][:N]
    temps  = h['temperature_2m'][:N]
    precip = h['precipitation'][:N]
    pprob  = h['precipitation_probability'][:N]
    wind   = h['wind_speed_10m'][:N]
    name   = os.environ.get('NAME', '')
    W = 2  # column width (each hour spans W chars)
    # ── temp chart bounds, snapped to multiples of 3°
    tmin, tmax = min(temps), max(temps)
    span = max(tmax - tmin, 3)
    tmin_r = math.floor((tmin - span * 0.1) / 3) * 3
    tmax_r = math.ceil ((tmax + span * 0.1) / 3) * 3
    rows = 5
    step = (tmax_r - tmin_r) / rows
    blocks = ' ▁▂▃▄▅▆▇█'
    GREEN = "\033[38;5;82m"; YELLOW = "\033[38;5;226m"; RED = "\033[38;5;203m"
    BLUE  = "\033[38;5;39m"; GREY = "\033[38;5;244m"; RESET = "\033[0m"
    def temp_color(t):
        if t < 5:  return BLUE
        if t < 15: return GREEN
        if t < 25: return YELLOW
        return RED
    # build chart matrix
    def temp_cell(t, r):
        cell_bot = tmin_r + r * step
        cell_top = tmin_r + (r + 1) * step
        if t >= cell_top: return '█'
        if t <= cell_bot: return ' '
        frac = (t - cell_bot) / step
        return blocks[min(8, max(1, round(frac * 8)))]
    print()
    header_pad = max(0, 52 - len(name) - len(" · next 24h "))
    print(f"  ──── {GREY}{name}{RESET} · next 24h " + "─" * header_pad)
    for r in range(rows - 1, -1, -1):
        label = f"{int(tmin_r + (r + 1) * step):3d}°"
        line = ''
        for t in temps:
            ch = temp_cell(t, r)
            line += (temp_color(t) + ch + RESET) * W
        print(f"  {label}┤{line}")
    print(f"      └" + "─" * (N * W))
    xax_chars = []
    for i in range(N):
        hh = int(times[i][11:13])
        if i % 3 == 0:
            xax_chars.append(f"{hh:02d}" + " " * (W * 3 - 2))
    print("       " + "".join(xax_chars))
    # ── bottom strips
    def shaded_bar(vals, maxv):
        out = ''
        for v in vals:
            f = min(1.0, v / maxv) if maxv > 0 else 0
            if f < 0.01:   c = ' '
            elif f < 0.25: c = '░'
            elif f < 0.50: c = '▒'
            elif f < 0.75: c = '▓'
            else:          c = '█'
            out += c * W
        return out
    def block_bar(vals, maxv):
        out = ''
        for v in vals:
            f = min(1.0, v / maxv) if maxv > 0 else 0
            ch = ' ' if f < 0.01 else blocks[min(8, max(1, round(f * 8)))]
            out += ch * W
        return out
    print()
    rain_max = max(precip) if precip else 0
    wind_max = max(wind)   if wind   else 0
    print(f"  rain  │{BLUE}{block_bar(precip, max(rain_max, 0.1))}{RESET}│ max {rain_max:.1f} mm")
    print(f"  p(%)  │{BLUE}{shaded_bar(pprob, 100)}{RESET}│ peak {max(pprob)}%")
    print(f"  wind  │{GREY}{block_bar(wind, max(wind_max, 1))}{RESET}│ {min(wind):.0f}–{wind_max:.0f} km/h")
    print()
    PY

# wttr.in v2 — graph view: hourly temp curve, precip bars, wind arrows (3 days)
[group('system')]
forecast-graph city="":
    #!/usr/bin/env bash
    city_enc=$(printf %s "{{city}}" | jq -sRr @uri)
    url="https://wttr.in/${city_enc}?format=v2"
    echo "━━━ curl -s '$url' ━━━" >&2
    curl -s "$url"

# Hourly numeric table for next 24h via Open-Meteo
[group('system')]
forecast-hourly city="":
    #!/usr/bin/env bash
    set -uo pipefail
    echo "[1/2] resolving location..." >&2
    IFS=$'\t' read -r lat lon name < <(just -g _resolve-location "{{city}}")
    [ -z "$lat" ] && exit 1
    echo "[2/2] fetching next 24h for $name..." >&2
    url="https://api.open-meteo.com/v1/forecast?latitude=${lat}&longitude=${lon}&hourly=temperature_2m,precipitation,precipitation_probability,wind_speed_10m&forecast_hours=24&timezone=auto"
    echo "━━━ curl -s '$url' ━━━" >&2
    curl -s "$url" | jq -r '
        .hourly as $h
        | "  time              temp    precip   p(%)   wind",
          "  ──────────────────────────────────────────────────",
          (range(0; $h.time|length) as $k |
            "  \($h.time[$k] | sub("T"; " "))   \($h.temperature_2m[$k])°    \($h.precipitation[$k])mm    \($h.precipitation_probability[$k])%    \($h.wind_speed_10m[$k]) km/h")
    '

# 7-day forecast via Open-Meteo (free, no key). Resolves city → lat/lon first.
[group('system')]
forecast-week city="":
    #!/usr/bin/env bash
    set -uo pipefail
    echo "[1/2] resolving location..." >&2
    IFS=$'\t' read -r lat lon name < <(just -g _resolve-location "{{city}}")
    [ -z "$lat" ] && exit 1
    echo "[2/2] fetching 7-day forecast for $name (lat=$lat lon=$lon)..." >&2
    fc_url="https://api.open-meteo.com/v1/forecast?latitude=${lat}&longitude=${lon}&daily=temperature_2m_max,temperature_2m_min,precipitation_sum,weather_code&timezone=auto&forecast_days=7"
    echo "━━━ curl -s '$fc_url' ━━━" >&2
    fc=$(curl -s "$fc_url")
    echo "$fc" | jq -r '
        def wmo(c):
            {"0":"☀️  clear","1":"🌤️  mostly clear","2":"⛅️ partly cloudy","3":"☁️  overcast",
             "45":"🌫️  fog","48":"🌫️  rime fog","51":"🌦️  drizzle","53":"🌦️  drizzle","55":"🌦️  drizzle",
             "61":"🌧️  rain","63":"🌧️  rain","65":"🌧️  heavy rain","71":"🌨️  snow","73":"🌨️  snow",
             "75":"🌨️  heavy snow","80":"🌦️  showers","81":"🌦️  showers","82":"⛈️  violent showers",
             "95":"⛈️  thunderstorm","96":"⛈️  thunder+hail","99":"⛈️  thunder+hail"}[c|tostring] // "  ?";
        .daily as $d
        | "  date          min   max   precip   weather",
          "  ───────────────────────────────────────────────",
          (range(0; $d.time|length) as $k |
            "  \($d.time[$k])  \($d.temperature_2m_min[$k])°  \($d.temperature_2m_max[$k])°   \($d.precipitation_sum[$k])mm    \(wmo($d.weather_code[$k]))")
    '

# Listening TCP ports
[group('system')]
ports:
    #!/usr/bin/env bash
    echo "→ lsof -iTCP -sTCP:LISTEN -P -n" >&2
    lsof -iTCP -sTCP:LISTEN -P -n 2>/dev/null | awk 'NR==1 || /LISTEN/'

# Disk usage of $HOME top-level dirs (top 15, human-readable)
[group('system')]
disk:
    #!/usr/bin/env bash
    echo "→ du -sh ~/* (top 15 by size)" >&2
    du -sh "$HOME"/* 2>/dev/null | sort -rh | head -15

# --- Todoist / Claude quick refs --------------------------------------------

# Today's Todoist tasks (uses $TODOIST_TOKEN from ~/dotfiles/.env)
[group('claude/todoist')]
todo-today:
    #!/usr/bin/env bash
    set -uo pipefail
    [ -f "$HOME/dotfiles/.env" ] && set -a && source "$HOME/dotfiles/.env" && set +a
    if [ -z "${TODOIST_TOKEN:-}" ]; then
        echo "TODOIST_TOKEN not set — add it to ~/dotfiles/.env" >&2; exit 1
    fi
    echo "━━━ curl -s -G 'https://api.todoist.com/api/v1/tasks' --data-urlencode 'filter=today' -H 'Authorization: Bearer \$TODOIST_TOKEN' ━━━" >&2
    curl -s -G "https://api.todoist.com/api/v1/tasks" \
        --data-urlencode "filter=today" \
        -H "Authorization: Bearer $TODOIST_TOKEN" \
        | jq -r '.results[]? | "  • \(.content)   [\(.id)]"' 2>/dev/null \
        || echo "  (no tasks or jq missing)"

# Forward to the project-local Claude statusline tokens recipe
[group('claude/todoist')]
tokens:
    @cd ~/dotfiles && just tokens

# --- Search / FS helpers ----------------------------------------------------

# Fuzzy-pick a directory under ~ via fd + fzf, print path
[group('search')]
pickdir:
    #!/usr/bin/env bash
    echo "→ fd dirs under \$HOME → fzf..." >&2
    fd --type d --hidden --exclude .git --exclude node_modules . "$HOME" \
        | fzf --prompt="cd → " --height=50% --border --preview='ls -la {}'

# rg + bat preview from the current dir
[group('search')]
rgp pattern:
    #!/usr/bin/env bash
    echo "→ rg '{{pattern}}' in $(pwd) → fzf+bat preview..." >&2
    rg --color=always --line-number -- "{{pattern}}" \
        | fzf --ansi --delimiter=: \
              --preview='bat --color=always --style=numbers --highlight-line {2} {1}' \
              --preview-window='right,60%,+{2}/2'

# --- TIL: engineering growth loop -------------------------------------------
# Capture: /til у Claude-сесії пише wiki/til-*.md у zettelkasten.
# Review:  ці рецепти — читання, повторення (spaced repetition), пошук.

TIL_DIR := env_var('HOME') / "zettelkasten/claude_code/wiki"

# Browse all TILs: fzf + bat preview, Enter = open in nvim
[group('til')]
til:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "→ TIL browser ({{TIL_DIR}}/til-*.md) → fzf+bat..." >&2
    pick=$(fd 'til-.*\.md' "{{TIL_DIR}}" 2>/dev/null | sort -r \
        | fzf --prompt="TIL → " --height=80% --border \
              --preview='bat --color=always --style=plain {}' \
              --preview-window='right,65%') || { echo "  (нічого не обрано)" >&2; exit 0; }
    nvim "$pick"

# Random TIL in the terminal — spaced repetition, add to shell startup or cron
[group('til')]
til-random:
    #!/usr/bin/env bash
    set -euo pipefail
    f=$(fd 'til-.*\.md' "{{TIL_DIR}}" 2>/dev/null | sort -R | head -1)
    if [ -z "$f" ]; then echo "  поки нема TIL — у Claude-сесії: /til <що вивчив>" >&2; exit 0; fi
    echo "━━━ 🎲 random TIL: $(basename "$f") ━━━" >&2
    bat --color=always --style=plain "$f"

# Full-text search across TILs (rg + fzf + bat)
[group('til')]
til-grep pattern:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "→ rg '{{pattern}}' у TIL-ах..." >&2
    rg --color=always --line-number -- "{{pattern}}" "{{TIL_DIR}}" --glob 'til-*.md' \
        | fzf --ansi --delimiter=: \
              --preview='bat --color=always --style=plain --highlight-line {2} {1}' \
              --preview-window='right,60%,+{2}/2'

# --- Self-help --------------------------------------------------------------

# List all global recipes
[group('self')]
ls:
    @just -g --list

# Show source of a recipe without running it
[group('self')]
show recipe:
    @just -g --show {{recipe}}
