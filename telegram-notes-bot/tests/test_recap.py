from datetime import datetime
from zoneinfo import ZoneInfo

import pytest

from notesbot.config import Config
from notesbot.recap import (
    RecapError,
    build_prompt,
    generate_recap,
    run_claude,
    save_recap,
)
from notesbot.storage import Note, append_note

TZ = ZoneInfo("Europe/Kyiv")


def _dt(day, hour=12):
    return datetime(2026, 7, day, hour, tzinfo=TZ)


def _note(day, text):
    return Note(ts=_dt(day), text=text, message_id=day)


def test_build_prompt_includes_notes_and_range():
    prompt = build_prompt(
        [_note(6, "buy milk"), _note(8, "call bank")], _dt(6, 0), _dt(13, 0)
    )
    assert "buy milk" in prompt
    assert "call bank" in prompt
    assert "06.07" in prompt  # start date rendered
    assert "1." in prompt and "2." in prompt  # numbered


def test_run_claude_success(monkeypatch):
    class FakeCompleted:
        returncode = 0
        stdout = "  # Recap\nbody  "
        stderr = ""

    def fake_run(cmd, **kwargs):
        assert cmd[0] == "claude"
        assert cmd[1] == "-p"
        return FakeCompleted()

    monkeypatch.setattr("notesbot.recap.subprocess.run", fake_run)
    assert run_claude("prompt", timeout=10) == "# Recap\nbody"


def test_run_claude_nonzero_raises(monkeypatch):
    class FakeCompleted:
        returncode = 1
        stdout = ""
        stderr = "boom"

    monkeypatch.setattr(
        "notesbot.recap.subprocess.run", lambda cmd, **kw: FakeCompleted()
    )
    with pytest.raises(RecapError, match="boom"):
        run_claude("prompt", timeout=10)


def test_run_claude_timeout_raises(monkeypatch):
    import subprocess

    def fake_run(cmd, **kwargs):
        raise subprocess.TimeoutExpired(cmd, 10)

    monkeypatch.setattr("notesbot.recap.subprocess.run", fake_run)
    with pytest.raises(RecapError, match="timed out"):
        run_claude("prompt", timeout=10)


def test_save_recap_writes_file(tmp_path):
    path = save_recap(tmp_path, _dt(6, 0), _dt(13, 0), 3, "# Weekly\ncontent", _dt(13, 9))
    assert path == tmp_path / "2026-07-06.md"
    text = path.read_text()
    assert "week_start: 2026-07-06" in text
    assert "notes_count: 3" in text
    assert "# Weekly" in text


def _config(tmp_path):
    return Config(
        bot_token="t",
        owner_id=1,
        tz=TZ,
        tz_name="Europe/Kyiv",
        notes_path=tmp_path / "data" / "notes.jsonl",
        recaps_dir=tmp_path / "recaps",
        claude_timeout=10,
    )


def test_generate_recap_empty_returns_no_path(tmp_path):
    cfg = _config(tmp_path)
    result = generate_recap(cfg, _dt(6, 0), _dt(13, 0), _dt(13, 9))
    assert result.notes_count == 0
    assert result.path is None
    assert result.body is None


def test_generate_recap_full_flow(tmp_path, monkeypatch):
    cfg = _config(tmp_path)
    append_note(cfg.notes_path, "did a thing", 1, _dt(7))
    monkeypatch.setattr(
        "notesbot.recap.run_claude", lambda prompt, timeout: "# Recap body"
    )
    result = generate_recap(cfg, _dt(6, 0), _dt(13, 0), _dt(13, 9))
    assert result.notes_count == 1
    assert result.body == "# Recap body"
    assert result.path == cfg.recaps_dir / "2026-07-06.md"
    assert result.path.exists()
