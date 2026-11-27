---
description: "Тогл монітора deputy — 🫡 W<N>:13 кожні 10 хв перевіряє, чи все працює (вікна живі, модалі, помилки, простій «на ліді», deploy, lock); стан у статуслайні"
argument-hint: "[on [3h|90m]|off|status]  (on без тривалості = 3 год; on 5h = продовжити)"
---
# /deputy-monitor — deputy стежить, чи все працює (Mike 26.11)

Mike 26.11: «deputy включимо йому monitor, щоб він передивлявся, чи все працює… це треба зробити командою on off і показувати десь у статуслайні».
Не плутати з `/monitor-tiki`: той — cron ЛІДА, який пише звіт Mike. Цей — health-check у вікні deputy, Mike не пише, лише 🙋 LEAD у своєму вікні + статуслайн.

Сесія = `tmux display -p '#S'` (W47), дошка `B=~/.claude/fleet-board/<сесія lc>/`, deputy = вікно `<S>:13`, місія `missions/<сесія lc>-deputy-monitor.md`
(нема для нового тижня → `sed 's/W47/W<N>/g; s/w47/w<N>/g' missions/w47-deputy-monitor.md`).

## Аргумент `$ARGUMENTS`
- `on [тривалість]` → **за замовчуванням 3 години** (Mike 26.11: «по дефолту на 3 години, хіба я збільшу»); `on 5h` / `on 90m` — інша тривалість. Пиши `$B/deputy-monitor.on` одним рядком `<start HH:MM> <until HH:MM>` (until = зараз + тривалість, `date -v+3H +%H:%M`).
  Монітор уже йде (`.last` свіжіший за 25 хв, `/loop` живий у pane) → лише онови `until` у файлі і `send.sh <S>:13 "LEAD: monitor до <until>"`; другий `/loop` НЕ запускати.
  Не йде → `send.sh <S>:13 "LEAD: monitor ON до <until> — /loop 10m Read missions/<lc>-deputy-monitor.md and do one tick. Перший тік одразу."`; через ~30 с `tmux capture-pane -p -t <S>:13 | tail -5` — тік пішов.
- `off` → `rm -f $B/deputy-monitor.on`; `send.sh <S>:13 "LEAD: monitor OFF — зупини /loop (ScheduleWakeup stop:true або CronDelete свого job), допиши в progress «monitor off HH:MM»."`; перевір pane.
- `status` / порожньо → чи є `$B/deputy-monitor.on` (з якого часу) + `cat $B/deputy-monitor.last` + `tail -3 $B/progress/13.md`.
Відповідь: одна-дві строки + що зараз у статуслайні.

## Статуслайн (вікно ліда, рядок 1)
`~/.claude/statusline.sh` блок «deputy-monitor»: є `.on` → `🫡 mon <last-tick HH:MM> ✅|🔴N 🟡N · 🙋N 🧭N 💤N [⇉] · до <until>`; until минув → `🫡 mon off`; останній тік старший за 25 хв → `🫡 mon ⚠ мовчить з HH:MM`. Джерело — `$B/deputy-monitor.last`, його пише deputy кожен тік (крок 5 місії).
