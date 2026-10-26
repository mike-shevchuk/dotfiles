---
description: LGTM in the new style — ONE review page for a PR (house style, highlighted diff) that explains every hunk and DEFENDS the change rung by rung (ponytail) + a teach-me lesson page (ideas, interactive diagram, quiz) → hub links
argument-hint: "[PR number | current branch]  [owner/repo, default back2back-team/rescue-serverless]"
---

# /lgtm — сторінка рев'ю в новому стилі

Mike 22.10: «мені не зручний такий формат (.lgtm …/page.html) — треба переробити, ти маєш захистити, чому ми це робимо, у стилі ponytail»; «треба створити claude command для lgtm у новому стилі».
Результат — ОДНА сторінка для Mike: `~/zettelkasten/claude_code/rescue-serverless/reviews/pr<N>-handover.html` (рендерер `~/.claude/fleet-board/bin/handover-html.py`, шаблон house style, підсвічений diff). Старий LGTM — лише сирий додаток. Нічого не публікує в GitHub/Linear.

**Еталон (Mike 22.10: «в цілому задоволений, хочу схожий стиль, можна навіть більше діаграм і пояснень»):** `reviews/pr2379-handover.html`.
Більше діаграм, де вони щось пояснюють: `sequenceDiagram` — коли дія проходить кілька сервісів/Lambda/черг; `stateDiagram` — коли змінюється стан (тривога відкрита → закрита, слот, статус); діаграма даних до/після — коли міняється запис у БД. Кладіть їх у `diagram` (кілька — через `"diagrams": [{"title", "src"}]`).

## 1. Ціль
`$ARGUMENTS` → PR N (+ repo). Порожньо → `gh pr view --json number -q .number` для поточної гілки. Нема PR → скажи і зупинись.

## 2. Прочитати ПОВНІСТЮ (не з пам'яті)
`gh pr view N --json title,body,headRefOid,files` · `gh pr diff N` · кожен змінений файл навколо шматка (виклики, хто викликає) · Linear-тікет і план (`## Grill` — рішення Mike) · recap `~/.claude/fleet-board/w*/recaps/<N>.md`, якщо є.
Для кожного «вже було в коді» — знайди його (`rg`/graphify) і дай `file:line`. Не вигадуй: не перевірив → «⚠ не перевірено».

## 3. Написати нотатки `~/.claude/fleet-board/handover/pr<N>.json`
Простими словами українською (`*_en` — за бажанням). Обов'язкові ключі:
```json
{
  "verdict": "1–3 речення: що робить PR, чи готовий, головний ризик",
  "summary": ["що зміниться для юзера/Mike — 3–5 пунктів"],
  "try": "jb2b <recipe>  (якщо є проба)",
  "flow": "ASCII-схема: звідки → куди йде дія (коротко)",
  "diagram": "mermaid flowchart TD — ОБОВ'ЯЗКОВО (Mike 22.10): вхід → кожна перевірка → КОЖЕН вихід (усі HTTP-коди) → що змінюється в системі (БД, SNS/черги, чат, сповіщення, 911…)",
  "io": {"inputs":  [{"name": "", "where": "заголовок|тіло|query|подія", "required": "так|ні", "example": "", "rule": "що буде, якщо не так"}],
         "outputs": [{"case": "", "status": "201|200|4xx|5xx|подія", "body": "", "effects": "що змінюється в системі"}]},
  "ponytail": {
    "exists":  "чи це взагалі треба: яку проблему має юзер/Mike без цього (доказ: тікет, баг, лог)",
    "reused":  [{"what": "path/file.py:123 symbol", "why": "що з наявного взяли і навіщо"}],
    "simpler": "яку простішу версію розглянули (один рядок / stdlib / нічого) і чому вона не годиться",
    "size":    "+X −Y у N файлах — чи міг diff бути меншим; що з нього можна викинути",
    "skipped": [{"what": "що свідомо НЕ зроблено", "add_when": "коли додати"}]
  },
  "decisions": [{"title": "", "why": "", "without": "", "drop": "", "cost": "", "evidence": "file:line",
                 "alternatives": [{"option": "", "plus": "", "minus": "", "verdict": ""}]}],
  "files": {"path/to/file.py": {"role": "для чого цей файл у PR",
            "hunks": [{"what": "", "why": "", "need": "чи треба цей шматок взагалі",
                       "reuse": "що взято готове (file:line)", "smaller": "чому не менше",
                       "used_by": "хто викликає", "check": "як перевірити", "find": "знахідка рев'ю (якщо є) — проблема · шкода · фікс"}]}}
}
```
Порядок `hunks` = порядок шматків у `gh pr diff` для файлу. Пояснити треба **кожен** шматок (рендерер показує «пояснено X/Y»).

## 4. Рев'ю — знахідки
Під час читання шукай справжні проблеми (баги, два джерела правди, дірки доступу, FE, що зламається на новому полі, env/ліміти AWS). Кожну — у `find` відповідного шматка + 1 рядок у `verdict`, якщо серйозна. Немає — так і напиши.

## 5. Рендер і перевірка
```bash
python3 ~/.claude/fleet-board/bin/handover-html.py <N> [owner/repo]   # друкує шлях і «explained X/Y»
xh -I -h HEAD http://192.168.50.85:8890/rescue-serverless/reviews/pr<N>-handover.html   # чекай 200
```
X < Y → допиши нотатки й перегенеруй. Відкрий у браузері (Playwright): діаграма намалювалась (є SVG, без «Syntax error»), таблиці входів/виходів є, diff підсвічений, розділ «🐴 Чому саме так» є, мова UA, без горизонтального скролу на 760 px.
Онови сторінку статусу, якщо треба: `python3 ~/.claude/fleet-board/bin/status-html.py`.

## 5b. teach-me — урок з ідей PR (Mike 24.10: «коли я використовую /lgtm, також використовуй teach-me»)
Skill `~/.claude/skills/teach-me/SKILL.md` (sshah03/teach-me @ 41e7a64, перевірено: лише stdlib, без мережі). `/lgtm` = явний запуск teach-me для того ж PR.
Виконай його кроки 1–5 для цього PR (концепти → уроки + інтерактивна діаграма + квіз → перевірка кожного уроку окремим агентом за `references/check.md` → збірка + layout-перевірка). Відмінності від SKILL.md:
- уроки й квіз **українською** (код, ідентифікатори, `file:line` — як є);
- крок 6 НЕ через Artifact: `python3 -I ~/.claude/skills/teach-me/scripts/build_page.py <folder>/lessons.json --standalone > ~/zettelkasten/claude_code/rescue-serverless/reviews/pr<N>-teach-me.html` → `xh -I -h HEAD http://<LAN>:8890/rescue-serverless/reviews/pr<N>-teach-me.html` = 200;
- нічого вчити (лише перейменування / тривіальний фікс) → один рядок «teach-me: нема концептів, бо …», сторінку не роби.
Можна паралельно з кроком 3–4 (окремий агент), лише читання коду.

## 6. Відповідь Mike
LAN-лінк handover · LAN-лінк teach-me (або «нема концептів») · `explained X/Y` · 3 рядки: що PR робить, головний аргумент «чому саме так», знахідки (або «немає») · `result:` одним рядком.
