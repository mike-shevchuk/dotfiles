---
description: "Choose the best data architecture for one entity (DynamoDB keys, GSIs, history/audit, idempotency, TTL, concurrency) — BEFORE implementation, or AFTER it as an audit of what was built — from real access patterns, with priced alternatives and Mike's choice in the modal"
argument-hint: "<entity | PUN-x | #PR>  [before|after]  (default: after if the model already exists in code, else before)"
---

# /model-entity — найкраща архітектура сутності, з цифрами

Mike 06.11 (PUN-1943, «який новий GSI пропонуєш?»): «давай створимо команду /model-entity, в якій ми детально будемо обирати
найкращу архітектуру перед реалізацією або після, як зараз».
Chat: Ukrainian, terms in English. No Mermaid in the terminal — ASCII boxes. Read-only on code and AWS: this command
decides, it never edits code, CDK or data. Code changes come after Mike's choice, through the normal PR flow.

## 0. Режим
- `before` — сутності ще нема в коді: обираємо модель до плану/TDD. Результат іде в план (`## Data model`) до «план так».
- `after` — модель уже є (як `EventDBModel` у #2452): аудит зробленого проти найкращого варіанту → список змін з розміром, або «лишаємо, ось чому».
- Без аргументу режиму: `rg "class <Entity>DBModel"` у `backend/src/_common_layer/python/models/` знайшов → `after`, інакше `before`.

## 1. Зібрати факти (наживо, не з пам'яті)
1. **Задача:** Linear-тікет + УСІ коментарі й sub-issues, план (`~/zettelkasten/claude_code/rescue-serverless/architecture/`), контракт (`~/.claude/fleet-board/w*/drafts/*contract*`), tiki-notes PR.
2. **Код:** DB-модель, репозиторій, сервіс, роути, які читають/пишуть сутність (`rg` по `pk`/`sk`-префіксу — ВСІ виклики, не лише в PR). graphify першим, якщо є граф.
3. **Таблиця наживо** (read-only):
   ```bash
   T=$(aws lambda get-function-configuration --function-name dev-rescue-serverless-fast-api --query 'Environment.Variables.TABLE_NAME' --output text)
   aws dynamodb describe-table --table-name "$T" --query 'Table.{gsi:GlobalSecondaryIndexes[].{n:IndexName,k:KeySchema[].AttributeName,p:Projection.ProjectionType},ttl:TableName,billing:BillingModeSummary.BillingMode}'
   aws dynamodb describe-time-to-live --table-name "$T"
   ```
   + хто вже займає кожен GSI (`rg "gsiN_pk"` по моделях) — GSI спільні для всіх сутностей.
4. **Обсяг:** скільки записів на org/день зараз і через рік (джерело: тікет, prod-метрики, аналог-сутність). Без цифри — пиши «невідомо» і бери песимістичну оцінку, позначену як оцінка.

## 2. Access patterns — серце рішення
Таблиця, рядок на кожен шлях читання/запису (включно з FE-екранами, workers, метриками, міграціями, аудитом):

`# | Хто (екран / lambda / worker) | Операція | Ключ / фільтр | Частота | Розмір відповіді | Консистентність | Що зламається, якщо повільно/неточно`

Правила: кожен рядок має реального споживача (файл:рядок або екран); «колись знадобиться» — у окремий список YAGNI, не в таблицю.

## 3. Кандидати (2–4, різні по суті)
Для кожного — один ASCII-блок:
```
 pk = ORG#{orgId}          sk = EVENT#{ulid}
 gsi2_pk = …               gsi2_sk = …          (sparse? projection?)
 sentinel / counter / history item — якщо є
 ttl = …                   item ≈ N KB (стеля 400 KB)
```
Обов'язкові осі, на кожну — відповідь для кожного кандидата:
- **Ключі й GSI:** переюз gsi1–4 (який, що там уже лежить, чи не зіткнуться префікси) vs новий sparse GSI (CDK на СПІЛЬНІЙ таблиці dev+prod, побудова на prod, backfill старих рядків).
- **Кожен access pattern з §2** — Query/GetItem/BatchGet, скільки RCU, чи є `FilterExpression` (⚠ `Limit` діє ДО фільтра — порожні сторінки), чи нема Scan (заборонено).
- **Історія / аудит / одне джерело правди:** де живе стан, де журнал; що буде, коли два записи одного факту розійдуться.
- **Ідемпотентність:** повтор з тим самим externalId / ретрай черги — sentinel, conditional put, content-addressing.
- **Конкурентність:** два одночасні записи — condition expression, version, retry, 409.
- **Життєвий цикл:** TTL (що з sentinel, S3-об'єктами, GSI-копіями), архів, видалення.
- **Межі валідатора:** жорстка межа в DB-моделі ламає ЧИТАННЯ старих рядків — межі лише на вході (request), не в DB-моделі.
- **Вартість:** WCU на запис (кожен GSI = ще один запис), RCU на типовий екран, S3/CDN, за місяць на prod при обсязі з §1.4.
- **Prod-вплив:** CDK, міграція, backfill, env vars, порядок деплою.
- **FE-вплив:** які поля/форми екран отримує, що null, що асинхронно (GSI eventually consistent).

## 4. Матриця
Рядки = осі §3 + кожен access pattern §2; стовпці = кандидати; клітинка `✅ / ⚠ / ❌` + ≤8 слів чому.
Нижче — розмір зміни для кожного кандидата (`+/- рядків`, файли, CDK так/ні) і, в режимі `after`, що з уже зробленого викидається.

## 5. Рішення Mike — модаль
Перед модалем — картка сутності продуктовими словами (хто → що робить → що бачить користувач; чим вона НЕ є).
`AskUserQuestion`, одна вісь рішення = одне питання (не пакуй дві), ≤4 за раз:
- `question`: що вирішуємо + головний факт (з цифрою) + що зміниться.
- варіанти = кандидати; рекомендований першим з `(Recommended)`; `preview` 6–12 рядків: ключі · як читає головний екран · ціна · пастка · prod-вплив · хто що робить далі.
- Mike бачить ЛИШЕ модаль, поки він відкритий — контекст усередині.

## 6. Записати
- Нотатка: `~/zettelkasten/claude_code/rescue-serverless/models/<YYYY-MM-DD>-<entity>-model.md` (спершу прочитати `~/zettelkasten/claude_code/CLAUDE.md`; frontmatter, `[[wikilinks]]`, `#tags`): access patterns, кандидати, матриця, рішення `→ Mike: …`, відкинуте й чому.
- План задачі: `## Data model` з посиланням на нотатку + рядок `→ Mike: …` під `## Grill`.
- tiki-notes PR: 3–5 рядків + посилання.
- Режим `after` з рішенням «міняємо»: список змін (файл · що · розмір) → вікну задачі через лід; код лише після OK ліда на дельту.

## 7. Відповідь у чаті
Коротко: рекомендація одним реченням, таблиця «кандидат → чим платимо», рішення Mike, де записано, що далі. Кінець — footer вікна.

## Пастки цього репо (перевір кожну)
- Scan заборонений; FilterExpression після `Limit` дає порожні сторінки (audit list `category=EVENT limit=50` → 0 рядків, 06.11).
- Два джерела правди = баг, поки не названо, хто головний і що буде при розходженні.
- GSI спільні: новий префікс у gsi1–4 не має збігатися з чужим `begins_with`.
- Межі (max_length, ge/le) у DB-моделі ламають читання історичних рядків.
- Новий механізм (sentinel, counter) — лише після «існуючий не підходить, бо …» (`ExternalIdReservation`, `IdempotencyStore`).
- Async-шлях (SQS → worker) не видно одразу у відповіді — UI, що показує «щойно змінене», читає синхронне джерело.
- Ціна AWS рахується на prod-обсязі, не на dev.
