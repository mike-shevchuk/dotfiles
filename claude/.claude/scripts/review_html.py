#!/usr/bin/env python3
"""review_html.py — generate a self-contained HTML review page.

(unified diff text, explanations.json, lang) -> one standalone .html file.
Pure rendering, Python stdlib only. Driven by the /review-html Claude command.
"""
from __future__ import annotations

import argparse
import html
import json
import os
import sys
import tempfile


def hunk_id(file_idx: int, hunk_idx: int) -> str:
    """Stable anchor id for a hunk: file index + hunk index, e.g. 'F0H1'."""
    return f"F{file_idx}H{hunk_idx}"


def parse_diff(text: str) -> list[dict]:
    """Parse `git diff` unified output.

    Returns a list of files, each:
      {"path": str, "added": int, "removed": int,
       "hunks": [{"header": str, "lines": [(tag, text)]}]}
    where tag is one of "ctx" | "add" | "del".
    """
    files: list[dict] = []
    cur: dict | None = None
    for line in text.splitlines():
        if line.startswith("diff --git "):
            path = line.split(" b/", 1)[-1].strip()
            cur = {"path": path, "added": 0, "removed": 0, "hunks": []}
            files.append(cur)
        elif line.startswith("+++ "):
            p = line[4:].strip()
            if cur is not None and p != "/dev/null":
                cur["path"] = p[2:] if p.startswith("b/") else p
        elif line.startswith("--- "):
            p = line[4:].strip()
            if cur is not None and p != "/dev/null" and cur["path"] == "/dev/null":
                cur["path"] = p[2:] if p.startswith("a/") else p
        elif line.startswith("@@"):
            if cur is None:
                cur = {"path": "?", "added": 0, "removed": 0, "hunks": []}
                files.append(cur)
            cur["hunks"].append({"header": line, "lines": []})
        elif cur is not None and cur["hunks"]:
            h = cur["hunks"][-1]
            if line.startswith("+"):
                h["lines"].append(("add", line[1:]))
                cur["added"] += 1
            elif line.startswith("-"):
                h["lines"].append(("del", line[1:]))
                cur["removed"] += 1
            elif line.startswith(" "):
                h["lines"].append(("ctx", line[1:]))
            # ignore "\ No newline at end of file" and other noise
    return files
