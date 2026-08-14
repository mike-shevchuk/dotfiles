# Telegram Notes Bot Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A personal aiogram 3.x Telegram bot that saves every message as a note and produces a weekly Claude-generated recap (auto Monday 09:00 Europe/Kyiv + on-demand `/recap`), saved as a Markdown file.

**Architecture:** Flat `notesbot/` package. Pure-logic modules (`config`, `storage`, `weeks`, `recap`) are unit-tested; `handlers`, `scheduler`, and `__main__` wire aiogram + APScheduler around them. Notes are append-only JSONL; recaps are Markdown files named by the week's Monday date. Claude runs via the `claude -p` headless CLI in a subprocess.

**Tech Stack:** Python 3.12, uv, aiogram 3.x, APScheduler 3.x, python-dotenv, pytest.

## Global Constraints

- Python 3.12 (project `.python-version` = `dotfiles`, interpreter is 3.12.11).
- Package manager: **uv**. Run everything via `uv run …`.
- aiogram **3.x** API only (Router + Dispatcher, `@router.message()`, `dp.start_polling(bot)`). No aiogram 2.x patterns.
- Single user: every handler is gated to `OWNER_ID`; messages from anyone else are ignored.
- Secrets live in `~/dotfiles/.env` (already gitignored): `TELEGRAM_BOT_TOKEN`, `TELEGRAM_OWNER_ID`, optional `RECAP_TZ` (default `Europe/Kyiv`).
- All timestamps are timezone-aware in the configured tz (`Europe/Kyiv`).
- `data/` and `recaps/` directories are gitignored (personal data never committed).
- Notes storage format: JSONL, one object per line: `{"ts": "<ISO>", "text": "...", "message_id": <int>}`.
- Recap filename: `recaps/<YYYY-MM-DD>.md` where the date is the **Monday** of the recapped week.
- Just recipes are loud (echo `→` before, `OK`/`FAIL` after) per repo CLAUDE.md conventions.

---

## File structure

```
telegram-notes-bot/
├── pyproject.toml            # uv project (application, package=false)
├── .gitignore                # ignore data/ recaps/ __pycache__/ .venv/
├── README.md
├── justfile                  # just run / test / recap
├── notesbot/
│   ├── __init__.py
│   ├── config.py             # Config dataclass + load()
│   ├── storage.py            # Note, append_note(), notes_in_range()
│   ├── weeks.py              # monday_of(), current_week_range(), previous_week_range()
│   ├── recap.py              # build_prompt(), run_claude(), save_recap(), generate_recap()
│   ├── handlers.py           # build_router(config) -> Router
│   ├── scheduler.py          # setup_scheduler(bot, config)
│   └── __main__.py           # main(): wire Bot + Dispatcher + scheduler, start polling
├── data/notes.jsonl          # runtime (gitignored)
├── recaps/                   # runtime (gitignored)
└── tests/
    ├── test_config.py
    ├── test_storage.py
    ├── test_weeks.py
    └── test_recap.py
```

All paths below are relative to `telegram-notes-bot/` at the dotfiles worktree root.

---

### Task 1: Project scaffold + config

**Files:**
- Create: `telegram-notes-bot/pyproject.toml`
- Create: `telegram-notes-bot/.gitignore`
- Create: `telegram-notes-bot/notesbot/__init__.py` (empty)
- Create: `telegram-notes-bot/notesbot/config.py`
- Test: `telegram-notes-bot/tests/test_config.py`

**Interfaces:**
- Produces:
  - `Config` dataclass with fields: `bot_token: str`, `owner_id: int`, `tz: ZoneInfo`, `tz_name: str`, `notes_path: Path`, `recaps_dir: Path`, `claude_timeout: int`.
  - `load_config(env: Mapping[str, str] | None = None, base_dir: Path | None = None) -> Config` — reads from `env` (defaults to `os.environ` after loading `~/dotfiles/.env`); raises `RuntimeError` with a clear message if `TELEGRAM_BOT_TOKEN` or `TELEGRAM_OWNER_ID` is missing/blank. `base_dir` defaults to the package parent (the `telegram-notes-bot/` dir); `notes_path = base_dir/"data"/"notes.jsonl"`, `recaps_dir = base_dir/"recaps"`.

- [ ] **Step 1: Create `pyproject.toml`**

