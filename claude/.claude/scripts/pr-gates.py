#!/usr/bin/env python3
"""pr-gates.py — /pr-state verdicts: reads `pipeline-stamp.sh _fleet_rows` TSV on stdin, prints ONE table, one verdict per PR.

Rules (Mike 2026-10-20):
  1. Exactly one verdict per PR: ✅ МЕРДЖ · 🙋 ТИ (only Mike's try/approval missing) · 🔴 СТОП (first failing gate + one action) · ⏸ пауза.
  2. Eleven gates in a fixed order; ✅ only when all pass: PLAN CI MRG MAIN CR PT 🐛 TRY PRE JT MIKE.
  3. A gate that cannot be checked counts as failed. MAIN = behind 0, no threshold.
Called as: pipeline-stamp.sh gates   (rows come from the same _fleet_rows as `fleet`, so the data has one source).
"""
import glob
import json
import os
import re
import subprocess
import time
import sys
import unicodedata

REPOS = {"rescue-serverless": "back2back-team/rescue-serverless", "workflow-engine": "back2back-team/workflow-engine"}
GATES = ["PLAN", "CI", "MRG", "MAIN", "CR", "PT",  # SMP dropped (Mike 11.11: duplicated PT)
         "🐛", "TRY", "PRE", "JT", "MIKE"]
DEMO_GATES = {"TRY", "PRE", "MIKE", "JT"}  # rescue-serverless only (the DEMO gate and tries exist there)
# Mike 2026-10-21: he reads + approves the plan before implementation; PRs opened before the rule are not checked
PLAN_FILE = os.path.expanduser("~/.claude/fleet-board/plan-approvals.tsv")
PLAN_SINCE = {"rescue-serverless": 2380, "workflow-engine": 78}
# Mike 03.11: optional UI demo — a just recipe that opens the browser and shows the change in the UI, when the task has one.
UI_FILE = os.path.expanduser("~/.claude/fleet-board/ui-demos.tsv")   # pr<TAB>recipe or -<TAB>what it shows
JUSTFILE = os.path.expanduser("~/code/b2b/rescue-serverless/backend/src/lambdas/api/fast/justfile.v2")
_ui, _recipes = None, None


def ui_cell(num, repo_short):
    """✓ demo recipe exists · ✗ PR needs a UI demo but it is missing · · not a UI task (info only, not a gate)."""
    global _ui, _recipes
    if repo_short != "rescue-serverless":
        return "·"
    if _ui is None:
        rows = [ln.split("\t") for ln in open(UI_FILE, encoding="utf-8").read().splitlines() if ln.strip() and not ln.startswith("#")] if os.path.exists(UI_FILE) else []
        _ui = {r[0].lstrip("#"): (r[1].strip() if len(r) > 1 else "-") for r in rows}
    rec = _ui.get(str(num))
    if rec is None:
        return "·"
    if rec in ("", "-"):
        return "✗"
    if _recipes is None:
        out = subprocess.run(["just", "--justfile", JUSTFILE, "--summary"], capture_output=True, text=True).stdout
        _recipes = set(out.split())
    return "✓" if rec.split()[0] in _recipes else "✗"


LOCALS = {"rescue-serverless": "~/code/b2b/rescue-serverless", "workflow-engine": "~/code/b2b/workflow-engine"}
DEMO_DIR = os.path.expanduser(os.environ.get("DEMO_RESULT_DIR", "~/.claude/demo-results"))
FIXTURE_SINCE = "2026-11-09T12:45:00Z"  # Mike 09.11 (grill c): PRE runs finished earlier have no fixture_alerts_before and stay valid
_dev_cache = {}


def contains(repo_short, head, sha):
    """True when `sha` (a dev build) contains the PR HEAD — unknown sha/head counts as no."""
    if not head or not sha:
        return False
    git = ["git", "-C", os.path.expanduser(LOCALS[repo_short])]
    if subprocess.run(git + ["merge-base", "--is-ancestor", head, sha], capture_output=True).returncode == 0:
        return True
    # head = merge-main commits on top of what dev has (pull-main after the train): merging it into dev changes nothing
    mt = subprocess.run(git + ["merge-tree", "--write-tree", sha, head], capture_output=True, text=True)
    tree = subprocess.run(git + ["rev-parse", f"{sha}^{{tree}}"], capture_output=True, text=True)
    return mt.returncode == 0 and mt.stdout.split("\n")[0] == tree.stdout.strip()


