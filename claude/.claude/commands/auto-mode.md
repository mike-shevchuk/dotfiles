Toggle auto-mode for tool permissions (no confirmation prompts).

Usage: /auto-mode [on|off|status]

## Instructions

1. Read `~/.claude/settings.json`
2. Check the current value of `permissions.defaultMode`

Based on the argument (or toggle if no argument):

### `on` (or toggle when currently NOT auto)
- Set `permissions.defaultMode` to `"auto"` in settings.json
- Add allow rules if not present: `["Bash", "Read", "Write", "Edit", "Glob", "Grep"]`
- Print: "Auto-mode ON - all tools execute without confirmation"

### `off` (or toggle when currently auto)
- Remove `permissions.defaultMode` (or set to `"default"`)
- Remove the `permissions` block if it only had defaultMode and allow
- Print: "Auto-mode OFF - tools will ask for confirmation"

### `status` (or no argument and just want to check)
- Print current mode: auto or default
- List any allow/deny rules

IMPORTANT: Merge carefully with existing settings. Do not remove hooks, plugins, or other config.
