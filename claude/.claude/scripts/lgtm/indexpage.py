"""LGTM index page: entry point listing PRs/branches/worktrees/recent reviews.

UI contract: adapted from the validated mockup
rescue-serverless/.superpowers/brainstorm/68067-1783145500/content/lgtm-index-live.html
(ixFilter + card/section markup). CSS/JS for the shared review-page chrome are
reused from lgtm.render; the index page ships its own small `.ix` CSS block
(copied verbatim from the mockup) plus the `ixFilter`/`ixPick` JS, adapted so
that in M1 (no live server yet) picking a card copies its run command via the
same `cpy()` helper used by render.py's pages.
"""
from __future__ import annotations
import html as H
import json
import subprocess
from dataclasses import dataclass
from pathlib import Path

from lgtm.render import CSS, JS, FAVICON, _cpy_attr

MAX_BRANCHES = 8
MAX_RECENTS = 5

SECTION_ORDER = (
    ("head", "▸ поточний стан"),
    ("pr", "⇅ відкриті PR"),
    ("branch", "⎇ локальні гілки"),
    ("worktree", "◐ worktrees"),
    ("recent", "🕘 нещодавні рев'ю"),
)

CHIP = {
    "head": ("c-head", "⎇ HEAD"),
    "pr": ("c-open", "open"),
    "branch": ("c-local", "local"),
    "worktree": ("c-wt", "◐ worktree"),
    "recent": ("c-local", "🕘"),
}


@dataclass(frozen=True)
class IndexEntry:
    kind: str          # 'head' | 'pr' | 'branch' | 'worktree' | 'recent'
    ref: str
    title: str
    plus: int
    minus: int
    when: str
    cmd: str


def _run(cmd: list[str], cwd: Path) -> str:
    return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, check=True).stdout


def _collect_head(repo: Path) -> list[IndexEntry]:
    try:
        branch = _run(["git", "branch", "--show-current"], repo).strip() or "HEAD"
        n = len([l for l in _run(["git", "status", "--porcelain"], repo).splitlines() if l.strip()])
    except (subprocess.CalledProcessError, FileNotFoundError):
        return []
    title = f"{n} uncommitted файлів" if n else "чисто — немає uncommitted змін"
    return [IndexEntry("head", branch, title, 0, 0, "", "jb2b review")]


def _collect_prs(repo: Path) -> list[IndexEntry]:
    try:
        out = _run(["gh", "pr", "list", "--author", "@me", "--state", "open", "--json",
                    "number,title,headRefName,additions,deletions"], repo)
        prs = json.loads(out)
    except (subprocess.CalledProcessError, FileNotFoundError, json.JSONDecodeError):
        return []
    entries = []
    for pr in prs:
        number = pr["number"]
        entries.append(IndexEntry("pr", f"pr{number}", pr.get("title", ""),
                                  pr.get("additions", 0), pr.get("deletions", 0),
                                  "", f"jb2b review {number}"))
    return entries


def _pr_heads(repo: Path) -> set[str]:
    try:
        out = _run(["gh", "pr", "list", "--author", "@me", "--state", "open", "--json",
                    "headRefName"], repo)
        return {pr["headRefName"] for pr in json.loads(out)}
    except (subprocess.CalledProcessError, FileNotFoundError, json.JSONDecodeError):
        return set()


def _collect_branches(repo: Path, skip: set[str]) -> list[IndexEntry]:
    try:
        current = _run(["git", "branch", "--show-current"], repo).strip()
        out = _run(["git", "for-each-ref", "--sort=-committerdate", "refs/heads",
                    "--format=%(refname:short)|%(committerdate:relative)"], repo)
    except (subprocess.CalledProcessError, FileNotFoundError):
        return []
    skip = skip | {current}
    entries = []
    for line in out.splitlines():
        if not line.strip() or "|" not in line:
            continue
        name, when = line.split("|", 1)
        if name in skip:
            continue
        entries.append(IndexEntry("branch", name, "", 0, 0, when, f"jb2b review {name}"))
        if len(entries) >= MAX_BRANCHES:
            break
    return entries


