---
description: "Terminal-first PR review-summary: every change in plain words WITH its code hunks, improvement proposals, optimization + existing-style checks, and a design-principles audit (SOLID, DRY, KISS, YAGNI, Strategy/other patterns)"
argument-hint: "<PR number> | <branch> | (empty = current branch vs main)"
---

# PR Summary #$ARGUMENTS — plain-language review with hunks

Terminal-ONLY output in **Ukrainian** (прості слова — читач може бути джуном).
This command never posts anywhere (use /review-pr-ukr for posting). ASCII only —
NO Mermaid in terminal. Every code excerpt is a real hunk from the diff, verbatim.

## Gather (in parallel)

- `gh pr view $ARGUMENTS --json title,state,mergeable,additions,deletions,changedFiles,labels,headRefName` and `gh pr diff $ARGUMENTS` (or `git diff origin/main...HEAD` if the argument is a branch/empty)
- `gh pr checks $ARGUMENTS` (CI one-liner)
- Read the FULL source of every changed file (not just hunks) — style comparison
  needs the surrounding code and at least one SIBLING file of the same kind
  (e.g. a neighbouring route/service module) as the style baseline.

## Output — EXACTLY these sections, in this order

### 1. Шапка (ASCII box)
```
┌─ PR #N: <title> ─────────────────────────────
│ +adds/−dels · F files · CI: ✅/❌ · mergeable
│ Гілка: <head> → main · Лейбли: …
└──────────────────────────────────────────────
```

### 2. Про що цей PR (один абзац, ≤10 речень, дорослий рісьорч)
Один рівень, без спрощень «для джуна» і без аналогій. Пиши ПІСЛЯ того, як
реально дослідив diff: прочитані повні файли, простежені виклики (хто кличе
змінений код і кого кличе він), звірені контракти залежностей — опис має
випливати з ханків, а не з назви PR.

Вимоги до абзацу:
- ≤10 речень, кожне несе факт; разом вони покривають УСІ значні ханки дифу
  (назви функцій/модулів згадуй прямо: «`_fetch_owned_credential` перефетчує…»);
- обов'язково: яку проблему вирішує → що саме змінено по ханках → ключове
  дизайн-рішення з trade-off'ом → чого PR свідомо НЕ робить;
- якщо рісьорч виявив факт, якого нема в описі PR (прихована залежність,
  побічний ефект, неочевидний ризик) — саме він і має бути в абзаці.

### 3. Мапа файлів (ASCII-дерево)
Кожен файл + один рядок «що тут» + маркер `NEW`/`MOD`/`DEL`.

### 4. Зміни по суті — ПО ОДНІЙ СЕКЦІЇ НА ЛОГІЧНУ ЗМІНУ (не на файл)
Для КОЖНОЇ логічної зміни:
- заголовок `### 4.N <назва зміни>` + 2-4 речення простою мовою (що і НАВІЩО);
- справжній hunk з diff у ```diff``` блоці (обрізай до суті, але код verbatim);
- якщо є що покращити → блок «Пропозиція:» зі своїм кодом у ```<lang>``` блоці
  (робочий код, не псевдо) і одним реченням чому так краще;
- `**Порада:**` — професійний принцип, який ця зміна ілюструє або порушує
  (мовою «щоб ти виніс з цього на майбутнє», без цитат стандартів).

### 5. Оптимізація (обов'язкова секція, навіть якщо порожня)
Пройди diff питаннями: повторні I/O? зайві обчислення? послідовне, що може бути
паралельним? важке в hot path / cold start? зайві алокації?
Формат: таблиця `Місце (file:line) | Що | Пропозиція | Виграш`, або чесне
«Оптимізувати нічого — <чому>».

### 6. Відповідність існуючому стилю (обов'язкова)
Порівняй з sibling-файлами: іменування, логування, error-handling, структура
роуту/сервісу, докстрінги. Формат: `✓/✗ <аспект> — <доказ: file:line проти file:line>`.

### 7. Аудит принципів і патернів (обов'язкова таблиця)
| Принцип | Вердикт | Де саме (file:line) + пояснення одним реченням |
Рядки: S·O·L·I·D (кожна літера окремо, лише релевантні — нерелевантним пиши «н/з»),
DRY, KISS, YAGNI, і використані/порушені патерни (Strategy, Guard Clause,
Repository, Facade/Proxy, Singleton, …). Вердикти: ✅ дотримано / ⚠ частково / ❌ порушено.
Кожен ⚠/❌ мусить мати місце в коді і пропозицію (можна посиланням на секцію 4.N).

### 8. Підсумок
| # | Знахідка/пропозиція | Тип | Severity | Дія |
Severity за домашньою шкалою: емодзі + число, напр. `🟠 72/100`
(Критично 80-100 / Серйозно 60-79 / Помірно 30-59 / Мінорно 0-29).
Закінчи вердиктом одним рядком: готовий до мержу / що добити спершу.

## Правила якості
- Кожна знахідка = Проблема → Шкода → Фікс з кодом (не «подумай про…»).
- Хвали конкретно: що зроблено добре і чому це правильний прийом.
- Якщо PR великий (>15 логічних змін) — секція 4 покриває ВСІ зміни, але
  найдрібніші можна групувати по 2-3 з одним спільним hunk-прикладом.
- Числа severity відображають нюанс УСЕРЕДИНІ кольорової смуги.
