---
description: Handoff перед /clear — дописати розділ у LEAD-HANDOFF.md поточного тижня (лід W<N>)
---
Ти — лід W<N> (N = поточний тиждень). Зроби handoff для нової сесії ліда, яку підхопить хук `handoff-inject.sh` після `/clear`.

1. Визнач N (W1 = тиждень першого понеділка січня):
   `python3 -c "import datetime as d;t=d.date.today();j=d.date(t.year,1,1);m=j+d.timedelta((7-j.weekday())%7);print((t-m).days//7+1)"`
2. Зніми стан:
   - `~/.claude/fleet-board/bin/fleet-busy.sh W<N>`
   - `tail -40 ~/.claude/fleet-board/w<N>/need-mike.tsv`
   - `tail -15 ~/.claude/fleet-board/w<N>/grill-log.md` (якщо файл є)
   - рядки «Чекаю на» з `~/.claude/fleet-board/w<N>/progress/*.md`
3. Дописати в `~/.claude/fleet-board/w<N>/LEAD-HANDOFF.md` розділ, заголовок ТОЧНО такого вигляду (хук шукає слово `handoff`):
   `## <DD.MM HH:MM> — handoff перед /clear (лід W<N>:1)`
   Зміст: вікна (стан · крок · «Чекаю на») · відкриті рішення Mike · що чекає на Mike · уроки дня. Формат як попередні розділи файлу. Лише дописати, нічого не видаляти.
4. Остання відповідь — один рядок: `готово — тепер /clear`. Сам `/clear` не виконувати.
