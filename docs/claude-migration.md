# Migrating Claude Code to a new machine

Everything Claude-related lives in **three places**. Two are git repos; one is
manual-copy only. Follow the steps in order.

```
┌───────────────────────────────────────────────────────────────┐
│ 1. ~/dotfiles        public repo   → clone + just setup       │
│ 2. ~/zettelkasten    private repo  → clone + just claudes-link│
│ 3. manual files      NOT in git    → copy by hand (secrets)   │
└───────────────────────────────────────────────────────────────┘
```

## 1. Dotfiles (public repo — carries all Claude config)

```bash
git clone git@github.com:mike-shevchuk/dotfiles.git ~/dotfiles
cd ~/dotfiles && just setup      # stows claude, zsh, tmux, kitty, lz, yazi
```

The `claude` stow package symlinks into `~/.claude/`:

| What | Files |
|------|-------|
| Settings | `settings.json` (hooks wiring, statusline, model) |
| Statusline | `statusline.sh` |
| Hooks | `danger-guard`, `notification`, `stop`, `cost-logger`, `subagent_stop`, `shared` (.ts), `context-status.sh` |
| Sounds | `notification.wav`, `stop.wav`, `subagent_stop.wav` |
| Commands (17) | `sprint`, `next`, `prs`, `pr-state`, `pr-recap`, `week-recap`, `review-pr-eng`, `review-pr-ukr`, `review-html`, `self-review`, `just-test`, `coaching`, `check-pr`, `auto-mode`, `trigger`, `gsd-zettel-sync`, … |
| Scripts | `pipeline-stamp.sh`, `gsd-zettel-sync.sh`, `scripts/lgtm/` |

After any change made directly in `~/.claude`, run `just claude-drift` to see
files that never reached the repo.

## 2. Zettelkasten (private repo — carries all CLAUDE.md files)

```bash
git clone git@github.com:mike-shevchuk/zettelekasten.git ~/zettelkasten
cd ~/dotfiles && just claudes-link   # symlinks ~/CLAUDE.md + per-repo CLAUDE.md
```

Source of truth: `~/zettelkasten/claude_code/claudes/{global,<repo>}/CLAUDE.md`.
Also holds all notes, MOCs, and private Claude context. **Run `just sync` on the
old machine first** so nothing uncommitted is left behind.

## 3. Manual copies (secrets + machine state — never in git)

| File | Why manual | How |
|------|-----------|-----|
| `~/dotfiles/.env` | gitignored secrets: `TODOIST_TOKEN`, `GOOGLE_*`, `LINEAR_API_KEY`, `OTTER_*` | AirDrop / scp / password manager |
| `~/.claude/settings.local.json` | excluded by global git ignore; holds `enabledMcpjsonServers` (slack, linear, gdrive) + local permissions | copy the file |
| `~/.claude/projects/*/memory/` | Claude's persistent per-project memory (6 projects incl. rescue-serverless) | `rsync -a` the `memory/` dirs only — NOT the whole `projects/` (489 MB of transcripts) |
| `~/.claude/channels/telegram/` | Telegram bot pairing/token | copy, or just re-pair with `/telegram:configure` |
| `~/.claude/.credentials.json` | per-machine auth | do NOT copy — run `claude login` |
| `~/.claude.json` | MCP servers + per-project state | do NOT copy — re-add MCP: `claude mcp add obsidian …` |

```bash
# memory-only rsync (run from old machine):
rsync -a --include '*/' --include '*/memory/**' --exclude '*' \
      ~/.claude/projects/ newmachine:~/.claude/projects/
```

## 4. Reinstallables (do NOT back up — reinstall)

**GSD** — all `gsd-*` skills/agents/hooks are installer-managed:
install GSD fresh, it recreates `~/.claude/{skills,agents,hooks}/gsd-*`.

**Plugins** — reinstall from marketplaces (`/plugin` in Claude Code):

| Marketplace | Plugins |
|-------------|---------|
| claude-plugins-official | context7, code-review, code-simplifier, playwright, superpowers, huggingface-skills, claude-md-management, ralph-loop, telegram, linear, frontend-design |
| claude-code-kanban | claude-code-kanban |
| ui-ux-pro-max-skill | ui-ux-pro-max |
| cAI-tools | stop-slop |
| ralph-marketplace | ralph-skills |

**MCP auth** — slack / linear / gdrive are claude.ai-connected: they re-auth
through the browser on first use after `claude login`.

## 5. Verify

```bash
just claude-drift        # everything symlinked?
just hooks-status        # hooks + sounds present, registered in settings.json
just statusline-test     # statusline renders
claude                   # /prs, /sprint etc. appear in slash-command list
```

## Known issue: orphaned telegram daemons

Telegram plugin v0.0.6 leaves `bun server.ts` daemons behind when a session
exits; each orphan spins at ~30 % CPU forever (25 of them once produced a
load average of 33). If the machine feels slow:

```bash
just claude-orphans      # kills PPID-1 plugin daemons, spares live sessions
```
