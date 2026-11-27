---
description: "Повернути Mike в контекст задачі: хто створив тікет, хто робить, які PR (відкриті / змерджені), Slack, Otter / esp-deck, нотатки, наші рішення — і що реально лишилось"
argument-hint: "<PUN-xxxx | #PR | слово>  [save]  (save = записати в картку як «🧾 Звідки це»)"
---
# /ctx — повний контекст однієї задачі (Mike 26.11)

Mike 26.11 (PUN-2157): «хто створив тікет, хто створив PR, чи не був він уже відкритий — принеси повний контекст, додаткові джерела з esp, slack, otter, нотатків, розмови» → «хочу клод команду, яка повертає мене в контекст для цієї задачі».
Read-only: нічого не пише в Linear / Slack / GitHub / prod. Чат українською, цитати джерел — дослівно англійською. Усе наживо, не з пам'яті.

## 1. Зібрати (паралельно, де можна)
Аргумент `$ARGUMENTS`: PUN-id → тікет; `#N` → PR, тікет з назви/гілки/body; слово → `list_issues query=` і візьми найближчий (покажи, який саме).
1. **Linear:** `get_issue` (creator · assignee · status + stateHistory · project · priority · dueDate · attachments) + `list_comments` (усі) + parent / sub-issues / related (ті самі два виклики на кожен).
2. **GitHub:** `gh search prs --owner back2back-team "<PUN>"` + PR з attachments тікета + `git log origin/main --grep "<PUN>"` і за ключовими словами з назви. На кожен PR: `gh pr view N --json author,state,createdAt,mergedAt,title,body,comments` — автор, opened → merged / ще відкритий, суть одним рядком, `## PROD steps` / backfill з body, коментарі (особливо «integration» / JT).
3. **Slack** (`slack_search_public_and_private`): PUN-id; 2–3 ключові фрази з назви/опису; канали `#rescue_backend_webapp`, `#notify-rescue-integration`; `after:` = дата за 7 днів до створення тікета. Треди — з усіма відповідями (`slack_read_thread`). PM bot check-in-и рахуються (статуси, хто чекає).
4. **Мітинги:** `rg -l -i "<PUN>|<ключові слова>" ~/zettelkasten/claude_code/meetings ~/.local/share/esp-deck/meetings ~/.claude/fleet-board/w*/meetings` → цитата + файл:час. esp-deck: читай .md, .txt і КОЖЕН скрін у `_shots/`; «Спікер N» ≠ людина (учасників і атрибуцію бери зі скрінів і змісту); розділяй ✅ вирішено / 💬 запропоновано. Нема — «у мітингах нічого» (теж факт).
5. **Наше:** tiki-картка (`~/.claude/fleet-board/w*/tiki-notes/*` з цим PUN): `## Grill` рядки «→ Mike:», 📌 Поточне рішення, вікно і його «Чекаю на»; `w*/grill-log.md`, `need-mike.tsv`, `plan-approvals.tsv`; нотатки `~/zettelkasten/claude_code/rescue-serverless/**` з PUN.

## 2. Відповідь (такий порядок, коротко)
1. **Головне** — 2–3 речення: що це за задача продуктовими словами, що вже зроблено ким, **що реально лишилось нам** (може бути «нічого»).
2. **Таймлайн** (code block, старі зверху): `DD.MM HH:MM  джерело · хто` + «дослівна цитата» — Slack, Linear (створено / статуси / коментарі), PR (opened / merged), коміти, changelog, мітинги.
3. **Хто що робить:** тікет (creator → assignee, статус) · кожен PR (автор, стан, що додає) · наше вікно і його крок.
4. **Що ти вже вирішив:** рядки «→ Mike:» з картки / grill-log, дослівно, з датою.
5. **🔎 Не знаємо** + як дізнатись (кого спитати — чернетка; read-only перевірка — лише з «так»).
6. **Що далі:** 2–3 варіанти дії з ➕/➖ (думку ліда позначити як думку), відповідь одним словом.
Посилання: Linear URL, PR URL, Slack permalink, картка на борді `http://macbook.local:8890/rescue-serverless/fleet/w<N>/#WIN<idx>`.

## 3. `save`
Записати розділ `## 🧾 Звідки це` у tiki-картку задачі (перед `## 🌍`; /card-plan §0.4) і зробити `tiki-board.py <N> && board-html.py <N>`. Без `save` — лише відповідь у чаті.
