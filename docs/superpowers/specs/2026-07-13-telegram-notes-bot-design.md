# Telegram Notes Bot — Design

**Date:** 2026-07-13
**Status:** Approved
**Owner:** Mike Shevchuk

## Purpose

A personal (single-user) Telegram bot built on **aiogram 3.x** that:

1. Saves any text message sent by the owner as a note, instantly.
2. Once a week (Monday 09:00 Europe/Kyiv) — and on-demand via `/recap` — collects that
   week's notes, runs them through the `claude -p` headless CLI to produce a themed
   weekly summary, saves it as a Markdown file next to the bot, and sends it to the chat.

## Decisions (locked)

| Question | Decision |
|----------|----------|
| Users / storage | Single user (owner only). Notes in a JSONL file; recap output in Markdown. |
| Claude invocation | `claude -p` headless CLI via subprocess (uses existing subscription, no API key). |
| Weekly trigger | Both: APScheduler cron (auto) **and** `/recap` command (manual). |
| Recap file location | Next to the bot: `recaps/YYYY-MM-DD.md`. |
| Note capture | Any text message from the owner = a note. |
| Auto-recap schedule | Monday 09:00, Europe/Kyiv. |

## Project structure

```
telegram-notes-bot/
├── pyproject.toml            # uv project: aiogram, apscheduler, python-dotenv
├── README.md
├── justfile                  # just run / just test / just recap
├── src/notesbot/
│   ├── __init__.py
│   ├── config.py             # reads ~/dotfiles/.env: TOKEN, OWNER_ID, tz, paths
│   ├── storage.py            # append_note(), notes_in_range() — pure logic
│   ├── recap.py              # build_prompt(), run_claude(), save_recap() — logic + subprocess
│   ├── handlers.py           # aiogram handlers: text→note, /recap /list /start /help
│   ├── scheduler.py          # APScheduler cron: Mon 09:00 → recap previous week
│   └── __main__.py           # wires Dispatcher + Bot + scheduler, runs polling
├── data/notes.jsonl          # source of truth (gitignored)
├── recaps/YYYY-MM-DD.md      # output, name = Monday of that week (gitignored)
└── tests/                    # pytest: storage + recap prompt/subprocess (mocked)
```

## Data model

- **Source of truth:** `data/notes.jsonl` — one JSON object per line:
  ```json
  {"ts": "2026-07-13T10:42:00+03:00", "text": "note body", "message_id": 123}
  ```
  Append-only; easy to filter by date range for a given week.
- **Recap output:** `recaps/2026-07-06.md` (filename = the Monday date of that week),
  with YAML frontmatter (`week_start`, `week_end`, `notes_count`, `generated`) + Claude body.
- Both `data/` and `recaps/` are gitignored (personal data never committed).

## Flow

1. **Note capture:** message from `OWNER_ID` → `append_note()` → short ✅ acknowledgement.
   Messages from anyone else are ignored.
2. **Recap (`/recap` or cron):** `notes_in_range(start, end)` →
   - if empty → reply "no notes this week", no file written;
   - else → `build_prompt()` → `run_claude()` (subprocess, ~120s timeout) →
     `save_recap()` → send the text to the chat.
   - `/recap` window = current week (Mon..now). Auto (Mon 09:00) window = previous full
     week (Mon..Sun that just ended).
3. **Scheduler:** APScheduler `CronTrigger(day_of_week='mon', hour=9, timezone='Europe/Kyiv')`
   in the bot process.

## Claude prompt (shape)

System instruction: "You summarise a week of personal notes. Group by theme, split into
Done / Ideas / To-do, write in Ukrainian, concise, Markdown." Body = numbered notes with
timestamps. Called as `claude -p "<prompt>" --output-format text` (non-interactive).

## Error handling

- `claude` crash/timeout → log + message owner with the error; **bot does not crash**.
- Empty week → friendly message, no file created.
- Note write failure → reply "couldn't save", log.
- Missing `TELEGRAM_BOT_TOKEN` / `TELEGRAM_OWNER_ID` → clear fail at startup with instructions.

## Config / secrets (in `~/dotfiles/.env`)

`TELEGRAM_BOT_TOKEN`, `TELEGRAM_OWNER_ID`. Optional `RECAP_TZ` (default `Europe/Kyiv`).
`.env` is already gitignored.

## Testing

`pytest` on pure logic:
- `storage`: append + range selection against a tmp file.
- `recap.build_prompt`: formatting.
- `recap.run_claude`: with a mocked subprocess.

aiogram handlers are not tested over the network.

## Running

- `just run` — `uv run python -m notesbot` (polling).
- `just test` — `uv run pytest`.
- `just recap` — one-off manual recap without starting the bot.
- Later (optional): launchd plist for auto-start on the Mac.

## Out of scope (YAGNI)

Multi-user, tags/categories, note editing/deletion, a database, webhooks, Docker.
All easy to add later if a real need appears.
