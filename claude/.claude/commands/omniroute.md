---
description: "Switch Claude Code to the local OmniRoute fallback (when Anthropic tokens run out) — checks server, key, model, then hands over the exact relaunch command"
argument-hint: "[status|switch|back] [model]"
---

# OmniRoute switch

Usage: /omniroute [status|switch|back] [model]   (default: switch, model `auto`)

A running session cannot change its own backend — switching = relaunching
Claude Code through OmniRoute. This command makes sure the fallback works,
then gives Mike the ready command. Always run shell steps from `~`
(the CLI loads `.env` from cwd and would pick up project env otherwise).

## Instructions

Load the key for every step (never print it, show only the prefix):
`export OMNIROUTE_API_KEY=$(grep '^OMNIROUTE_API_KEY=' ~/dotfiles/.env | cut -d= -f2-)`

### `status`
1. Server: `lsof -nP -iTCP:20128 -sTCP:LISTEN` → must be `127.0.0.1:20128`.
   Down → tell Mike to run `! cd ~ && omniroute serve --daemon --no-open --no-tray`
   (starting the daemon is blocked for the agent).
2. Key: `xh -b --ignore-stdin GET http://127.0.0.1:20128/v1/models "Authorization:Bearer $OMNIROUTE_API_KEY"`
   → model count, or the error (401 = wrong key; OmniRoute keys start `sk-`,
   `ci_live_` is Cheaper Inference, not OmniRoute).
3. Model: POST `/v1/chat/completions` with `model=<model>` and `reply OK`,
   `max_tokens:=20`. Print latency + reply or error. Echo every xh call in a
   `━━━ xh ━━━` banner with the key shown as `$OMNIROUTE_API_KEY`.
4. Session: say whether THIS session already runs via OmniRoute
   (`echo $ANTHROPIC_BASE_URL` contains `20128`).

### `switch` (default)
Run `status`. If the model answered, print as numbered steps for Mike:
1. Exit this session (`/exit`), or open a new terminal.
2. Run `claude-free --continue` (zsh function in `~/dotfiles/zsh/.zshrc`):
   opens an fzf model picker, tests the pick (`reply OK`), re-opens the picker
   on failure, launches only once a model answered. `--continue` resumes this
   conversation. Skip the picker: `OMNIROUTE_MODEL=<model> claude-free --continue`
   (still tested first). Test only: `omni-test <model>`; pick only: `omni-pick`.
   Statusline line 2 then shows `🔀 OmniRoute:<model>` instead of `🤖 <model>`.
3. Copy the command to the clipboard with `pbcopy`.
If the model failed: show the error and the known-good model from the
table below instead of handing over a broken command.

### `back`
Anthropic tokens are back → `/exit`, then plain `cc --continue`
(alias of `claude`). Nothing to undo: `claude-free` sets env only for its own
process. Confirm: statusline shows `🤖 <model>` again, not `🔀 OmniRoute`.
Optional: `omni-stop` stops the daemon; `claude-free` starts it again on demand.

## Known state (2026-10-13) — availability drifts day to day, always `omni-test`
| Model | Result |
|---|---|
| `ddgw/claude-haiku-4-5` (DuckDuckGo) | OK, ~3s — the only working free one |
| `auto` | OK (routes to the above) |
| Cloudflare `cfp/zai-org/glm-5.2` | OK ~7s on 10-13 (502 on 10-12) |
| UncloseAI `unc/*` | 404 |
| OpenCode `oc/*` | 403 — free tier works only inside the OpenCode app |
Stronger options: `omniroute providers auth kiro` (free Claude, OAuth) or
a funded Cheaper Inference / OpenRouter key.