def _collect_worktrees(repo: Path) -> list[IndexEntry]:
    """Parse `git worktree list --porcelain` blank-line-separated blocks.
    The first block is always the main worktree (the repo itself) — skip it."""
    try:
        out = _run(["git", "worktree", "list", "--porcelain"], repo)
    except (subprocess.CalledProcessError, FileNotFoundError):
        return []
    blocks = out.strip("\n").split("\n\n") if out.strip() else []
    entries = []
    for block in blocks[1:]:
        path, branch = None, None
        for line in block.splitlines():
            if line.startswith("worktree "):
                path = line[len("worktree "):]
            elif line.startswith("branch "):
                branch = line[len("branch "):].replace("refs/heads/", "")
        if branch:
            entries.append(IndexEntry("worktree", branch, path or "", 0, 0, "",
                                      f"jb2b review {branch}"))
    return entries


def _collect_recents(repo: Path) -> list[IndexEntry]:
    reviews_dir = repo / ".lgtm" / "reviews"
    if not reviews_dir.is_dir():
        return []
    try:
        dirs = [d for d in reviews_dir.iterdir() if d.is_dir()]
    except (OSError, FileNotFoundError):
        return []
    dirs.sort(key=lambda d: d.stat().st_mtime, reverse=True)
    entries = []
    for d in dirs[:MAX_RECENTS]:
        entries.append(IndexEntry("recent", d.name, "", 0, 0, "", f"jb2b review {d.name}"))
    return entries


def collect_entries(repo: Path) -> list[IndexEntry]:
    entries = list(_collect_head(repo))
    prs = _collect_prs(repo)
    entries += prs
    pr_heads = _pr_heads(repo)
    entries += _collect_branches(repo, pr_heads)
    entries += _collect_worktrees(repo)
    entries += _collect_recents(repo)
    return entries


def _fuzzy_key(e: IndexEntry) -> str:
    return H.escape(f"{e.ref} {e.title}".lower(), quote=True)


def _card_html(e: IndexEntry) -> str:
    cls, label = CHIP[e.kind]
    title = f'<div class="title">{H.escape(e.title)}</div>' if e.title else ""
    stats = f" · +{e.plus}/−{e.minus}" if (e.plus or e.minus) else ""
    when = f" · {H.escape(e.when)}" if e.when else ""
    foot = f'<div class="foot">{H.escape(e.cmd)}{stats}{when}</div>'
    return (f'<div class="pcard" data-k="{_fuzzy_key(e)}" onclick="{_cpy_attr(e.cmd)}">'
            f'<span class="chip {cls}">{label}</span> <span class="num">{H.escape(e.ref)}</span>'
            f'{title}{foot}</div>')


def render_index(repo_name: str, entries: list[IndexEntry]) -> str:
    by_kind: dict[str, list[IndexEntry]] = {}
    for e in entries:
        by_kind.setdefault(e.kind, []).append(e)
    sections = []
    for kind, label in SECTION_ORDER:
        group = by_kind.get(kind)
        if not group:
            continue
        cards = "".join(_card_html(e) for e in group)
        sections.append(f'<div class="sect" data-sect>{label}</div>'
                        f'<div class="cards" data-grid>{cards}</div>')
    total = len(entries)
    header = (f'<div style="font-weight:800;letter-spacing:1px;font-size:1.1em">'
              f'<span style="color:var(--grn)">L</span><span style="color:var(--acc)">G</span>'
              f'<span style="color:var(--purple)">T</span><span style="color:var(--org)">M</span>'
              f'<span style="color:var(--dim);font-weight:400;font-size:.65em">'
              f' · {H.escape(repo_name)}</span></div>'
              f'<div class="search"><span style="color:var(--grn)">❯</span>'
              f'<input id="ixq" placeholder="fuzzy: 1499, chat, welcome…" '
              f'oninput="ixFilter(this.value)"><span class="pill" id="ixcount">{total}</span></div>')
    empty = ('<div id="ixempty" class="hid" style="text-align:center;color:var(--dim);'
             'padding:30px">нічого не знайдено — спробуй інший запит</div>')
    return f"""<!DOCTYPE html>
<html lang="uk"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>LGTM · index · {H.escape(repo_name)}</title>
<link rel="icon" href="{FAVICON}">
<style>{CSS}{IX_CSS}</style></head>
<body><div class="ix">
<div style="display:flex;align-items:center;gap:12px;padding:12px 16px;border-bottom:1px solid var(--line);background:var(--panel);flex-wrap:wrap">{header}</div>
<div style="padding:16px">{"".join(sections)}{empty}</div>
</div><div class="toast" id="cpToast"></div>
<script>{JS}{IX_JS}</script></body></html>"""


