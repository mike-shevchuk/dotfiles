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
