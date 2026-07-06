---
description: "Full code review of a PR: analyze diff, find bugs, post Ukrainian beginner-friendly review on GitHub"
argument-hint: "<PR number>"
---

# Review PR #$ARGUMENTS

Perform a full code review of PR #$ARGUMENTS and post a detailed, educational review comment on GitHub.

## Step 1: Gather context

Run these commands in parallel:

```bash
# Get PR metadata
gh pr view $ARGUMENTS --json baseRefName,headRefName,title,headRefOid,files

# Get the diff
gh pr diff $ARGUMENTS

# Get existing reviews (to see previous feedback and style)
gh api repos/{owner}/{repo}/pulls/$ARGUMENTS/reviews --jq '.[] | {state: .state, body: .body}'

# Get repo owner
gh repo view --json nameWithOwner --jq '.nameWithOwner'
```

## Step 2: Verify branch cleanliness

Fetch and compare the PR branch against the base branch:

```bash
git fetch origin {headRefName}
git diff origin/{baseRefName}..origin/{headRefName}
```

Check for overlapping changes — if the diff contains files or changes that don't belong to this PR's purpose (based on the title), the branch needs a rebase. This is a common issue when multiple PRs are open simultaneously.

## Step 3: Read source files

For every file in the diff, read the FULL file to understand context:
- What functions surround the change?
- Who calls the changed code?
- Are there related files (imports, utilities, models)?

Also check for:
- Remaining instances of bugs/typos the PR claims to fix: `grep -rn "pattern" --include="*.py"`
- Template variables that need matching renames
- Related code that should change together

## Step 4: Analyze for bugs

Look for these categories:
1. Logic errors — wrong conditions, missing returns, off-by-one
2. Dead code — unused variables, unreachable code after early return
3. Type mismatches — comparing enum with string, wrong argument types
4. UX issues — confusing messages, blocking access unnecessarily
5. Naming — typos, misleading names, inconsistent conventions
6. DRY violations — copy-pasted code that should be extracted
7. Missing edge cases — negative numbers, empty strings, None values
8. Overlap with other PRs — changes that don't belong here
9. Debug leftovers — print statements, >>>> markers, temporary logs
10. Security — injection, hardcoded secrets, unsafe deserialization
11. **Читабельність та професійний стиль** — вчи PEP 8 і пайтонічні ідіоми, щоб автор ріс з кожним рев'ю:
    - **PEP 8**: пробіли навколо `=` у присвоєннях (`x = 1`, а не `x=1`), 4-space відступи (без випадкових 8-space під `if`), без trailing whitespace, newline в кінці файлу, дві порожні лінії між top-level def, не використовуй однолітерні імена що перекривають builtin (`l`, `I`, `O`) — ruff ловить як E741
    - **Naming**: ім'я описує *чим* є значення, а не *звідки* воно взялося (`level_name` замість `target_new_level`, якщо значення — це рядкове ім'я, а не Level). Дієслова для функцій, іменники для змінних.
    - **Control flow**: розгортай вкладені `try/except`, коли raise може виникнути тільки в одному рядку; звужуй scope `try`. Early return / guard clauses замість глибоких пірамід if.
    - **Ідіоми**: `if key in Enum.__members__` замість `try: Enum[key] except KeyError`; `.isdigit()` замість `try: int(x)` для "чи це число"; f-strings замість `.format()` / `%`; `pathlib.Path` замість `os.path`.
    - **Порядок операцій**: спершу валідуй дешеве (парсинг, enum lookup), потім — дороге (диск, БД). Погані вхідні дані мають падати швидко, не зачіпаючи сховище.
    - **Concurrency**: незалежні `await` (наприклад, повідомити юзера + відповісти адміну) мають запускатися паралельно через `asyncio.gather(..., return_exceptions=True)`, а не послідовно — і `gather` дозволяє ізолювати помилку однієї задачі, щоб зламаний побічний ефект не видавав себе за повний провал.
    - **Error handling**: `loguru`'s `.exception()` вже захоплює traceback — не дублюй через `f"...: {e}"`. Широкий `except Exception` має бути зовнішньою сіткою, а не catch-all, що ховає конкретні баги (наприклад, помилка Telegram send ковтає успішний update БД).
    - **Консистентність з house style**: використовуй патерни, які вже є в сусідніх handler-ах (`Level.__members__`, `get_name_from_pydantic`, і т.д.), замість винаходити нові.

Подавай це як *моменти навчання* — читач має вийти з розумінням принципу, не просто fix-а. Пояснюй простими словами реальний вплив (що зламається для юзера / он-колла о 3-й ночі) — БЕЗ посилань на номери PEP.

