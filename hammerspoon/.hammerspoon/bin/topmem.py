"""Memory tree for the sysmonitor menu: groups (Claude, each app, system) → processes → children.

Footprint from `top` (counts compressed + swapped pages; ps RSS hides them — a claude session
read 168 MB in RSS while holding ~450 MB). A Claude session = one claude process whose parent is
not claude; everything under it (MCP servers, node, uv…) is summed into it and listed as its kids.
It is named after its tmux window (+ @agent_state); a prewarmed one is "bg-spare".
Prints JSON: {"groups":[{"name","desc","kb","cpu","n","items":[{"pid","label","kb","cpu","etime","kids":[…]}]}]}
"""
import json
import os
import re
import subprocess
from collections import defaultdict

DESC = {
    "Claude": "Claude Code: одна сесія = одне tmux-вікно; MCP/node/uv під нею — її діти",
    "Thorium Browser": "браузер: Renderer = вкладка або розширення, GPU/Network — служби",
    "Brave Browser": "браузер: Renderer = вкладка або розширення, GPU/Network — служби",
    "Google Chrome": "браузер: Renderer = вкладка або розширення",
    "Google Chrome for Testing": "браузер Playwright (MCP/тести) — закривається з сесією",
    "WindowServer": "macOS малює екран — не чіпати",
    "kernel_task": "ядро macOS — не чіпати",
    "Hammerspoon": "меню, deck, гарячі клавіші — не вбивати",
    "Docker": "VM Docker",
}
BROWSERS = ("Thorium Browser", "Brave Browser", "Google Chrome", "Microsoft Edge")
UNIT = {"B": 1 / 1024, "K": 1, "M": 1024, "G": 1024 * 1024}


def sh(*a):
    try:
        return subprocess.run(a, capture_output=True, text=True, timeout=20).stdout
    except Exception:
        return ""


mem = {}
for line in sh("top", "-l", "1", "-stats", "pid,mem").splitlines():
    m = re.match(r"\s*(\d+)\s+([\d.]+)([BKMG])", line)
    if m:
        mem[int(m[1])] = float(m[2]) * UNIT[m[3]]
procs, kids = {}, defaultdict(list)
for line in sh("ps", "-axo", "pid=,ppid=,%cpu=,etime=,args=").splitlines():
    p = line.split(None, 4)
    if len(p) == 5:
        pid, ppid = int(p[0]), int(p[1])
        procs[pid] = {"ppid": ppid, "cpu": float(p[2]), "etime": p[3], "args": p[4]}
        kids[ppid].append(pid)
panes = {}
for line in sh("tmux", "list-panes", "-a", "-F", "#{pane_pid}\t#S:#I #W\t#{@agent_state}").splitlines():
    a = line.split("\t")
    if len(a) == 3:
        panes[int(a[0])] = a[1] + (f" [{a[2]}]" if a[2] else "")


def exe(args):
    return os.path.basename(args.split()[0]) if args else "?"


def is_claude(pid):
    a = procs.get(pid, {}).get("args", "")
    b = exe(a)
    return b == "claude" or re.fullmatch(r"2\.1\.\d+", b) or "/claude/versions/" in a.split()[0]


def app_of(args):
    m = re.search(r"/([^/]+)\.app/", args)
    return m[1] if m else exe(args)


def subtree(pid):
    out = [pid]
    for k in kids[pid]:
        out += subtree(k)
    return out


def item(pid, label, members):
    return {"pid": pid, "label": label, "kb": sum(mem.get(x, 0) for x in members),
            "cpu": sum(procs[x]["cpu"] for x in members if x in procs), "etime": procs[pid]["etime"]}


