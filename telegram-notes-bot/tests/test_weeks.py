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
