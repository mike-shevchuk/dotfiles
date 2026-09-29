#!/usr/bin/env python3
"""Log Codex session token totals from the native rollout JSONL."""

import json
from datetime import datetime, timezone
from pathlib import Path

from common import first, read_event

event = read_event()
session_id = str(first(event, "session_id", "sessionId", "thread_id", "threadId", default=""))
cwd = str(first(event, "cwd", default=""))
session_root = Path.home() / ".codex" / "sessions"
candidates = list(session_root.rglob(f"*{session_id}*.jsonl")) if session_id else []
if not candidates:
    candidates = list(session_root.rglob("*.jsonl"))
path = max(candidates, key=lambda item: item.stat().st_mtime) if candidates else None
usage: dict = {}
if path:
    with path.open(errors="replace") as stream:
        for line in stream:
            try:
                row = json.loads(line)
                payload = row.get("payload", {})
                if row.get("type") == "event_msg" and payload.get("type") == "token_count":
                    usage = payload.get("info", {}).get("total_token_usage", usage)
            except (json.JSONDecodeError, AttributeError):
                pass
now = datetime.now(timezone.utc)
log_dir = Path.home() / ".codex"
input_tokens = int(usage.get("input_tokens", 0))
output_tokens = int(usage.get("output_tokens", 0))
with (log_dir / "session-usage.log").open("a") as stream:
    stream.write(f"{now:%Y-%m-%d %H:%M:%S} cwd={cwd} in={input_tokens:,} out={output_tokens:,} session={session_id}\n")
summary_dir = log_dir / "sessions-summary"
summary_dir.mkdir(exist_ok=True)
with (summary_dir / f"{now:%Y-%m-%d-%H}.md").open("a") as stream:
    stream.write(f"# Session {now:%Y-%m-%d %H:%M:%S}\n\n**CWD:** `{cwd}`\n**Session:** `{session_id}`\n**Tokens:** {input_tokens:,} in / {output_tokens:,} out\n\n---\n\n")
