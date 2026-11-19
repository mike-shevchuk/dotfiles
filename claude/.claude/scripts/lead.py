#!/usr/bin/env python3
"""lead.py — the sprint lead console (session = newest fleet-board w<N>, or LEAD_SESSION): gathers fleet state in ONE call so a slash command costs one tool call.

  lead.py mine|devnow|fleet|idle|stuck|tokens|trylog [name]|ask|board
Sources: tmux panes, ~/.claude/fleet-board/<week>/{progress,briefs,need-mike.tsv}, ~/.claude/sessions,
/tmp/try-logs, gh (deploy runs, PRs), aws (engine target). Read-only except `ask` (tmux send-keys).
"""
import datetime as dt
import glob
import json
import os
import re
import subprocess
import sys
import time

def _tmux_session():
    """the tmux session this command runs in ("esp", "W44"): /mine-grill in the esp lead sees esp, not the newest sprint"""
    if not os.environ.get("TMUX"):
        return ""
    try:
        return subprocess.run(["tmux", "display", "-p", "#S"], capture_output=True, text=True, timeout=5).stdout.strip()
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return ""


SESSION = os.environ.get("LEAD_SESSION") or _tmux_session() or "W" + str(max((int(m.group(1)) for d in os.listdir(os.path.expanduser("~/.claude/fleet-board")) if (m := re.fullmatch(r"w(\d+)", d))), default=41))  # newest sprint board (was hardcoded W41)
FB = os.path.expanduser("~/.claude/fleet-board")
WK = f"{FB}/{SESSION.lower()}"
REPO = "back2back-team/rescue-serverless"
DEPLOY_WF = "165841775"
SKIP = {"1"}  # the lead; Mike console / tiki board are skipped by NAME (18.11: after a renumber index 2 was a real teammate)
SKIP_NAME = re.compile(r"(⌨️\s*mike|🗂\s*tiki|fleet-live|^mike$)", re.I)
ENGINES = {"ov25px5uvj": "DEV", "lo2z395bb1": "STAGING", "workflows-stage": "STAGING (CDK default — every rescue deploy resets to it; DEV again: cd ~/code/b2b/workflow-engine && just wf-engine-switch-dev)"}
NEEDS_INPUT = re.compile(r"Do you want to|❯ 1\. Yes|Allow (once|always)|\(y/N\)|\[Y/n\]|⏎ (далі|прибрати|продовжити)")
ACK = re.compile(r"🙋 LEAD: (brief|mine) \d+")  # file-written acks — the content lives in the brief
BAR = re.compile(r"[\[▕]?[█▓▒░]{5,}[\]▏]?\s*\d+%|\d+/\d+\s*[█▓░]+")


def sh(*cmd, timeout=20):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout).stdout
    except (subprocess.TimeoutExpired, FileNotFoundError) as e:
        return f"__ERR {e}"


def age(path):
    if not os.path.exists(path):
        return None
    m = int((time.time() - os.path.getmtime(path)) / 60)
    return f"{m}хв" if m < 60 else f"{m // 60}г{m % 60:02d}"


def windows():
    out = sh("tmux", "list-windows", "-t", SESSION, "-F", "#I\t#W\t#{@agent_state}\t#{pane_id}")
    for line in out.splitlines():
        i, name, state, pane = (line.split("\t") + ["", "", "", ""])[:4]
        name = name.split("│", 1)[-1]  # window-state.py prefixes «<icons>│»: strip it, so names match everywhere (board, timeline, footer)
        if i in SKIP or SKIP_NAME.search(name) or re.match(r"(scratch|w\d+-\d+-|pf\d+$)", name):  # helper panes of a teammate (scratch-…, w42-4-pre1937)
            continue
        yield {"i": i, "name": name, "state": state or "?", "pane": pane}


def tail(w, n=25):
    return [x for x in sh("tmux", "capture-pane", "-p", "-J", "-t", f"{SESSION}:{w['i']}", "-S", f"-{n}").splitlines() if x.strip()]


def status_line(w):
    p = f"{WK}/progress/{w['i']}.md"
    if not os.path.exists(p):
        return "—", None
    lines = open(p, encoding="utf-8", errors="replace").read().splitlines()
    st = next((x for x in reversed(lines) if x.startswith("STATUS:")), lines[-1] if lines else "—")
    return st.removeprefix("STATUS:").strip(), age(p)


def brief(w):
    """brief file → {title, now, mike[], next} (empty dict if none)."""
    p = f"{WK}/briefs/{w['i']}.md"
    if not os.path.exists(p):
        return {}
    sec, out = None, {"mike": [], "now": "", "next": "", "done": [], "what": [], "age": age(p)}
    for line in open(p, encoding="utf-8", errors="replace").read().splitlines():
        if line.startswith("# "):
            out["title"] = line[2:].strip()
        elif line.startswith("## "):
            sec = line[3:].split("(")[0].strip()
        elif line.strip() and sec:
            s = line.strip()
            if sec.startswith("Що це"):
                out["what"].append(s.lstrip("- "))
            elif sec.startswith("Де ми"):
                out["now"] = (out["now"] + " " + s).strip()
            elif sec.startswith("Що потрібно") and re.match(r"^(\d+\.|\*\*\(|- )", s):
                out["mike"].append(s)
            elif sec.startswith("Наступний") and not out["next"]:
                out["next"] = s.lstrip("- ")
            elif sec.startswith("Що зроблено") and s.startswith("- "):
                out["done"].append(s[2:])
    return out


def needs_input(w):
    t = tail(w, 12)
    hit = next((x.strip() for x in t if NEEDS_INPUT.search(x)), None)
    return hit


def box(title, rows):
    print(f"┌─ {title}")
    for r in rows or ["(нічого)"]:
        print(f"│ {r}")
    print("└" + "─" * 60)


def bar_of(text):
    m = BAR.search(text or "")
    return m.group(0) if m else ""


# ── commands ──────────────────────────────────────────────────────────────

def unanswered(w):
    """last «🙋 LEAD» report that came after the lead's last «❯ LEAD HH:MM» message, else None."""
    t = sh("tmux", "capture-pane", "-p", "-J", "-t", f"{SESSION}:{w['i']}", "-S", "-400").splitlines()
    rep = max((k for k, x in enumerate(t) if "🙋 LEAD" in x and not x.lstrip().startswith("❯") and not ACK.search(x)), default=-1)
    ask = max((k for k, x in enumerate(t) if x.lstrip().startswith(("❯ LEAD", "❯ 🧭 LEAD"))), default=-1)  # send.sh relays start with «🧭 LEAD» (11.11)
    return t[rep].strip().lstrip("⏺ ") if rep > ask else None


def cmd_stuck():
    rows = []
    for w in windows():
        hit = needs_input(w)
        st, a = status_line(w)
        rep = unanswered(w)
        if hit:
            rows.append(f"{SESSION}:{w['i']} 🙋 чекає ТВОЄЇ дії у вікні: «{hit[:90]}»")
        if rep:
            rows.append(f"{SESSION}:{w['i']} 📨 звіт без відповіді ліда: {rep[:120]}")
        if w["state"] == "working" and a and "г" in a:
            rows.append(f"{SESSION}:{w['i']} 🔇 працює, але progress не оновлювався {a} · {st[:70]}")
    box("🧯 /stuck — дозвіл/пауза у вікні · звіт без відповіді · мовчить >1 год", rows)


PRIO_RANK = {"P0": 0, "P1": 1, "P2": 2, "P3": 3, "⏸": 4, "✗": 5}


def prio_rank(label):
    """Mike 22.10 scores tickets 0–100 (higher = first); old P0–P3 labels still sort, after any score."""
    return -int(label) if label and label.isdigit() else PRIO_RANK.get(label, 9)


