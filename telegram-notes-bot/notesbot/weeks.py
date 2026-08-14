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
