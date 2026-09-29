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
