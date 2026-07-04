"""Tests for LGTM CLI."""
import subprocess
import sys
import json
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parents[2]   # .../scripts
FIX = Path(__file__).parent / "fixtures" / "sample.diff"


def test_review_from_diff_file(tmp_path):
    out = tmp_path / "rev"
    # --diff-file bypasses git: deterministic unit path
    r = subprocess.run([sys.executable, "-m", "lgtm.cli", "review",
                        "--diff-file", str(FIX), "--ref-name", "test",
                        "--out", str(out)],
                       cwd=SCRIPTS, capture_output=True, text=True)
    assert r.returncode == 0, r.stderr
    page = Path(r.stdout.strip().splitlines()[-1])
    assert page.exists() and "backend/app.py" in page.read_text()
    assert (out / "diff.txt").exists()


def test_review_uses_findings_when_present(tmp_path):
    out = tmp_path / "rev"; out.mkdir()
    (out / "findings.json").write_text(json.dumps({
        "meta": {"ref": "test", "base": "x", "mode": "refs", "generated": "now",
                 "repo": "demo", "lang": "ukr"},
        "findings": [{"id": "f1", "layer": "claude", "source": "claude-deep",
                      "file": "backend/app.py", "line": 11, "hunk": "F0H0",
                      "severity_emoji": "🟠", "severity_score": 65,
                      "problem": {"ukr": "П"}, "harm": {"ukr": "Ш"},
                      "fix": {"ukr": "Ф"}, "agrees_with": [], "coach": None,
                      "status": "open", "thread": []}]}, ensure_ascii=False))
    r = subprocess.run([sys.executable, "-m", "lgtm.cli", "review",
                        "--diff-file", str(FIX), "--ref-name", "test",
                        "--out", str(out)],
                       cwd=SCRIPTS, capture_output=True, text=True)
    page = Path(r.stdout.strip().splitlines()[-1]).read_text()
    assert "65/100" in page


def test_review_bad_pr_readable_error(tmp_path):
    r = subprocess.run([sys.executable, "-m", "lgtm.cli", "review",
                        "--repo", "/Users/mikeshevchuk/code/b2b/rescue-serverless",
                        "--pr", "999999", "--out", str(tmp_path / "x")],
                       cwd=SCRIPTS, capture_output=True, text=True)
    assert r.returncode == 1
    assert "команда впала" in r.stderr
    assert "Traceback" not in r.stderr