def dev_deploy_sha(repo):
    """Last successful dev deploy sha (the build a train/main deploy put on dev); '' when unreadable."""
    if repo not in _dev_cache:
        wf = "0. Backend Infrastructure Deploy" if repo.endswith("rescue-serverless") else "0. Deploy Backend (dev)"
        _dev_cache[repo] = (gh("run", "list", "-R", repo, "--workflow", wf, "-L", "20", "--json", "headSha,conclusion,updatedAt",
                               "-q", '[.[]|select(.conclusion=="success")]|sort_by(.updatedAt)|last|.headSha // ""') or "").strip()
    return _dev_cache[repo]


def demo_ok(num, head, repo_short, mike=False):
    """PRE (agent file) / MIKE (.mike file) is valid only if its dev build contains the PR head; PRE also needs a quiet fixture org."""
    try:
        d = json.load(open(f"{DEMO_DIR}/pr-{num}{'.mike' if mike else ''}.json"))
    except (OSError, ValueError):
        return False
    if not contains(repo_short, head, d.get("dev_sha", "")):
        return False
    if mike:
        return True
    n = d.get("fixture_alerts_before")
    return n == 0 if n is not None else d.get("finished", "") < FIXTURE_SINCE


def plan_approved():
    """Linear ids Mike approved a plan for (written by fleet-board/bin/plan-approve.sh)."""
    try:
        return {ln.split("\t")[0] for ln in open(PLAN_FILE) if ln.strip()}
    except OSError:
        return set()


def gh(*args):
    # one retry: ~30 gh calls per run, and a single rate-limit/network blip silently emptied a whole block (22.10 «ЗРОБЛЕНО»)
    for attempt in (1, 2):
        try:
            r = subprocess.run(["gh", *args], capture_output=True, text=True, timeout=60)
        except subprocess.TimeoutExpired:
            continue
        if r.returncode == 0:
            return r.stdout
        if attempt == 1:
            time.sleep(2)
    return None


def width(s):
    return sum(0 if unicodedata.combining(c) or c == "️" else 2 if unicodedata.east_asian_width(c) in "WF" else 1 for c in s)


def pad(s, n):
    s = s if width(s) <= n else s[: max(n - 1, 1)] + "…"
    while width(s) > n:
        s = s[:-2] + "…"
    return s + " " * (n - width(s))


def _week(path):
    m = re.search(r"/w(\d+)/", path)
    return int(m.group(1)) if m else 0


def paused():
    """Union of the two newest sprint boards' pause lists (older boards keep stale entries)."""
    files = sorted(glob.glob(os.path.expanduser("~/.claude/fleet-board/w[0-9]*/state.json")),
                   key=_week)[-2:]
    out = set()
    for f in files:
        try:
            out |= {int(x) for x in json.load(open(f)).get("paused", [])}
        except (OSError, ValueError):
            pass
    return out


def boards():
    """The two newest sprint boards, oldest first."""
    return sorted(glob.glob(os.path.expanduser("~/.claude/fleet-board/w[0-9]*/")), key=_week)[-2:]


def paused_branches():
    """Branch prefixes paused by Mike (state.json `paused_branches` on the two newest boards)."""
    out = set()
    for b in boards():
        try:
            out |= set(json.load(open(b + "state.json")).get("paused_branches", []))
        except (OSError, ValueError):
            pass
    return out


def merged_this_week(repo):
    """My PRs merged since Monday (sprint week): [(number, title)]."""
    from datetime import date, timedelta
    monday = date.today() - timedelta(days=date.today().weekday())
    raw = gh("pr", "list", "-R", repo, "--state", "merged", "--author", "@me", "-L", "100",
             "--search", f"merged:>={monday}", "--json", "number,title")
    if raw is None:  # never show a silently empty «done» list — say it could not be read
        return [(0, f"⚠ не вдалося прочитати змерджені PR {repo} — перезапусти /pr-state all")]
    return [(r["number"], r["title"]) for r in json.loads(raw) if not r["title"].startswith("REVIEW:")]


def planned():
    """Open tracks of the newest board: last row per track whose status is not done → 'track · step (pct%)'."""
    b = boards()
    try:
        rows = [r.split("\t") for r in open(b[-1] + "tracks.tsv").read().splitlines() if r.strip()] if b else []
    except OSError:
        return []
    last = {}
    for r in rows:
        last[r[0]] = r  # insertion order = operation order, so the last row is the current state
    return [f"{t} · {r[3] if len(r) > 3 else ''} ({r[2] or 0}%)" + (" ⛔" if r[1] == "block" else "")
            for t, r in last.items() if len(r) > 1 and r[1] != "done"]