## Step 5: Write and post the review

### CRITICAL: Review style rules

The review MUST follow this exact style (the user mentors beginner programmers):

- **Language:** Ukrainian ONLY
- **Tone:** Ти **senior engineer, який менторить junior-а**. Будь зрозумілим і освітнім — пояснюй ЧОМУ щось не так, а не просто ЩО, простими словами з реальним впливом. Без цитування номерів PEP. Показуй fix *і* принцип за ним.
- **Візуалізація:** кожна ВАЖЛИВА знахідка містить Mermaid-діаграму ВСЕРЕДИНІ знахідки (потік бага, before/after) — GitHub рендерить Mermaid нативно.
- **Structure:**
  - Start with `## Review: {emoji} {Approve/Request Changes}`
  - Use emoji section headers: 🚨 (critical), 🐛 (bug), 🗑️ (dead code), 📉 (perf), 💡 (suggestion), 📋 (style), ✅ (good)
  - Number each finding: `### 1. 🚨 Title`
- **Severity badge + score (0-100)** on EVERY finding — a colored circle and numeric score showing how critical the issue is:
  - 🔴 **Критично (80-100)** — блокер, мерджити не можна (data loss, security, broken build)
  - 🟠 **Серйозно (60-79)** — баг або проблема, яка вплине на production
  - 🟡 **Помірно (30-59)** — не баг, але може спричинити проблеми в майбутньому
  - 🟢 **Мінорно (0-29)** — стиль, naming, покращення якості коду
  - Format: `### 1. 🚨 Title 🔴 85/100`
  - The score reflects nuance WITHIN the color band (e.g., 🟠 65/100 is less urgent than 🟠 78/100)
- **Code examples:** Show the broken code, explain the problem, show the fix
- **"Порада:" blocks** after each finding — teach the underlying programming principle
- **Tables** for comparisons (before/after, different approaches, edge cases)
- **"Що робити?"** section at the end — numbered action items, sorted by severity (🔴 first)
- **"Підсумок"** table — status of each finding with severity column:

```markdown
| # | Знахідка | Тип | Severity | Статус |
|---|----------|-----|----------|--------|
| 1 | Description | 🚨 Critical | 🔴 95/100 | Потрібно виправити |
| 2 | Description | 🐛 Bug | 🟠 70/100 | ... |
| 3 | Description | 💡 Suggestion | 🟡 45/100 | ... |
| 4 | Description | 📋 Style | 🟢 15/100 | ... |
```

### Decision logic

- If ALL issues are cosmetic/optional → вердикт ✅ Approve (з порадами)
- If there are real bugs or the branch needs rebase → вердикт 🔄 Request Changes
- If fixes from previous review were applied successfully → acknowledge each one with ✅

### Show draft, then post (GATED — ніколи не постити автоматично)

1. СПОЧАТКУ прочитай УСІ існуючі бот-коментарі (Cursor Bugbot, Gemini) і дай
   кожному вердикт + score, перш ніж писати власні знахідки.
2. Виведи ПОВНЕ тіло рев'ю в термінал. НЕ пости.
3. Чекай явного підтвердження ("go", "пости", "post"). Повторний виклик цієї
   команди — НЕ підтвердження. Будь-що інше = стоїмо.
4. On go — обери спосіб:
   - **PR Майка** → переклади драфт на English і `gh pr comment $ARGUMENTS --body-file <tmp>` —
     ніколи `--approve`/`--request-changes` на власних PR (GitHub-пости — English-only).
   - **Чужий PR** → `gh pr review $ARGUMENTS --{approve|request-changes} --body-file <tmp>` (English body).
   Use a temp file / HEREDOC for the body to preserve formatting.
5. After a successful post, stamp the pipeline state so the statusline badge
   (`/pr-state` → `RPR`) reflects it:

```bash
~/.claude/pipeline-stamp.sh stamp review-pr pr-comment
```

### Previous review references

If there were previous reviews on this PR, reference them:
- "Як я вже писав у попередньому рев'ю — ..."
- "Бачу, що ти виправив {X} з минулого рев'ю — чудово! ✅"
- Don't repeat findings that were already addressed

### Important rules

- ALWAYS read source files before analyzing — never review from diff alone
- Check the FULL codebase for related issues (grep for patterns)
- Be honest — not everything needs fixing, say so explicitly
- Acknowledge good work — if something was done well, say it
- If a finding is about pre-existing code (not changed in this PR), note it explicitly
- One review comment per invocation — don't post multiple reviews
- End with clear action items the developer can follow
