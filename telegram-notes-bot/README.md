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
