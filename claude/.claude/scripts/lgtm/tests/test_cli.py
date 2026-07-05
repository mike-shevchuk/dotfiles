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


def test_lang_flag_overrides_findings_meta(tmp_path):
    out = tmp_path / "rev"; out.mkdir()
    (out / "findings.json").write_text(json.dumps({
        "meta": {"ref": "test", "base": "x", "mode": "refs", "generated": "now",
                 "repo": "demo", "lang": "ukr"},
        "findings": []}, ensure_ascii=False))
    r = subprocess.run([sys.executable, "-m", "lgtm.cli", "review",
                        "--diff-file", str(FIX), "--ref-name", "test",
                        "--lang", "eng", "--out", str(out)],
                       cwd=SCRIPTS, capture_output=True, text=True)
    page = Path(r.stdout.strip().splitlines()[-1]).read_text()
    assert '<html lang="en"' in page
    assert "перекриває" in r.stderr

def test_minimal_findings_meta_lang_only(tmp_path):
    """New meta-ownership contract (review-html.md): findings.json only needs to
    carry `lang` — ref/base/mode/repo/generated are always recomputed fresh by
    the CLI, so a minimal meta block must still load and render correctly."""
    out = tmp_path / "rev"; out.mkdir()
    (out / "findings.json").write_text(json.dumps({
        "meta": {"lang": "eng"},
        "findings": [{"id": "f1", "layer": "claude", "source": "claude-deep",
                      "file": "backend/app.py", "line": 11, "hunk": "F0H0",
                      "severity_emoji": "🟠", "severity_score": 65,
                      "problem": {"eng": "P"}, "harm": {"eng": "H"},
                      "fix": {"eng": "F"}, "agrees_with": [], "coach": None,
                      "status": "open", "thread": []}]}, ensure_ascii=False))
    r = subprocess.run([sys.executable, "-m", "lgtm.cli", "review",
                        "--diff-file", str(FIX), "--ref-name", "test",
                        "--out", str(out)],
                       cwd=SCRIPTS, capture_output=True, text=True)
    assert r.returncode == 0, r.stderr
    page = Path(r.stdout.strip().splitlines()[-1]).read_text()
    assert "65/100" in page
    assert '<html lang="en"' in page          # meta.lang="eng" honored


def test_unknown_hunk_id_warns_and_hunks_json_written(tmp_path):
    """hunks.json is the review's authoritative hunk map; a finding pointing at a
    hunk id that doesn't exist in it must warn (readably) instead of silently
    rendering nowhere."""
    out = tmp_path / "rev"; out.mkdir()
    (out / "findings.json").write_text(json.dumps({
        "meta": {"ref": "test", "base": "x", "mode": "refs", "generated": "now",
                 "repo": "demo", "lang": "ukr"},
        "findings": [{"id": "f1", "layer": "claude", "source": "claude-deep",
                      "file": "backend/app.py", "line": 11, "hunk": "F9H9",
                      "severity_emoji": "🟠", "severity_score": 65,
                      "problem": {"ukr": "П"}, "harm": {"ukr": "Ш"},
                      "fix": {"ukr": "Ф"}, "agrees_with": [], "coach": None,
                      "status": "open", "thread": []}]}, ensure_ascii=False))
    r = subprocess.run([sys.executable, "-m", "lgtm.cli", "review",
                        "--diff-file", str(FIX), "--ref-name", "test",
                        "--out", str(out)],
                       cwd=SCRIPTS, capture_output=True, text=True)
    assert r.returncode == 0, r.stderr
    assert "невідомий hunk" in r.stderr
    hunks = json.loads((out / "hunks.json").read_text())
    assert hunks["files"][0]["hunks"][0]["id"] == "F0H0"


def test_invalid_findings_json_readable_error(tmp_path):
    """Malformed findings.json should produce readable error, not raw traceback."""
    out = tmp_path / "rev"; out.mkdir()
    (out / "findings.json").write_text("{not json")
    r = subprocess.run([sys.executable, "-m", "lgtm.cli", "review",
                        "--diff-file", str(FIX), "--ref-name", "test", "--out", str(out)],
                       cwd=SCRIPTS, capture_output=True, text=True)
    assert r.returncode == 1
    assert "невалідний" in r.stderr.lower() or "invalid" in r.stderr.lower()
    assert "Traceback" not in r.stderr
