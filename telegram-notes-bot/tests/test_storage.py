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
