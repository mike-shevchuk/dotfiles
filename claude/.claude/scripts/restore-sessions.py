#!/usr/bin/env python3
"""After a reboot: bring back the Claude sessions that were alive, each in its own tmux window with --resume.

  restore-sessions.py [--hours 6] [--all] [--yes] [--dry]   (--all: b2b too, its sprint lead restores those itself)
  restore-sessions.py --selftest

Takes transcripts touched in the hours before the boot; skips a session that already runs.
"""
import argparse
import glob
import json
import os
import re
import shutil
import subprocess
import time

HOME = os.path.expanduser("~")


def tmux_session(cwd: str) -> str:
    """The tmux session a directory belongs to: esp-deck (+ its worktrees) → esp, dotfiles → dotfiles, else the project."""
    rel = cwd.replace(HOME, "").strip("/")
    if rel.startswith("code/esp-deck"):
        return "esp"
    if rel.startswith("dotfiles"):
        return "dotfiles"
    m = re.match(r"code/([^/]+)", rel)
    return m[1] if m else "restored"


def window_name(title: str, cwd: str) -> str:
    return re.sub(r"[.:]", " ", title or os.path.basename(cwd)).strip()[:28]


def saved_place(sid: str, cwd: str, title: str) -> tuple:
    """(tmux session, window): what agent-state.sh saved for this session, else guessed from its directory and title."""
    try:
        with open(f"{HOME}/.claude/window-names/{sid}") as f:
            t, _, w = f.read().strip().partition("|")
        if t and w:
            return t, w
    except OSError:
        pass
    return tmux_session(cwd), window_name(title, cwd)


def read_session(path: str) -> dict:
    cwd, title, lines = "", "", 0
    with open(path, errors="replace") as f:
        for line in f:
            lines += 1
            try:
                d = json.loads(line)
            except ValueError:
                continue
            cwd = d.get("cwd", cwd)
            if d.get("type") == "custom-title":
                title = d.get("customTitle") or title
            elif d.get("type") == "ai-title" and not title:
                title = d.get("aiTitle") or title
    return {"id": os.path.basename(path)[:-6], "cwd": cwd, "title": title, "lines": lines, "at": os.path.getmtime(path)}


def live_ids() -> set:
    ids = set(re.findall(r"--(?:resume|session-id)[ =]([0-9a-f-]{36})", subprocess.run(["ps", "-axo", "command"], capture_output=True, text=True).stdout))
    for f in glob.glob(f"{HOME}/.claude/sessions/*.json"):
        try:
            with open(f) as h:
                d = json.load(h)
            os.kill(d["pid"], 0)
            ids.add(d["sessionId"])
        except (OSError, ValueError, KeyError):
            pass
    return ids


def pick(sessions: list, live: set, since: float, now: float, everything: bool) -> list:
    out = []
    for s in sessions:
        if s["at"] < since or s["id"] in live or s["lines"] < 20 or not os.path.isdir(s["cwd"]):
            continue
        if now - s["at"] < 180:  # still being written: alive somewhere (a background job) even with no process found
            continue
        if not everything and "/code/b2b" in s["cwd"]:
            continue
        out.append(s)
    return sorted(out, key=lambda s: (tmux_session(s["cwd"]), -s["at"]))


def run(argv: list, **kw) -> subprocess.CompletedProcess:
    return subprocess.run(argv, capture_output=True, text=True, **kw)


def restore(s: dict) -> None:
    t, name = saved_place(s["id"], s["cwd"], s["title"])
    if run(["tmux", "has-session", "-t", f"={t}"]).returncode:
        run(["tmux", "new-session", "-d", "-s", t, "-c", s["cwd"]])
    cmd = f"claude --resume {s['id']}; exec zsh"
    print(f"━━━ tmux ━━━  tmux new-window -d -t {t} -n '{name}' -c {s['cwd']} '{cmd}'", flush=True)
    run(["tmux", "new-window", "-d", "-t", f"{t}:", "-n", name, "-c", s["cwd"], cmd])
    run(["tmux", "set-window-option", "-t", f"{t}:{name}", "automatic-rename", "off"])


def selftest() -> None:
    assert tmux_session(f"{HOME}/code/esp-deck-wifi") == "esp" and tmux_session(f"{HOME}/dotfiles/.claude/worktrees/lan") == "dotfiles"
    assert tmux_session(f"{HOME}/code/asja/kurs") == "asja" and tmux_session("/tmp/x") == "restored"
    assert window_name("Бриф flexbar.md для ESP", "/x") == "Бриф flexbar md для ESP" and window_name("", "/a/b") == "b"
    base = {"cwd": HOME, "title": "", "lines": 50, "at": 1000.0}
    ss = [dict(base, id="ok"), dict(base, id="live"), dict(base, id="old", at=1.0), dict(base, id="short", lines=3),
          dict(base, id="b2b", cwd=f"{HOME}/code/b2b"), dict(base, id="gone", cwd="/no/such/dir"), dict(base, id="fresh", at=4900.0)]
    assert [s["id"] for s in pick(ss, {"live"}, 500, 5000, False)] == ["ok"]
    assert saved_place("no-such-session", f"{HOME}/code/asja", "Назва") == ("asja", "Назва")
    print("restore-sessions ok")


def main() -> None:
    a = argparse.ArgumentParser()
    a.add_argument("--hours", type=float, default=6)
    a.add_argument("--all", action="store_true")
    a.add_argument("--yes", action="store_true")
    a.add_argument("--dry", action="store_true")
    a.add_argument("--selftest", action="store_true")
    o = a.parse_args()
    if o.selftest:
        return selftest()
    boot = int(re.search(r"sec = (\d+)", run(["sysctl", "-n", "kern.boottime"]).stdout)[1])
    now = time.time()
    paths = glob.glob(f"{HOME}/.claude/projects/*/*.jsonl")
    since = boot - o.hours * 3600
    found = pick([read_session(p) for p in paths if os.path.getmtime(p) >= since], live_ids(), since, now, o.all)
    if not found:
        print("→ nothing to restore")
        return
    rows = [f"{saved_place(s['id'], s['cwd'], s['title'])[0]:<10} {time.strftime('%H:%M', time.localtime(s['at']))}  {saved_place(s['id'], s['cwd'], s['title'])[1]}  [{s['id'][:8]}]" for s in found]
    if o.dry:
        print("\n".join(rows))
        return
    if not o.yes and shutil.which("gum"):
        got = subprocess.run(["gum", "choose", "--no-limit", "--selected=" + ",".join(rows), "--header", "Які сесії відновити?", *rows], stdout=subprocess.PIPE, text=True).stdout
        found = [s for s, r in zip(found, rows) if r in got.splitlines()]
    for s in found:
        restore(s)
        time.sleep(1)
    print(f"  OK ({len(found)} restored)")


if __name__ == "__main__":
    main()
