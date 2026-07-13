from __future__ import annotations

import logging
from datetime import datetime

from aiogram import F, Router
from aiogram.filters import Command
from aiogram.types import Message, ReactionTypeEmoji

from notesbot.config import Config
from notesbot.recap import RecapError, generate_recap
from notesbot.storage import append_note, notes_in_range
from notesbot.weeks import current_week_range

logger = logging.getLogger(__name__)

HELP_TEXT = (
    "📝 <b>Notes bot</b>\n\n"
    "Надішли будь-який текст — я збережу його як замітку.\n\n"
    "Команди:\n"
    "/recap — підсумок за цей тиждень (через Claude)\n"
    "/list — останні замітки цього тижня\n"
    "/help — ця довідка"
)


def _now(config: Config) -> datetime:
    return datetime.now(config.tz)


def build_router(config: Config) -> Router:
    router = Router()
    router.message.filter(F.from_user.id == config.owner_id)

    @router.message(Command("start", "help"))
    async def cmd_help(message: Message) -> None:
        await message.answer(HELP_TEXT)

    @router.message(Command("list"))
    async def cmd_list(message: Message) -> None:
        start, end = current_week_range(_now(config))
        notes = notes_in_range(config.notes_path, start, end)
        if not notes:
            await message.answer("Порожньо — цього тижня ще немає заміток.")
            return
        lines = [f"• [{n.ts.strftime('%a %H:%M')}] {n.text}" for n in notes[-10:]]
        await message.answer("\n".join(lines))

    @router.message(Command("recap"))
    async def cmd_recap(message: Message) -> None:
        now = _now(config)
        start, end = current_week_range(now)
        await message.answer("⏳ Генерую підсумок через Claude…")
        try:
            result = generate_recap(config, start, end, now)
        except RecapError as exc:
            logger.exception("recap failed")
            await message.answer(f"⚠️ Не вдалося зробити recap: {exc}")
            return
        if result.path is None:
            await message.answer("Немає заміток за цей тиждень.")
            return
        await message.answer(result.body)
        await message.answer(f"💾 Збережено: {result.path}")

    @router.message(F.text)
    async def save_message(message: Message) -> None:
        now = _now(config)
        try:
            append_note(config.notes_path, message.text, message.message_id, now)
        except OSError:
            logger.exception("failed to save note")
            await message.answer("⚠️ Не вдалося зберегти замітку.")
            return
        await message.react([ReactionTypeEmoji(emoji="👍")])

    return router