def prio_map():
    """PUN-id → short priority from <board>/priorities.tsv (last row per id wins; Mike sets it via sprint-prio / sprint-board)."""
    out, p = {}, f"{WK}/priorities.tsv"
    if os.path.exists(p):
        for ln in open(p, encoding="utf-8").read().splitlines():
            f = ln.split("\t")
            if len(f) > 1 and f[1].split():
                out[f[0]] = f[1].split()[0]
    return out


def window_prio(w, b, pm):
    """(rank, label) of a window = its most important ticket; tickets come from the brief + window name."""
    text = " ".join([w["name"], b.get("title", ""), b.get("now", "")] + b.get("what", []) + b.get("mike", []))
    ids = list(dict.fromkeys(re.findall(r"PUN-\d+", text)))
    tagged = sorted(((prio_rank(pm.get(i)), f"{pm.get(i, '—')} {i}") for i in ids), key=lambda x: x[0])
    rank = tagged[0][0] if tagged else 9
    return rank, " · ".join(t for _, t in tagged[:3]) or "без пріоритету"


def cmd_mine_full():
    """per window that waits on Mike: the problem/feature, where we are, what is done — then the questions."""
    print(f"🖥 зручніше читати по фічах (доріжка етапів + «від тебе»): {HUB}/rescue-serverless/fleet/{SESSION.lower()}-status.html#mine  · оновити: jb2b status-html")
    pm = prio_map()
    if pm:  # Mike 21.10: show the sprint priorities on top so a wrong order is visible at once
        by = {}
        for i, pr in pm.items():
            by.setdefault(pr, []).append(i)
        print("Пріоритети спринту (priorities.tsv): " + "  │  ".join(f"{k} {' '.join(by[k])}" for k in sorted(by, key=prio_rank)))
    items = []
    for w in windows():
        b, hit = brief(w), needs_input(w)
        if not (b.get("mike") or hit):
            continue
        rank, plabel = window_prio(w, b, pm)
        rows = ["ПРОБЛЕМА / ФІЧА:"] + [f"  {x[:150]}" for x in b.get("what", [])]
        if b.get("done"):
            rows += ["ЗРОБЛЕНО:"] + [f"  ✅ {d[:140]}" for d in b["done"][:4]]
        rows.append(f"ЗАРАЗ: {b.get('now', '—')[:150]}")
        rows += ["ПИТАННЯ ДО ТЕБЕ:"] + [f"  {m[:150]}" for m in b.get("mike", [])]
        if hit:
            rows.append(f"  ⌨ дія у вікні: «{hit[:90]}»")
        title = re.sub(r"^W\d+:\d+\s*·\s*", "", b.get("title", w["name"]))
        items.append((rank, int(w["i"]), f"[{plabel}] {SESSION}:{w['i']} · {title[:80]}   [бриф {b.get('age')}]", rows))
    for _, _, head, rows in sorted(items, key=lambda x: (x[0], x[1])):  # most important first (P0 → ⏸), then window number
        box(head, rows)
    print("Брифи старші за останнє рішення можуть містити вже відповідені питання → оновити: jb2b lead mine ask")


def cmd_mine(arg=""):
    if arg == "ask":
        return cmd_ask()
    if arg == "full":
        return cmd_mine_full()
    rows = []
    for w in windows():
        hit = needs_input(w)
        if hit:
            rows.append(f"{SESSION}:{w['i']} ⌨ дія у вікні (tmux {SESSION}:{w['i']}): «{hit[:80]}»")
        b = brief(w)
        for m in b.get("mike", []):
            rows.append(f"{SESSION}:{w['i']} {m[:150]}  [бриф {b.get('age')}]")
    nm = f"{WK}/need-mike.tsv"
    if os.path.exists(nm):
        rows += [f"{x.split(chr(9))[0]} {x.split(chr(9), 1)[-1][:140]} [need-mike.tsv]" for x in open(nm).read().splitlines() if x.strip()]
    # DEMO: agent preflight passed, Mike's own run missing
    prs = json.loads(sh("gh", "pr", "list", "-R", REPO, "--author", "@me", "--state", "open", "--json", "number,title", "-L", "50") or "[]")
    for pr in prs:
        n = pr["number"]
        res = os.path.expanduser(f"~/.claude/demo-results/pr-{n}.json")
        if os.path.exists(res) and not os.path.exists(res.replace(".json", ".mike.json")):
            rows.append(f"PR #{n} 🧪 твоя проба не пройдена (preflight агента є) · {pr['title'][:70]}")
    box("🙋 /mine — що чекає ТЕБЕ (оновити: jb2b lead ask)", rows)


def cmd_ask():
    hhmm = dt.datetime.now().strftime("%H:%M")
    sent = []
    for w in windows():
        if w["name"].startswith(("⏸", "🫡")):
            continue
        msg = (f"LEAD {hhmm} — Mike питає: чи ти десь чекаєш на Mike (рішення, проба, мердж, дозвіл)? "
               f"Онови розділ «Що потрібно від Mike» у {WK}/briefs/{w['i']}.md (повний бриф, якщо файлу нема; «нічого», якщо не блокує) "
               f"і відпиши «🙋 LEAD: mine {w['i']}».")
        sh("tmux", "send-keys", "-t", f"{SESSION}:{w['i']}", "-l", msg)
        time.sleep(0.5)
        sh("tmux", "send-keys", "-t", f"{SESSION}:{w['i']}", "Enter")
        sent.append(w["i"])
    print(f"→ спитав вікна: {' '.join(sent)} · через ~5 хв: jb2b lead mine", file=sys.stderr)


def cmd_fleet():
    for w in windows():
        st, a = status_line(w)
        b = brief(w)
        icon = "🟢" if w["state"] == "working" else ("⏸" if w["name"].startswith("⏸") else "⚪")
        hit = needs_input(w)
        rows = [f"що:     {b.get('title', w['name'])[:110]}",
                f"зараз:  {st[:130]}  ({a or 'немає progress'} тому)"]
        if bar_of(b.get("now")) or bar_of(st):
            rows.append(f"прогрес: {bar_of(st) or bar_of(b.get('now'))}")
        for d in b.get("done", [])[:3]:
            rows.append(f"✅ {d[:120]}")
        if b.get("next"):
            rows.append(f"⏭ {b['next'][:130]}")
        if hit:
            rows.append(f"🙋 ЧЕКАЄ ТЕБЕ У ВІКНІ: {hit[:90]}")
        box(f"{icon} {SESSION}:{w['i']} {w['name']}", rows)
    print("ETA: лише де teammate сам його записав у STATUS; решта — без підстав (не вигадую).")


def cmd_idle():
    rows = []
    free = re.compile(r"100%|наступну задачу|наступний запит|вільн|закрит|готові|done|MERGED", re.I)
    for w in windows():
        if w["state"] == "working":
            continue
        st, a = status_line(w)
        b = brief(w)
        text = f"{st} {b.get('now', '')}"
        if w["name"].startswith("⏸"):
            rows.append(f"{SESSION}:{w['i']} ⏸ пауза · {w['name']}")
        elif free.search(text):
            rows.append(f"{SESSION}:{w['i']} 💤 ВІЛЬНЕ — {st[:90]} → закрити / дати задачу")
        else:
            why = b.get("mike", [st])[0] if b.get("mike") else st
            rows.append(f"{SESSION}:{w['i']} ⏳ чекає: {why[:110]} ({a})")
    box("💤 /idle — хто не працює і чому", rows)


