"""Coach progress between reviews (design §4): append-only review-stats.jsonl.

One line per review run, appended by the findings author (Codex) right after
findings.json is written:

    {"ts": "2026-07-06T21:00:00", "ref": "pr1700",
     "patterns": {"truthiness-vs-presence": 1, "inline-import": 0}}

`patterns` counts house-rule violations found in THAT review. Zeroes matter:
"0× two-sources-of-truth" is the win the coach celebrates.
"""
from __future__ import annotations
import json
from pathlib import Path

STATS_NAME = "review-stats.jsonl"


def stats_path(repo: Path) -> Path:
    return repo / ".lgtm" / STATS_NAME


def load_series(repo: Path, last: int = 5) -> list[dict]:
    """Last N reviews, one entry per ref (the newest line wins for a re-reviewed
    ref, keeping its latest position in the timeline)."""
    p = stats_path(repo)
    if not p.exists():
        return []
    by_ref: dict[str, dict] = {}
    for ln in p.read_text(encoding="utf-8").splitlines():
        ln = ln.strip()
        if not ln:
            continue
        try:
            e = json.loads(ln)
        except json.JSONDecodeError:
            continue
        ref = e.get("ref") or "?"
        by_ref.pop(ref, None)          # re-review → move to the end
        by_ref[ref] = e
    return list(by_ref.values())[-last:]


def aggregate(series: list[dict]) -> dict[str, list[tuple[str, int]]]:
    """{pattern: [(ref, count), ...]} over the series; patterns missing in an
    entry count as 0 — an explicit zero IS the progress signal."""
    pats = sorted({p for e in series for p in (e.get("patterns") or {})})
    return {p: [(e.get("ref", "?"), int((e.get("patterns") or {}).get(p, 0)))
                for e in series]
            for p in pats}


def render_progress(series: list[dict]) -> str:
    """Plain-ASCII terminal table: pattern | counts per review | trend."""
    if not series:
        return ("  (порожньо — review-stats.jsonl ще не має записів;\n"
                "   рядок додається разом із findings.json при /review-html)")
    agg = aggregate(series)
    refs = [e.get("ref", "?") for e in series]
    w = max([len(p) for p in agg] + [10])
    head = "  " + "PATTERN".ljust(w) + "  " + "  ".join(f"{r:>8}" for r in refs) + "  TREND"
    lines = [head, "  " + "-" * (len(head) - 2)]
    for pat, pts in agg.items():
        counts = [c for _, c in pts]
        if counts[-1] == 0 and any(counts[:-1]):
            trend = "0 🎉"
        elif len(counts) > 1 and counts[-1] < counts[-2]:
            trend = "↓ краще"
        elif len(counts) > 1 and counts[-1] > counts[-2]:
            trend = "↑ гірше"
        else:
            trend = "→"
        lines.append("  " + pat.ljust(w) + "  "
                     + "  ".join(f"{c:>8}" for c in counts) + f"  {trend}")
    total = sum(sum(c for _, c in pts) for pts in agg.values())
    lines.append(f"\n  {len(series)} рев'ю · {len(agg)} патернів · {total} знахідок разом")
    return "\n".join(lines)