def open_prs(repo):
    """number → {title, branch} for my open PRs, plus branch → number for every open PR (mirror lookup)."""
    raw = gh("pr", "list", "-R", repo, "--state", "open", "-L", "200", "--json", "number,title,headRefName,headRefOid,author,files,reviewDecision")
    rows = json.loads(raw) if raw else []
    by_branch = {r["headRefName"]: r["number"] for r in rows}
    # Mike 22.10 «я бекенд розробник, FE-проба не для мене»: an FE-only PR is reviewed by the FE dev, not tried by Mike
    return {r["number"]: {"title": r["title"], "branch": r["headRefName"], "head": r["headRefOid"], "review": r.get("reviewDecision") or "",
                          "fe_only": bool(r.get("files")) and all(f["path"].startswith("frontend/") for f in r["files"])}
            for r in rows}, by_branch


def bugbot_open(repo, mirror):
    """Unresolved Bugbot review threads on the mirror PR; None when it cannot be read."""
    owner, name = repo.split("/")
    q = ('query($o:String!,$n:String!,$p:Int!){repository(owner:$o,name:$n){pullRequest(number:$p){'
         'reviewThreads(first:100){nodes{isResolved comments(first:1){nodes{author{login}}}}}}}}')
    raw = gh("api", "graphql", "-f", f"query={q}", "-F", f"o={owner}", "-F", f"n={name}", "-F", f"p={mirror}")
    if not raw:
        return None
    nodes = json.loads(raw)["data"]["repository"]["pullRequest"]["reviewThreads"]["nodes"]
    return sum(1 for t in nodes if not t["isResolved"]
               and any("cursor" in (c["author"] or {}).get("login", "") for c in t["comments"]["nodes"]))


def gates_of(row, repo_short, bug, num, plans, fe_only=False, review="", head=""):
    """row: _fleet_rows fields → {gate: (ok, note)}."""
    badges = dict(re.findall(r"(CR|SMP|PT|JT|FE)(\S+)", row["badges"]))
    ci = dict(re.findall(r"([✓✗⏳↷])(\d+)", row["ci"]))
    try_pm = row["try"].split()
    recipe = try_pm[0] if try_pm else "-"
    pre, mike = (try_pm[1].split("/") + ["·", "·"])[:2] if len(try_pm) > 1 else ("·", "·")
    behind = row["behind"]
    g = {}
    if num < PLAN_SINCE[repo_short]:
        g["PLAN"] = (None, "PR до правила плану")
    else:
        g["PLAN"] = (row["linear"] in plans or f"#{num}" in plans, f"Mike: прочитай і апрувни план {row['linear']} → plan-approve.sh")
    # Mike 09.11 (grill a): «✓0» = no check ran, not green — needs a real green check or a green dev deploy that contains the head
    ran = int(ci.get("✓", 0)) > 0 or contains(repo_short, head, dev_deploy_sha(REPOS[repo_short]))
    g["CI"] = (int(ci.get("✗", 0)) == 0 and int(ci.get("⏳", 0)) == 0 and ran,
               f"CI ✓{ci.get('✓', '?')} ✗{ci.get('✗', '?')} ⏳{ci.get('⏳', '?')}" + ("" if ran else " — жодна перевірка не бігла"))
    g["MRG"] = (row["mergeable"] == "MERGEABLE", f"mergeable={row['mergeable']}")
    # Mike 04.11 «нащо робити train а потім мерджити і робити новий»: behind main without conflicts is no blocker —
    # trains are built from fresh origin/main and GitHub merges a CLEAN behind PR; conflicts are the MRG gate
    g["MAIN"] = (behind == "0" or row["mergeable"] == "MERGEABLE", f"behind {behind}" + (" (без конфліктів — ок)" if behind != "0" else ""))
    for k, name in (("CR", "requesting-code-review + /code-review high"), ("PT", "/ponytail-review")):  # PT: Mike 04.11
        b = badges.get(k, "·")
        g[k] = (b == "✓", f"{name} " + ("не робився" if b == "·" else f"застарів ({b[2:]} коміт. після)" if b.startswith("✓-") else f"не перевіряється ({b})"))
    if repo_short == "workflow-engine":
        g["🐛"] = (None, "Bugbot не підключений у workflow-engine")  # no mirrors, no check-run (checked 2026-10-20)
    else:
        g["🐛"] = (bug == 0, "Bugbot не прочитано" if bug is None else f"{bug} відкр. тредів Bugbot")
    if repo_short == "rescue-serverless" and fe_only:
        for k in ("TRY", "PRE", "JT"):
            g[k] = (None, "FE-only PR — н/з")
        g["MIKE"] = (review == "APPROVED", "рев'ю FE dev на GitHub (FE-only PR, не твоя проба)")
    elif repo_short == "rescue-serverless":
        jt = badges.get("JT", "·")
        g["TRY"] = (recipe not in ("no-try", "-"), "немає проби → try + рядок preflight-map")
        g["MIKE"] = (mike == "✓" and demo_ok(num, head, repo_short, mike=True), f"твоя проба jb2b {recipe} + апрув на dev-збірці з поточним head")
        # Mike's own passing run on a build that contains the head supersedes an older agent preflight (13.11: #2496 PRE ✗ after pull-main)
        g["PRE"] = ((pre == "✓" and demo_ok(num, head, repo_short)) or g["MIKE"][0],
                    "preflight агента не ✓ на dev-збірці, що містить поточний head (або фікстура була не порожня)")
        g["JT"] = (jt in ("✓", "✓c"), "/just-test " + ("не робився" if jt == "·" else f"застарів ({jt})"))
    else:
        for k in DEMO_GATES:
            g[k] = (None, "н/з для engine")
    return g


