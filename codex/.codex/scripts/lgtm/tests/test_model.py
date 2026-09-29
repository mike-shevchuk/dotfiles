import json
from lgtm.model import (DiffLine, Hunk, FileDiff, Finding, ReviewMeta,
                        load_findings, save_findings)

def _hunk():
    return Hunk(hunk_id="F0H0", header="@@ -1,2 +1,3 @@", old_start=1, new_start=1,
                lines=[DiffLine("ctx", 1, 1, "a"),
                       DiffLine("del", 2, None, "old"),
                       DiffLine("add", None, 2, "new"),
                       DiffLine("add", None, 3, "new2")])

def test_hunk_counts_and_flags():
    h = _hunk()
    assert h.additions == 2 and h.deletions == 1
    assert h.has_add and h.has_del

def test_filediff_totals():
    f = FileDiff(path="a.py", status="M", hunks=[_hunk(), _hunk()])
    assert f.additions == 4 and f.deletions == 2

def test_review_meta_minimal_lang_only():
    """ref/base/mode/repo/generated are identity fields the CLI always recomputes
    fresh (see cli.cmd_review's meta-ownership fix) — ReviewMeta must load from a
    findings.json meta block that carries only `lang`."""
    meta = ReviewMeta(**{"lang": "eng"})
    assert meta.lang == "eng"
    assert meta.ref == "" and meta.base == "" and meta.mode == ""
    assert meta.repo == "" and meta.generated == ""

def test_hunk_first_new_line_delete_only_never_zero():
    """Delete-only hunk (`@@ -1,5 +0,0 @@`, no add/ctx lines) has no truthy new_ln
    anywhere; first_new_line must fall back to max(new_start, 1) so nvim/rg
    commands never target line 0."""
    h = Hunk(hunk_id="F0H0", header="@@ -1,5 +0,0 @@", old_start=1, new_start=0,
              lines=[DiffLine("del", 1, None, "a"), DiffLine("del", 2, None, "b")])
    assert h.first_new_line == 1

def test_hunk_first_new_line_uses_first_truthy_new_ln():
    h = _hunk()
    assert h.first_new_line == 1   # first line is ctx with new_ln=1

def test_load_findings_null_tolerant(tmp_path):
    """findings.json produced by hand (or an older Codex pass) may carry
    explicit JSON nulls for problem/harm/fix/agrees_with/thread — load_findings
    must normalize these to {}/[] at the load boundary instead of exploding."""
    p = tmp_path / "findings.json"
    p.write_text(json.dumps({
        "meta": {"lang": "ukr"},
        "findings": [{"id": "f1", "layer": "claude", "source": "claude-deep",
                      "file": "a.py", "line": 1, "hunk": "F0H0",
                      "severity_emoji": "🟠", "severity_score": 1,
                      "problem": None, "harm": None, "fix": None,
                      "agrees_with": None, "coach": None,
                      "status": "open", "thread": None}]}))
    meta, findings = load_findings(p)
    f = findings[0]
    assert f.problem == {} and f.harm == {} and f.fix == {}
    assert f.agrees_with == [] and f.thread == []

def test_findings_roundtrip(tmp_path):
    meta = ReviewMeta(ref="pr1651", base="(github)", mode="pr",
                      generated="2026-07-04 10:00", repo="rescue-serverless", lang="ukr")
    f = Finding(id="f-1", layer="claude", source="claude-deep", file="a.py", line=79,
                hunk="F0H0", severity_emoji="🟠", severity_score=65,
                problem={"ukr": "п"}, harm={"ukr": "ш"},
                fix={"ukr": "ф", "code": "x = 1"},
                agrees_with=["bugbot#1"], coach=None, status="open", thread=[])
    p = tmp_path / "findings.json"
    save_findings(p, meta, [f])
    meta2, fs = load_findings(p)
    assert meta2 == meta and fs == [f]
    raw = json.loads(p.read_text())
    assert raw["meta"]["ref"] == "pr1651" and raw["findings"][0]["line"] == 79
