---
name: sprint
description: "Sync Linear + Todoist, analyze rescue-serverless, create/update weekly sprint note in zettelkasten with estimates, today/tomorrow plan, and pro tips"
---

# Sprint Weekly Plan

Generate a professional weekly sprint note for Mike (backend engineer, rescue-serverless).

## Regenerate Mode (`/sprint regenerate`)

If `$ARGUMENTS` is exactly `regenerate`, **skip Steps 2–4 entirely** and run this instead:

### Regenerate Step 1: Get current date + locate file

```bash
python3 -c "
from datetime import date
today = date.today()
year = today.year
jan1 = date(year, 1, 1)
offset = (7 - jan1.weekday()) % 7
first_monday = date(year, 1, 1 + offset) if jan1.weekday() != 0 else jan1
week_num = (today - first_monday).days // 7 + 1 if today >= first_monday else 1
print(f'TODAY={today}')
print(f'WEEK_LABEL={year}-W{week_num:02d}')
print(f'WEEKDAY={today.strftime(\"%A\")}')
"
# export — the python heredoc below reads os.environ; a plain shell var is
# invisible to it and extraction always printed NO_USER_NOTES
export WEEK_LABEL="<computed above>"
COMB_NOTE="$HOME/zettelkasten/comb-notes/weekly_staff/${WEEK_LABEL}.md"
cat "$COMB_NOTE"
```

### Regenerate Step 2: Extract all tasks with scores

From the existing comb-notes file, extract every task block — both the `## 🚧 В роботі` and `## 📋 Todo` sections — and read the `- [ ] **[PUN-XXXX]**` header lines to get current 🔥N · ⚡N scores.

Do NOT read or modify `> 👤`, `> 🎓`, or `> 💬❓` lines.

### Regenerate Step 3: Re-rank and rewrite Today/Tomorrow only

**Ranking rule:** sort tasks by (⚡ urgency desc, 🔥 importance desc). Skip tasks already in ✅ Done or In Review.

**Today** = top 3 by urgency×importance. For each, copy the ENTIRE task block verbatim from the existing file (preserving `> 💬`, `> 👤`, `> 🎓`, `> 💬❓` exactly as they are).

**Tomorrow** = next 2–3 tasks by same ranking.

Replace ONLY the `## 🔥 Сьогодні` section and the `## ☀️ Завтра` section in the comb-notes file. Every other line in the file stays exactly as-is.

### Regenerate Step 4: Print summary

```
✅ Regenerated: ~/zettelkasten/comb-notes/weekly_staff/<WEEK_LABEL>.md

TODAY'S FOCUS:
  1. [PUN-XXXX] Title — Xh (🔥N · ⚡N)
  2. ...

TOMORROW:
  1. [PUN-XXXX] Title — Xh (🔥N · ⚡N)
  ...
```

---
## Step 1: Get current date context

```bash
python3 -c "
from datetime import date

today = date.today()
year = today.year
jan1 = date(year, 1, 1)

# Week number = weeks since first Monday of the year (W1 = week of first Monday)
offset = (7 - jan1.weekday()) % 7
first_monday = date(year, 1, 1 + offset) if jan1.weekday() != 0 else jan1
week_num = (today - first_monday).days // 7 + 1 if today >= first_monday else 1

print(f'TODAY={today}')
print(f'WEEKDAY={today.strftime(\"%A\")}')
print(f'WEEK_LABEL={year}-W{week_num:02d}')
"
```

**Week convention:** W1 = first Mon–Sun week of January (not ISO). Use `$ARGUMENTS` as the week label if provided, otherwise use the computed `WEEK_LABEL`.

## Step 2: Fetch data in parallel

Run all of these simultaneously:

**2a. Todoist — Back2Back project tasks**
```bash
source ~/dotfiles/.env
curl -s "https://api.todoist.com/api/v1/tasks" \
  -H "Authorization: Bearer $TODOIST_TOKEN" | \
python3 -c "
import json, sys
obj = json.load(sys.stdin)
tasks = obj.get('results', [])
# Back2Back rescue project ID
PROJECT_ID = '6cf7g4H5532pQmW3'
for t in tasks:
    if t.get('project_id') == PROJECT_ID:
        due = (t.get('due') or {}).get('date', 'no-due')
        p = t.get('priority', 1)
        desc = (t.get('description') or '')[:120]
        url = f'https://todoist.com/app/task/{t[\"id\"]}'
        print(f'P{p} | {t[\"content\"]} | due:{due} | id:{t[\"id\"]} | url:{url}')
        if desc:
            print(f'  desc: {desc}')
"
```

