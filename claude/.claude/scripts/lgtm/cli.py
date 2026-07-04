"""LGTM CLI. Static mode (Milestone 1): collect → render → print page path."""
from __future__ import annotations
import argparse
import dataclasses
import datetime
import subprocess
import sys
from pathlib import Path

from lgtm.collect import collect_diff
from lgtm.diffparse import parse_unified_diff
from lgtm.indexpage import collect_entries, render_index
from lgtm.model import ReviewMeta, load_findings
from lgtm.render import render_page


def _log(msg: str) -> None:
    print(msg, file=sys.stderr)


def cmd_index(a: argparse.Namespace) -> int:
    repo = Path(a.repo).resolve()
    _log(f"→ збираю PR/гілки/worktrees/рев'ю для {repo.name}…")
    entries = collect_entries(repo)
    _log(f"  OK: {len(entries)} записів")
    out_dir = repo / ".lgtm"
    out_dir.mkdir(parents=True, exist_ok=True)
    page = out_dir / "index.html"
    page.write_text(render_index(repo.name, entries), encoding="utf-8")
    _log(f"  page: {page}")
    print(page)
    return 0


def cmd_review(a: argparse.Namespace) -> int:
    try:
        repo = Path(a.repo).resolve()
        if a.diff_file:
            text = Path(a.diff_file).read_text(encoding="utf-8")
            mdict = {"ref": a.ref_name or "diff", "base": "(file)", "mode": "refs"}
        elif a.pr:
            _log(f"→ збираю diff PR#{a.pr} через gh…")
            text, mdict = collect_diff(repo, "pr", pr=a.pr)
        elif a.refs:
            text, mdict = collect_diff(repo, "refs", base=a.refs[0], head=a.refs[1])
        else:
            _log("→ збираю локальний diff (merge-base + uncommitted)…")
            text, mdict = collect_diff(repo, "local")
        out = Path(a.out) if a.out else repo / ".lgtm" / "reviews" / mdict["ref"].replace("/", "-")
        out.mkdir(parents=True, exist_ok=True)
        (out / "diff.txt").write_text(text, encoding="utf-8")
        files = parse_unified_diff(text)
        _log(f"  OK: {len(files)} файлів, "
             f"+{sum(f.additions for f in files)} −{sum(f.deletions for f in files)}")
        fpath = out / "findings.json"
        if fpath.exists():
            fmeta, findings = load_findings(fpath)
            meta = fmeta
            if a.lang is not None and a.lang != fmeta.lang:
                meta = dataclasses.replace(fmeta, lang=a.lang)
                _log(f"  --lang {a.lang} перекриває lang={fmeta.lang!r} з findings.json")
            _log(f"  findings.json: {len(findings)} знахідок")
        else:
            findings = []
            meta = ReviewMeta(ref=mdict["ref"], base=mdict["base"], mode=mdict["mode"],
                              generated=datetime.datetime.now().strftime("%Y-%m-%d %H:%M"),
                              repo=repo.name, lang=a.lang or "ukr")
            _log("  findings.json відсутній — рендерю без знахідок")
        page = out / "page.html"
        page.write_text(render_page(meta, files, findings, None), encoding="utf-8")
        _log(f"  page: {page}")
        print(page)
        return 0
    except subprocess.CalledProcessError as e:
        _log(f"✗ команда впала: {' '.join(e.cmd)}")
        if e.stderr:
            _log(f"  stderr: {e.stderr.strip()}")
        return 1


def main() -> int:
    p = argparse.ArgumentParser(prog="lgtm")
    sub = p.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("review")
    r.add_argument("--repo", default=".")
    r.add_argument("--pr", type=int)
    r.add_argument("--refs", nargs=2, metavar=("BASE", "HEAD"))
    r.add_argument("--diff-file")
    r.add_argument("--ref-name")
    r.add_argument("--lang", default=None, choices=["ukr", "eng", "both"])
    r.add_argument("--out")
    r.set_defaults(fn=cmd_review)
    i = sub.add_parser("index")
    i.add_argument("--repo", default=".")
    i.set_defaults(fn=cmd_index)
    a = p.parse_args()
    return a.fn(a)


if __name__ == "__main__":
    raise SystemExit(main())