def main():
    lines = [ln.rstrip("\n").split("\t") for ln in sys.stdin if ln.strip()]
    if not lines:
        sys.exit("pr-gates: no rows from _fleet_rows")
    head, rows = lines[0], [dict(zip(["pr", "linear", "badges", "behind", "ci", "try", "mergeable", "deploy", "train", "local"], r)) for r in lines[1:]]
    _ = head
    stop_paused = paused()
    plans = plan_approved()
    meta, mirrors = {}, {}
    for short, repo in REPOS.items():
        meta[short], mirrors[short] = open_prs(repo)

    out = {"✅": [], "🙋": [], "🔴": [], "⏸": []}
    paused_rows = []
    local_only = []
    for r in rows:
        m = re.match(r"#(\d+) (\S+)", r["pr"])
        if not m:
            local_only.append(r)
            continue
        num, short = int(m.group(1)), m.group(2)
        repo = REPOS[short]
        info = meta[short].get(num, {"title": "?", "branch": ""})
        if info["title"].startswith("REVIEW:") or info["branch"].endswith("-review"):
            continue  # Bugbot mirror — its threads are counted on the original
        mirror = mirrors[short].get(info["branch"] + "-review")
        bug = bugbot_open(repo, mirror) if mirror else bugbot_open(repo, num)
        g = gates_of(r, short, bug, num, plans, info.get("fe_only", False), info.get("review", ""), info.get("head", ""))
        failed = [k for k in GATES if g[k][0] is False]
        cells = [("✓" if g[k][0] else "·" if g[k][0] is None else "✗") for k in GATES]
        cells.append(dict(re.findall(r"(FE)(\S+)", r["badges"])).get("FE", "·")[:1])  # info only (Mike 21.10): just-fe posted?
        cells.append(ui_cell(num, short))  # info only (Mike 03.11): browser UI demo recipe, if the task has UI
        # Mike 19.11 «Mike це останній gate — спершу агент … запушити just-test та just-fe»: no 🙋 before just-fe is posted
        if short == "rescue-serverless" and not info.get("fe_only", False) and cells[len(GATES)] != "✓" and "MIKE" in failed:
            g["FE"] = (False, "/just-fe не запощено — агент постить у PR до твоєї проби")
            failed.insert(failed.index("MIKE"), "FE")
        tag = f"{'' if short == 'rescue-serverless' else 'WE'}#{num}"
        title = re.sub(r"^[a-z]+(\([^)]*\))?:\s*", "", info["title"])
        title = re.sub(r"\s*\((PUN-\d+)\)\s*$", "", title)
        if num in stop_paused and short == "rescue-serverless":
            out["⏸"].append(f"{tag}")
            paused_rows.append((tag, r["linear"], title, cells, "⏸ пауза / hold", short))  # gates still shown on the status page
            continue
        if not failed:
            verdict, action = "✅", f"gh pr merge {num} -R {repo} --merge --delete-branch=false"
        elif failed == ["MIKE"]:
            verdict, action = "🙋", g["MIKE"][1]
        else:
            verdict, action = "🔴", g[failed[0]][1] + (f"  (+{len(failed) - 1})" if len(failed) > 1 else "")
        if mirror and not g["🐛"][0]:
            action += f" · дзеркало #{mirror}"
        out[verdict].append((tag, r["linear"], title, cells, action, short))

    # an engine PR lands only after the rescue PR of the same ticket (the engine change is useless or unsafe alone)
    rescue_open = {x[1]: x[0] for v in ("🙋", "🔴") for x in out[v] if x[5] == "rescue-serverless"}
    for x in list(out["✅"]):
        if x[5] == "workflow-engine" and x[1] in rescue_open:
            out["✅"].remove(x)
            out["🙋"].append(x[:4] + (f"мердж після {rescue_open[x[1]]} (той самий {x[1]})", x[5]))

    names = [(re.search(r"\(([^)]+)\)", r["local"]) or re.match(r"(.*)", r["linear"])).group(1) for r in local_only]
    names = [x for x in names if x != "no origin"]
    pb = paused_branches()
    titles = {num: i["title"] for num, i in meta["rescue-serverless"].items()}
    extra = {
        "done": [(f"{'' if s == 'rescue-serverless' else 'WE'}#{num}", t) for s, repo in REPOS.items() for num, t in merged_this_week(repo)],
        "planned": planned(),
        "paused_br": [x for x in names if any(x.startswith(p) for p in pb)],
        "paused": [(tag, titles.get(int(tag[1:]), "")) for tag in out["⏸"]],
    }
    extra["todo_br"] = [x for x in names if x not in extra["paused_br"]]
    if os.environ.get("PR_GATES_JSON"):  # for fleet-board/bin/status-html.py — same data as the terminal table
        rows = [dict(verdict=v, tag=x[0], linear=x[1], title=x[2], cells=dict(zip(GATES + ["FE", "UI"], x[3])), action=x[4], repo=x[5])
                for v in ("✅", "🙋", "🔴") for x in out[v]] + \
               [dict(verdict="⏸", tag=x[0], linear=x[1], title=x[2], cells=dict(zip(GATES + ["FE", "UI"], x[3])), action=x[4], repo=x[5]) for x in paused_rows]
        json.dump(dict(gates=GATES + ["FE", "UI"], rows=rows, **extra), sys.stdout, ensure_ascii=False)
        return
    gw = [max(width(k), 1) for k in GATES + ["FE", "UI"]]
    cols = [3, 7, 9, 30] + gw + [56]
    head = ["", "PR", "LINEAR", "ЗАДАЧА"] + GATES + ["FE", "UI", "ЩО ДАЛІ"]

    def sep(left, mid, right):
        return left + mid.join("─" * (n + 2) for n in cols) + right

    def line(cells):
        return "│ " + " │ ".join(pad(c, n) for c, n in zip(cells, cols)) + " │"

    print(sep("┌", "┬", "┐"))
    print(line(head))
    for v in ("✅", "🙋", "🔴"):
        if not out[v]:
            continue
        print(sep("├", "┼", "┤"))
        for tag, lin, title, cells, action, _repo in out[v]:
            print(line([v, tag, lin, title] + cells + [action]))
    print(sep("└", "┴", "┘"))
    n = {k: len(v) for k, v in out.items()}
    print(f"✅ МЕРДЖ {n['✅']} · 🙋 ТИ {n['🙋']} · 🔴 СТОП {n['🔴']} · ⏸ пауза {n['⏸']}: {' '.join(out['⏸']) or '—'}")
    # Mike 2026-10-21: under the table also what is done, what is planned, what is paused
    print("\n✅ ЗРОБЛЕНО (змерджено з понеділка)")
    for tag, t in extra["done"] or [("—", "")]:
        print(f"  {tag:<7} {t}")
    print("🗓 ПЛАНУЄТЬСЯ / В РОБОТІ (треки спринту + гілки без PR)")
    for p in extra["planned"] or ["—"]:
        print(f"  • {p}")
    if extra["todo_br"]:
        print("  • гілки без PR: " + " · ".join(extra["todo_br"]))
    print("⏸ НА ПАУЗІ")
    for tag, t in extra["paused"]:
        print(f"  {tag:<7} {t}")
    if extra["paused_br"]:
        print("  гілки: " + " · ".join(extra["paused_br"]))
    if not extra["paused"] and not extra["paused_br"]:
        print("  —")
    print("ворота: 0 PLAN твій апрув плану · 1 CI (✓0 = не бігло = ✗) · 2 MRG без конфлікту · 3 MAIN behind 0 або без конфліктів (MERGEABLE) · 4 CR · 5 PT /ponytail-review (без переускладнень) · 6 🐛 0 тредів Bugbot · "
          "7 TRY · 8 PRE preflight (dev ⊇ head, фікстура без алертів) · 9 JT · 10 MIKE апрув (dev ⊇ head) · FE just-fe запощено · UI демо в браузері (jb2b <рецепт>, ui-demos.tsv) — обидва інфо, не ворота   ✓ ок · ✗ ні · · н/з (engine)")


if __name__ == "__main__":
    main()