def cmd_devnow():
    rows = []
    runs = json.loads(sh("gh", "run", "list", "-R", REPO, "--workflow", DEPLOY_WF, "-L", "8",
                         "--json", "headBranch,status,conclusion,createdAt") or "[]")
    runs = [r for r in runs if r.get("conclusion") != "skipped"][:3]  # PR-label runs that never deployed
    for r in runs:
        t = dt.datetime.fromisoformat(r["createdAt"].replace("Z", "+00:00")).astimezone().strftime("%d.%m %H:%M")
        rows.append(f"deploy {t} · {r['headBranch']} · {r['status']}/{r.get('conclusion') or '…'}")
    live = next((r for r in runs if r.get("conclusion") == "success"), None)
    if live:
        br = live["headBranch"]
        rows.append(f"на dev зараз: {br}")
        if br.startswith("train"):
            sh("git", "fetch", "-q", "origin", br, timeout=40)
            subj = sh("git", "log", "--merges", "--format=%s", f"origin/main..origin/{br}")
            heads = re.findall(r"(?:from \S+/|branch '(?:origin/)?|^train[^:\n]*: merge )([^' (\n#]+)", subj, re.M)
            nums = re.findall(r"^train[^:\n]*: merge #(\d+)", subj, re.M)  # legacy «merge #N» subjects (train-w43-10)
            pulls = {p["headRefName"]: p for p in json.loads(sh("gh", "pr", "list", "-R", REPO, "--state", "all", "-L", "150",
                                                                   "--json", "number,headRefName,title,state") or "[]")}
            by_num = {str(p["number"]): p for p in pulls.values()}
            for n in nums:
                p = by_num.get(n)
                rows.append(f"  в {br}: " + (f"#{p['number']} {p['title'][:70]} [{p['state']}]" if p else f"#{n}"))
            for h in (x for x in dict.fromkeys(heads) if x != "main"):  # «Merge origin/main into <pr>» inside a PR branch is not a train member
                p = pulls.get(h)
                rows.append(f"  в {br}: " + (f"#{p['number']} {p['title'][:70]} [{p['state']}]" if p else h))
    url = sh("aws", "lambda", "get-function-configuration", "--function-name", "dev-rescue-serverless-fast-api",
             "--query", "Environment.Variables.WORKFLOW_ENGINE_BASE_URL", "--output", "text").strip()
    eng = next((v for k, v in ENGINES.items() if k in url), "?")
    rows.append(f"engine: {eng} ({url or 'aws не відповів'})")
    lock = "/tmp/b2b-dev-fixture.lock.d"
    rows.append(f"lock проб: {'🔒 ' + (sh('cat', lock + '/owner').strip() or 'зайнято') + ' · ' + str(age(lock)) if os.path.isdir(lock) else '🔓 вільно'}")
    box("🚂 /devnow — що зараз на dev", rows)


def cmd_tokens():
    today = dt.date.today()
    names = {w["pane"]: w for w in windows()}
    names.update({p: {"i": i, "name": n} for i, n, p in
                  [row.split("\t") for row in sh("tmux", "list-windows", "-t", SESSION, "-F", "#I\t#W\t#{pane_id}").splitlines()] if i in SKIP})
    per = {}
    for f in glob.glob(os.path.expanduser("~/.claude/sessions/*.json")):
        try:
            s = json.load(open(f))
        except (OSError, json.JSONDecodeError):
            continue
        pane = (s.get("tmux") or "").rsplit(".", 1)[-1]
        if not (s.get("tmux") or "").startswith(SESSION + ":") or pane not in names:
            continue
        files = glob.glob(os.path.expanduser(f"~/.claude/projects/*/{s['sessionId']}.jsonl")) + \
            glob.glob(os.path.expanduser(f"~/.claude/projects/*/{s['sessionId']}/**/*.jsonl"), recursive=True)
        seen, fresh, cached = set(), 0, 0
        for jf in files:
            for line in open(jf, encoding="utf-8", errors="replace"):
                if '"usage"' not in line:
                    continue
                try:
                    e = json.loads(line)
                except json.JSONDecodeError:
                    continue
                m, ts = e.get("message") or {}, e.get("timestamp", "")
                u = m.get("usage")
                if not u or m.get("id") in seen or not ts:
                    continue
                if dt.datetime.fromisoformat(ts.replace("Z", "+00:00")).astimezone().date() != today:
                    continue
                seen.add(m.get("id"))
                fresh += u.get("input_tokens", 0) + u.get("output_tokens", 0) + u.get("cache_creation_input_tokens", 0)
                cached += u.get("cache_read_input_tokens", 0)
        w = names[pane]
        key = w["i"]
        f0, c0 = per.get(key, (w["name"], 0, 0))[1:]
        per[key] = (w["name"], f0 + fresh, c0 + cached)
    rows = [f"{SESSION}:{i:<3} {f/1e6:6.2f}M нових · {c/1e6:7.1f}M з кешу · {n[:50]}"
            for i, (n, f, c) in sorted(per.items(), key=lambda kv: -kv[1][1])]
    tot = sum(v[1] for v in per.values())
    rows.append(f"РАЗОМ {tot/1e6:.2f}M нових за {today:%d.%m} (кеш у ~10× дешевший)")
    box("🪙 /tokens — за сьогодні, дорогі перші", rows)


def cmd_trylog(name=""):
    logs = sorted(glob.glob(f"/tmp/try-logs/*{name}*.log.screen") + glob.glob(f"/tmp/try-logs/*{name}*.log"),
                  key=os.path.getmtime)
    if not logs:
        return box("🧪 /trylog", [f"логів /tmp/try-logs/*{name}* нема"])
    log = logs[-1].removesuffix(".screen")
    log = log + ".screen" if os.path.exists(log + ".screen") else log
    text = re.sub(r"\x1b\[[0-9;]*m", "", open(log, encoding="utf-8", errors="replace").read())
    lines = [re.sub(r"^[║│\s]+|[║│\s]+$", "", x) for x in text.splitlines()]
    keep = re.compile(r"Крок \d+/\d+|^P\d|🔑|гейтів:|НЕ ДОВЕДЕНО|ЛИШИЛОСЬ|demo-result|8777|alertId|alert[ =]|RESULT|sabotage")
    rows = [f"файл: {log} ({age(log)} тому)"]
    for x in lines:
        if x and keep.search(x) and x not in rows:
            rows.append(x[:170])
    rows.append(f"весь прогін: ov --section-delimiter \"Крок [0-9]+/[0-9]+\" --section-header \"{log}\"")
    box("🧪 /trylog — останній прогін", rows[:45])


def bar(pct, n=10):
    pct = max(0, min(100, int(pct or 0)))
    k = round(pct * n / 100)
    return "▓" * k + "░" * (n - k)


ARCH = os.path.expanduser("~/zettelkasten/claude_code/rescue-serverless/architecture")
# stable Bonjour name: the LAN IP changes between networks
HUB = "http://mac.local:8890"


def plan_doc(tid):
    """ONE plan finder (status page + blockers pane): Mike-approved path → newest architecture/*pun-<n>-* plan|contract|root-cause
    → any architecture note named after the ticket → <board>/drafts/pun<n>*plan*."""
    n = tid.split("-")[1]
    try:
        for ln in reversed(open(f"{FB}/plan-approvals.tsv", encoding="utf-8").read().splitlines()):
            f = ln.split("\t")
            if len(f) > 2 and f[0] == tid and os.path.exists(f[2]):
                return f[2]
    except OSError:
        pass
    names = sorted(x for x in os.listdir(ARCH) if x.endswith(".md")) if os.path.isdir(ARCH) else []
    hits = [x for x in names if re.search(rf"pun-{n}-.*(plan|contract|root-cause)", x)] or [x for x in names if re.search(rf"pun-?{n}\b", x)]
    if hits:
        return f"{ARCH}/{hits[-1]}"
    d = f"{WK}/drafts"
    hits = sorted(x for x in os.listdir(d) if x.startswith(f"pun{n}") and "plan" in x) if os.path.isdir(d) else []
    return f"{d}/{hits[-1]}" if hits else None


