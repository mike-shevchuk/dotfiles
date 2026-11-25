---
description: Після /handoff + /clear — підхопити роботу ліда з останнього handoff-розділу LEAD-HANDOFF.md (без пояснень словами)
argument-hint: "[питання/вказівка до ліда, необов'язково]"
allowed-tools: Bash(python3:*), Bash(grep:*), Bash(tail:*), Bash(awk:*), Bash(cut:*), Bash(~/.claude/fleet-board/bin/fleet-busy.sh:*)
---
Ти — лід W<N> (вікно W<N>:1). Mike щойно зробив `/handoff` і `/clear`. Продовжуй з місця, де зупинився попередній лід — нічого не перепитуй про контекст.

## Останній handoff
!`n=$(python3 -c "import datetime as d;t=d.date.today();j=d.date(t.year,1,1);m=j+d.timedelta((7-j.weekday())%7);print((t-m).days//7+1)"); f="$HOME/.claude/fleet-board/w$n/LEAD-HANDOFF.md"; echo "N=$n · $f"; s=$(grep -n "^## .*handoff" "$f" | tail -1 | cut -d: -f1); tail -n +"$s" "$f" | awk 'NR>1 && /^## / && !/handoff/{exit} 1'`

## Живий стан вікон зараз
!`n=$(python3 -c "import datetime as d;t=d.date.today();j=d.date(t.year,1,1);m=j+d.timedelta((7-j.weekday())%7);print((t-m).days//7+1)"); ~/.claude/fleet-board/bin/fleet-busy.sh "W$n" 2>&1 | tail -40; echo "--- need-mike (tail) ---"; tail -15 "$HOME/.claude/fleet-board/w$n/need-mike.tsv" 2>/dev/null`

## Що зробити
1. Прочитай файли з рядка «Читати:» handoff-розділу (якщо є) — мовчки, без переказу.
2. Порівняй handoff із живим станом: що змінилось після handoff (вікно закрилось, PR змерджено, новий «Чекаю на»).
3. Відповідь — у форматі звичайного статусу ліда (A1): спершу 🧭 lead lane, потім вікна (бал · PUN · #PR · опис · крок), блокери Mike з контекстом, 🧪 проби окремим абзацом, прогресбари + ETA, футер.
4. Далі працюй як лід — не чекай, поки Mike пояснить, що робили.
5. Якщо Mike дописав текст після `/pickup` — це його питання/вказівка: відповідай на нього ПЕРШИМ, потім статус.
