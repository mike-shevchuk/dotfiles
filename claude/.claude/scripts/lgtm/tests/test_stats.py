"""Tests for coach stats (stats.py): series loading, aggregation, rendering."""
import json
from pathlib import Path

from lgtm.stats import aggregate, load_series, render_progress, stats_path


def _write(repo: Path, entries: list[dict]) -> None:
    p = stats_path(repo)
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text("".join(json.dumps(e) + "\n" for e in entries), encoding="utf-8")


def test_load_series_last_n_and_rereview_wins(tmp_path):
    _write(tmp_path, [
        {"ref": "pr1", "patterns": {"inline-import": 3}},
        {"ref": "pr2", "patterns": {"inline-import": 1}},
        {"ref": "pr1", "patterns": {"inline-import": 2}},   # re-review of pr1
    ])
    series = load_series(tmp_path, last=5)
    # pr1 deduped to its LAST entry and moved to the end of the timeline
    assert [e["ref"] for e in series] == ["pr2", "pr1"]
    assert series[-1]["patterns"]["inline-import"] == 2


def test_aggregate_fills_missing_patterns_with_zero(tmp_path):
    _write(tmp_path, [
        {"ref": "pr1", "patterns": {"two-sources-of-truth": 2}},
        {"ref": "pr2", "patterns": {"inline-import": 1}},   # no two-sources key
    ])
    agg = aggregate(load_series(tmp_path))
    assert agg["two-sources-of-truth"] == [("pr1", 2), ("pr2", 0)]
    assert agg["inline-import"] == [("pr1", 0), ("pr2", 1)]


def test_render_progress_celebrates_zero(tmp_path):
    _write(tmp_path, [
        {"ref": "pr1", "patterns": {"two-sources-of-truth": 3}},
        {"ref": "pr2", "patterns": {"two-sources-of-truth": 0}},
    ])
    out = render_progress(load_series(tmp_path))
    assert "two-sources-of-truth" in out and "🎉" in out


def test_render_progress_empty_is_helpful(tmp_path):
    out = render_progress(load_series(tmp_path))
    assert "review-stats.jsonl" in out  # tells the user how stats appear


def test_garbage_lines_are_skipped(tmp_path):
    p = stats_path(tmp_path)
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text('{"ref":"pr1","patterns":{"x":1}}\nnot json\n\n', encoding="utf-8")
    assert [e["ref"] for e in load_series(tmp_path)] == ["pr1"]
