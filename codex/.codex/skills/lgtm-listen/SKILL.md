---
name: lgtm-listen
description: "LGTM live loop — listen to review-page comments (inbox.jsonl), answer into outbox.jsonl; the page updates via SSE without reload"
---

# LGTM listen — live comment→Codex loop

You are the Codex side of the LGTM live loop (design: `.lgtm/design.md` §3).
Mike writes comments under diff hunks in the browser; the lgtm server appends
them to `inbox.jsonl`; you answer into `outbox.jsonl`; the page shows your
answer via SSE without reload. Stay in this loop until Mike says stop.

## Setup

1. Resolve the review dir:
   - `$ARGUMENTS` is a path → use it.
   - `$ARGUMENTS` is a ref name → `<repo>/.lgtm/reviews/<ref with / → ->/`.
   - empty → the review dir with the newest `page.html` under `<repo>/.lgtm/reviews/`.
2. `DIR=<resolved>`; files: `$DIR/inbox.jsonl` (read), `$DIR/outbox.jsonl` (append),
   cursor `$DIR/.listen-cursor` (int = inbox lines already answered; missing → current
   line count, i.e. only NEW comments from now on; `0` would replay history).
3. Announce: dir, current inbox/outbox counts, LAN URL from `$DIR/server.pid`
   sibling output if the server is up (`lsof -iTCP:8642 -sTCP:LISTEN` to check).
   If the server is NOT running, tell Mike to run `jb2b review-serve` first.

## Loop (repeat until told to stop)

1. Wait for new inbox lines with a background waiter (re-invokes you on exit):

```bash
# run_in_background: true — exits the moment inbox grows past the cursor
CUR=$(cat "$DIR/.listen-cursor" 2>/dev/null || echo 0)
while [ "$(wc -l < "$DIR/inbox.jsonl" 2>/dev/null || echo 0)" -le "$CUR" ]; do sleep 2; done
echo "new comments: $(($(wc -l < "$DIR/inbox.jsonl") - CUR))"
```

2. When it fires, read the new lines (`tail -n +$((CUR+1)) inbox.jsonl`), and for EACH:
   - Parse `{id, text, file, line, hunk, finding_id}`.
   - **Read the actual code**: the file around `line` (±40 lines), the diff hunk in
     `$DIR/diff.txt`, and the finding in `$DIR/findings.json` if `finding_id` set.
     Verify claims against the codebase before answering (house rule) — grep callers,
     check enums/models exist. Never answer from the diff alone.
   - Answer in the language of the question (UA question → UA answer). Format:
     short, direct, Problem→Why→Fix style when applicable; plain words; severity
     score `🟠 NN/100` if you are asserting a new issue; include a `code` field
     with a concrete snippet when a fix is proposed.
   - Append ONE JSON line to `outbox.jsonl` via python3 (guarantees valid JSON —
     never hand-quote):

```bash
python3 - "$DIR/outbox.jsonl" <<'PY'
import json, sys, time
msg = {
  "id": f"a-{int(time.time()*1000)}",
  "ts": time.strftime("%Y-%m-%dT%H:%M:%S"),
  "who": "claude",
  "reply_to": "<inbox id>",
  "hunk": "<same hunk>", "file": "<same file>", "finding_id": "<same or empty>",
  "text": "<your answer>",
  "code": "<optional fix snippet or empty>",
}
with open(sys.argv[1], "a", encoding="utf-8") as fh:
    fh.write(json.dumps(msg, ensure_ascii=False) + "\n")
PY
```

3. Advance the cursor: `echo <new line count> > "$DIR/.listen-cursor"`.
4. In the terminal, print one compact line per answered comment:
   `↩ F2H1 devices.py:79 — answered (🟠 72/100)`.
5. Go back to step 1 (start the next background waiter).

## Rules

- If a comment asks to CHANGE code ("виправ", "зроби фікс") — make the edit in the
  repo working tree, mention the file:line in the answer, but NEVER commit/push
  from this loop.
- If a comment marks a finding wrong — verify; if Mike is right, say so plainly
  and update that finding's `status` to `"reviewed"` in `findings.json`.
- Thread replies stay local (`.lgtm/` is gitignored); nothing goes to GitHub
  from this loop — export is a separate explicit step.
- One answer per comment; if a question needs long research, send a short
  interim answer first ("копаю глибше, зараз повернусь"), then a follow-up line.
