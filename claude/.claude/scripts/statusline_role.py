#!/usr/bin/env python3
"""statusline_role.py — role lines for ~/.claude/statusline.sh (Mike 19.11, layout picked on the hub page
rescue-serverless/fleet/statusline-by-role-proposal-2026-11-19.html).

Prints up to 3 ANSI lines for a fleet window (lead · PR teammate · plan teammate · guru · service); prints NOTHING for
any other session, so statusline.sh falls back to its default. The shared last line (model, context, usage) stays in bash.

  statusline_role.py [--lead] <cwd>      render (role is read from the tmux window name, never from its number)
  statusline_role.py --explain [--win W46:3] <cwd>      /sl: every block of that window in words, untruncated, plus details
  statusline_role.py --refresh pr <N> <cwd> | --refresh dev <cwd>      background cache refresh (gh calls)
Everything slow (gh) is cached in /tmp/claude and refreshed in the background: a render never waits for the network.
"""
import json
import os
import re
import subprocess
import sys
import time

HOME = os.path.expanduser("~")
CACHE = "/tmp/claude"
E = "\033"
C = {"c": f"{E}[38;2;46;149;153m", "g": f"{E}[38;2;0;160;0m", "o": f"{E}[38;2;255;176;85m", "r": f"{E}[38;2;255;85;85m",
     "y": f"{E}[38;2;230;200;0m", "w": f"{E}[38;2;220;220;220m", "p": f"{E}[38;2;190;130;255m", "b": f"{E}[38;2;0;153;255m", "d": f"{E}[2m"}
R = f"{E}[0m"
DOT = f" {C['d']}·{R} "


def col(k, s):
    return f"{C[k]}{s}{R}"


def link(url, label):  # OSC 8: a short clickable label, the address itself is never printed
    return f"{E}]8;;{url}\a{label}{E}]8;;\a"


def sh(*cmd, cwd=None, timeout=4, env=None):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, cwd=cwd, env=env).stdout.strip()
    except (subprocess.TimeoutExpired, OSError):
        return ""


def mins(m):
    return f"{m}хв" if m < 60 else f"{m // 60}г{m % 60:02d}"


def cut(s, n):
    s = " ".join(s.split())
    return s if len(s) <= n else s[: n - 1].rstrip() + "…"


