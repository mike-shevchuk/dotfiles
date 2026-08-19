# --- PUN-1650: Anthropic Managed Agent → direct Verkada access --------------
# Drive a Managed Agents session (api.anthropic.com/v1/sessions/.../events).
#
# ANTHROPIC_API_KEY is resolved, in order, and NEVER printed (banners show the
# variable NAME, like `todo-today`):
#   1. $ANTHROPIC_API_KEY already in the environment
#   2. ~/dotfiles/.env
#   3. AWS Secrets Manager  →  /dev/rescue-serverless  (same blob as `jb2b secret-keys`)
# Linear: https://linear.app/punchrescue/issue/PUN-1650

_VK_SESSION := "sesn_01R3QaeE8wkg7kMUvknzfnBt"
_VK_BETA    := "managed-agents-2026-04-01"
_VK_MSG     := "List the available Verkada cameras. First call POST /token to get an auth token, then GET /cameras/v1/devices. Report what you get back — do not fetch any thumbnails yet."
_VK_SID     := "/dev/rescue-serverless"
_VK_REGION  := "us-east-1"
_VK_ENVFILE := "/tmp/verkada-session.env"

# Send a user.message event to the CMA session (default: list Verkada devices)
[group('claude/verkada')]
verkada-send session=_VK_SESSION text=_VK_MSG:
    #!/usr/bin/env bash
    set -uo pipefail
    echo "→ [1/3] resolving ANTHROPIC_API_KEY (env → .env → AWS Secrets Manager)..." >&2
    if [ -z "${ANTHROPIC_API_KEY:-}" ] && [ -f "$HOME/dotfiles/.env" ]; then set -a; source "$HOME/dotfiles/.env"; set +a; fi
    if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
        echo "  · not in env/.env — pulling from AWS Secrets Manager ({{_VK_SID}})..." >&2
        ANTHROPIC_API_KEY=$(aws secretsmanager get-secret-value --secret-id '{{_VK_SID}}' \
            --query SecretString --output text --region '{{_VK_REGION}}' 2>/dev/null \
            | jq -r '.ANTHROPIC_API_KEY // empty')
    fi
    if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
        echo "  FAIL — could not resolve ANTHROPIC_API_KEY (env / .env / AWS all empty)." >&2; exit 1
    fi
    echo "  OK (key resolved, ${#ANTHROPIC_API_KEY} chars — value hidden)" >&2

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

# Tail the session event stream (SSE). max_time=0 → no timeout (Ctrl-C to stop)
[group('claude/verkada')]
verkada-stream session=_VK_SESSION max_time="0":
    #!/usr/bin/env bash
    set -uo pipefail
    if [ -z "${ANTHROPIC_API_KEY:-}" ] && [ -f "$HOME/dotfiles/.env" ]; then set -a; source "$HOME/dotfiles/.env"; set +a; fi
    if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
        ANTHROPIC_API_KEY=$(aws secretsmanager get-secret-value --secret-id '{{_VK_SID}}' \
            --query SecretString --output text --region '{{_VK_REGION}}' 2>/dev/null \
            | jq -r '.ANTHROPIC_API_KEY // empty')
    fi
    [ -n "${ANTHROPIC_API_KEY:-}" ] || { echo "  FAIL — ANTHROPIC_API_KEY unresolved." >&2; exit 1; }
    url="https://api.anthropic.com/v1/sessions/{{session}}/events/stream"
    echo "━━━ curl ━━━" >&2
    echo "curl -N --max-time {{max_time}} '$url' -H 'x-api-key: \$ANTHROPIC_API_KEY' -H 'anthropic-version: 2023-06-01' -H 'anthropic-beta: {{_VK_BETA}}'" >&2
    echo "━━━━━━━━━━━━ (Ctrl-C to stop)" >&2
    curl -N --max-time {{max_time}} "$url" \
        -H "x-api-key: $ANTHROPIC_API_KEY" \
        -H "anthropic-version: 2023-06-01" \
        -H "anthropic-beta: {{_VK_BETA}}"

# Materialize a Linux session env file (0600) with secrets pulled from AWS.
# Default: just ANTHROPIC_API_KEY. Values go to the file only, never to stdout.
#   just verkada-env                       → writes ANTHROPIC_API_KEY
#   just verkada-env "ANTHROPIC_API_KEY OPENAI_API_KEY"
#   source /tmp/verkada-session.env        → loads them into THIS shell
[group('claude/verkada')]
verkada-env keys="ANTHROPIC_API_KEY":
    #!/usr/bin/env bash
    set -euo pipefail
    echo "→ [1/2] fetching {{keys}} from AWS Secrets Manager ({{_VK_SID}})..." >&2
    blob=$(aws secretsmanager get-secret-value --secret-id '{{_VK_SID}}' \
        --query SecretString --output text --region '{{_VK_REGION}}')
    out="{{_VK_ENVFILE}}"
    echo "→ [2/2] writing 0600 env file → $out ..." >&2
    ( umask 077
      { echo "# {{_VK_SID}} — written by 'just verkada-env'. Delete when done (verkada-env-clean)."
        for k in {{keys}}; do
            v=$(printf '%s' "$blob" | jq -r --arg k "$k" '.[$k] // empty')
            if [ -z "$v" ]; then echo "  · WARN: '$k' absent in secret — skipped" >&2; continue; fi
            printf 'export %s=%q\n' "$k" "$v"
        done
      } > "$out" )
    n=$(grep -c '^export' "$out" || true)
    echo "  OK — wrote $n secret(s) → $out ($(stat -f '%Sp' "$out" 2>/dev/null || stat -c '%A' "$out"))" >&2
    echo "  use:  source $out    (loads into your current shell/session)" >&2

# Delete the session env file
[group('claude/verkada')]
verkada-env-clean:
    #!/usr/bin/env bash
    set -uo pipefail
    if [ -f "{{_VK_ENVFILE}}" ]; then rm -f "{{_VK_ENVFILE}}"; echo "  removed {{_VK_ENVFILE}}" >&2
    else echo "  nothing to remove ({{_VK_ENVFILE}})" >&2; fi

# Browse the secret's key NAMES via fzf; on pick, show a MASKED value (abcd…wxyz).
# Never prints a full value. Needs fzf.
[group('claude/verkada')]
verkada-secrets:
    #!/usr/bin/env bash
    set -uo pipefail
    command -v fzf >/dev/null || { echo "  FAIL: fzf not installed." >&2; exit 2; }
    echo "→ fetching secret key names ({{_VK_SID}})..." >&2
    blob=$(aws secretsmanager get-secret-value --secret-id '{{_VK_SID}}' \
        --query SecretString --output text --region '{{_VK_REGION}}')
    name=$(printf '%s' "$blob" | jq -r 'keys[]' \
        | fzf --prompt="secret ({{_VK_SID}}) > " --height=50% --reverse \
              --header="Enter = show masked value (never the full secret)") || true
    [ -n "$name" ] || { echo "  (nothing picked)" >&2; exit 130; }
    v=$(printf '%s' "$blob" | jq -r --arg k "$name" '.[$k] // empty')
    printf '  %-34s %s…%s  (%d chars)\n' "$name" "${v:0:4}" "${v: -4}" "${#v}" >&2