```toml
[project]
name = "notesbot"
version = "0.1.0"
description = "Personal Telegram notes bot with weekly Claude recap"
requires-python = ">=3.12"
dependencies = [
    "aiogram>=3.20,<4",
    "apscheduler>=3.10,<4",
    "python-dotenv>=1.0",
]

[dependency-groups]
dev = ["pytest>=8.0"]

[tool.uv]
package = false
```

- [ ] **Step 2: Create `.gitignore`**

```gitignore
data/
recaps/
__pycache__/
.venv/
*.pyc
```

- [ ] **Step 3: Create empty `notesbot/__init__.py`**

```python
```

- [ ] **Step 4: Write the failing test** — `tests/test_config.py`

```python
from pathlib import Path

import pytest

from notesbot.config import load_config


def test_load_config_reads_env(tmp_path):
    env = {"TELEGRAM_BOT_TOKEN": "123:abc", "TELEGRAM_OWNER_ID": "42"}
    cfg = load_config(env=env, base_dir=tmp_path)
    assert cfg.bot_token == "123:abc"
    assert cfg.owner_id == 42
    assert cfg.tz_name == "Europe/Kyiv"
    assert cfg.notes_path == tmp_path / "data" / "notes.jsonl"
    assert cfg.recaps_dir == tmp_path / "recaps"


def test_load_config_custom_tz(tmp_path):
    env = {
        "TELEGRAM_BOT_TOKEN": "t",
        "TELEGRAM_OWNER_ID": "1",
        "RECAP_TZ": "Europe/London",
    }
    cfg = load_config(env=env, base_dir=tmp_path)
    assert cfg.tz_name == "Europe/London"


def test_load_config_missing_token_raises(tmp_path):
    with pytest.raises(RuntimeError, match="TELEGRAM_BOT_TOKEN"):
        load_config(env={"TELEGRAM_OWNER_ID": "42"}, base_dir=tmp_path)


def test_load_config_missing_owner_raises(tmp_path):
    with pytest.raises(RuntimeError, match="TELEGRAM_OWNER_ID"):
        load_config(env={"TELEGRAM_BOT_TOKEN": "t"}, base_dir=tmp_path)
```

- [ ] **Step 5: Run test to verify it fails**

Run: `cd telegram-notes-bot && uv run pytest tests/test_config.py -v`
Expected: FAIL (`ModuleNotFoundError: No module named 'notesbot.config'`)

- [ ] **Step 6: Write `notesbot/config.py`**

```python
from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path
from typing import Mapping
from zoneinfo import ZoneInfo

from dotenv import load_dotenv

DEFAULT_TZ = "Europe/Kyiv"
DEFAULT_CLAUDE_TIMEOUT = 120


@dataclass(frozen=True)
class Config:
    bot_token: str
    owner_id: int
    tz: ZoneInfo
    tz_name: str
    notes_path: Path
    recaps_dir: Path
    claude_timeout: int


def _require(env: Mapping[str, str], key: str) -> str:
    value = env.get(key, "").strip()
    if not value:
        raise RuntimeError(
            f"{key} is not set. Add it to ~/dotfiles/.env "
            f"(TELEGRAM_BOT_TOKEN and TELEGRAM_OWNER_ID are required)."
        )
    return value


def load_config(
    env: Mapping[str, str] | None = None,
    base_dir: Path | None = None,
) -> Config:
    if env is None:
        load_dotenv(Path.home() / "dotfiles" / ".env")
        env = os.environ
    if base_dir is None:
        base_dir = Path(__file__).resolve().parent.parent

    tz_name = env.get("RECAP_TZ", "").strip() or DEFAULT_TZ
    return Config(
        bot_token=_require(env, "TELEGRAM_BOT_TOKEN"),
        owner_id=int(_require(env, "TELEGRAM_OWNER_ID")),
        tz=ZoneInfo(tz_name),
        tz_name=tz_name,
        notes_path=base_dir / "data" / "notes.jsonl",
        recaps_dir=base_dir / "recaps",
        claude_timeout=DEFAULT_CLAUDE_TIMEOUT,
    )
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `cd telegram-notes-bot && uv run pytest tests/test_config.py -v`
Expected: PASS (4 passed)

- [ ] **Step 8: Commit**

```bash
git add telegram-notes-bot/pyproject.toml telegram-notes-bot/.gitignore telegram-notes-bot/notesbot/__init__.py telegram-notes-bot/notesbot/config.py telegram-notes-bot/tests/test_config.py telegram-notes-bot/uv.lock
git commit -m "feat(notesbot): project scaffold + config loader"
```

---

### Task 2: Note storage

**Files:**
- Create: `telegram-notes-bot/notesbot/storage.py`
- Test: `telegram-notes-bot/tests/test_storage.py`

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces:
  - `Note` dataclass: `ts: datetime` (tz-aware), `text: str`, `message_id: int`.
  - `append_note(notes_path: Path, text: str, message_id: int, ts: datetime) -> Note` — creates parent dir if missing, appends one JSON line `{"ts": ts.isoformat(), "text": text, "message_id": message_id}`, returns the `Note`.
  - `notes_in_range(notes_path: Path, start: datetime, end: datetime) -> list[Note]` — returns notes with `start <= ts < end`, sorted by `ts` ascending; returns `[]` if file is missing. Skips blank/corrupt lines.

- [ ] **Step 1: Write the failing test** — `tests/test_storage.py`

```python
from datetime import datetime
from zoneinfo import ZoneInfo

