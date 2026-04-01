Manually trigger a scheduled task to run immediately.

Usage: /trigger <task>

Available tasks:
- `standup` — Standup Prep (Linear + Slack + Git summary)
- `digest` — Daily Tech Digest & English
- `reddit` — Reddit App Setup Reminder
- `all` — Run all three

## Instructions

Use the RemoteTrigger tool with action "run" for the requested task(s):

### standup
RemoteTrigger action=run trigger_id=trig_01UhvaiZykGoWfvpyGqxGoXD

### digest
RemoteTrigger action=run trigger_id=trig_01S4nP8ArmuP7BQszCCH5aXs

### reddit
RemoteTrigger action=run trigger_id=trig_01KST4xUjpz8nzWEaXXNRb2G

### all
Run all three triggers above in parallel.

After triggering, print which task(s) were launched and remind to check Telegram/Slack for results.

If no argument provided, show the list of available tasks.
