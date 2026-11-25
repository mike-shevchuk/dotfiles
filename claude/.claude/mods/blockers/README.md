# blockers

A side pane (like `/diff`) that shows what waits on Mike, in detail.

- `/blockers` opens the pane and refreshes it; it also refreshes itself every minute.
- In the fleet lead (tmux window `W<N>:1`, or a non-`W<N>` session) it lists **every teammate**: window number, task, state, progress bar + ETA, what the window waits on, and every question for Mike (from `w<N>/briefs/<idx>.md` and `w<N>/need-mike.tsv`), plus blockers tied to no window.
- In a teammate window (`W<N>:<idx>`) it shows **only that window**.

Data comes from `~/.claude/scripts/lead.py blockers [idx] --json` (the same source as `jb2b lead footer`).
