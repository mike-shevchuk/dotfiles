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