def plan_brief(tid):
    """What Mike needs to close a «plan approval» blocker without hunting: where the plan is, its gist, its open questions, what to say."""
    path = plan_doc(tid)
    if not path:
        return None
    lines = open(path, encoding="utf-8").read().splitlines()

    def section(pat):
        i = next((k for k, x in enumerate(lines) if x.startswith("#") and re.search(pat, x, re.I)), None)
        if i is None:
            return []
        out = []
        for x in lines[i + 1:]:
            if x.startswith("## ") or (x.startswith("# ") and out):
                break
            if x.strip():
                out.append(re.sub(r"\*\*", "", x.strip()))
        return out

    gist = section(r"TL;DR|Summary|Підсумок|Висновок|Коротко")[:4]
    if not gist:
        gist = [x for x in lines if x.strip() and not x.startswith(("#", "---", "title:", "date:", "tags:", "linear:", "status:"))][:3]
    approved = any(ln.split("\t")[0] == tid for ln in open(f"{FB}/plan-approvals.tsv", encoding="utf-8").read().splitlines()) if os.path.exists(f"{FB}/plan-approvals.tsv") else False
    return {"id": tid, "path": path.replace(os.path.expanduser("~"), "~"), "url": f"{HUB}/rescue-serverless/fleet/{SESSION.lower()}-status.html#f-{tid}",
            "gist": [g[:220] for g in gist], "questions": [q[:220] for q in section(r"Questions|Питання|Open questions")[:6]],
            "approved": approved, "say": f"план так {tid}" + (" + відповіді на питання" if section(r"Questions|Питання") else "")}


_OPEN_PR_IDS = None


def open_pr_ids():
    """PUN ids that already have an open PR of Mike's (one gh call per process) — a «PR так» ask for them is answered."""
    global _OPEN_PR_IDS
    if _OPEN_PR_IDS is None:
        raw = sh("gh", "pr", "list", "-R", REPO, "--author", "@me", "--state", "open", "--json", "title,headRefName", "-L", "100")
        try:
            _OPEN_PR_IDS = set(re.findall(r"PUN-\d+", " ".join(x["title"] + " " + x["headRefName"].upper() for x in json.loads(raw or "[]"))))
        except ValueError:
            _OPEN_PR_IDS = set()
    return _OPEN_PR_IDS


def answered(ask):
    """Mike 21.10 «я вже відповідав на ці питання»: drop asks the facts already answer — «PR так» with an open PR,
    a plan approval for an approved plan."""
    ids = set(re.findall(r"PUN-\d+", ask))
    if not ids:
        return False
    if re.search(r"PR так", ask) and ids <= open_pr_ids():
        return True
    approved = {ln.split("\t")[0] for ln in open(f"{FB}/plan-approvals.tsv", encoding="utf-8").read().splitlines()} if os.path.exists(f"{FB}/plan-approvals.tsv") else set()
    return bool(re.search(r"план", ask, re.I)) and not re.search(r"PR так", ask) and ids <= approved


def fleet_rows():
    """ONE source for the footer and the blockers pane: per teammate window its track (bar/step/ETA), state,
    waiting-on line and Mike's asks from its brief; plus open tracks with no window and need-mike rows."""
    ws = list(windows())
    last = {}
    try:
        for pos, ln in enumerate(open(f"{WK}/tracks.tsv", encoding="utf-8").read().splitlines()):
            f = (ln.split("\t") + [""] * 5)[:5]
            if f[0]:
                last.pop(f[0], None)
                last[f[0]] = f  # last row per track = its current state; re-insert keeps dict order = recency
    except OSError:
        pass
    ops = [f for f in last.values() if f[1] != "done"]
    nm = f"{WK}/need-mike.tsv"
    need = [x.split("\t", 1)[-1] for x in open(nm, encoding="utf-8").read().splitlines() if x.strip()] if os.path.exists(nm) else []
    keys = lambda txt: set(re.findall(r"PUN-\d+|#\d{3,5}", txt))  # noqa: E731
    used, rows = set(), []
    for w in ws:
        ids = keys(w["name"])
        b = brief(w)
        ids |= keys(b.get("title", ""))
        mine = [f for f in ops if f"{SESSION}:{w['i']}" in f[3] or ids & keys(f[0] + " " + f[3])]
        recency = {f[0]: n for n, f in enumerate(ops)}
        mine.sort(key=lambda f: (not (ids & keys(f[0])), -recency[f[0]]))  # Mike 22.10: the freshest track, not a stale «run» one
        used |= {f[0] for f in mine}
        why, _ = status_line(w)
        pfile = f"{WK}/progress/{w['i']}.md"
        waiting = next((x for x in reversed(open(pfile, encoding="utf-8").read().splitlines()) if x.startswith("Чекаю на")), "") if os.path.exists(pfile) else ""
        t = mine[0] if mine else None
        asks_txt = " ".join(b.get("mike", []) + [n for n in need if ids & keys(n)])
        plan_ids = [i for i in sorted(ids & keys(asks_txt)) if i.startswith("PUN-") and re.search(rf"{i}[^.;]*план|план[^.;]*{i}", asks_txt)]
        plans = [x for x in (plan_brief(i) for i in plan_ids) if x and not x["approved"]]
        rows.append({"win": f"{SESSION}:{w['i']}", "i": w["i"], "name": w["name"], "state": w["state"], "plans": plans,
                     "track": t[0] if t else "", "pct": int(t[2] or 0) if t else None, "step": t[3] if t else why,
                     "eta": (t[4] or "?") if t else "", "waiting": waiting, "asks": [a for a in b.get("mike", []) if not answered(a)],
                     "need": [n for n in need if ids & keys(n)], "brief_age": b.get("age")})
    rest = [f for f in ops if f[0] not in used]
    matched = {n for r in rows for n in r["need"]}
    extra = [n for n in need if n not in matched] + [f"{f[0]}: {f[3]}" for f in rest if f[1] == "block" and not (keys(f[0]) & keys(" ".join(need)))]
    return rows, rest, ops, extra


def paused_wins(rows):
    """Mike 17.11: «все що менше 35 поки на паузі… я не блокую бо це на паузі» — state.json `paused` (win or PUN) + `pause_below` vs priorities.tsv."""
    try:
        st = json.load(open(f"{WK}/state.json"))
    except (OSError, ValueError):
        st = {}
    names, below = set(st.get("paused") or []), st.get("pause_below")
    score = {}
    if below and os.path.exists(f"{WK}/priorities.tsv"):
        for ln in open(f"{WK}/priorities.tsv").read().splitlines():  # last row per id wins
            c = ln.split("\t")
            m = re.search(r"\b(\d{1,3})\b", c[1]) if len(c) > 1 else None
            if m:
                score[c[0]] = int(m.group(1))
    out = set()
    for r in rows:
        pun = set(re.findall(r"PUN-\d+", r["name"]))
        if r["win"] in names or pun & names or (below and any(score.get(x, 100) < below for x in pun)):
            out.add(r["win"])
    return out


def blocker_groups(rows, extra):
    """Mike 21.10: 🙋 now = HE blocks a window that already waits · 🧭 = a window waits on the LEAD · 🕐 later. One source for footer and status page."""
    blk = list(dict.fromkeys([n for r in rows for n in r["need"]] + extra))
    # Mike 21.10: split «блокуєш ЗАРАЗ» (a window already stands and waits for it) from «ПОТІМ» (not ready yet / not blocking)
    keys = lambda txt: set(re.findall(r"PUN-\d+|#\d{3,5}", txt)) | {f"PUN-{n}" for n in re.findall(r"pun-?(\d{3,5})", txt, re.I)}  # noqa: E731 — «pun1902-try» counts too
    later_rx = re.compile(r"НЕ мерджити|не блокує|після |потім|⏸|ЧЕКАЙ|не терміново|коли буде", re.I)
    waiting = [r for r in rows if r["win"] not in paused_wins(rows) and r["state"] != "working" and not re.search(r"deputy|🧭 pm", r["name"])]  # service windows mention everything
    now, later = [], []
    for x in blk:
        who = [r["win"] for r in waiting if keys(x) & (keys(r["name"]) | keys(r["step"]) | keys(r["waiting"]))]
        (later if later_rx.search(x) or not who else now).append((x, who))
    for r in waiting:  # a waiting window whose ask lives only in its brief still blocks on Mike now
        if r["asks"] and not any(r["win"] in who for _, who in now):
            a = re.sub(r"[*]{2}|^\d+\.\s*", "", r["asks"][0]).strip()
            now.append((a + (f" (+{len(r['asks']) - 1} ще в /blockers)" if len(r["asks"]) > 1 else ""), [r["win"]]))
    # Mike 21.10: 🙋 = HE blocks (his decision/action) · 🧭 = a window waits on the LEAD (my debt, I clear it) · 🕐 = later
    mike_wins = {w for _, ws in now for w in ws}
    lead_wait = [r for r in waiting if r["win"] not in mike_wins
                 and re.search(r"\blead\b|лід|LEAD", r["waiting"] or r["step"]) and not re.search(r"Mike|Майк", r["waiting"] or r["step"])]
    return now, lead_wait, later


