from __future__ import annotations

import logging
from datetime import datetime

from aiogram import Bot
from apscheduler.schedulers.asyncio import AsyncIOScheduler
from apscheduler.triggers.cron import CronTrigger

from notesbot.config import Config
from notesbot.recap import RecapError, generate_recap
from notesbot.weeks import previous_week_range

logger = logging.getLogger(__name__)


async def weekly_recap_job(bot: Bot, config: Config) -> None:
    now = datetime.now(config.tz)
    start, end = previous_week_range(now)
    logger.info("running weekly recap for %s..%s", start.date(), end.date())
    try:
        result = generate_recap(config, start, end, now)
    except RecapError as exc:
        logger.exception("weekly recap failed")
        await bot.send_message(config.owner_id, f"⚠️ Тижневий recap не вдався: {exc}")
        return
    if result.path is None:
        await bot.send_message(config.owner_id, "Минулого тижня не було заміток.")
        return
    await bot.send_message(
        config.owner_id, f"🗓 Тижневий підсумок ({start.date()}–{end.date()}):"
    )
    await bot.send_message(config.owner_id, result.body)
    await bot.send_message(config.owner_id, f"💾 Збережено: {result.path}")


def setup_scheduler(bot: Bot, config: Config) -> AsyncIOScheduler:
    scheduler = AsyncIOScheduler(timezone=config.tz)
    scheduler.add_job(
        weekly_recap_job,
        CronTrigger(day_of_week="mon", hour=9, minute=0, timezone=config.tz),
        args=(bot, config),
        id="weekly_recap",
        replace_existing=True,
    )
    scheduler.start()
    return scheduler