claimed, claude_items = set(), []
for pid in procs:
    parent = procs.get(procs[pid]["ppid"], {}).get("args", "")
    if not is_claude(pid) or "bg-pty-host" in procs[pid]["args"] or (is_claude(procs[pid]["ppid"]) and "bg-pty-host" not in parent):
        continue
    t = subtree(pid)
    claimed.update(t)
    if "bg-spare" in procs[pid]["args"]:
        label = "bg-spare (запасний, стартує наперед)"
    else:
        p, label = pid, None
        while p > 1 and label is None:
            label = panes.get(p)
            p = procs.get(p, {}).get("ppid", 1)
        sid = re.search(r"--session-id (\w{8})", procs[pid]["args"])
        label = label or ("фонова сесія (claude --bg) " + (sid[1] if sid else "") if "bg-pty-host" in parent
                          else "поза tmux: " + " ".join(procs[pid]["args"].split()[1:4])[:40])
    it = item(pid, label, t)
    by = defaultdict(lambda: [0, 0.0])
    for x in t[1:]:
        a = procs[x]["args"]
        if "shell-snapshots" in a or exe(a) in ("zsh", "bash", "sh"):
            continue
        name = next((n for k, n in (("@playwright/mcp", "MCP playwright"), ("aws-serverless", "MCP aws-serverless"),
                                    ("pyright", "LSP pyright"), ("context7", "MCP context7")) if k in a), app_of(a))
        by[name][0] += 1
        by[name][1] += mem.get(x, 0)
    it["kids"] = [{"name": n, "n": c, "kb": kb} for n, (c, kb) in sorted(by.items(), key=lambda v: -v[1][1]) if kb >= 5 * 1024]
    claude_items.append(it)

INTERP = re.compile(r"(python[\d.]*|Python|node|bun|ruby|perl|java|uvicorn)$")


def script_label(pid, args):
    """python helper/x.py serve 8893 → "x.py serve 8893 · esp-deck" (script + args + the dir it runs in)."""
    a = args.split()
    rest = [x for x in a[1:] if not x.startswith("-")][:3]
    if "-m" in a[1:]:
        rest = a[a.index("-m") + 1:a.index("-m") + 4]
    script = " ".join([os.path.basename(rest[0])] + rest[1:]) if rest else exe(args)
    cwd = sh("lsof", "-a", "-p", str(pid), "-d", "cwd", "-Fn")
    m = re.search(r"^n(.+)$", cwd, re.M)
    return f"{script} · {os.path.basename(m[1])}" if m else script


UTIL = {"network": "мережа (усі запити браузера)", "storage": "сховище (cookies, IndexedDB)",
        "audio": "аудіо", "video_capture": "камера / захоплення відео", "data_decoder": "розбір JSON/картинок"}


def chromium_label(a):
    """Chromium helpers: the flags say what a process is (tab names are only in the browser's ⇧Esc task manager)."""
    t = re.search(r"--type=([\w-]+)", a)
    if not t:
        return "головний процес (вікна, історія, вкладки)" if "Helper" not in a else None
    if t[1] == "renderer":
        cid = re.search(r"--renderer-client-id=(\d+)", a)
        return ("розширення" if "--extension-process" in a else "вкладка або iframe") + (f" #{cid[1]}" if cid else "")
    if t[1] == "gpu-process":
        return "GPU (малює сторінки)"
    if t[1] == "utility":
        u = re.search(r"--utility-sub-type=(\w+)", a)
        return "служба: " + UTIL.get(u[1] if u else "", u[1] if u else "?")
    return t[1]


groups = defaultdict(list)
for pid, p in procs.items():
    if pid in claimed or mem.get(pid, 0) < 1024:
        continue
    a = p["args"]
    if INTERP.search(exe(a)) and ".app/" not in a:
        grp = "Python" if "ython" in exe(a) or "uvicorn" in a else exe(a)
        label = script_label(pid, a) + (" · сирота (батько помер)" if p["ppid"] == 1 else "")
    elif ".app/" in a:
        grp, label = app_of(a), chromium_label(a) or re.sub(r"^.*/", "", a.split(" --")[0])[:40]
    else:
        grp, label = exe(a), exe(a)
    groups[grp].append(item(pid, label, [pid]))
DESC["Python"] = "скрипти: файл + аргументи · тека, де запущено; «сирота» = його запускач уже завершився"
groups["Claude"] = claude_items
out = []
for name, items in groups.items():
    items.sort(key=lambda i: -i["kb"])
    out.append({"name": name, "desc": DESC.get(name, ""), "taskman": name in BROWSERS, "n": len(items), "kb": sum(i["kb"] for i in items),
                "cpu": sum(i["cpu"] for i in items), "items": items[:40]})
out.sort(key=lambda g: -g["kb"])
print(json.dumps({"groups": out[:10]}, ensure_ascii=False))
