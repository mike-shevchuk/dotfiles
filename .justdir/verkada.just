# --- PUN-1650: Anthropic Managed Agent → direct Verkada access --------------
# Drive a Managed Agents session (api.anthropic.com/v1/sessions/.../events).
# Reads $ANTHROPIC_API_KEY from ~/dotfiles/.env — the value is NEVER printed;
# banners show the variable NAME (\$ANTHROPIC_API_KEY), like `todo-today`.
# Linear: https://linear.app/punchrescue/issue/PUN-1650

_VK_SESSION := "sesn_01R3QaeE8wkg7kMUvknzfnBt"
_VK_BETA    := "managed-agents-2026-04-01"
_VK_MSG     := "List the available Verkada cameras. First call POST /token to get an auth token, then GET /cameras/v1/devices. Report what you get back — do not fetch any thumbnails yet."

# Send a user.message event to the CMA session (default: list Verkada devices)
[group('claude/verkada')]
verkada-send session=_VK_SESSION text=_VK_MSG:
    #!/usr/bin/env bash
    set -uo pipefail
    echo "→ [1/3] loading credentials from ~/dotfiles/.env..." >&2
    [ -f "$HOME/dotfiles/.env" ] && set -a && source "$HOME/dotfiles/.env" && set +a
    if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
        echo "  FAIL — ANTHROPIC_API_KEY not set. Add it to ~/dotfiles/.env (value stays out of the terminal)." >&2
        exit 1
    fi
    echo "  OK (key present, ${#ANTHROPIC_API_KEY} chars — value hidden)" >&2

    url="https://api.anthropic.com/v1/sessions/{{session}}/events"
    echo "→ [2/3] building user.message payload..." >&2
    payload=$(jq -cn --arg t "{{text}}" \
        '{events:[{type:"user.message",content:[{type:"text",text:$t}]}]}')
    echo "  OK payload: $payload" >&2

    echo "→ [3/3] POSTing event to session {{session}}..." >&2
    echo "━━━ curl ━━━" >&2
    echo "curl -X POST '$url' \\" >&2
    echo "  -H 'x-api-key: \$ANTHROPIC_API_KEY' \\" >&2
    echo "  -H 'anthropic-version: 2023-06-01' \\" >&2
    echo "  -H 'anthropic-beta: {{_VK_BETA}}' \\" >&2
    echo "  -H 'content-type: application/json' \\" >&2
    echo "  -d '$payload'" >&2
    echo "━━━━━━━━━━━━" >&2

    resp=$(curl -sS -w $'\n%{http_code}' -X POST "$url" \
        -H "x-api-key: $ANTHROPIC_API_KEY" \
        -H "anthropic-version: 2023-06-01" \
        -H "anthropic-beta: {{_VK_BETA}}" \
        -H "content-type: application/json" \
        -d "$payload")
    code=$(printf '%s' "$resp" | tail -n1)
    body=$(printf '%s' "$resp" | sed '$d')
    printf '%s\n' "$body" | jq . 2>/dev/null || printf '%s\n' "$body"
    if [ "$code" -ge 200 ] && [ "$code" -lt 300 ]; then
        echo "  OK ($code) — event queued. Watch it with: just verkada-stream" >&2
    else
        echo "  FAIL ($code)" >&2; exit 1
    fi

# Tail the session event stream (SSE) — Ctrl-C to stop
[group('claude/verkada')]
verkada-stream session=_VK_SESSION:
    #!/usr/bin/env bash
    set -uo pipefail
    echo "→ loading credentials from ~/dotfiles/.env..." >&2
    [ -f "$HOME/dotfiles/.env" ] && set -a && source "$HOME/dotfiles/.env" && set +a
    if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
        echo "  FAIL — ANTHROPIC_API_KEY not set. Add it to ~/dotfiles/.env." >&2
        exit 1
    fi
    url="https://api.anthropic.com/v1/sessions/{{session}}/events/stream"
    echo "━━━ curl ━━━" >&2
    echo "curl -N '$url' \\" >&2
    echo "  -H 'x-api-key: \$ANTHROPIC_API_KEY' \\" >&2
    echo "  -H 'anthropic-version: 2023-06-01' \\" >&2
    echo "  -H 'anthropic-beta: {{_VK_BETA}}'" >&2
    echo "━━━━━━━━━━━━ (Ctrl-C to stop)" >&2
    curl -N "$url" \
        -H "x-api-key: $ANTHROPIC_API_KEY" \
        -H "anthropic-version: 2023-06-01" \
        -H "anthropic-beta: {{_VK_BETA}}"
