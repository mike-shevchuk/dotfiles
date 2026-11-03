---
description: "Нагадай, над чим ми з teammate працювали" — бриф одного або всіх вікон W41: задача, що зроблено, стан, що від Mike, наступний крок
argument-hint: "<window N | all | high>"
---

# /brief — refresh Mike's memory about a teammate's work

Chat: Ukrainian, plain words. Token-cheap: the teammate (who already has the context) writes the brief to a file; you only relay and print it.

## Steps
1. Windows: `$ARGUMENTS` = one tmux window number of session `W41`, `all`, or `high` (windows whose name contains 🔴).
   Never kill or renumber windows (`renumber-windows` must stay off).
2. If `~/.claude/fleet-board/w41/briefs/<N>.md` exists and is newer than the window's last `🙋 LEAD` line → print it as is (0 new work).
3. Otherwise send to each window (tmux send-keys -l, then Enter; verify @agent_state=working):
   `LEAD HH:MM — Mike просить бриф. Запиши ~/.claude/fleet-board/w41/briefs/<N>.md за шаблоном нижче (≤40 рядків, прості слова, факти з git/PR/Linear, без вигадок) і відпиши «🙋 LEAD: brief <N>».`
   Template (the teammate fills it):
   ```
   # W41:<N> · <тікет PUN-…> · <назва простими словами>
   ## Що це і навіщо   (2–3 рядки: проблема, приклад)
   ## Що зроблено      (PR #, гілки, коміти, тести, CR/SMP/JT, preflight — з датами)
   ## Де ми зараз      (одним рядком + прогрес-бар)
   ## Що потрібно від Mike   (питання / дія — нумеровано, з варіантами і «раджу»)
   ## Наступний крок   (що зробить teammate, коли Mike відповість)
   ## Посилання        (PR, Linear, сторінки hub на поточному LAN IP, проба jb2b …)
   ```
4. Wait with one background until-loop for the `🙋 LEAD: brief <N>` line(s) (max 15 min), then print each file inside its own box frame,
   and end with ONE framed box «Mike, одним рядком» that merges every «Що потрібно від Mike» item, each line starting with `W41:<N>`.