**Todoist task URLs** — always format as `[task title](https://todoist.com/app/task/{id})` in the sprint note.
**Updating Todoist descriptions** — after codebase analysis (Step 3), for each Todoist task being worked this sprint, optionally PATCH the description with key findings:
```bash
source ~/dotfiles/.env
curl -s -X POST "https://api.todoist.com/api/v1/tasks/{TASK_ID}" \
  -H "Authorization: Bearer $TODOIST_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"description\": \"<codebase findings, file:line, next step>\"}"
```
Only update if the codebase analysis adds meaningful context not already in the description. Keep it short (3–5 lines max).

**Todoist labels** — apply to all Back2Back project tasks during the run:
- `sprint-W{NN}` — tasks active in this sprint (per-sprint label, e.g. `sprint-W16`); create it if missing: `POST /api/v1/labels` with `{"name": "sprint-W{NN}"}`
- `backend` / `bug` / `feature` — task type
- `today` / `tomorrow` — day-level priority; `sprint` — generic "in a sprint" (all already exist)
- Apply via `POST /api/v1/tasks/{id}` with `{"labels": [...]}` (full replacement — include existing labels)

**2b. Linear — Mike's active issues (MCP)**

Use `mcp__linear__list_issues` with:
- `assignee: "me"`
- `limit: 100`

Then filter to issues where status is NOT "Done" and NOT "Cancelled".

**2c. Check existing sprint note AND extract user notes**
```bash
WEEK_LABEL="<computed above>"
NOTE="$HOME/zettelkasten/claude_code/rescue-serverless/sprints/${WEEK_LABEL}.md"
COMB_NOTE="$HOME/zettelkasten/comb-notes/weekly_staff/${WEEK_LABEL}.md"

# Read full note
cat "$NOTE" 2>/dev/null || echo "NO_EXISTING_NOTE"

# Extract user notes AND follow-up questions, mapped to their PUN-XXXX task.
# Only track PUN from task header lines (- [ ] **[PUN-XXXX]** or **[PUN-XXXX]**)
# to avoid false matches inside 🎓 tips that reference other PUN numbers.
python3 - <<'EOF'
import re
from pathlib import Path
import os, json

week = os.environ.get("WEEK_LABEL", "")
path = Path.home() / f"zettelkasten/comb-notes/weekly_staff/{week}.md"
if not path.exists():
    print("NO_USER_NOTES")
    import sys; sys.exit(0)

text = path.read_text()
# Only update current_pun when a line is a task header (starts with - [ ], - [x], or **[PUN-)
HEADER_RE = re.compile(r'(?:^-\s*\[[ xX]\].*?\*\*\[PUN-(\d+)\]|^\*\*\[PUN-(\d+)\])')
notes = {}   # pun -> list of > 👤 content strings (verbatim, multiline)
followups = {}  # pun -> > 💬❓ content string

current_pun = None
in_user_note = False
user_note_lines = []

lines = text.splitlines()
i = 0
while i < len(lines):
    line = lines[i]
    m = HEADER_RE.match(line.strip())
    if m:
        # Save any open user note
        if current_pun and user_note_lines:
            notes.setdefault(current_pun, []).append("\n".join(user_note_lines))
            user_note_lines = []
        in_user_note = False
        current_pun = f"PUN-{m.group(1) or m.group(2)}"
    
    stripped = line.strip()
    if current_pun:
        if stripped.startswith("> 👤") and stripped != "> 👤":
            # Start capturing user note (may span multiple lines)
            if user_note_lines:
                notes.setdefault(current_pun, []).append("\n".join(user_note_lines))
            user_note_lines = [stripped]
            in_user_note = True
        elif in_user_note and (stripped.startswith("> ") or stripped.startswith("{")):
            # Continuation of multiline user note (e.g. JSON block)
            user_note_lines.append(line.rstrip())
        else:
            if user_note_lines:
                notes.setdefault(current_pun, []).append("\n".join(user_note_lines))
                user_note_lines = []
            in_user_note = False
        
        if stripped.startswith("> 💬❓") and stripped != "> 💬❓":
            followups[current_pun] = stripped

    i += 1

if current_pun and user_note_lines:
    notes.setdefault(current_pun, []).append("\n".join(user_note_lines))

output = {}
for pun, note_list in notes.items():
    output[pun] = {"notes": note_list}
for pun, fup in followups.items():
    output.setdefault(pun, {})["followup"] = fup

if output:
    for pun, data in output.items():
        for note in data.get("notes", []):
            print(f"NOTE::{pun}::{note}")
        if "followup" in data:
            print(f"FOLLOWUP::{pun}::{data['followup']}")
else:
    print("NO_USER_NOTES")
EOF
```

