#!/usr/bin/env python3
"""Format files modified through apply_patch/Edit/Write hook events."""

import shutil
import subprocess
from pathlib import Path

from common import first, read_event, tool_input

event = read_event()
data = tool_input(event)
raw = first(data, "file_path", "filePath", "path", default="")
if not raw:
    raise SystemExit(0)
path = Path(str(raw))
commands: dict[str, list[list[str]]] = {
    ".py": [["ruff", "check", "--fix", str(path)], ["ruff", "format", str(path)]],
    ".ts": [["eslint", "--fix", str(path)]],
    ".tsx": [["eslint", "--fix", str(path)]],
    ".js": [["eslint", "--fix", str(path)]],
    ".mjs": [["eslint", "--fix", str(path)]],
    ".lua": [["stylua", str(path)]],
}
for command in commands.get(path.suffix, []):
    if shutil.which(command[0]):
        subprocess.run(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
