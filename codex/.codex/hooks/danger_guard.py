#!/usr/bin/env python3
"""Warn about destructive shell commands before Codex executes them."""

import re

from common import first, notify, read_event, tool_input

event = read_event()
data = tool_input(event)
command = str(first(data, "command", "cmd", default=""))
patterns = [
    (r"rm\s+-[rf]{1,2}\b", "rm -rf"),
    (r"git\s+reset\s+--hard", "git reset --hard"),
    (r"git\s+push\s+(-f|--force)", "git push --force"),
    (r"git\s+clean\s+-[a-z]*f", "git clean -f"),
    (r"git\s+checkout\s+--\s", "git checkout --"),
    (r"git\s+branch\s+-D\s", "git branch -D"),
    (r"DROP\s+(TABLE|DATABASE)", "DROP database object"),
    (r"TRUNCATE\s+TABLE", "TRUNCATE TABLE"),
    (r"chmod\s+-R\s+777", "chmod -R 777"),
    (r":\s*>\s*\S", "file truncate"),
]
matches = [label for pattern, label in patterns if re.search(pattern, command, re.IGNORECASE)]
if matches:
    notify("Codex danger guard", f"{', '.join(matches)}: {command[:100]}", "notification")
