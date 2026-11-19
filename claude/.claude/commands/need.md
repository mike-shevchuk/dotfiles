---
description: Кому ти потрібен зараз — порядок денний Mike за пріоритетом, з контекстом і варіантами відповіді: ① зроби зараз ② скоро ③ прохання ④ без вікна ⑤ не твоє
argument-hint: "[list]  (list = лише надрукувати, без вікна з питаннями)"
---
# /need — кому я потрібен, для чого, в якому порядку (Mike 19.11: «щоб need давали варіанти відповіді і контекст»)

## 1. Надрукувати порядок денний
Run exactly one command and print its stdout VERBATIM in a code block:
`LEAD_SESSION=$(tmux display -p '#S' 2>/dev/null) python3 ~/.claude/scripts/lead.py need`

Each ① item already carries «зробити / навіщо / розблокує / чекає», its context and the lettered answers. Under the block write at most 2 lines in Ukrainian: which item to take first and why (score, what it unblocks, whether the try lock is free).
`$ARGUMENTS` = `list` → stop here.

## 2. Спитати через вікно — `AskUserQuestion`, лише пункти ①
Data: `LEAD_SESSION=… python3 ~/.claude/scripts/lead.py need --json` → `items[]` with `sec == "now"`, already sorted by score. Never re-gather with tmux/gh; a missing fact belongs in `lead.py need_items`.
- One question per item, ≤4 per modal, highest score first. No ① items → say so and stop; do not ask about ②–⑤.
- `header` ≤12 chars (`2538 проба`, `2081 план`).
- `question` — 2–3 sentences in Ukrainian built from the item's `context`: what the feature is in product words (the `що доводить` / `суть` lines), the fact (gates, who stands, how long), what his answer decides. Every term gets a gloss right there. Domain terms stay English (org, enterprise, alert, release, try…).
- `options` = the item's `options` in the same order, the first marked `(Recommended)` only when it is the safe default (a ready try with the try lock free; never «план так»). `description` = the «→ …» consequence. Each option gets a `preview` of 6–10 lines: Що це · Зараз · Після цього варіанту · Ризик · Хто що робить далі; for a try the full command stands in the preview.
- `try_lock == true` → a try is running on dev: say it in the question and do not recommend «Запускаю пробу зараз».
- A plan item follows the rule «план так — ніколи наосліп»: read the card/plan yourself first (`context` has the path), put its gist into the question and previews, and keep the first option «Ще ні — покажи суть».

## 3. Після відповіді
- You are the lead window → close each answer as /mine-grill §5 does (send.sh to the waiting window, `plan-approve.sh` for «план так», clear the need-mike row).
- Any other window → do NOT message windows or write approvals. Print one line per answer: `🙋 LEAD: Mike — <пункт>: <відповідь>` so the lead relays it.
- A try Mike runs himself is not something you run: give the command, wait for his «апрув».

Then a 3-column summary: пункт → відповідь Mike → що далі і хто це робить.