## Step 3: Analyze codebase for ALL active tasks

Search the codebase for **every** In Progress and high-priority Todo task — not just In Progress.

```bash
cd /Users/mikeshevchuk/code/b2b/rescue-serverless
```

For **backend** tasks:
- `backend/src/lambdas/api/fast/routes/` — FastAPI endpoints
- `backend/src/_common_layer/python/models/` — Pydantic models (web_models.py, db_models.py, enums.py)
- `backend/src/_common_layer/python/services/` — business logic
- `backend/src/_common_layer/python/repositories/` — DynamoDB access
- `backend/src/workers/` — async Lambda workers
- `backend/infra/` — CDK infrastructure (CloudWatch alarms etc.)

For each task, find and note:
1. **Exact file:line** where the relevant code lives
2. **What already exists** — endpoint, model field, handler, etc.
3. **What is missing** — the specific gap (field not in model, condition not checked, handler case absent)
4. **Concrete next step** — the first line of code to write, not a generic "check X"
5. **Time estimate** — based on what you found (not guessed)

The `> 🎓` block in the note should read like a senior dev who already looked at the code and is telling you exactly where to go and what to change — not a list of things to check.

## Step 4: Build the sprint note

Create or **overwrite** TWO files:
1. `~/zettelkasten/claude_code/rescue-serverless/sprints/<WEEK_LABEL>.md` — full detailed note (YAML frontmatter, full codebase analysis, pro tips)
2. `~/zettelkasten/comb-notes/weekly_staff/<WEEK_LABEL>.md` — compact version (no YAML, hashtag header `#weekly #<WEEK_LABEL> #sprint #rescue-serverless #backend`, wikilinks, tables). Never delete existing files in that directory — only create/overwrite the current week's file.

**CRITICAL — task block format (follow this order exactly for every task):**

```
- [ ] **[PUN-XXXX](url)** Title — *Xh* · 🔥N · ⚡N
  > 💬 <one-line summary of current state from codebase — NOT a generic hint>
  > 👤 <user note VERBATIM — copy from extraction, never modify>
  > 🎓 <full analysis — see below>
  > 💬❓
```

**What goes in `> 🎓` (the analysis block):**
- If `> 💬❓` from previous run had content → start by addressing it directly
- If `> 👤` has content → acknowledge it (agree/update scores/explain)
- Then: concrete codebase findings — `file.py:LINE` → what exists → what's missing
- Then: the exact first step to start coding (not "check X", but "open file Y, add condition Z on line N")
- End with revised estimate if your analysis changed it
- Write in Ukrainian, practical tone, as if you already read the code

`> 💬❓` — always leave empty. This is where the user writes their response/question for next sprint run.

**Score changes**: only change 🔥N · ⚡N on the `- [ ]` header line if user's `> 👤` requests it. Never touch `> 👤` content.

Use this structure:

