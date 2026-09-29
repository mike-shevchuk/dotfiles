"""LGTM CLI. Static mode (Milestone 1): collect → render → print page path."""
from __future__ import annotations
import argparse
import datetime
import json
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
    entries, footnotes = collect_entries(repo)
    _log(f"  OK: {len(entries)} записів")
    out_dir = repo / ".lgtm"
    out_dir.mkdir(parents=True, exist_ok=True)
    page = out_dir / "index.html"
    page.write_text(render_index(repo.name, entries, footnotes=footnotes), encoding="utf-8")
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
            text, mdict = collect_diff(repo, pr=a.pr)
        elif a.refs:
            text, mdict = collect_diff(repo, base=a.refs[0], head=a.refs[1])
        else:
            _log("→ збираю локальний diff (merge-base + uncommitted)…")
            text, mdict = collect_diff(repo)
        out = Path(a.out) if a.out else repo / ".lgtm" / "reviews" / mdict["ref"].replace("/", "-")
        out.mkdir(parents=True, exist_ok=True)
        old_diff = out / "diff.txt"
        if (out / "findings.json").exists() and old_diff.exists() \
                and old_diff.read_text(encoding="utf-8") != text:
            _log("⚠ diff змінився після створення findings.json — hunk-прив'язки можуть "
                 "бути зміщені; перегенеруй findings.json")
        (out / "diff.txt").write_text(text, encoding="utf-8")
        files = parse_unified_diff(text)
        _log(f"  OK: {len(files)} файлів, "
             f"+{sum(f.additions for f in files)} −{sum(f.deletions for f in files)}")
        hunks_doc = {"files": [{"path": f.path, "status": f.status,
                                "hunks": [{"id": h.hunk_id, "header": h.header,
                                          "first_new_line": h.first_new_line}
                                         for h in f.hunks]}
                               for f in files]}
        (out / "hunks.json").write_text(json.dumps(hunks_doc, ensure_ascii=False, indent=2),
                                        encoding="utf-8")
        known_hunks = {h["id"] for fd in hunks_doc["files"] for h in fd["hunks"]}
        now = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
        fpath = out / "findings.json"
        if fpath.exists():
            try:
                fmeta, findings = load_findings(fpath)
            except (json.JSONDecodeError, TypeError, KeyError) as e:
                _log(f"✗ findings.json невалідний: {e}")
                return 1
            lang = a.lang if a.lang is not None else fmeta.lang
            if a.lang is not None and a.lang != fmeta.lang:
                _log(f"  --lang {a.lang} перекриває lang={fmeta.lang!r} з findings.json")
            # meta identity (ref/base/mode/repo/generated) is always fresh from this
            # run, not carried over from a possibly-stale findings.json — only lang
            # (and its explicit --lang override) is meta ownership findings.json keeps.
            # Warn only when the file carried a REAL (non-empty) value that differs;
            # the documented minimal-meta path (lang-only, "" defaults) is not stale.
            fresh = {"ref": mdict["ref"], "base": mdict["base"],
                     "mode": mdict["mode"], "repo": repo.name}
            stale = [k for k, v in fresh.items()
                     if getattr(fmeta, k) and getattr(fmeta, k) != v]
            if stale:
                _log(f"  findings.json meta.{{{','.join(stale)}}} застарілі — "
                     f"перезаписано свіжими значеннями цього запуску")
            meta = ReviewMeta(ref=mdict["ref"], base=mdict["base"], mode=mdict["mode"],
                              generated=now, repo=repo.name, lang=lang)
            _log(f"  findings.json: {len(findings)} знахідок")
            unknown = [f for f in findings if f.hunk not in known_hunks]
            for f in unknown:
                _log(f"⚠ finding {f.id}: невідомий hunk {f.hunk!r} — не буде показаний")
            if unknown:
                findings = [f for f in findings if f.hunk in known_hunks]
        else:
            findings = []
            meta = ReviewMeta(ref=mdict["ref"], base=mdict["base"], mode=mdict["mode"],
                              generated=now, repo=repo.name, lang=a.lang or "ukr")
            _log("  findings.json відсутній — рендерю без знахідок")
        # coach progress (design §4): aggregate review-stats.jsonl into the page
        from lgtm.stats import aggregate, load_series
        series = load_series(repo)
        stats = aggregate(series) if series else None
        if stats:
            _log(f"  coach: прогрес по {len(stats)} патернах ({len(series)} рев'ю)")
        page = out / "page.html"
        page.write_text(render_page(meta, files, findings, None, stats), encoding="utf-8")
        _log(f"  page: {page}")
        print(page)
        return 0
    except ValueError as e:
        _log(f"✗ {e}")
        return 1
    except subprocess.CalledProcessError as e:
        _log(f"✗ команда впала: {' '.join(e.cmd)}")
        if e.stderr:
            _log(f"  stderr: {e.stderr.strip()}")
        return 1


def cmd_stats(a: argparse.Namespace) -> int:
    """Coach progress across the last N reviews (review-stats.jsonl)."""
    from lgtm.stats import load_series, render_progress, stats_path
    repo = Path(a.repo).resolve()
    _log(f"→ coach-статистика {stats_path(repo)} (останні {a.last})…")
    print(render_progress(load_series(repo, a.last)))
    return 0


def cmd_serve(a: argparse.Namespace) -> int:
    from lgtm.serve import run
    repo = Path(a.repo).resolve()
    if a.dir:
        root = Path(a.dir).resolve()
    else:
        # newest review under .lgtm/reviews/ — matches "continue where I left off"
        reviews = repo / ".lgtm" / "reviews"
        cands = sorted((d for d in reviews.glob("*") if (d / "page.html").exists()),
                       key=lambda d: (d / "page.html").stat().st_mtime, reverse=True) \
            if reviews.exists() else []
        if not cands:
            _log(f"✗ немає жодного рев'ю у {reviews} — спершу: lgtm review")
            return 1
        root = cands[0]
    _log(f"→ live-сервер для {root.name} (port {a.port})…")
    run(root, a.port, a.key)
    return 0


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
    st = sub.add_parser("stats")
    st.add_argument("--repo", default=".")
    st.add_argument("--last", type=int, default=5)
    st.set_defaults(fn=cmd_stats)
    s = sub.add_parser("serve")
    s.add_argument("--repo", default=".")
    s.add_argument("--dir", help="явний шлях до .lgtm/reviews/<ref>/ (дефолт: найсвіжіший)")
    s.add_argument("--port", type=int, default=8642)
    s.add_argument("--key", default=None, help="короткий ключ доступу (?key=…)")
    s.set_defaults(fn=cmd_serve)
    a = p.parse_args()
    return a.fn(a)


if __name__ == "__main__":
    raise SystemExit(main())
