---
description: "Toggle auto-mode for tool permissions (no confirmation prompts) — flips permissions.defaultMode in settings.local.json"
argument-hint: "[on|off|status]"
---

# Auto-mode

Toggle auto-mode for tool permissions (no confirmation prompts).

Usage: /auto-mode [on|off|status]

## Instructions

1. Read `~/.claude/settings.local.json` (NOT settings.json — that one is
   stow-symlinked into dotfiles and shared; the local file is machine-private).
2. Check the current value of `permissions.defaultMode`.

Valid `defaultMode` values: `default`, `acceptEdits`, `plan`,
`bypassPermissions`. (`"auto"` is NOT a valid value — it is silently ignored.)

Based on the argument (or toggle if no argument):

### `on` (or toggle when currently NOT bypass)
- Set `permissions.defaultMode` to `"bypassPermissions"` in `~/.claude/settings.local.json`
- Do NOT add blanket allow rules (a bare `"Bash"` allow would whitelist every
  shell command and defeat the danger-guard hook)
- Print: "Auto-mode ON (bypassPermissions) — tools execute without confirmation"

### `off` (or toggle when currently bypass)
- Remove `permissions.defaultMode` (or set to `"default"`)
- Remove the `permissions` block if it only had defaultMode
- Print: "Auto-mode OFF — tools will ask for confirmation"

### `status` (or no argument and just want to check)
- Print current mode: bypassPermissions or default
- List any allow/deny rules

IMPORTANT: Merge carefully with existing settings. Do not remove hooks, plugins, or other config.
