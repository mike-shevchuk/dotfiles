#!/usr/bin/env python3
"""Shared, dependency-free helpers for Codex hooks."""

import json
import os
import platform
import re
import subprocess
import sys
from pathlib import Path
from typing import Any


def read_event() -> dict[str, Any]:
    raw = sys.stdin.read().strip()
    if not raw and len(sys.argv) > 1 and sys.argv[-1].lstrip().startswith("{"):
        raw = sys.argv[-1]
    try:
        value = json.loads(raw or "{}")
        return value if isinstance(value, dict) else {}
    except json.JSONDecodeError:
        return {}


def first(event: dict[str, Any], *names: str, default: Any = "") -> Any:
    for name in names:
        value = event.get(name)
        if value is not None:
            return value
    return default


def tool_input(event: dict[str, Any]) -> dict[str, Any]:
    value = first(event, "tool_input", "toolInput", "input", default={})
    return value if isinstance(value, dict) else {}


def clean(value: Any, limit: int = 180) -> str:
    return re.sub(r"[^\w .,:;!?/@+_()#=\-]", "", str(value), flags=re.UNICODE)[:limit]


def notify(title: str, message: str, sound: str = "notification") -> None:
    title, message = clean(title, 80), clean(message)
    candidates = [
        Path.home() / ".codex" / "sounds" / f"{sound}.wav",
        Path.home() / ".claude" / "sounds" / f"{sound}.wav",
    ]
    if platform.system() == "Darwin":
        script = "display notification " + json.dumps(message) + " with title " + json.dumps(title)
        subprocess.Popen(["osascript", "-e", script], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        audio = next((path for path in candidates if path.exists()), None)
        if audio:
            subprocess.Popen(["afplay", str(audio)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    else:
        subprocess.Popen(["notify-send", title, message], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        audio = next((path for path in candidates if path.exists()), None)
        if audio:
            player = "paplay" if any(Path(p, "paplay").exists() for p in os.environ.get("PATH", "").split(os.pathsep)) else "aplay"
            subprocess.Popen([player, str(audio)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