IX_CSS = r"""
  .ix{--bg:#0d1117;--panel:#161b22;--panel2:#1c2330;--line:#30363d;--txt:#e6edf3;--dim:#8b949e;--acc:#58a6ff;--grn:#3fb950;--red:#f85149;--org:#d29922;--purple:#a371f7;
    background:var(--bg);color:var(--txt);border:1px solid var(--line);border-radius:12px;overflow:hidden;font-size:clamp(13px,.5vw + 11px,15px);line-height:1.5}
  .ix code{font-family:ui-monospace,monospace}
  .ix .search{display:flex;align-items:center;gap:8px;background:var(--panel2);border:1px solid var(--line);border-radius:8px;padding:7px 12px;flex:1;min-width:200px}
  .ix .search input{flex:1;background:transparent;border:none;outline:none;color:var(--txt);font-family:ui-monospace,monospace;font-size:1em}
  .ix .search:focus-within{border-color:var(--acc)}
  .ix .sect{font-size:.78em;text-transform:uppercase;color:var(--dim);letter-spacing:.6px;margin:18px 4px 8px}
  .ix .cards{display:grid;grid-template-columns:repeat(auto-fill,minmax(270px,1fr));gap:12px}
  .ix .pcard{background:var(--panel);border:1px solid var(--line);border-radius:10px;padding:12px;cursor:pointer;transition:.12s;position:relative}
  .ix .pcard:hover{border-color:var(--acc);transform:translateY(-2px)}
  .ix .num{font-family:ui-monospace,monospace;color:var(--acc);font-weight:700}
  .ix .title{font-size:.93em;margin:5px 0 8px;line-height:1.35}
  .ix .foot{display:flex;gap:8px;color:var(--dim);font-size:.82em;flex-wrap:wrap}
  .ix .chip{border-radius:20px;padding:1px 8px;font-size:.76em}
  .ix .c-open{background:rgba(63,185,80,.16);color:#8ff0a0;border:1px solid rgba(63,185,80,.4)}
  .ix .c-local{background:rgba(163,113,247,.15);color:#d2b8ff;border:1px solid rgba(163,113,247,.4)}
  .ix .c-wt{background:rgba(210,153,34,.16);color:#f0d48a;border:1px solid rgba(210,153,34,.4)}
  .ix .c-head{background:rgba(88,166,255,.16);color:#a5d0ff;border:1px solid rgba(88,166,255,.4)}
  .ix .hid{display:none!important}
  .ix .pill{background:var(--panel2);border:1px solid var(--line);border-radius:20px;padding:2px 10px;font-size:.8em}
"""

IX_JS = r"""
  function ixFilter(q){
    q = q.toLowerCase().trim();
    var n = 0;
    document.querySelectorAll('.ix .pcard').forEach(function(c){
      var hit = !q || (c.dataset.k + ' ' + c.textContent).toLowerCase().indexOf(q) >= 0;
      c.classList.toggle('hid', !hit); if (hit) n++;
    });
    document.querySelectorAll('.ix [data-sect]').forEach(function(s){
      var grid = s.nextElementSibling;
      var any = grid && grid.querySelector('.pcard:not(.hid)');
      s.classList.toggle('hid', !any); if (grid) grid.classList.toggle('hid', !any);
    });
    document.getElementById('ixcount').textContent = n;
    document.getElementById('ixempty').classList.toggle('hid', n > 0);
  }
"""