from notesbot.storage import Note, append_note, notes_in_range

TZ = ZoneInfo("Europe/Kyiv")


def _dt(day, hour=12):
    return datetime(2026, 7, day, hour, tzinfo=TZ)


def test_append_creates_file_and_returns_note(tmp_path):
    path = tmp_path / "data" / "notes.jsonl"
    note = append_note(path, "hello", 10, _dt(6))
    assert isinstance(note, Note)
    assert note.text == "hello"
    assert note.message_id == 10
    assert path.exists()
    assert path.read_text().count("\n") == 1


def test_notes_in_range_filters_by_time(tmp_path):
    path = tmp_path / "notes.jsonl"
    append_note(path, "before", 1, _dt(5))
    append_note(path, "inside-a", 2, _dt(6))
    append_note(path, "inside-b", 3, _dt(8))
    append_note(path, "after", 4, _dt(13))
    result = notes_in_range(path, _dt(6, 0), _dt(13, 0))
    assert [n.text for n in result] == ["inside-a", "inside-b"]


def test_notes_in_range_missing_file_returns_empty(tmp_path):
    assert notes_in_range(tmp_path / "nope.jsonl", _dt(6), _dt(13)) == []


def test_notes_in_range_skips_corrupt_lines(tmp_path):
    path = tmp_path / "notes.jsonl"
    append_note(path, "good", 1, _dt(6))
    with path.open("a") as f:
        f.write("not json\n\n")
    result = notes_in_range(path, _dt(5), _dt(13))
    assert [n.text for n in result] == ["good"]
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd telegram-notes-bot && uv run pytest tests/test_storage.py -v`
Expected: FAIL (`ModuleNotFoundError: No module named 'notesbot.storage'`)

- [ ] **Step 3: Write `notesbot/storage.py`**

```python
from __future__ import annotations

import json
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path


@dataclass(frozen=True)
class Note:
    ts: datetime
    text: str
    message_id: int


def append_note(notes_path: Path, text: str, message_id: int, ts: datetime) -> Note:
    notes_path.parent.mkdir(parents=True, exist_ok=True)
    record = {"ts": ts.isoformat(), "text": text, "message_id": message_id}
    with notes_path.open("a", encoding="utf-8") as f:
        f.write(json.dumps(record, ensure_ascii=False) + "\n")
    return Note(ts=ts, text=text, message_id=message_id)


