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

from lgtm.collect import _run
from lgtm.render import _cpy_attr, _page_shell

MAX_BRANCHES = 8
MAX_RECENTS = 5
MAX_WORKTREES = 8
# Convention owned by Claude Code harness worktree scaffolding: if this marker
# renames, the filter goes inert (worktrees reappear as clutter, no error).
AGENT_SCRATCH_MARKER = "/.claude/worktrees/agent-"

_GIT_ERR = (subprocess.CalledProcessError, FileNotFoundError)
_GH_ERR = _GIT_ERR + (json.JSONDecodeError,)

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
    title: str = ""
    plus: int = 0
    minus: int = 0
    when: str = ""
    cmd: str = ""


def _collect_head(repo: Path, branch: str) -> list[IndexEntry]:
    try:
        n = len([l for l in _run(["git", "status", "--porcelain"], repo).splitlines() if l.strip()])
    except _GIT_ERR:
        return []
    title = f"{n} uncommitted файлів" if n else "чисто — немає uncommitted змін"
    return [IndexEntry(kind="head", ref=branch, title=title, cmd="jb2b review")]


def _collect_prs(repo: Path) -> tuple[list[IndexEntry], set[str]]:
    try:
        out = _run(["gh", "pr", "list", "--author", "@me", "--state", "open", "--json",
                    "number,title,headRefName,additions,deletions"], repo)
        prs = json.loads(out)
    except _GH_ERR:
        return [], set()
    entries = []
    heads = set()
    for pr in prs:
        number = pr["number"]
        heads.add(pr["headRefName"])
        entries.append(IndexEntry(kind="pr", ref=f"pr{number}", title=pr.get("title", ""),
                                  plus=pr.get("additions", 0), minus=pr.get("deletions", 0),
                                  cmd=f"jb2b review {number}"))
    return entries, heads


def _collect_branches(repo: Path, skip: set[str], current: str) -> list[IndexEntry]:
    try:
        out = _run(["git", "for-each-ref", "--sort=-committerdate", "refs/heads",
                    "--format=%(refname:short)|%(committerdate:relative)"], repo)
    except _GIT_ERR:
        return []
    skip = skip | {current}
    entries = []
    for line in out.splitlines():
        if not line.strip() or "|" not in line:
            continue
        name, when = line.split("|", 1)
        if name in skip:
            continue
        entries.append(IndexEntry(kind="branch", ref=name, when=when, cmd=f"jb2b review {name}"))
        if len(entries) >= MAX_BRANCHES:
            break
    return entries


def _filter_worktrees(pairs: list[tuple[str, str]]) -> tuple[list[tuple[str, str]], int]:
    """Pure filtering for worktree (path, branch) pairs.

    Agent scratch worktrees (paths under .claude/worktrees/agent-*) are noise —
    excluded entirely, not counted as hidden. Real worktrees are capped at
    MAX_WORKTREES; the overflow count is returned so the page can show an
    honest "…ще N приховано" line instead of silently truncating."""
    real = [(p, b) for p, b in pairs if AGENT_SCRATCH_MARKER not in p]
    return real[:MAX_WORKTREES], max(0, len(real) - MAX_WORKTREES)


def _collect_worktrees(repo: Path) -> tuple[list[IndexEntry], int]:
    """Parse `git worktree list --porcelain` blank-line-separated blocks.
    The first block is always the main worktree (the repo itself) — skip it."""
    try:
        out = _run(["git", "worktree", "list", "--porcelain"], repo)
    except _GIT_ERR:
        return [], 0
    blocks = out.strip("\n").split("\n\n") if out.strip() else []
    pairs = []
    for block in blocks[1:]:
        path, branch = None, None
        for line in block.splitlines():
            if line.startswith("worktree "):
                path = line[len("worktree "):]
            elif line.startswith("branch "):
                branch = line[len("branch "):].replace("refs/heads/", "")
        if branch:
            pairs.append((path or "", branch))
    kept, hidden = _filter_worktrees(pairs)
    entries = [IndexEntry(kind="worktree", ref=branch, title=path, cmd=f"jb2b review {branch}")
               for path, branch in kept]
    return entries, hidden


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
        entries.append(IndexEntry(kind="recent", ref=d.name, cmd=f"jb2b review {d.name}"))
    return entries


def collect_entries(repo: Path) -> tuple[list[IndexEntry], dict[str, str]]:
    try:
        current = _run(["git", "branch", "--show-current"], repo).strip() or "HEAD"
    except _GIT_ERR:
        current = "HEAD"
    entries = _collect_head(repo, current)
    prs, pr_heads = _collect_prs(repo)
    entries += prs
    entries += _collect_branches(repo, pr_heads, current)
    wt_entries, wt_hidden = _collect_worktrees(repo)
    entries += wt_entries
    entries += _collect_recents(repo)
    footnotes = {}
    if wt_hidden:
        footnotes["worktree"] = f"…ще {wt_hidden} приховано"
    return entries, footnotes


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


def render_index(repo_name: str, entries: list[IndexEntry],
                  footnotes: dict[str, str] | None = None) -> str:
    footnotes = footnotes or {}
    by_kind: dict[str, list[IndexEntry]] = {}
    for e in entries:
        by_kind.setdefault(e.kind, []).append(e)
    sections = []
    for kind, label in SECTION_ORDER:
        group = by_kind.get(kind)
        footnote = footnotes.get(kind)
        if not group and not footnote:
            continue
        cards = "".join(_card_html(e) for e in group) if group else ""
        foot_html = (f'<div style="color:var(--dim);font-size:.85em;padding:4px 2px">'
                     f'{H.escape(footnote)}</div>') if footnote else ""
        sections.append(f'<div class="sect" data-sect>{label}</div>'
                        f'<div class="cards" data-grid>{cards}</div>{foot_html}')
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
    body = (f'<div class="ix">'
            f'<div style="display:flex;align-items:center;gap:12px;padding:12px 16px;'
            f'border-bottom:1px solid var(--line);background:var(--panel);flex-wrap:wrap">{header}</div>'
            f'<div style="padding:16px">{"".join(sections)}{empty}</div>'
            f'</div>')
    return _page_shell(f"LGTM · index · {H.escape(repo_name)}", "uk", body,
                        extra_css=IX_CSS, extra_js=IX_JS)


IX_CSS = r"""
  .ix{background:var(--bg);color:var(--txt);border:1px solid var(--line);border-radius:12px;overflow:hidden;font-size:clamp(13px,.5vw + 11px,15px);line-height:1.5}
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
