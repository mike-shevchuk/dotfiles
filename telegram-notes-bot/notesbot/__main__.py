from __future__ import annotations

import asyncio
import logging

from aiogram import Bot, Dispatcher
from aiogram.client.default import DefaultBotProperties
from aiogram.enums import ParseMode

from notesbot.config import load_config
from notesbot.handlers import build_router
from notesbot.scheduler import setup_scheduler

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s: %(message)s",
)
logger = logging.getLogger("notesbot")


async def main() -> None:
    config = load_config()
    bot = Bot(
        token=config.bot_token,
        default=DefaultBotProperties(parse_mode=ParseMode.HTML),
    )
    dp = Dispatcher()
    dp.include_router(build_router(config))
    setup_scheduler(bot, config)
    logger.info("notesbot starting (owner=%s, tz=%s)", config.owner_id, config.tz_name)
    await dp.start_polling(bot)


if __name__ == "__main__":
    asyncio.run(main())
