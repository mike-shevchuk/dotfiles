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


def _text(obj, lang: str) -> str:
    """Pick a language string from {'ukr':..,'eng':..} or a plain string."""
    if isinstance(obj, dict):
        return obj.get(lang) or obj.get("eng") or obj.get("ukr") or ""
    return obj or ""


def render_text(obj, lang: str) -> str:
    """Escaped HTML for a bilingual field.

    lang 'ukr'|'eng' -> just that language. lang 'both' -> two spans
    (.L-ukr shown, .L-eng hidden); the page's toggle flips them.
    """
    if lang == "both":
        u = html.escape(_text(obj, "ukr"))
        e = html.escape(_text(obj, "eng"))
        return f'<span class="L L-ukr">{u}</span><span class="L L-eng" hidden>{e}</span>'
    return html.escape(_text(obj, lang))


def render_hunk(hid: str, hunk: dict, expl: dict, lang: str) -> str:
    rows = []
    for tag, text in hunk["lines"]:
        sign = {"add": "+", "del": "-", "ctx": " "}[tag]
        rows.append(
            f'<div class="ln {tag}"><span class="sign">{sign}</span>'
            f'<code>{html.escape(text)}</code></div>'
        )
    diff_html = "".join(rows)

    desc = expl.get("description")
    desc_html = ""
    if desc:
        desc_html = (
            '<details class="review-desc" open><summary>📝 Description</summary>'
            f'<div class="body">{render_text(desc, lang)}</div></details>'
        )

    problems = expl.get("problems") or []
    prob_html = ""
    if problems:
        items = "".join(
            f'<li class="sev-{html.escape(str(p.get("severity", "info")))}">'
            f'<span class="badge">{html.escape(str(p.get("severity", "info")))}</span>'
            f'{render_text(p.get("text", ""), lang)}</li>'
            for p in problems
        )
        prob_html = (
            '<details class="review-problems" open><summary>⚠️ Problems</summary>'
            f'<ul>{items}</ul></details>'
        )

    replies = expl.get("replies") or []
    rep_html = ""
    if replies:
        threads = []
        for r in replies:
            mark = "✅" if r.get("status") == "addressed" else "💬"
            threads.append(
                f'<div class="thread"><div class="you">🗣 {html.escape(str(r.get("comment", "")))}</div>'
                f'<div class="claude">{mark} {render_text(r.get("reply", ""), lang)}</div></div>'
            )
        rep_html = f'<div class="replies">{"".join(threads)}</div>'

    return (
        f'<div class="hunk" id="{hid}">'
        f'<div class="hunk-head"><code>{html.escape(hunk["header"])}</code>'
        f'<button class="copy" data-hunk="{hid}">Copy for Claude</button></div>'
        f'<div class="diff">{diff_html}</div>'
        f'{desc_html}{prob_html}{rep_html}'
        f'<textarea class="comment" data-hunk="{hid}" '
        f'placeholder="comment for Claude…"></textarea>'
        f'</div>'
    )
