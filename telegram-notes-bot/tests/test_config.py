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