def notes_in_range(notes_path: Path, start: datetime, end: datetime) -> list[Note]:
    if not notes_path.exists():
        return []
    notes: list[Note] = []
    with notes_path.open(encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                record = json.loads(line)
                ts = datetime.fromisoformat(record["ts"])
            except (json.JSONDecodeError, KeyError, ValueError):
                continue
            if start <= ts < end:
                notes.append(
                    Note(ts=ts, text=record["text"], message_id=record["message_id"])
                )
    notes.sort(key=lambda n: n.ts)
    return notes
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd telegram-notes-bot && uv run pytest tests/test_storage.py -v`
Expected: PASS (4 passed)

- [ ] **Step 5: Commit**

```bash
git add telegram-notes-bot/notesbot/storage.py telegram-notes-bot/tests/test_storage.py
git commit -m "feat(notesbot): JSONL note storage with range queries"
```

---

### Task 3: Week range helpers

**Files:**
- Create: `telegram-notes-bot/notesbot/weeks.py`
- Test: `telegram-notes-bot/tests/test_weeks.py`

**Interfaces:**
- Consumes: nothing.
- Produces (all datetimes tz-aware, in the passed `now`'s tzinfo):
  - `monday_of(now: datetime) -> datetime` — Monday 00:00:00 of `now`'s week.
  - `current_week_range(now: datetime) -> tuple[datetime, datetime]` — `(monday_of(now), now)`.
  - `previous_week_range(now: datetime) -> tuple[datetime, datetime]` — `(monday_of(now) - 7 days, monday_of(now))`.

- [ ] **Step 1: Write the failing test** — `tests/test_weeks.py`

```python
from datetime import datetime
from zoneinfo import ZoneInfo

from notesbot.weeks import current_week_range, monday_of, previous_week_range

TZ = ZoneInfo("Europe/Kyiv")


def test_monday_of_from_wednesday():
    # 2026-07-08 is a Wednesday
    now = datetime(2026, 7, 8, 15, 30, tzinfo=TZ)
    assert monday_of(now) == datetime(2026, 7, 6, 0, 0, 0, tzinfo=TZ)


def test_monday_of_from_monday_is_same_day_midnight():
    now = datetime(2026, 7, 6, 9, 0, tzinfo=TZ)
    assert monday_of(now) == datetime(2026, 7, 6, 0, 0, 0, tzinfo=TZ)


def test_current_week_range():
    now = datetime(2026, 7, 8, 15, 30, tzinfo=TZ)
    start, end = current_week_range(now)
    assert start == datetime(2026, 7, 6, 0, 0, 0, tzinfo=TZ)
    assert end == now


def test_previous_week_range():
    now = datetime(2026, 7, 13, 9, 0, tzinfo=TZ)  # Monday
    start, end = previous_week_range(now)
    assert start == datetime(2026, 7, 6, 0, 0, 0, tzinfo=TZ)
    assert end == datetime(2026, 7, 13, 0, 0, 0, tzinfo=TZ)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd telegram-notes-bot && uv run pytest tests/test_weeks.py -v`
Expected: FAIL (`ModuleNotFoundError: No module named 'notesbot.weeks'`)

- [ ] **Step 3: Write `notesbot/weeks.py`**

```python
from __future__ import annotations

from datetime import datetime, timedelta


def monday_of(now: datetime) -> datetime:
    midnight = now.replace(hour=0, minute=0, second=0, microsecond=0)
    return midnight - timedelta(days=now.weekday())


def current_week_range(now: datetime) -> tuple[datetime, datetime]:
    return monday_of(now), now


def previous_week_range(now: datetime) -> tuple[datetime, datetime]:
    this_monday = monday_of(now)
    return this_monday - timedelta(days=7), this_monday
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd telegram-notes-bot && uv run pytest tests/test_weeks.py -v`
Expected: PASS (4 passed)

- [ ] **Step 5: Commit**

```bash
git add telegram-notes-bot/notesbot/weeks.py telegram-notes-bot/tests/test_weeks.py
git commit -m "feat(notesbot): week range helpers"
```

---

### Task 4: Recap generation (prompt, Claude subprocess, file output)

**Files:**
- Create: `telegram-notes-bot/notesbot/recap.py`
- Test: `telegram-notes-bot/tests/test_recap.py`

**Interfaces:**
- Consumes:
  - `notesbot.storage.Note`, `notes_in_range`.
  - `notesbot.config.Config`.
- Produces:
  - `build_prompt(notes: list[Note], start: datetime, end: datetime) -> str` — system-style instruction + numbered notes with `HH:MM DD.MM` timestamps.
  - `run_claude(prompt: str, timeout: int) -> str` — runs `["claude", "-p", prompt, "--output-format", "text"]` via `subprocess.run`, returns stripped stdout; raises `RecapError` on non-zero exit or `subprocess.TimeoutExpired`.
  - `save_recap(recaps_dir: Path, week_start: datetime, week_end: datetime, notes_count: int, body: str, generated: datetime) -> Path` — writes `recaps_dir/<week_start date>.md` with YAML frontmatter + body; returns the path.
  - `generate_recap(config: Config, start: datetime, end: datetime, now: datetime) -> RecapResult` — orchestrates: loads notes in `[start, end)`; if none, returns `RecapResult(path=None, body=None, notes_count=0)`; else builds prompt, runs Claude, saves file, returns `RecapResult(path=<Path>, body=<str>, notes_count=<int>)`.
  - `RecapError(Exception)`.
  - `RecapResult` dataclass: `path: Path | None`, `body: str | None`, `notes_count: int`.

- [ ] **Step 1: Write the failing test** — `tests/test_recap.py`

```python
from datetime import datetime
from pathlib import Path
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
    prompt = build_prompt([_note(6, "buy milk"), _note(8, "call bank")], _dt(6, 0), _dt(13, 0))
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

    monkeypatch.setattr("notesbot.recap.subprocess.run", lambda cmd, **kw: FakeCompleted())
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
    monkeypatch.setattr("notesbot.recap.run_claude", lambda prompt, timeout: "# Recap body")
    result = generate_recap(cfg, _dt(6, 0), _dt(13, 0), _dt(13, 9))
    assert result.notes_count == 1
    assert result.body == "# Recap body"
    assert result.path == cfg.recaps_dir / "2026-07-06.md"
    assert result.path.exists()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd telegram-notes-bot && uv run pytest tests/test_recap.py -v`
Expected: FAIL (`ModuleNotFoundError: No module named 'notesbot.recap'`)

- [ ] **Step 3: Write `notesbot/recap.py`**

```python
from __future__ import annotations

import subprocess
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

from notesbot.config import Config
from notesbot.storage import Note, notes_in_range

SYSTEM_INSTRUCTION = (
    "Ти асистент, що робить тижневий підсумок особистих заміток користувача. "
    "Проаналізуй замітки нижче та згрупуй їх за темами. Виділи розділи: "
    "**Зроблено**, **Ідеї**, **Треба зробити**. Пиши українською, стисло, у Markdown. "
    "Не вигадуй фактів, яких немає в замітках. Поверни лише готовий підсумок."
)


class RecapError(Exception):
    pass


@dataclass(frozen=True)
class RecapResult:
    path: Path | None
    body: str | None
    notes_count: int


def build_prompt(notes: list[Note], start: datetime, end: datetime) -> str:
    header = (
        f"{SYSTEM_INSTRUCTION}\n\n"
        f"Період: {start.strftime('%d.%m.%Y')} – {end.strftime('%d.%m.%Y')}\n"
        f"Кількість заміток: {len(notes)}\n\n"
        f"Замітки:\n"
    )
    lines = [
        f"{i}. [{note.ts.strftime('%d.%m %H:%M')}] {note.text}"
        for i, note in enumerate(notes, start=1)
    ]
    return header + "\n".join(lines)


def run_claude(prompt: str, timeout: int) -> str:
    try:
        completed = subprocess.run(
            ["claude", "-p", prompt, "--output-format", "text"],
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired as exc:
        raise RecapError(f"claude -p timed out after {timeout}s") from exc
    except FileNotFoundError as exc:
        raise RecapError("claude CLI not found on PATH") from exc
    if completed.returncode != 0:
        raise RecapError(f"claude -p failed: {completed.stderr.strip() or 'unknown error'}")
    return completed.stdout.strip()


def save_recap(
    recaps_dir: Path,
    week_start: datetime,
    week_end: datetime,
    notes_count: int,
    body: str,
    generated: datetime,
) -> Path:
    recaps_dir.mkdir(parents=True, exist_ok=True)
    path = recaps_dir / f"{week_start.strftime('%Y-%m-%d')}.md"
    frontmatter = (
        "---\n"
        f"week_start: {week_start.strftime('%Y-%m-%d')}\n"
        f"week_end: {week_end.strftime('%Y-%m-%d')}\n"
        f"notes_count: {notes_count}\n"
        f"generated: {generated.isoformat()}\n"
        "---\n\n"
    )
    path.write_text(frontmatter + body + "\n", encoding="utf-8")
    return path


def generate_recap(
    config: Config, start: datetime, end: datetime, now: datetime
) -> RecapResult:
    notes = notes_in_range(config.notes_path, start, end)
    if not notes:
        return RecapResult(path=None, body=None, notes_count=0)
    prompt = build_prompt(notes, start, end)
    body = run_claude(prompt, config.claude_timeout)
    path = save_recap(config.recaps_dir, start, end, len(notes), body, now)
    return RecapResult(path=path, body=body, notes_count=len(notes))
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd telegram-notes-bot && uv run pytest tests/test_recap.py -v`
Expected: PASS (8 passed)

- [ ] **Step 5: Run the full suite**

Run: `cd telegram-notes-bot && uv run pytest -v`
Expected: PASS (all tasks 1–4 green)

- [ ] **Step 6: Commit**

```bash
git add telegram-notes-bot/notesbot/recap.py telegram-notes-bot/tests/test_recap.py
git commit -m "feat(notesbot): recap prompt, claude -p runner, and file output"
```

---

### Task 5: aiogram handlers

**Files:**
- Create: `telegram-notes-bot/notesbot/handlers.py`

**Interfaces:**
- Consumes:
  - `notesbot.config.Config`.
  - `notesbot.storage.append_note`, `notes_in_range`.
  - `notesbot.weeks.current_week_range`.
  - `notesbot.recap.generate_recap`, `RecapError`.
- Produces:
  - `build_router(config: Config) -> aiogram.Router` — a Router gated to `config.owner_id` (`router.message.filter(F.from_user.id == config.owner_id)`), with handlers:
    - `/start`, `/help` → usage text.
    - `/list` → last 10 notes of the current week (or "порожньо").
    - `/recap` → `generate_recap(config, *current_week_range(now), now)`; reply with body, or "немає заміток за цей тиждень", or an error message on `RecapError`.
    - any other text message → `append_note(...)`, then react/acknowledge.
  - `_now(config)` helper returning tz-aware current time (`datetime.now(config.tz)`), so tests/scheduler can share the tz logic.

Note: handlers are wired around already-tested pure logic; they are exercised by the manual smoke test in Task 7, not unit-tested over the network (per the design's testing scope).

- [ ] **Step 1: Write `notesbot/handlers.py`**

```python
from __future__ import annotations

import logging
from datetime import datetime

from aiogram import F, Router
from aiogram.filters import Command
from aiogram.types import Message

from notesbot.config import Config
from notesbot.recap import RecapError, generate_recap
from notesbot.storage import append_note, notes_in_range
from notesbot.weeks import current_week_range

logger = logging.getLogger(__name__)

HELP_TEXT = (
    "📝 <b>Notes bot</b>\n\n"
    "Надішли будь-який текст — я збережу його як замітку.\n\n"
    "Команди:\n"
    "/recap — підсумок за цей тиждень (через Claude)\n"
    "/list — останні замітки цього тижня\n"
    "/help — ця довідка"
)


def _now(config: Config) -> datetime:
    return datetime.now(config.tz)


def build_router(config: Config) -> Router:
    router = Router()
    router.message.filter(F.from_user.id == config.owner_id)

    @router.message(Command("start", "help"))
    async def cmd_help(message: Message) -> None:
        await message.answer(HELP_TEXT)

    @router.message(Command("list"))
    async def cmd_list(message: Message) -> None:
        start, end = current_week_range(_now(config))
        notes = notes_in_range(config.notes_path, start, end)
        if not notes:
            await message.answer("Порожньо — цього тижня ще немає заміток.")
            return
        lines = [f"• [{n.ts.strftime('%a %H:%M')}] {n.text}" for n in notes[-10:]]
        await message.answer("\n".join(lines))

    @router.message(Command("recap"))
    async def cmd_recap(message: Message) -> None:
        now = _now(config)
        start, end = current_week_range(now)
        await message.answer("⏳ Генерую підсумок через Claude…")
        try:
            result = generate_recap(config, start, end, now)
        except RecapError as exc:
            logger.exception("recap failed")
            await message.answer(f"⚠️ Не вдалося зробити recap: {exc}")
            return
        if result.path is None:
            await message.answer("Немає заміток за цей тиждень.")
            return
        await message.answer(result.body)
        await message.answer(f"💾 Збережено: {result.path}")

    @router.message(F.text)
    async def save_message(message: Message) -> None:
        now = _now(config)
        try:
            append_note(config.notes_path, message.text, message.message_id, now)
        except OSError:
            logger.exception("failed to save note")
            await message.answer("⚠️ Не вдалося зберегти замітку.")
            return
        await message.react([{"type": "emoji", "emoji": "👍"}])

    return router
```

- [ ] **Step 2: Verify it imports**

Run: `cd telegram-notes-bot && uv run python -c "from notesbot.handlers import build_router; print('ok')"`
Expected: prints `ok`

- [ ] **Step 3: Commit**

```bash
git add telegram-notes-bot/notesbot/handlers.py
git commit -m "feat(notesbot): aiogram handlers for notes, /recap, /list, /help"
```

---

### Task 6: Scheduler + entrypoint

**Files:**
- Create: `telegram-notes-bot/notesbot/scheduler.py`
- Create: `telegram-notes-bot/notesbot/__main__.py`

**Interfaces:**
- Consumes:
  - `notesbot.config.Config`.
  - `notesbot.recap.generate_recap`, `RecapError`.
  - `notesbot.weeks.previous_week_range`.
  - `aiogram.Bot`.
- Produces:
  - `setup_scheduler(bot: Bot, config: Config) -> AsyncIOScheduler` — schedules `weekly_recap_job` on `CronTrigger(day_of_week="mon", hour=9, minute=0, timezone=config.tz)`; returns the (started) scheduler.
  - `async weekly_recap_job(bot: Bot, config: Config) -> None` — computes `previous_week_range(datetime.now(config.tz))`, runs `generate_recap`, and sends the body (or "немає заміток") to `config.owner_id`; logs + messages owner on `RecapError`.
  - `async main() -> None` in `__main__.py` — loads config, builds `Bot` (HTML parse mode) + `Dispatcher`, includes `build_router(config)`, starts the scheduler, and runs `dp.start_polling(bot)`.

- [ ] **Step 1: Write `notesbot/scheduler.py`**

```python
from __future__ import annotations

import logging
from datetime import datetime

from aiogram import Bot
from apscheduler.schedulers.asyncio import AsyncIOScheduler
from apscheduler.triggers.cron import CronTrigger

from notesbot.config import Config
from notesbot.recap import RecapError, generate_recap
from notesbot.weeks import previous_week_range

logger = logging.getLogger(__name__)


async def weekly_recap_job(bot: Bot, config: Config) -> None:
    now = datetime.now(config.tz)
    start, end = previous_week_range(now)
    logger.info("running weekly recap for %s..%s", start.date(), end.date())
    try:
        result = generate_recap(config, start, end, now)
    except RecapError as exc:
        logger.exception("weekly recap failed")
        await bot.send_message(config.owner_id, f"⚠️ Тижневий recap не вдався: {exc}")
        return
    if result.path is None:
        await bot.send_message(config.owner_id, "Минулого тижня не було заміток.")
        return
    await bot.send_message(config.owner_id, f"🗓 Тижневий підсумок ({start.date()}–{end.date()}):")
    await bot.send_message(config.owner_id, result.body)
    await bot.send_message(config.owner_id, f"💾 Збережено: {result.path}")


def setup_scheduler(bot: Bot, config: Config) -> AsyncIOScheduler:
    scheduler = AsyncIOScheduler(timezone=config.tz)
    scheduler.add_job(
        weekly_recap_job,
        CronTrigger(day_of_week="mon", hour=9, minute=0, timezone=config.tz),
        args=(bot, config),
        id="weekly_recap",
        replace_existing=True,
    )
    scheduler.start()
    return scheduler
```

- [ ] **Step 2: Write `notesbot/__main__.py`**

```python
from __future__ import annotations

import asyncio
import logging

from aiogram import Bot, Dispatcher
from aiogram.client.default import DefaultBotProperties
from aiogram.enums import ParseMode

from notesbot.config import load_config
from notesbot.handlers import build_router
from notesbot.scheduler import setup_scheduler

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s: %(message)s",
)
logger = logging.getLogger("notesbot")


async def main() -> None:
    config = load_config()
    bot = Bot(
        token=config.bot_token,
        default=DefaultBotProperties(parse_mode=ParseMode.HTML),
    )
    dp = Dispatcher()
    dp.include_router(build_router(config))
    setup_scheduler(bot, config)
    logger.info("notesbot starting (owner=%s, tz=%s)", config.owner_id, config.tz_name)
    await dp.start_polling(bot)


if __name__ == "__main__":
    asyncio.run(main())
```

- [ ] **Step 3: Verify imports and scheduler wiring (no token needed)**

Run:
```bash
cd telegram-notes-bot && uv run python -c "
from notesbot.scheduler import setup_scheduler, weekly_recap_job
from notesbot import __main__
print('ok')
"
```
Expected: prints `ok`

- [ ] **Step 4: Commit**

```bash
git add telegram-notes-bot/notesbot/scheduler.py telegram-notes-bot/notesbot/__main__.py
git commit -m "feat(notesbot): APScheduler weekly job + polling entrypoint"
```

---

### Task 7: justfile, README, manual recap CLI, smoke test

**Files:**
- Create: `telegram-notes-bot/justfile`
- Create: `telegram-notes-bot/README.md`
- Create: `telegram-notes-bot/notesbot/manual_recap.py`

**Interfaces:**
- Consumes: `load_config`, `previous_week_range`, `generate_recap`.
- Produces: `notesbot/manual_recap.py` with a `main()` that runs a recap for the previous week and prints the resulting path — for `just recap` (no bot/polling).

- [ ] **Step 1: Write `notesbot/manual_recap.py`**

```python
from __future__ import annotations

from datetime import datetime

from notesbot.config import load_config
from notesbot.recap import generate_recap
from notesbot.weeks import previous_week_range


def main() -> None:
    config = load_config()
    now = datetime.now(config.tz)
    start, end = previous_week_range(now)
    print(f"→ recap for {start.date()}..{end.date()}")
    result = generate_recap(config, start, end, now)
    if result.path is None:
        print("  no notes in range")
        return
    print(f"  OK: {result.path} ({result.notes_count} notes)")


if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Write `justfile`** (loud recipes per repo convention)

```just
# Telegram notes bot

# Run the bot (polling)
run:
    @echo "→ starting notesbot..." >&2
    uv run python -m notesbot

# Run the test suite
test:
    @echo "→ running tests..." >&2
    uv run pytest -v

# Generate last week's recap without starting the bot
recap:
    @echo "→ generating manual recap..." >&2
    uv run python -m notesbot.manual_recap
```

- [ ] **Step 3: Write `README.md`**

```markdown
# telegram-notes-bot

Personal Telegram bot (aiogram 3.x): save any message as a note, get a weekly
Claude-generated recap.

## Setup

1. Create a bot via [@BotFather](https://t.me/BotFather), copy the token.
2. Find your Telegram user id (e.g. via [@userinfobot](https://t.me/userinfobot)).
3. Add to `~/dotfiles/.env`:

   ```
   TELEGRAM_BOT_TOKEN=123456:your-token
   TELEGRAM_OWNER_ID=your-numeric-id
   # optional, default Europe/Kyiv
   RECAP_TZ=Europe/Kyiv
   ```

4. Install deps: `uv sync`

## Usage

- `just run` — start the bot (long-polling).
- `just test` — run the test suite.
- `just recap` — generate last week's recap once, without the bot.

Send any text to the bot → it's saved to `data/notes.jsonl`.
`/recap` summarises the current week; every Monday 09:00 (Europe/Kyiv) the bot
auto-recaps the previous week. Recaps are saved to `recaps/<monday-date>.md`.

Requires the `claude` CLI on PATH (used headless via `claude -p`).
```

- [ ] **Step 4: Sync deps and run full test suite**

Run: `cd telegram-notes-bot && uv sync && uv run pytest -v`
Expected: PASS (all tests from Tasks 1–4 green)

- [ ] **Step 5: Verify manual recap wiring (expect a clean config error without env, OR runs)**

Run: `cd telegram-notes-bot && uv run python -c "import notesbot.manual_recap; print('ok')"`
Expected: prints `ok`

- [ ] **Step 6: Commit**

```bash
git add telegram-notes-bot/justfile telegram-notes-bot/README.md telegram-notes-bot/notesbot/manual_recap.py telegram-notes-bot/uv.lock
git commit -m "feat(notesbot): justfile, README, manual recap CLI"
```

- [ ] **Step 7: Live smoke test (manual, requires real token)**

This step needs the user's real `TELEGRAM_BOT_TOKEN`/`TELEGRAM_OWNER_ID` in `~/dotfiles/.env`.
1. `just run`
2. In Telegram: send "test note" → expect a 👍 reaction.
3. Send `/list` → expect the note listed.
4. Send `/recap` → expect a Claude-generated summary + a saved-path message, and a new file under `recaps/`.
5. Stop with Ctrl-C.

If the user's token isn't configured yet, leave this unchecked and report that the
automated build is complete but the live smoke test is pending their credentials.

---

## Notes for the executor

- Everything runs from the `telegram-notes-bot/` directory (its own `pyproject.toml` / `justfile`).
- The deviation from the spec's `src/notesbot/` layout to a flat `notesbot/` package is intentional: with `[tool.uv] package = false`, `uv run python -m notesbot` works because the project root (containing `notesbot/`) is on `sys.path`. No build step needed.
- Do not commit `data/` or `recaps/` (gitignored in Task 1).
- Secrets never get committed — they live in `~/dotfiles/.env`, which the repo already gitignores.
```