def blocked_by(rows, extra):
    """Mike 22.10: every window says WHO it stands on — 🔄 works · 🙋 Mike · 🧭 lead · 🚂 dev queue · ⏳ another window · 💤 free."""
    now, lead_wait, _ = blocker_groups(rows, extra)
    mike = {w for _, ws in now for w in ws}
    lead = {r["win"] for r in lead_wait}
    out, paused = {}, paused_wins(rows)
    for r in rows:
        if r["win"] in paused:  # Mike 17.11: a paused window is not on Mike — shown as ⏸
            out[r["win"]] = "⏸ пауза"
            continue
        txt = f"{r['waiting']} {r['step']}"
        # Mike 22.10: the FIRST target after «Чекаю на:» decides — «… ; Mike — проби» later in the line made every window read «на ТОБІ»
        first = re.match(r"Чекаю на:\s*([^—–;·,]+)", r["waiting"] or "")
        first = first.group(1).strip() if first else ""
        if re.match(r"(Mike|Майк)\b", first):  # Mike 09.11: «Чекаю на: Mike» beats a running spinner (W45:7 sat in 🔄)
            out[r["win"]] = "🙋 на ТОБІ"
        elif r["state"] == "working":
            out[r["win"]] = "🔄 працює"
        elif re.match(r"(нікого|—|-)", first):
            out[r["win"]] = "💤 вільне"
        elif re.match(r"(лід|LEAD|lead)", first) and re.search(r"\bdev\b|train|deploy|деплой", r["waiting"], re.I):
            out[r["win"]] = "🚂 черга dev"  # Mike 18.11: «lead — dev ✅ / train» waits on dev, not on the lead
        elif re.match(r"(лід|LEAD|lead)", first) and re.search(r"(deputy|guru|grill|pm)\b", r["name"], re.I) and re.search(r"next (task|question)|idle", r["waiting"], re.I):
            out[r["win"]] = "💤 вільне"  # an idle service window is free capacity, not lead debt
        elif re.match(r"(лід|LEAD|lead)", first):
            out[r["win"]] = "🧭 на ЛІДІ"
        elif re.match(rf"{SESSION}:\d+|pm|W\d+:\d+", first):
            out[r["win"]] = "🚂 черга dev" if re.search(r"dev|train", r["waiting"], re.I) else "⏳ інше вікно"
        elif re.match(r"deputy\b", first, re.I):  # «deputy «dev твій» …(після проби Mike)» waits on dev, not on Mike
            out[r["win"]] = "🚂 черга dev" if re.search(r"dev|train", r["waiting"], re.I) else "⏳ інше вікно"
        elif re.search(r"\b(Mike|Майк)\b", re.sub(r"\([^)]*\)", "", first)):  # Mike 19.11: «чекаю проби Mike» read as 💤 free; a mention in brackets does not count
            out[r["win"]] = "🙋 на ТОБІ"
        elif r["win"] in mike or re.search(r"Чекаю на: Mike|🙋 твоя", txt):
            out[r["win"]] = "🙋 на ТОБІ"
        elif r["win"] in lead or re.search(r"Чекаю на: (лід|LEAD)", txt, re.I):
            out[r["win"]] = "🧭 на ЛІДІ"
        elif re.search(r"dev|train", r["waiting"], re.I):
            out[r["win"]] = "🚂 черга dev"
        elif re.search(rf"{SESSION}:\d+", r["waiting"]):
            out[r["win"]] = "⏳ інше вікно"
        else:
            out[r["win"]] = "💤 вільне"
        if out[r["win"]] == "🙋 на ТОБІ" and is_request(r["waiting"]):
            out[r["win"]] = "💬 прохання"  # Mike 19.11: «блокер від мене і прохання — різні значки, це ж путає»
        if out[r["win"]] == "🚂 черга dev" and re.search(r"deputy", r["name"], re.I):
            out[r["win"]] = "⏳ інше вікно"  # Mike 19.11: deputy runs the dev queue, it is not in it
    return out


REQUEST_SAYS = re.compile(r"не блоку|не терміново|коли буде час|\bFYI\b|прохання|для інфо", re.I)
REQUEST_LOOK = re.compile(r"подивитись|подивись|глянути|глянь|показати|ознайомитись", re.I)
BLOCKS = re.compile(r"проб|\btry\b|merge|мердж|план|plan|рішення|апрув|approve|відповід|питання|дозв", re.I)


def is_request(waiting):
    """a line addressed to Mike that does NOT stop the window: it says so itself («не блокує», «FYI», «прохання»), or it only asks him
    to look and names nothing he must do (no try, merge, plan, decision). When in doubt it stays a blocker — a missed blocker costs more."""
    text = (waiting or "").replace("Чекаю на:", "")
    return bool(REQUEST_SAYS.search(text) or (REQUEST_LOOK.search(text) and not BLOCKS.search(text)))


def cmd_badge():
    """One line for the lead's statusline (Mike 17.11): how many teammates work · are blocked · have a question for the lead."""
    rows, _, _, extra = fleet_rows()
    st = list(blocked_by(rows, extra).values())
    n = lambda *marks: sum(s.startswith(marks) for s in st)  # noqa: E731
    # Mike 18.11: «заблоковані — це мною чи кимось ще»: every blocker on its own, zero ones hidden
    parts = [f"🔄{n('🔄')} працюють"] + [f"{m}{n(m)} {t}" for m, t in BLOCKERS if n(m)] + ([f"💬{n('💬')} прохання"] if n("💬") else []) + [f"💤{n('💤')} вільні"]
    print(f"👥{len(st)} · " + " · ".join(parts))


BLOCKERS = [("🙋", "на тобі"), ("🧭", "на ліді"), ("🚂", "на dev"), ("⏳", "на іншому вікні"), ("⏸", "пауза")]


def cmd_sl(win=""):
    """Mike 19.11: explain a window's statusline block by block, untruncated — `lead.py sl [3|W46:3|lead]` (no arg = this window)."""
    args = ["--lead"] if win in ("lead", "1") or (not win and not os.environ.get("TMUX_PANE")) else ["--win", f"{SESSION}:{win}" if win.isdigit() else win] if win else []
    subprocess.run([sys.executable, os.path.expanduser("~/.claude/scripts/statusline_role.py"), "--explain", *args, os.getcwd()])


# Mike 19.11: ONE icon vocabulary for the tmux window name (window-state.py) and the statusline (statusline_role.py).
# want = WHAT the window waits for, from its «Чекаю на» line — the keyword that comes first in the text wins.
WANTS = [("🧪", r"проб|\btry\b|прогін"), ("📋", r"план так|card-plan|\bплан\b"), ("🔀", r"merge|мердж|змердж"),
         ("🚀", r"deploy|деплой|train|dev твій|dev free|dev ✅"), ("👀", r"прочитати|подивитись|глянути|review|рев.ю"),
         ("❓", r"питання|рішення|вибір|відповід"), ("⚙️", r"працюю|роблю|пишу")]
GATES = (("code-review", "CR"), ("ponytail", "PT"), ("review-pr", "RPR"), ("just-test", "JT"), ("just-fe", "FE"), ("demo", "DEMO"))


def want(text):
    hits = [(m.start(), mark) for mark, rx in WANTS if (m := re.search(rx, text, re.I))]
    return min(hits)[1] if hits else ""


