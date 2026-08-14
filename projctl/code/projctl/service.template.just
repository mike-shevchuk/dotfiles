# ─── projctl standard service interface ─────────────────────────────────────
# Copy the block below into a project's justfile and adjust the three vars.
# Then add ONE line to the registry in ~/code/projctl/justfile:
#     name|/abs/path/to/project|SESSION|PORT|EXTRA
#
# Contract every project keeps: start · stop · restart · status · logs · attach,
# every long-running process lives in a tmux session named {{session}}.

set dotenv-load

session := "myproj"                       # tmux session name (must be unique)
port    := "8000"                         # HTTP port, or "" if the app has none
run     := "python main.py"               # foreground command to run in tmux

# Start the service in a detached tmux session (idempotent)
start:
    #!/usr/bin/env bash
    set -uo pipefail
    if tmux has-session -t "{{session}}" 2>/dev/null; then
      echo "→ {{session}} already running (use: just restart)" >&2; exit 0
    fi
    echo "→ starting {{session}}..." >&2
    tmux new-session -d -s "{{session}}" -c "{{justfile_directory()}}"
    tmux send-keys -t "{{session}}" 'set -a; [ -f .env ] && . ./.env; set +a; {{run}}' Enter
    echo "  OK ({{session}} started)" >&2

# Stop the service
stop:
    #!/usr/bin/env bash
    set -uo pipefail
    if tmux has-session -t "{{session}}" 2>/dev/null; then
      tmux send-keys -t "{{session}}" C-c 2>/dev/null || true
      sleep 1
      tmux kill-session -t "{{session}}" 2>/dev/null || true
      echo "  OK ({{session}} stopped)" >&2
    else
      echo "→ {{session}} not running" >&2
    fi

# Restart the service
restart: stop
    @sleep 1
    @just start

# Show status (tmux session alive? port listening?)
status:
    #!/usr/bin/env bash
    set -uo pipefail
    if tmux has-session -t "{{session}}" 2>/dev/null; then
      echo "● {{session}} running"
    else
      echo "○ {{session}} stopped"
    fi
    if [ -n "{{port}}" ]; then
      lsof -iTCP:{{port}} -sTCP:LISTEN >/dev/null 2>&1 \
        && echo "  port :{{port}} LISTEN" || echo "  port :{{port}} (not listening)"
    fi

# Tail recent tmux output
logs:
    tmux capture-pane -t "{{session}}" -p -S -200 2>/dev/null || echo "not running"

# Attach to the tmux session (Ctrl-b d to detach)
attach:
    tmux attach -t "{{session}}"
