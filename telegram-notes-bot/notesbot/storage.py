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