def gate_progress(num):
    """Mike 19.11: how far a PR is through ALL /pr-state gates (PLAN CI MRG MAIN CR PT 🐛 TRY PRE JT MIKE FE UI) — read from the statusline's
    cache of `pipeline-stamp.sh gates` (/tmp/claude/sl-gates.json). → {cells, done, total, next, pct} or None. «·» = not applicable, not counted."""
    try:
        d = json.load(open("/tmp/claude/sl-gates.json"))
    except (OSError, ValueError):
        return None
    row = next((r for r in d.get("rows", []) if r.get("tag") == f"#{num}"), None)
    if not row:
        return None
    cells = [(g, row["cells"].get(g, "·")) for g in d["gates"]]
    need = [(g, c) for g, c in cells if c != "·"]
    done = sum(c == "✓" for _, c in need)
    return {"cells": cells, "done": done, "total": len(need), "next": next((g for g, c in need if c != "✓"), ""),
            "pct": done * 100 // len(need) if need else 0}


def try_of(num):
    """PR → its try recipe from <board>/preflight-map.tsv («2538\tpun2139-try»), or ''"""
    try:
        return next((f[1] for f in (ln.split("\t") for ln in open(f"{WK}/preflight-map.tsv").read().splitlines()) if f[0] == str(num) and len(f) > 1), "")
    except OSError:
        return ""


def mike_tries(rows):
    """Mike 19.11 «показуй проби, якщо треба, щоб я затестив»: (window, PR, recipe, ready) for every open PR that still needs his try.
    ready = every /pr-state gate before MIKE is ✓ (his own Mike-ready rule), so the agent's run is green on this dev."""
    out = []
    for r in rows:
        pr = win_pr(r["win"])
        gp = gate_progress(pr["number"]) if pr and pr["state"] == "OPEN" else None
        if gp and dict(gp["cells"]).get("MIKE") == "✗":
            out.append((r["win"], pr["number"], try_of(pr["number"]), gp["next"] == "MIKE", gp["next"]))
    return out


def win_pr(win):
    """the window's PR as the statusline cached it (/tmp/claude/sl-pr-N.json, no network here): the open one, else the newest known"""
    try:
        prs = [ln.split("\t")[0] for ln in open(f"{WK}/pr-windows.tsv").read().splitlines() if ln.split("\t")[1:2] == [win]]
    except OSError:
        return None
    known = []
    for n in reversed(prs):
        try:
            d = json.load(open(f"/tmp/claude/sl-pr-{n}.json"))
        except (OSError, ValueError):
            continue
        if d.get("state"):
            known.append(d)
    return next((d for d in known if d["state"] == "OPEN"), known[0] if known else None)


def win_icons(r, mark):
    """{want, alarm, stage, gate, prio} for one fleet_rows() row. alarm: 🧱 permission prompt · ⚠ says «працюю» but is not running ·
    🔥 waits on Mike/the lead for over an hour. stage/gate mirror the statusline: PR state (+❌ conflict, 🟡 deploying) and the next gate."""
    w = "" if mark == "💤" else want((r["waiting"] or "").replace("Чекаю на:", ""))  # a free window wants nothing: its line is a report, not a request
    p = f"{WK}/progress/{r['i']}.md"
    waited = (time.time() - os.path.getmtime(p)) / 60 if os.path.exists(p) else 0
    alarm = "🧱" if needs_input(r) else "⚠" if w == "⚙️" and r["state"] != "working" else "🔥" if mark in ("🙋", "🧭") and waited > 60 else ""
    stage = gate = ""
    pr = win_pr(r["win"])
    if pr:
        stage = "📝" if pr.get("isDraft") else {"OPEN": "🟢", "MERGED": "🟣", "CLOSED": "🔴"}.get(pr["state"], "")
        stage += ("❌" if pr.get("mergeable") == "CONFLICTING" else "") + ("🟡" if pr.get("deploy") == "deploying" else "")
        gp = gate_progress(pr["number"]) if pr["state"] == "OPEN" else None
        if gp and gp["next"] == "MIKE" and mark in ("🙋", "💬"):
            w = "🧪"  # every gate before MIKE is green: what this window wants from him is the try, whatever its line says
        if gp:  # 72%➜PRE: share of the gates passed + the next one; all passed → ✅ (Mike 19.11: a percent, no bar)
            gate = f"{gp['pct']}%" + (f"➜{gp['next']}" if gp["next"] else "✅")
    elif re.search(r"PUN-\d+", r["name"]) and w != "📋":
        stage = "📋"  # no PR yet: the plan stage
    tid = (re.search(r"PUN-\d+", r["name"]) or [""])[0]
    sc = re.search(r"\d+", prio_map_score().get(tid, ""))
    return {"want": w, "alarm": alarm, "stage": stage, "gate": gate, "prio": f"⭐{sc[0]}" if sc else ""}


def icon_prefix(r, status, pr_num=None):
    """THE icon string of a window — tmux window name, statusline and tiki card all print this (Mike 19.11 «sync with emoji and status»).
    pr_num: a PR card shows the stage and gates % of ITS PR, not of the window's newest one."""
    mark = status.split()[0]
    ic = win_icons(r, mark)
    tail = ic["stage"] + ic["gate"]
    if pr_num:
        gp = gate_progress(pr_num)
        tail = ("🟢" + f"{gp['pct']}%" + (f"➜{gp['next']}" if gp["next"] else "✅")) if gp else tail
    return f"{mark}{ic['want']}{ic['alarm']}{tail}"


def prio_map_score():
    """PUN-id → the raw priority cell («prio 98»), last row per id wins"""
    out, p = {}, f"{WK}/priorities.tsv"
    if os.path.exists(p):
        for ln in open(p, encoding="utf-8").read().splitlines():
            f = ln.split("\t")
            if len(f) > 1:
                out[f[0]] = f[1]
    return out


JUST_DIR = os.path.expanduser("~/code/b2b/rescue-serverless/backend/src/lambdas/api/fast/.just_dir_2")


def try_about(rec):
    """the try recipe's own «# try:» and «# why:» header lines — what it proves and why it exists"""
    try:
        head = open(f"{JUST_DIR}/{rec}.just", encoding="utf-8").read().splitlines()[:40]
    except OSError:
        return []
    return [f"{k}: {ln.split(':', 1)[1].strip()}" for k, p in (("що доводить", "# try:"), ("навіщо", "# why:")) for ln in head if ln.startswith(p)]


def need_items():
    """Mike's agenda as data: every item = {sec now|soon|ask|loose, score, win, head, do, why, unblocks, waited, kind, context[], options[]}.
    options = the answers he can give, each with what happens next — the same list feeds the /need modal."""
    rows, _, _, extra = fleet_rows()
    st = blocked_by(rows, extra)
    by = {r["win"]: r for r in rows}
    raw = prio_map_score()
    score = lambda text: max((int(m[0]) for i in re.findall(r"PUN-\d+", text) if (m := re.search(r"\d+", raw.get(i, "")))), default=0)  # noqa: E731
    waited = lambda r: age(f"{WK}/progress/{r['i']}.md") or "?"  # noqa: E731
    title = lambda r: re.sub(r"^.*│|^🔵\s*|\(plan\)", "", r["name"]).strip()  # noqa: E731
    queue = [w.split(":")[1] for w, s in st.items() if s.startswith("🚂")]
    try:
        gates = {x["tag"]: x for x in json.load(open("/tmp/claude/sl-gates.json")).get("rows", [])}
    except (OSError, ValueError):
        gates = {}
    items, done = [], set()
    tries = mike_tries(rows)
    for win, num, rec, ok, nxt in tries:
        r, gp, g = by[win], gate_progress(num), gates.get(f"#{num}", {})
        tid = g.get("linear") or ""  # the PR's own ticket: the window name may carry another one
        ctx = [f"PR#{num} {tid}: {g.get('title', '')}".strip()] + try_about(rec) + [
            "гейти: " + " ".join(f"{k}{c}" for k, c in gp["cells"]), f"вікно пише: {(r['waiting'] or '').replace('Чекаю на:', '').strip()[:200]}"]
        if ok:
            items.append(dict(sec="now", kind="try", score=score(tid) or score(r["name"]), win=win, head=f"{win} {title(r)} — 🧪 твоя проба ГОТОВА (PR#{num} {tid})",
                              do=f"jb2b {rec}" if rec else f"проба PR#{num} (рецепта нема в preflight-map.tsv — спитай ліда)",
                              why=f"останній гейт PR#{num} ({gp['pct']}%, лишився MIKE) → після неї merge",
                              unblocks="dev для вікон у черзі " + ", ".join(queue) if queue else "merge цього PR", waited=waited(r), context=ctx,
                              options=[("Запускаю пробу зараз", f"ти: jb2b {rec}; зелена → кажеш «апрув», лід мерджить"),
                                       ("Пізніше", "вікно і черга на dev чекають далі; скажи, після чого"),
                                       ("Хай лід прожене і покаже лог", "лід запускає сам і приносить підсумок; гейт MIKE лишається за тобою")]))
            done.add(win)
        else:
            items.append(dict(sec="soon", kind="try", score=score(tid) or score(r["name"]), win=win,
                              head=f"{win} {title(r)} — 🧪 {rec or 'проба'} · PR#{num} {gp['pct']}%, спершу гейт {nxt}" + (" · у черзі на dev" if st[win].startswith("🚂") else ""), context=ctx, options=[]))
    ready_prs = [num for _, num, _, ok, _ in tries if ok]
    for r in rows:
        if r["win"] in paused_wins(rows):
            continue
        why = (r["waiting"] or r["step"] or "").replace("Чекаю на:", "").strip()
        for p in r["plans"]:  # an unapproved plan needs his «план так» even when the window formally waits on the lead
            items.append(dict(sec="now", kind="plan", score=score(p["id"]), win=r["win"],
                              head=f"{r['win']} {title(r)} — 📋 «план так» {p['id']}" + (" (через ліда)" if st[r["win"]].startswith("🧭") else ""),
                              do=f"прочитати план → сказати «{p['say']}»", why="без твого апруву плану код не починається (гейт PLAN)",
                              unblocks=f"{r['win']} почне код", waited=waited(r),
                              context=[f"план: {p['path']}"] + [f"суть: {x}" for x in p["gist"][:3]] + [f"питання: {x}" for x in p["questions"][:5]],
                              options=[("Ще ні — покажи суть", "лід переказує card-plan: що, навіщо, було → стало, ризики; рішення поки нема"),
                                       ("Переглянув — план так", f"лід фіксує «{p['say']}», вікно починає код"),
                                       ("Є правки", "пишеш правки; вікно оновлює план і приносить знову")]))
            done.add(r["win"])
        if st[r["win"]].startswith("💬"):
            items.append(dict(sec="ask", kind="ask", score=score(r["name"]), win=r["win"], head=f"{r['win']} {title(r)} — {why[:150]}", context=[why], options=[]))
        elif st[r["win"]].startswith("🙋") and re.search(r"deputy|🧭 pm", r["name"]) and any(f"#{n}" in why for n in ready_prs):
            pass  # a service window repeating a try that is already listed above
        elif st[r["win"]].startswith("🙋") and r["win"] not in done:
            ic = win_icons(r, "🙋")
            items.append(dict(sec="now", kind="blocker", score=score(r["name"]), win=r["win"], head=f"{r['win']} {title(r)} — {ic['want'] or '🙋'}{ic['alarm']} блокер",
                              do=why[:200], why="вікно стоїть, доки ти не відповіси", unblocks=r["win"], waited=waited(r),
                              context=[f"вікно пише: {why}"] + [f"також: {n}" for n in r["need"][:3]],
                              options=[("Зроблю зараз", "пишеш відповідь або робиш дію; лід передає у вікно"), ("Пізніше", "вікно стоїть далі; скажи, після чого"),
                                       ("Це не до мене", "лід розбирається сам і прибирає блокер")]))
    items += [dict(sec="loose", kind="loose", score=score(x), win="", head=x[:170], context=[x], options=[]) for x in extra]
    return sorted(items, key=lambda x: -x["score"]), st


def cmd_need(*args):
    """Mike 19.11 «кому я потрібен, для чого, пріоритетність» + «варіанти відповіді і контекст»: his agenda, ranked by ticket score.
    ① do now · ② soon · ③ requests · ④ no window · ⑤ not his. `need --json` = the same items for the /need modal."""
    items, st = need_items()
    lock = "/tmp/b2b-dev-fixture.lock.d"
    try:
        dev = json.load(open("/tmp/claude/sl-dev.json"))
    except (OSError, ValueError):
        dev = {}
    devline = (f"{dev.get('branch', '?')} {'🟢 deploy завершено' if dev.get('live') else '🟡 deploy триває'} · проби: "
               + (f"🔒 зайнято {age(lock)} — другу не запускати" if os.path.isdir(lock) else "🔓 вільно, можна пробувати"))
    if "--json" in args:
        json.dump({"session": SESSION, "dev": devline, "try_lock": os.path.isdir(lock), "items": items}, sys.stdout, ensure_ascii=False, indent=1)
        return
    sec = lambda s: [x for x in items if x["sec"] == s]  # noqa: E731
    print(f"🎯 /need — кому ти потрібен · {SESSION} · {dt.datetime.now():%H:%M}\n   dev зараз: {devline}")
    print(f"\n① ЗРОБИ ЗАРАЗ — вікно стоїть і все готове ({len(sec('now'))}), за балом пріоритету")
    for n, x in enumerate(sec("now"), 1):
        print(f" {n}. ⭐{x['score'] or '—':<3} {x['head']}")
        for lab, key in (("зробити:  ", "do"), ("навіщо:   ", "why"), ("розблокує:", "unblocks"), ("чекає:    ", "waited")):
            print(f"        {lab} {x[key]}")
        print("        контекст:")
        for c in x["context"]:
            print(f"          · {c[:230]}")
        print("        варіанти відповіді:")
        for k, (lab, then) in enumerate(x["options"]):
            print(f"          {'abc'[k]}) {lab} → {then}")
    if not sec("now"):
        print("    нічого — жодне вікно не стоїть через тебе")
    for s, head in (("soon", "② СКОРО — потребуватиме тебе, але ще не готове"), ("ask", "③ ПРОХАННЯ 💬 — просять глянути, не блокує"),
                    ("loose", "④ БЕЗ ВІКНА — записано у need-mike.tsv, ніхто не стоїть")):
        print(f"\n{head} ({len(sec(s))})")
        for x in sec(s):
            print(f"    ⭐{x['score'] or '—':<3} {x['head']}")
    n = lambda m: [w.split(":")[1] for w, s in st.items() if s.startswith(m)]  # noqa: E731
    print("\n⑤ НЕ ТВОЄ ЗАРАЗ — " + " · ".join(f"{m} {lab} [{' '.join(n(m))}]" for m, lab in
                                             (("🧭", "на ліді"), ("🚂", "черга на dev"), ("⏳", "інше вікно"), ("🔄", "працюють"), ("⏸", "пауза"), ("💤", "вільні")) if n(m)))
    print("\n   відповідай літерою («1a», «2b») або своїми словами · /sl <N> — що у вікні N · /who — усі групи")


def cmd_sync():
    """Mike 19.11: make tmux window names say who each window stands on (first symbol), in step with the statusline — both read blocked_by().
    Claude runs it right after changing a «Чекаю на» line; the statusline also triggers it every 20 s, so it is a «now» button, not a duty."""
    subprocess.run([sys.executable, f"{FB}/bin/window-state.py"], env={**os.environ, "LEAD_SESSION": SESSION})
    rows, _, _, extra = fleet_rows()
    st = blocked_by(rows, extra)
    for w in sh("tmux", "list-windows", "-t", SESSION, "-F", "#I\t#W").splitlines():
        i, name = w.split("\t", 1)
        print(f"  {SESSION}:{i:<3} {name[:70]:<70} {st.get(f'{SESSION}:{i}', '')}")
    print("\n  🙋 БЛОКЕР на тобі (вікно стоїть) · 💬 прохання до тебе (не блокує) · 🧭 на ліді · 🚂 черга на dev · ⏳ інше вікно · 🔄 працює · ⏸ пауза · 💤 вільне")
    print("  агент пише прохання так: «Чекаю на: Mike (не блокує) — …»; без цих слів рядок до Mike = блокер")
    print("  другий символ — що саме чекає: 🧪 проба · 📋 план так · 🔀 merge · 🚀 dev/deploy · 👀 прочитати · ❓ рішення · ⚙️ зайнятий своїм")
    print("  тривога: 🧱 запит дозволу · ⚠ пише «працюю», але не запущений · 🔥 чекає понад годину")
    print("  стадія: 🟢 PR open · 🟣 merged · 📝 draft · 📋 план (PR ще нема) · ❌ конфлікт · 🟡 deploy триває")
    print("  гейти: 72%➜PRE — скільки з усіх гейтів /pr-state пройдено і який наступний (PLAN CI MRG MAIN CR PT 🐛 TRY PRE JT MIKE FE UI)")


def cmd_who():
    """Mike 18.11: who blocks whom — windows grouped by the one they wait on, with the reason from «Чекаю на»."""
    rows, _, _, extra = fleet_rows()
    st = blocked_by(rows, extra)
    by = {r["win"]: r for r in rows}
    cmd_badge()
    for mark, title in [("🔄", "працюють")] + BLOCKERS + [("💬", "прохання до тебе (не блокує)"), ("💤", "вільні")]:
        wins = [w for w, s in st.items() if s.startswith(mark)]
        if not wins:
            continue
        print(f"\n{mark} {title.upper()} · {len(wins)}")
        for w in wins:
            r = by.get(w, {})
            why = (r.get("waiting") or r.get("step") or "").replace("Чекаю на:", "").strip()
            print(f"  {w:<7} {r.get('name', '')[:42]:<42} {why[:110]}")


def cmd_footer(only=""):
    """Footer for EVERY lead reply (`footer`) and EVERY teammate reply (`footer <idx>`: only that window) (Mike 21.10): ONE ROW PER TEAMMATE with its window number (Mike: «щоб я міг знайти його»),
    bar + step + ETA from tracks.tsv, then operations without a window, then Mike's blockers."""
    rows, rest, ops, extra = fleet_rows()
    if only:  # teammate footer (Mike 21.10): its own row + what it waits on from Mike, nothing else
        rows = [r for r in rows if r["i"] == only]
        for r in rows:
            st = "🔄 працюю" if r["state"] == "working" else "⏳ чекаю"
            line = f"{bar(r['pct'])} {r['pct']:>3}%  {r['step'][:70]}  ETA {r['eta']}" if r["pct"] is not None else (r["waiting"] or r["step"])[:90]
            print(f"📍 {r['win']} {r['name']} · {st} · {line}")
            asks = list(dict.fromkeys(r["asks"] + r["need"]))
            print(f"🙋 від Mike ({len(asks) + len(r.get('plans', []))}):" if asks or r.get("plans") else "🙋 від Mike: нічого — працюю сам")
            for k, a in enumerate(asks, 1):
                print(f"  {k}. {re.sub(r'[*]{2}', '', a)[:160]}")
            for pl in r.get("plans", []):
                print(f"  📋 план {pl['id']}: {pl['path']} → «{pl['say']}»")
        return
    busy = sum(r["state"] == "working" for r in rows)
    print(f"👥 тіммейти: {busy} зайнято · {len(rows) - busy} чекають")
    by = blocked_by(rows, extra)
    for r in rows:
        st = by[r["win"]]
        if r["pct"] is not None:
            print(f"  {r['win']:<7} {r['name'][:34]:<34} {st:<12} {bar(r['pct'])} {r['pct']:>3}%  {r['step'][:52]:<52} ETA {r['eta']}")
        else:
            print(f"  {r['win']:<7} {r['name'][:34]:<34} {st:<12} {'':10}       {(r['waiting'] or r['step'])[:52]:<52}")
    if rest:
        print("  ── без вікна ──")
        for f in rest:
            print(f"  {'⛔' if f[1] == 'block' else '🔄'} {f[0][:40]:<40} {bar(f[2])} {int(f[2] or 0):>3}%  {f[3][:50]:<50} ETA {f[4] or '?'}")
    total = round(sum(int(f[2] or 0) for f in ops) / len(ops)) if ops else 100
    print(f"  Σ {bar(total)} {total}% по {len(ops)} відкритих операціях")
    now, lead_wait, later = blocker_groups(rows, extra)
    busy_n = sum(r["state"] == "working" for r in rows)
    mike_wins = {w for _, ws in now for w in ws}
    print(f"🧭 Що зараз: {busy_n} вікон працюють самі · {len(mike_wins)} стоять і чекають на ТЕБЕ · {len(lead_wait)} чекають на ЛІДА · {len(later)} — на потім.")
    print(f"🙋 Блокуєш ТИ ({len(now)}) — потрібне твоє рішення/дія:" if now else "🙋 Ти зараз нікого не блокуєш")
    for i, (x, who) in enumerate(now, 1):
        print(f"  {i}. {x[:150]}  ⟵ чекає {', '.join(who)}")
    if lead_wait:
        print(f"🧭 Чекають на ЛІДА ({len(lead_wait)}) — мій борг, закриваю сам:")
        for r in lead_wait:
            print(f"  · {r['win']} {r['name'][:30]} — {(r['waiting'] or r['step'])[:120]}")
    if later:
        print(f"🕐 Потім ({len(later)}):")
        for i, (x, _) in enumerate(later, 1):
            print(f"  {i}. {x[:150]}")


def cmd_blockers(*args):
    """Detailed blockers for the side pane (mod «blockers»): `blockers` = every teammate (lead), `blockers <idx>` = that window only.
    `--json` for the pane; text otherwise."""
    want = [a for a in args if a != "--json"]
    rows, rest, ops, extra = fleet_rows()
    if want:
        rows = [r for r in rows if r["i"] == want[0]]
        extra = []
    if "--json" in args:
        print(json.dumps({"session": SESSION, "scope": want[0] if want else "lead", "rows": rows, "extra": extra,
                          "ts": dt.datetime.now().strftime("%H:%M")}, ensure_ascii=False))
        return
    for r in rows:
        mark = "🙋" if r["asks"] or r["need"] else "·"
        print(f"{mark} {r['win']} · {r['name']} · {r['state']}")
        if r["pct"] is not None:
            print(f"   {bar(r['pct'])} {r['pct']}% · {r['step']} · ETA {r['eta']}")
        if r["waiting"]:
            print(f"   {r['waiting']}")
        for a in r["asks"] + r["need"]:
            print(f"   • {a}")
        for pl in r.get("plans", []):
            print(f"   📋 План {pl['id']} — чекає твій апрув · файл: {pl['path']}")
            print(f"      {pl['url']}")
            for g in pl["gist"]:
                print(f"      • {g}")
            for q in pl["questions"]:
                print(f"      ? {q}")
            print(f"      → напиши ліду: «{pl['say']}»")
    for x in extra:
        print(f"• {x}")


def cmd_board():
    for fn in (cmd_devnow, cmd_stuck, cmd_mine, cmd_idle):
        fn()


if __name__ == "__main__":
    what, *rest = sys.argv[1:] or ["board"]
    fn = globals().get(f"cmd_{what}")
    if not fn:
        sys.exit(f"usage: lead.py {{mine|devnow|fleet|idle|stuck|tokens|trylog [name]|ask|board|footer|badge|who|sl [win]|sync|need}} (got {what!r})")
    fn(*rest)