# ---- cache: stale-while-revalidate, the refresh runs detached ----
def cached(name, ttl, refresh_args):
    path = f"{CACHE}/sl-{name}.json"
    age = time.time() - os.path.getmtime(path) if os.path.exists(path) else 1e9
    stamp = path + ".stamp"
    if age > ttl and (not os.path.exists(stamp) or time.time() - os.path.getmtime(stamp) > 30):  # one refresh at a time
        os.makedirs(CACHE, exist_ok=True)
        open(stamp, "w").close()
        subprocess.Popen([sys.executable, __file__, "--refresh", *refresh_args], stdin=subprocess.DEVNULL,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    try:
        return json.load(open(path))
    except (OSError, ValueError):
        return {}


def put(name, data):
    os.makedirs(CACHE, exist_ok=True)
    tmp = f"{CACHE}/sl-{name}.json.tmp"
    json.dump(data, open(tmp, "w"))
    os.replace(tmp, f"{CACHE}/sl-{name}.json")


REPO = "back2back-team/rescue-serverless"


def refresh_pr(n, cwd):
    raw = sh("gh", "pr", "view", n, "-R", REPO, "--json", "number,state,isDraft,mergeable,additions,deletions,headRefName,headRefOid", timeout=20)
    if not raw:
        return
    d = json.loads(raw)
    cmp_ = sh("gh", "api", f"repos/{REPO}/compare/main...{d['headRefOid']}", "--jq", "[.ahead_by,.behind_by]|@tsv", timeout=20).split()
    d["behind"] = int(cmp_[1]) if len(cmp_) == 2 else None
    runs = sh("gh", "api", f"repos/{REPO}/commits/{d['headRefOid']}/check-runs", "--jq",
              '[.check_runs[]|select(.name|test("deploy";"i"))|(.conclusion // .status)]|@tsv', timeout=20).split()
    d["deploy"] = ("" if not runs else "deploying" if {"in_progress", "queued", "pending"} & set(runs)
                   else "failed" if {"failure", "timed_out"} & set(runs) else "deployed" if "success" in runs else "")
    put(f"pr-{n}", d)


def refresh_dev(cwd):
    runs = json.loads(sh("gh", "run", "list", "-R", REPO, "--workflow", "165841775", "-L", "8", "--json", "headBranch,status,conclusion,startedAt", timeout=20) or "[]")
    runs = [r for r in runs if r.get("conclusion") != "skipped"]
    cur = next((r for r in runs if r["status"] != "completed"), None) or next((r for r in runs if r.get("conclusion") == "success"), None)
    d = {}
    if cur:
        num = sh("gh", "pr", "list", "-R", REPO, "--head", cur["headBranch"], "--state", "all", "--json", "number", "--jq", ".[0].number", timeout=20)
        d = {"branch": cur["headBranch"], "pr": num, "live": cur["status"] == "completed", "started": cur.get("startedAt", "")}
    d["open"] = sh("gh", "pr", "list", "-R", REPO, "--author", "@me", "--state", "open", "--json", "number", "--jq", "length", timeout=20)
    put("dev", d)


# ---- fleet context ----
def pane(target=""):
    p = target or os.environ.get("TMUX_PANE")
    out = sh("tmux", "display", "-p", "-t", p, "#S\t#I\t#W") if p else ""
    return (out.split("\t") + ["", "", ""])[:3]


def role_of(name, lead_flag, idx):
    if lead_flag or idx == "1":
        return "lead"
    for mark, role in (("🧙", "guru"), ("🫡", "svc"), ("🌙", "svc"), ("🧭", "svc"), ("🔵", "mate")):
        if name.startswith(mark):
            return role
    return ""


def main():
    args = sys.argv[1:]
    if args[:1] == ["--refresh"]:
        if args[1] == "gates":  # every /pr-state gate of every open PR, one ~10 s call
            raw = sh(f"{HOME}/.claude/pipeline-stamp.sh", "gates", timeout=90, env={**os.environ, "PR_GATES_JSON": "1"})
            return put("gates", json.loads(raw[raw.index("{"):])) if "{" in raw else None
        return refresh_pr(args[2], args[3]) if args[1] == "pr" else refresh_dev(args[2])
    lead_flag, explain = "--lead" in args, "--explain" in args
    target = args[args.index("--win") + 1] if "--win" in args[:-1] else ""
    cwd = next((a for a in args if not a.startswith("--") and a != target), os.getcwd())
    session, idx, name = pane(target)
    name = name.split("│", 1)[-1]  # window-state.py prefixes «<state>│»: the role is read from the window's own name
    more = []  # --explain: the full values a statusline has no room for
    if lead_flag and not session:  # the lead may run with no tmux env: the newest fleet board is its session
        session, idx, name = "", "1", "lead"
    role = role_of(name, lead_flag, idx)
    if not role or (session and not re.fullmatch(r"W\d+", session)):
        if explain:
            print("Це вікно не має ролі у флоті. Вкажи вікно: jb2b lead sl 3   (або W46:3, або lead)")
        return
    if session:
        os.environ["LEAD_SESSION"] = session
    sys.path.insert(0, f"{HOME}/.claude/scripts")
    import lead as L  # the ONE source of fleet state (/who, /mine, footer)

    if not os.path.isdir(L.WK):
        return
    S, WK = L.SESSION, L.WK
    win = f"{S}:{idx}"
    rows, _rest, ops, extra = L.fleet_rows()
    cached("gates", 180, ["gates"])  # keeps /tmp/claude/sl-gates.json fresh for the gates bar here and in the window names
    stamp = f"{CACHE}/sl-winstate-{S}.stamp"  # window names follow the same state as this line: refreshed at most every 20 s, by whichever window renders first
    if not explain and (not os.path.exists(stamp) or time.time() - os.path.getmtime(stamp) > 20):
        os.makedirs(CACHE, exist_ok=True)
        open(stamp, "w").close()
        subprocess.Popen([sys.executable, f"{HOME}/.claude/fleet-board/bin/window-state.py"], env={**os.environ, "LEAD_SESSION": S},
                         stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    st = L.blocked_by(rows, extra)
    me = next((r for r in rows if r["win"] == win), {})
    project = sh("git", "-C", cwd, "rev-parse", "--show-toplevel").rsplit("/", 1)[-1] or os.path.basename(cwd)

    def state_block():
        s = st.get(win, "")
        if not s:
            return ""
        mark, text = s.split(" ", 1)
        k = {"🙋": "r", "💬": "c", "🧭": "y", "🚂": "y", "⏸": "d", "🔄": "g", "💤": "g", "⏳": "y"}.get(mark, "w")
        src = me.get("step") if mark == "🔄" else (me.get("waiting") or me.get("step"))  # a working window says what it does, not what it waited for
        why = cut((src or "").replace("Чекаю на:", ""), 70)
        p = f"{WK}/progress/{idx}.md"
        age = f" {C['d']}· {mins(int((time.time() - os.path.getmtime(p)) / 60))}{R}" if os.path.exists(p) else ""
        more.append(f"стан повністю: {s} — {' '.join((src or '—').split())}")
        ic = L.win_icons({**me, "name": name}, mark) if me else {"want": "", "alarm": ""}  # same icons as the tmux window name
        return col(k, f"{mark}{ic['want']}{ic['alarm']} {text.lower()}:") + f" {why}{age}"

    def git_blocks(branch=None, wt_path=None):
        """project · branch · worktree · changed files — of `wt_path` when the PR branch is checked out somewhere, else of cwd"""
        path = wt_path or cwd
        br = branch or sh("git", "-C", path, "branch", "--show-current")
        top, common = sh("git", "-C", path, "rev-parse", "--show-toplevel"), sh("git", "-C", path, "rev-parse", "--path-format=absolute", "--git-common-dir")
        wt = f"{C['d']}[wt:{R}{col('o', os.path.basename(top))}{C['d']}]{R}" if top and common and not common.startswith(top) else ""
        dirty = len(sh("git", "-C", path, "status", "--porcelain").splitlines()) if (wt_path or not branch) else None
        return {"project": f"📁 {col('c', project)}", "branch": f"🌿 {col('g', br)}" if br else "", "wt": wt,
                "dirty": f"✏️ {col('o', dirty)}" if dirty is not None else ""}

    def queue_block(compact=False):
        if not st.get(win, "").startswith("🚂"):
            return ""
        n = sum(s.startswith("🚂") for s in st.values())
        return f"🚂 {col('y', n)}" if compact else f"🚂 у черзі на dev {col('y', n)}"

    lines = []
    if role == "lead":
        groups = []
        for mark, k in (("🙋", "r"), ("💬", "c"), ("🧭", "y"), ("🚂", "w"), ("⏳", "w"), ("⏸", "d"), ("🔄", "g"), ("💤", "d")):
            wins = [w.split(":")[1] for w, s in st.items() if s.startswith(mark)]
            if wins:
                # Mike 19.11 picked variant B: «🙋3 [5 8 9]» — bold white numbers in dim brackets, colour only on the icon (paused/free stay grey)
                nums = " ".join(f"{E}[1m{C['d' if k == 'd' else 'w']}{w}{R}" for w in wins)
                groups.append(col(k, f"{mark}{len(wins)}") + f" {C['d']}[{R}{nums}{C['d']}]{R}")
        l1 = [col("w", "👑 LEAD") + f" {C['d']}{S}{R}", f"📁 {col('c', project)}", f" {C['d']}|{R} ".join(groups), f"👥{len(st)}"]
        dev = cached("dev", 60, ["dev", cwd])
        devb = ""
        if dev.get("branch"):
            what = col("o", f"#{dev['pr']}") if dev.get("pr") else col("o", cut(dev["branch"], 28))
            if dev.get("live"):
                devb = f"🚂 dev {what} 🟢"
            else:
                try:
                    el = time.time() - time.mktime(time.strptime(dev["started"], "%Y-%m-%dT%H:%M:%SZ")) + time.timezone
                    pct = max(0, min(99, int(el * 100 / 280)))
                    devb = f"🚂 dev {what} 🟡 {col('y', 'deploying')} {col('y', f'{pct}%')}"
                except (ValueError, KeyError):
                    devb = f"🚂 dev {what} 🟡 {col('y', 'deploying')}"
        lock = "/tmp/b2b-dev-fixture.lock.d"
        lockb = f"🧪 {col('r', '🔒 ' + (L.age(lock) or ''))}" if os.path.isdir(lock) else f"🧪 {col('g', '✓')}"
        rem = [re.sub(r"^\S+\s+\[active\]\s*", "", x) for x in sh(f"{HOME}/.claude/reminders.sh", "list").splitlines()
               if "[active]" in x and not x.startswith("lead-commands")]
        remb = f"{cut(rem[0], 44)} {C['d']}+{len(rem) - 1}{R}" if len(rem) > 1 else (cut(rem[0], 60) if rem else "")
        now, _lead_wait, _later = L.blocker_groups(rows, extra)
        plans = sum(len(r["plans"]) for r in rows)
        stuck = sum(bool(L.needs_input(w) or L.unanswered(w)) for w in L.windows())
        eta = next((f for f in ops if re.search(r"\d{1,2}:\d{2}|\d+\s*(хв|г)\b", f[4] or "")), None)  # only a real time counts as a forecast
        tries = L.mike_tries(rows)
        ready = [f"{C['d']}[{R}{E}[1m{C['w']}{w.split(':')[1]}{R}{C['d']}]{R} {col('g', rec or '#' + str(n))}" for w, n, rec, ok, _ in tries if ok]
        wait = [f"{w.split(':')[1]}→{nx}" for w, n, rec, ok, nx in tries if not ok]
        tryb = (f"🧪 твої проби: {' '.join(ready)}" if ready else "") + (f" {C['d']}ще не готові: {' '.join(wait)}{R}" if wait else "")
        more += [f"проба: {w} PR#{n} — {'ГОТОВА: jb2b ' + rec if ok and rec else 'готова, але рецепта нема в preflight-map.tsv' if ok else 'ще не готова, спершу гейт ' + nx}" for w, n, rec, ok, nx in tries]
        l3 = [tryb.strip(), f"⏱ далі: {cut(eta[0], 30)} {col('c', eta[4])}" if eta else "",
              col("r", f"🙋{len(now)}") if now else "", f"📋{col('y', plans)}" if plans else "", f"🧱{col('r', stuck)}" if stuck else "",
              f"🔀{col('o', dev['open'])}" if dev.get("open") else ""]
        etab = ""
        if os.path.exists(f"{WK}/eta-wake.on"):  # Mike 20.11: «якщо вона ввімкнена — вона має бути в статуслайні»
            free = sh("python3", f"{HOME}/.claude/fleet-board/bin/eta-free.py", f"{WK}/tracks.tsv", f"{WK}/night-audit-state.tsv", "--short")
            etab = col("c", "⏰ ETA ON") + (f" · {cut(free.replace(', якщо все піде за планом', ''), 48)}" if free else "")
        lines = [l1, [devb, lockb, col("y", f"🔔{len(rem)}") if rem else "", remb], [etab] + l3 if etab else l3]
        ids = [["role", "project", "whowin", "agents"], ["dev", "lock", "remcount", "remtext"], ["mytries", "forecast", "mikeq", "plansq", "stuckq", "openprs"]]
        more += [f"нагадування {k + 1}: {x}" for k, x in enumerate(rem)] + [f"дія від тебе: {x} → вікна {', '.join(w) or '—'}" for x, w in now]
        more.append(f"dev: гілка {dev.get('branch', '?')}, PR {dev.get('pr') or '— (train або без PR)'}, {'deploy завершено' if dev.get('live') else 'deploy триває'}")

    elif role == "mate":
        tid = (re.search(r"PUN-\d+", name) or [""])[0]
        title = cut(re.sub(r"^🔵\s*|PUN-\d+\s*·?\s*|\(plan\)", "", name), 40)
        prio = ""
        for ln in open(f"{WK}/priorities.tsv", encoding="utf-8").read().splitlines() if os.path.exists(f"{WK}/priorities.tsv") else []:
            f = ln.split("\t")  # last row per ticket wins
            if f[0] == tid and len(f) > 1 and re.search(r"\d+", f[1]):
                prio = re.search(r"\d+", f[1])[0]
        linear = ""
        for ln in open(f"{WK}/tickets.tsv", encoding="utf-8").read().splitlines() if os.path.exists(f"{WK}/tickets.tsv") else []:
            f = ln.split("\t")
            if f[0] == tid and len(f) > 1:
                linear = f"◷ {col('c', re.sub(r' *\(.*', '', f[1]))}"
        l1 = [col("w", "🔵 TEAMMATE") + f" {C['d']}{win}{R}", col("w", tid) + (f" {title}" if title else ""),
              f"⭐ {col('y', prio)}" if prio else "", state_block(), linear]
        prs = [ln.split("\t")[0] for ln in open(f"{WK}/pr-windows.tsv").read().splitlines() if ln.split("\t")[1:2] == [win]] if os.path.exists(f"{WK}/pr-windows.tsv") else []
        known = [d for d in (cached(f"pr-{n}", 120, ["pr", n, cwd]) for n in reversed(prs)) if d.get("state")]
        pr = next((d for d in known if d["state"] == "OPEN"), None)
        if pr is None and prs and "(plan)" not in name:  # nothing open: the newest PR with its real state (merged) — or just its number while the cache is cold
            pr = known[0] if known else {"number": prs[-1]}
        if pr:
            head = pr.get("headRefName", "")
            wt_path = ""
            for blk in sh("git", "-C", cwd, "worktree", "list", "--porcelain").split("\n\n"):
                if head and f"branch refs/heads/{head}" in blk:
                    wt_path = blk.splitlines()[0].removeprefix("worktree ")
            g = git_blocks(head, wt_path)
            state = {"OPEN": f"🟢 {col('g', 'open')}", "MERGED": f"🟣 {col('p', 'merged')}", "CLOSED": f"🔴 {col('r', 'closed')}"}.get(pr.get("state"), "")
            if pr.get("isDraft"):
                state = f"📝 {C['d']}draft{R}"
            ab = ""
            if wt_path and head:
                lr = sh("git", "-C", wt_path, "rev-list", "--left-right", "--count", f"origin/{head}...HEAD").split()
                ab = f"{col('g', '↑' + lr[1])} {col('r', '↓' + lr[0])}" if len(lr) == 2 else ""
            gates, nxt = [], ""
            pf = f"{HOME}/.claude/pipeline-state/pipeline-{head.replace('/', '-')}.json"
            if head and os.path.exists(pf):
                steps = json.load(open(pf)).get("steps", {})
                for key, lab in (("code-review", "CR"), ("ponytail", "PT"), ("review-pr", "RPR"), ("just-test", "JT"), ("just-fe", "FE"), ("demo", "DEMO")):
                    s = steps.get(key, {})
                    ago = sh("git", "-C", cwd, "rev-list", "--count", "--first-parent", "--no-merges", f"{s['head']}..origin/{head}") if s.get("done") and s.get("head") else ""
                    if s.get("done") and ago.isdigit() and int(ago) > 0:
                        gates.append(col("y", f"{lab}✓-{ago}"))
                    elif s.get("done"):
                        gates.append(col("g", f"{lab}✓"))
                    else:
                        gates.append(f"{C['d']}{lab}·{R}")
                    if not nxt and not gates[-1].startswith(C["g"]):
                        nxt = lab
            gp = L.gate_progress(pr["number"]) if pr.get("state") == "OPEN" else None
            if gp:  # all /pr-state gates instead of the 6 local stamps: bar, count, each gate, the next one
                mk = {"✓": lambda g: col("g", f"{g}✓"), "✗": lambda g: col("r", f"{g}✗")}
                gates = [f"{col('c', str(gp['pct']) + '%')} {C['d']}{gp['done']}/{gp['total']}{R}"] + [mk.get(c, lambda g: f"{C['d']}{g}·{R}")(g) for g, c in gp["cells"]]
                nxt = gp["next"]
            rec, tryb = L.try_of(pr["number"]), ""
            if gp and dict(gp["cells"]).get("MIKE") == "✗":  # the PR still needs Mike's try: say which one and whether it is time
                tryb = (f"🧪 {col('g', '✅ твоя проба: jb2b ' + rec)}" if gp["next"] == "MIKE" and rec else f"🧪 {col('g', '✅ готова до твоєї проби')}" if gp["next"] == "MIKE"
                        else f"🧪 {C['d']}⏳ проба {rec or ''} ще не готова: спершу {gp['next']}{R}")
            deploy = {"deploying": f"🟡 {col('y', 'deploying')}", "deployed": f"🟢 {col('g', 'deployed')}", "failed": f"🔴 {col('r', 'deploy failed')}"}.get(pr.get("deploy"), "")
            age = sh("git", "-C", cwd, "log", "-1", "--format=%cr", f"origin/{head}") if head else ""
            age = re.sub(r" (minute|hour|day|week|month)s? ago", lambda m: m.group(1)[0] + " ago", age).replace("mo ago", "mo ago")
            l2 = [f"🔀 {col('o', link(f'https://github.com/{REPO}/pull/{pr['number']}', f'PR#{pr['number']}'))} {state}".rstrip(), ab,
                  ("🧭 " + " ".join(gates) + (f" {C['d']}➜{R}{col('w', nxt)}" if nxt else "")) if gates else "", tryb, queue_block(), deploy,
                  f"🕐 {C['d']}{age}{R}" if age else "", col("r", "⚠conflict") if pr.get("mergeable") == "CONFLICTING" else ""]
            l3 = [g["project"], g["branch"], g["wt"], g["dirty"],
                  f"main {col('r' if pr['behind'] else 'g', '↓' + str(pr['behind']))}" if pr.get("behind") is not None else "",
                  f"{col('g', '+' + str(pr['additions']))} {col('r', '−' + str(pr['deletions']))}" if "additions" in pr else ""]
            ids = [["role", "ticket", "prio", "state", "linear"], ["pr", "ab", "gates", "mytries", "queue", "deploy", "age", "conflict"],
                   ["project", "branch", "wt", "dirty", "behind", "difflines"]]
            more.append(f"PR цього вікна: {', '.join('#' + n for n in prs)} · показано #{pr['number']} · mergeable {pr.get('mergeable', '?')} · worktree {wt_path or '— (гілка ніде не розгорнута)'}")
        else:  # plan teammate: the gate is the plan
            card = next((p for p in (f"{WK}/tiki-notes/win-{idx}.md", f"{WK}/tiki-notes/{tid.lower().replace('-', '')}.md") if os.path.exists(p)), "")
            text = open(card, encoding="utf-8").read() if card else ""
            vp = (re.search(r"Visual plan:\s*(http\S+)", text) or [None, ""])[1]
            approved = os.path.exists(f"{L.FB}/plan-approvals.tsv") and any(ln.split("\t")[0] == tid for ln in open(f"{L.FB}/plan-approvals.tsv", encoding="utf-8").read().splitlines())
            qs = re.findall(r"^#{2,4}\s*(Q\d+)\b", text, re.M)
            ok = lambda b: col("g", "✓") if b else f"{C['d']}·{R}"  # noqa: E731
            l2 = [f"📋 PLAN card {ok(card)} VP {ok(vp)} " + (col("g", "✅ план так") if approved else f"{C['d']}➜{R}{col('w', 'план так')}"),
                  f"питань до Mike {col('y', len(qs))} {C['d']}({' '.join(qs[:6])}){R}" if qs else "",
                  " ".join(x for x in (f"🔗 {col('b', link('file://' + card, 'card'))}" if card else "", f"🖼 {col('b', link(vp, 'VP'))}" if vp else "") if x)]
            g = git_blocks()
            age = sh("git", "-C", cwd, "log", "-1", "--format=%cr")
            l3 = [g["project"], g["wt"], g["branch"], g["dirty"], queue_block(compact=True), f"🕐 {C['d']}{age}{R}" if age else ""]
            ids = [["role", "ticket", "prio", "state", "linear"], ["plan", "questions", "links"], ["project", "wt", "branch", "dirty", "queue", "age"]]
            more += [f"card: {card or '—'}", f"Visual plan: {vp or '—'}"]
        lines = [l1, l2, l3]

    else:  # guru / service windows
        p = f"{WK}/progress/{idx}.md"
        prog = open(p, encoding="utf-8").read().splitlines() if os.path.exists(p) else []
        badge = {"guru": "🧙 GURU"}.get(role) or cut(name, 26).upper()
        l1 = [col("w", badge) + f" {C['d']}{win}{R}", f"📁 {col('c', project)}" if role == "guru" else "", state_block()]
        if role == "guru":
            wait = next((x for x in reversed(prog) if x.startswith("Чекаю на")), "")
            verdict = (re.search(r"\((.+)\)\s*$", wait) or [None, ""])[1]
            lastfile = next((x.split(":", 1)[1].strip() for x in reversed(prog) if x.startswith("Файл:")), "")
            l2 = [f"📨 {col('w', cut(verdict, 110))}" if verdict else "", f"📝 {col('c', os.path.basename(lastfile))}" if lastfile else ""]
        else:
            last = next((x for x in reversed(prog) if x.strip() and not x.startswith("Чекаю на")), "")
            l2 = [cut(last, 140)]
        lines = [l1, l2]
        ids = [["role", "project", "state"], ["verdict", "lastfile"] if role == "guru" else ["result"]]

    if not explain:
        print("\n".join(DOT.join(b for b in ln if b) for ln in lines if any(ln)))
        return
    plain = lambda x: re.sub(r"\033\[[0-9;]*m|\033\]8;;[^\a]*\a", "", x)  # noqa: E731
    print(f"📍 {win} · {name} · роль: {ROLE_NAME.get('plan' if role == 'mate' and 'plan' in ids[1] else role, role)}\n")
    for n, (ln, lid) in enumerate(zip(lines, ids), 1):
        print(f"РЯДОК {n}")
        for b, i in zip(ln, lid):
            title, text = DESC[i]
            print(f"  {plain(b) if b else '(зараз не показано)'}\n      ↳ {title}: {text}")
    print(f"РЯДОК {len(lines) + 1} · спільний для всіх ролей")
    for i in ("model", "ctx", "u5", "u7", "renew", "cost", "sess"):
        print(f"  {DESC[i][0]}: {DESC[i][1]}")
    print("\nДЕТАЛЬНІШЕ")
    for x in more:
        print(f"  {x}")
    q = [w for w, v in st.items() if v.startswith("🚂")]
    by = {r["win"]: r for r in rows}
    print(f"  черга на dev ({len(q)}): " + ("; ".join(f"{w} — {cut((by[w].get('waiting') or '').replace('Чекаю на:', ''), 90)}" for w in q) or "порожня"))
    print("\nХТО НА КОГО ЧЕКАЄ (те саме, що /who)")
    L.cmd_who()


ROLE_NAME = {"lead": "лід", "mate": "PR teammate", "plan": "plan teammate", "guru": "guru", "svc": "сервісне вікно"}
DESC = {
    "role": ("роль і вікно", "хто це; береться з назви tmux-вікна, тому не залежить від номера"),
    "project": ("проєкт", "назва каталогу репозиторію"),
    "whowin": ("/who з номерами вікон", "групи /who і номери вікон у кожній: 🙋 БЛОКЕР на тобі: вікно стоїть, доки ти не зробиш дію чи не даси рішення · 💬 прохання до тебе: просить глянути, але не стоїть через це · 🧭 чекають на ЛІДА (лід має відповісти, "
               "передати твоє рішення або дати dev) · 🚂 чекають своєї черги на спільний dev · ⏳ чекають на інше вікно · ⏸ на паузі · 🔄 працюють · 💤 вільні"),
    "agents": ("кількість агентів", "скільки вікон teammates у сесії"),
    "dev": ("dev slot", "що зараз на спільному dev: PR або train-гілка; 🟢 deploy завершено, 🟡 deploy триває з оцінкою у %"),
    "lock": ("lock проб", "🧪 ✓ — dev вільний для проби; 🔒 з часом — проба вже йде стільки хвилин, другу не запускати"),
    "remcount": ("лічильник нагадувань", "скільки твоїх нагадувань активні (без технічного «lead-commands»)"),
    "remtext": ("текст нагадувань", "перше нагадування і «+N» решти; повний список — нижче в «Детальніше»"),
    "forecast": ("прогноз наступного кроку", "найближча операція з часом; показується лише коли в треках записано справжній час"),
    "mikeq": ("дії від тебе", "🙋N — скільки окремих дій чи рішень зараз чекають на тебе і вже блокують вікно, що стоїть"),
    "plansq": ("плани на апрув", "📋N — скільки планів чекають твого «план так»"),
    "stuckq": ("застряглі вікна", "🧱N — вікна, що стоять на запиті дозволу або мають звіт «🙋 LEAD», на який лід ще не відповів (те, що рахує /stuck)"),
    "openprs": ("відкриті PR", "🔀N — скільки твоїх PR відкрито в репозиторії"),
    "mytries": ("твої проби", "проби, які маєш прогнати ти: ✅ готова — усі гейти до MIKE зелені, агент уже прогнав її на цьому dev, поруч команда; "
                "⏳ ще не готова — названо гейт, який треба пройти спершу. У ліда: номери вікон з готовими пробами і окремо «ще не готові»"),
    "ticket": ("тікет", "ім'я teammate: тікет і його суть із назви вікна"),
    "prio": ("бал пріоритету", "бал тікета у спринті 0–100 з priorities.tsv"),
    "state": ("стан із /who", "на кого вікно чекає, причина з рядка «Чекаю на» його progress-файлу і скільки хвилин цей рядок не мінявся. "
              "🚂 черга dev = вікно готове до проби, але спільний dev один: чекає, поки лід або deputy скаже «dev твій»"),
    "linear": ("статус у Linear", "зі спринтового tickets.tsv; оновлюється синком спринту, не наживо"),
    "pr": ("PR", "відкритий PR цього вікна з pr-windows.tsv (клікабельний) і його стан"),
    "ab": ("незапушені коміти", "↑ комітів локально попереду origin, ↓ позаду; лише коли гілка PR розгорнута у worktree"),
    "gates": ("гейти /pr-state", "кроки pipeline цього PR: зелений ✓ зроблено, жовтий ✓-N зроблено N комітів тому (застаріло), · ще ні; ➜ наступний крок"),
    "queue": ("черга на dev", "показується лише коли ЦЕ вікно чекає на dev; число — скільки вікон чекає разом із ним (не позиція: готового джерела позиції нема)"),
    "deploy": ("deploy", "стан deploy head-коміту цього PR на dev"),
    "age": ("вік останнього коміту", "як давно зроблено останній коміт гілки"),
    "conflict": ("конфлікт merge", "з'являється лише коли PR конфліктує з main"),
    "branch": ("гілка", "для PR teammate — гілка його PR; для plan teammate — гілка спільного checkout"),
    "wt": ("worktree", "у якому worktree розгорнута гілка"),
    "dirty": ("змінені файли", "скільки файлів змінено і не закомічено у цьому worktree"),
    "behind": ("позаду main", "на скільки комітів main попереду гілки PR; перед твоєю пробою має бути 0"),
    "difflines": ("розмір PR", "рядки, додані й видалені цим PR"),
    "plan": ("гейт плану", "чи написана card, чи є Visual plan, і чи ти сказав «план так»"),
    "questions": ("питання до тебе", "скільки питань Q1…Qn у card чекає твоєї відповіді"),
    "links": ("посилання", "короткі клікабельні мітки card і Visual plan; адреси — нижче в «Детальніше»"),
    "verdict": ("останній вердикт", "остання відповідь guru, з дужок рядка «Чекаю на» його progress-файлу"),
    "lastfile": ("останній файл", "файл, який guru записав останнім (рядок «Файл:» у progress)"),
    "result": ("останній результат", "останній рядок progress-файлу сервісного вікна"),
    "model": ("🤖 модель", "модель цієї сесії"),
    "ctx": ("🪙 контекст", "використані токени з вікна контексту і відсоток: бірюзовий до 50%, жовтий 50–79%, червоний від 80%"),
    "u5": ("⏱ 5h", "витрата підписки у 5-годинному вікні: смужка, %, токени, темп (~1.00x = рівно в ліміт до скидання), @час скидання"),
    "u7": ("📅 7d", "те саме для 7-денного вікна; «~4d left» — на скільки днів вистачить за поточного темпу"),
    "renew": ("💳", "днів до поновлення підписки"),
    "cost": ("💵", "вартість цієї сесії за звітом Claude Code"),
    "sess": ("⏲", "скільки годин минуло від старту цієї сесії"),
}


if __name__ == "__main__":
    try:
        main()
    except Exception:  # a broken role line must never blank the statusline: print nothing → the default renders
        if os.environ.get("SL_DEBUG"):
            raise
