# Codex configuration

This directory is a GNU Stow package for `~/.codex`.

- `config.toml` contains personal Codex defaults.
- `skills/` contains native Codex versions of the command workflows.
- `prompts/` retains `/prompts:<name>` compatibility aliases.
- `hooks.json` and `hooks/` provide safety, formatting, notification, usage,
  stop, and subagent-stop hooks.

`CLAUDE.md` is configured as an instruction fallback, so existing project
guidance works immediately. A native `AGENTS.md` takes precedence when present.

Codex custom prompts are deprecated upstream in favor of skills, but remain
supported by the CLI and provide the closest behavior-preserving migration for
the current command library. Invoke one as `/prompts:<name>`.

The TUI footer enables every useful native Codex field: model/reasoning, fast
mode, context use, 5-hour and weekly limits, token totals, Git branch, project,
directory, and session ID. Codex does not support arbitrary shell-rendered
statusline rows, so Claude's custom PR/GSD row remains available through the
migrated pipeline helpers rather than the footer.

Codex hook sounds first use `~/.codex/sounds`, then fall back to the existing
`~/.claude/sounds` assets. After stowing, open `/hooks` once to review and trust
the migrated hook definitions.

## Migration coverage

| Claude feature | Codex equivalent |
| --- | --- |
| Commands | 19 native skills plus 19 prompt aliases |
| `CLAUDE.md` | Fallback instruction filename; `AGENTS.md` wins |
| Pre-tool danger guard | `PreToolUse` hook |
| Edit formatting | `PostToolUse` hook |
| Stop notification and usage log | Two `Stop` hooks |
| Subagent notification | `SubagentStop` hook |
| General/approval notification | Native TUI notifications |
| Permission bypass | Explicit `auto` and `safe` profiles |
| Model/context/usage statusline | Native footer with every available field |
| Pipeline, review HTML, GSD sync | Ported helpers and Python modules |

Not directly portable:

- Claude's arbitrary three-line shell statusline; Codex footer fields are fixed.
- Claude OAuth usage API and estimated Anthropic cost. Codex displays native
  limits and the stop hook records native token totals instead.
- Claude marketplace plugin identifiers. Import/reinstall corresponding Codex
  plugins or MCP connections separately in the Codex app.
- The `RemoteTrigger` command requires that tool to be installed in Codex; the
  migrated skill reports the missing integration if it is unavailable.