```markdown
---
title: Sprint <WEEK_LABEL>
date: <TODAY>
tags: [weekly, sprint, rescue-serverless, backend, #<WEEK_LABEL>]
week: "<WEEK_LABEL>"
sprint_dates: "<Mon> – <Sun>"
---
# Sprint <WEEK_LABEL> — Backend
> <dates> · Mike · rescue-serverless

## 📊 Sprint Health
> **X / Y tasks done** · Est. remaining: **Xh**
> Focus score: [🟢 On track / 🟡 At risk / 🔴 Behind]

---
## 🔥 Today (<WEEKDAY>, <DATE>)

Max 3 items. Pick by: urgency × complexity × blocking others.

- [ ] **Task** — _X–Yh_ — why today: <reason>
- [ ] ...

## ☀️ Tomorrow

- [ ] **Task** — _X–Yh_
- [ ] ...

---
## 🚧 In Progress

For each issue include:
- Linear link, priority badge, status
- **Codebase context:** which files are touched, what's done, what's left
- **Estimate:** Xh remaining
- **Blocker/risk:** if any

## 📋 Todo This Sprint

Group by: Urgent → High → Medium

For each task use this exact format:

```
#### [PUN-XXXX](linear_url) — Title
| | |
|--|--|
| ⏱ Оцінка | **Xh** |
| 🔥 Важливість | **X / 10** |
| ⚡ Терміновість | **X / 10** |
| 📌 Чому важливо | одне речення: що блокує або який impact на продукт/юзерів |
| ⏰ Дедлайн | конкретний день: «вівторок 14 квітня» і чому саме тоді |
```

Шкала важливості 🔥 (1–10):
- 10 = продакшн зламаний або блокує реліз
- 8–9 = Urgent від Greg/Chandon, клієнти чекають
- 6–7 = High — помітно впливає на UX або інші задачі залежать
- 4–5 = Medium — треба зробити але є час
- 1–3 = Nice to have, backlog

Шкала терміновості ⚡ (1–10):
- 10 = треба закрити сьогодні
- 8–9 = до кінця завтра
- 6–7 = до кінця тижня
- 4–5 = до кінця спринту
- 1–3 = наступний спринт або backlog

Обидва бали визначай незалежно. Задача може бути важливою (8) але не терміновою (3) — наприклад велика архітектурна фіча. Або не дуже важливою (4) але терміновою (8) — наприклад дрібний баг про який сьогодні пишуть клієнти.

## ✅ Done This Sprint

List completed issues (completedAt within this week or status=Done from recent activity).

## 📝 Todoist — rescue backend

List all tasks from the Back2Back Todoist project with status. Each task must be a clickable link: `[task title](https://todoist.com/app/task/{id})`. Show any description snippet if available.

Format as a table:
| [Task title](todoist_url) | 🔥 | ⚡ | Оцінка | Примітка |

---
## 🧠 Pro Tips & Sprint Notes

For each **In Progress** and **high-priority Todo** task, provide:

### PUN-XXXX — <Title>

**Codebase context:**
- Relevant files: `path/to/file.py:line`
- Current state: what exists
- Missing: what needs to be built

**Implementation approach:**
Step-by-step technical plan (3-5 steps)

**Estimate breakdown:**
- Analysis/setup: Xh
- Implementation: Xh
- Tests: Xh
- Total: **Xh**

**Risks / watch out for:**
- ...

**Similar patterns in codebase:**
- Link to existing code that solves a similar problem
```

## Step 5: Display summary in terminal

After writing the file, print a concise summary:

```
✅ Sprint note: ~/zettelkasten/claude_code/rescue-serverless/sprints/<WEEK_LABEL>.md

TODAY'S FOCUS:
  1. [PUN-XXXX] Title — Xh
  2. [PUN-XXXX] Title — Xh
  3. [PUN-XXXX] Title — Xh

SPRINT: X done / Y total · ~Xh remaining
```

## Rules

- **Only Mike's tasks** — filter by `assignee: "me"` in Linear, never show other people's tasks
- **Backend only** — skip pure frontend issues unless they have a BE component
- **Overwrite** the existing note if it exists — don't append, rewrite with fresh data
- **Project header** — the comb-notes compact file must always start with:
  ```
  #weekly #<WEEK_LABEL> #sprint #rescue-serverless #backend

  # Sprint <WEEK_LABEL> — Backend
  <dates> · [[rescue-serverless]]

  > Проект: **rescue-serverless** · Back2Back · бекенд (FastAPI, Lambda, DynamoDB)
  > Повна нота з аналізом коду та про-тіпсами: [[sprints/<WEEK_LABEL>]]
  ```
- **User `> 👤` notes are sacred** — extract from step 2c, re-inject VERBATIM. Never rewrite, paraphrase, or remove. Only non-empty notes are re-injected; new tasks get empty `> 👤` placeholder.
- **Score adjustments** — if user's `> 👤` requests a score change ("зміни терміновість на X"), apply it on the `- [ ]` header line. Never touch the `> 👤` text itself.
- **`> 🎓` response** — address user's `> 👤` observation + any `> 💬❓` follow-up from previous run. Include: what you agree/disagree with, codebase file:line evidence, revised estimate if changed.
- **`> 💬❓` follow-up marker** — always add empty `> 💬❓` after every `> 🎓`. If it has content in existing file → address it in `> 🎓`, then reset to empty. This is the user's channel to push back or ask follow-up questions.
- **PUN tracking in extraction** — only update `current_pun` when the line is a task header (`- [ ] **[PUN-XXXX]**` or `**[PUN-XXXX]**`). Never update `current_pun` from PUN references inside `> 🎓` tips.
- **Todoist sync** — match Todoist task titles to Linear issues where possible, mark as linked
- **Ukrainian mentor commentary** — for every task (In Progress and Todo), add a `> 🎓 **Ментор:**` blockquote in Ukrainian with: why this matters, common pitfalls, how to approach it, what to check first. Write as an experienced senior backend dev talking to a teammate — practical, direct, no fluff.
- **Hour estimates** must be grounded in codebase analysis — not guesses. If codebase shows the endpoint already exists and just needs a flag, say 1h. If it requires a new Lambda + DynamoDB model + tests, say 6h+
- **Today's focus** = max 3 tasks, prioritized by: (1) In Progress items, (2) Urgent blockers, (3) items that unblock others
- If existing sprint note has checked checkboxes `[x]`, preserve that progress — copy done items to ✅ Done section
