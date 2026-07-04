"""Tests for unified diff parser."""
from pathlib import Path
from lgtm.diffparse import parse_unified_diff
from lgtm.model import FileDiff

FIX = (Path(__file__).parent / "fixtures" / "sample.diff").read_text()

def test_files_and_statuses():
    files = parse_unified_diff(FIX)
    assert [(f.path, f.status) for f in files] == [
        ("backend/app.py", "M"), ("backend/newfile.py", "A"), ("old/dead.py", "D")]

def test_hunk_ids_and_counts():
    files = parse_unified_diff(FIX)
    app = files[0]
    assert [h.hunk_id for h in app.hunks] == ["F0H0", "F0H1"]
    assert app.additions == 3 and app.deletions == 2

def test_line_numbers_tracked():
    h = parse_unified_diff(FIX)[0].hunks[0]
    kinds = [(l.kind, l.old_ln, l.new_ln, l.text) for l in h.lines]
    assert kinds == [("ctx", 10, 10, "ctx1"), ("del", 11, None, "old_line"),
                     ("add", None, 11, "new_line"), ("add", None, 12, "added_line"),
                     ("ctx", 12, 13, "ctx2")]

def test_empty_diff():
    assert parse_unified_diff("") == []

def test_plusplus_minusminus_content_lines_not_dropped():
    """Regression: content lines starting with ++ or -- should not be dropped."""
    diff_text = (
        "diff --git a/notes.md b/notes.md\n"
        "--- a/notes.md\n"
        "+++ b/notes.md\n"
        "@@ -1,3 +1,3 @@\n"
        " title: x\n"
        "----\n"
        "++i;\n"
        " end\n"
    )
    f = parse_unified_diff(diff_text)[0]
    h = f.hunks[0]
    assert h.deletions == 1 and h.additions == 1
    kinds = [(l.kind, l.old_ln, l.new_ln, l.text) for l in h.lines]
    assert kinds == [("ctx", 1, 1, "title: x"), ("del", 2, None, "---"),
                     ("add", None, 2, "+i;"), ("ctx", 3, 3, "end")]

def test_malformed_hunk_header_skipped():
    """Regression: malformed @@ lines should be skipped gracefully."""
    result = parse_unified_diff("diff --git a/x b/x\n@@ garbage\n")
    assert result == [FileDiff(path="x", status="M", hunks=[])]
