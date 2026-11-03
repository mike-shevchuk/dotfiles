---
description: Close Mike's blockers one by one in the AskUserQuestion modal — facts first, options + recommendation, then relay the answer to the waiting window and clear the blocker
argument-hint: "[PUN-x | W42:N | all]  (default: all, by priority)"
---

# /mine-grill — закрити мої блокери через модальне вікно

Mike 22.10: «добав команду /mine-grill яка буде теж через модальне вікно говорити зі мною і закривати блокери».
Mike відповідає у вікні з варіантами (+ своя думка через «Other») або в чаті — не перепечатує текстові блоки ([[feedback_questions_via_modal]]).

## 1. Зібрати (одна команда, не з пам'яті)
`python3 ~/.claude/scripts/lead.py blockers --json` (+ `--json` ↔ `blockers <idx>` для одного вікна) і `python3 ~/.claude/scripts/lead.py footer`.
Беремо лише 🙋 «Блокуєш ТИ» (не 🧭 лід — це мій борг, закриваю сам ДО того, як питати Mike). Порядок — бали з `w<N>/priorities.tsv` (100 → 0).
Аргумент `$ARGUMENTS`: PUN-x / W42:N — лише його; порожньо / `all` — усі.

## 2. Перевірити кожен блокер ДО питання
- Відкрий brief вікна (`w<N>/briefs/<idx>.md` «Що потрібно від Mike») і progress; звір наживо факт, на якому стоїть питання (URL/команда/sha). Застаріле — прибери з brief/need-mike, Mike не питай.
- Те, що Mike може зробити лише руками (проба `jb2b …-try`, `! jb2b …`), — не питання: дай команду в тексті, у модалі лише «запустив / пізніше».

## 3. Текст над модалем (для кожної пачки ≤4 питань)
На кожен блокер 3–5 рядків простими словами: **що сталось · факт з доказом · чому блокує (хто стоїть: W<N>:<idx>) · що зміниться після відповіді.** Без жаргону, без «див. вище».

## 4. Модаль — `AskUserQuestion`, ≤4 питання за раз
- `header` ≤12 символів (`2379 дедуп`, `1923 env`), `question` — одне речення з номером PR/PUN.
- 2–4 варіанти: рекомендований першим з `(Recommended)`, у `description` — наслідок одним рядком (що зробить команда далі).
- Не додавай варіант «Other» — він є сам. Відповідь «Other»/уточнення → обговори в чаті, потім переформулюй.

## 5. Закрити кожну відповідь одразу
1. Передай вікну, що чекає: `~/.claude/fleet-board/bin/send.sh W<N>:<idx> "LEAD: Mike — <рішення>. <що робити далі>"` (довге → допиши в місію, вікну — вказівник).
2. Запиши: рішення плану → `## Grill (Mike, <date>)` у плані (`→ Mike: …`), «план так» → `plan-approve.sh PUN-x <plan>`; бали → `w<N>/priorities.tsv`; пауза → `state.json`.
3. Прибери рядок з `w<N>/need-mike.tsv`, онови трек `track.sh <N> "<track>" "<step>" run|done <pct>`.
4. Зовнішні дії (Linear/GitHub/Slack/prod) — лише якщо відповідь Mike прямо це дозволяє; інакше чернетка.

## 6. Підсумок
Таблиця «блокер → рішення Mike → кому передано → що далі» + `lead.py footer` (мають зникнути закриті 🙋) + `result:` одним рядком.
