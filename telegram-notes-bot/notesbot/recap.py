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
        raise RecapError(
            f"claude -p failed: {completed.stderr.strip() or 'unknown error'}"
        )
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
