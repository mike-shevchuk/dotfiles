#!/usr/bin/env python3
"""Desktop notification adapter for Codex notify and lifecycle hooks."""

import sys

from common import first, notify, read_event

kind = sys.argv[1] if len(sys.argv) > 1 and not sys.argv[1].startswith("{") else "notification"
event = read_event()
event_type = first(event, "type", "hook_event_name", "hookEventName", default="Codex")
message = first(
    event,
    "last_assistant_message",
    "lastAssistantMessage",
    "message",
    "summary",
    default="Codex is ready",
)
title = "Codex - Subagent" if "subagent" in str(event_type).lower() else "Codex"
notify(title, str(message), kind)
