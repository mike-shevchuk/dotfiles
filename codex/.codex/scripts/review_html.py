#!/usr/bin/env python3
"""review_html.py — generate a self-contained HTML review page.

(unified diff text, explanations.json, lang) -> one standalone .html file.
Pure rendering, Python stdlib only. Driven by the /review-html Codex command.
"""
from __future__ import annotations

import argparse
import html
import json
import os
import tempfile


def hunk_id(file_idx: int, hunk_idx: int) -> str:
    """Stable anchor id for a hunk: file index + hunk index, e.g. 'F0H1'."""
    return f"F{file_idx}H{hunk_idx}"


def _strip_ab(path: str) -> str:
    """Strip a leading 'a/' or 'b/' from a diff path."""
    return path[2:] if path[:2] in ("a/", "b/") else path


def _new_file(path: str) -> dict:
    return {"path": path, "added": 0, "removed": 0, "hunks": []}


def parse_diff(text: str) -> list[dict]:
    """Parse `git diff` unified output.

    Returns a list of files, each:
      {"path": str, "added": int, "removed": int,
       "hunks": [{"header": str, "lines": [(tag, text)]}]}
    where tag is one of "ctx" | "add" | "del".
    """
    files: list[dict] = []
    cur: dict | None = None
    for line in text.splitlines():
        if line.startswith("diff --git "):
            path = line.split(" b/", 1)[-1].strip()
            cur = _new_file(path)
            files.append(cur)
        elif line.startswith("+++ "):
            p = line[4:].strip()
            if cur is not None and p != "/dev/null":
                cur["path"] = _strip_ab(p)
        elif line.startswith("--- "):
            p = line[4:].strip()
            if cur is not None and p != "/dev/null" and cur["path"] == "/dev/null":
                cur["path"] = _strip_ab(p)
        elif line.startswith("@@"):
            if cur is None:
                cur = _new_file("?")
                files.append(cur)
            cur["hunks"].append({"header": line, "lines": []})
        elif cur is not None and cur["hunks"]:
            h = cur["hunks"][-1]
            if line.startswith("+"):
                h["lines"].append(("add", line[1:]))
                cur["added"] += 1
            elif line.startswith("-"):
                h["lines"].append(("del", line[1:]))
                cur["removed"] += 1
            elif line.startswith(" "):
                h["lines"].append(("ctx", line[1:]))
            # ignore "\ No newline at end of file" and other noise
    return files


def _detail(cls: str, summary: str, body: str) -> str:
    """A collapsible <details open> block used for Description/Problems."""
    return (f'<details class="{cls}" open><summary>{summary}</summary>'
            f'{body}</details>')


# NOTE: single-language mode falls back across languages (show *something*),
# but `both` mode does NOT — a missing translation renders an empty span so the
# two languages never duplicate. This asymmetry is intentional.
def _text(obj, lang: str) -> str:
    """Pick a language string from {'ukr':..,'eng':..} or a plain string."""
    if isinstance(obj, dict):
        return obj.get(lang) or obj.get("eng") or obj.get("ukr") or ""
    return obj or ""


def render_text(obj, lang: str) -> str:
    """Escaped HTML for a bilingual field.

    lang 'ukr'|'eng' -> just that language. lang 'both' -> two spans
    (.L-ukr shown, .L-eng hidden); the page's toggle flips them.
    """
    if lang == "both":
        u = html.escape(obj.get("ukr", "")) if isinstance(obj, dict) else html.escape(obj or "")
        e = html.escape(obj.get("eng", "")) if isinstance(obj, dict) else ""
        return f'<span class="L L-ukr">{u}</span><span class="L L-eng" hidden>{e}</span>'
    return html.escape(_text(obj, lang))


def render_hunk(hid: str, hunk: dict, expl: dict, lang: str) -> str:
    rows = []
    for tag, text in hunk["lines"]:
        sign = {"add": "+", "del": "-", "ctx": " "}[tag]
        rows.append(
            f'<div class="ln {tag}"><span class="sign">{sign}</span>'
            f'<code>{html.escape(text)}</code></div>'
        )
    diff_html = "".join(rows)

    desc = expl.get("description")
    desc_html = ""
    if desc:
        desc_html = _detail(
            "review-desc", "📝 Description",
            f'<div class="body">{render_text(desc, lang)}</div>',
        )

    problems = expl.get("problems") or []
    prob_html = ""
    if problems:
        items = ""
        for p in problems:
            sev = html.escape(str(p.get("severity", "info")))
            items += (
                f'<li class="sev-{sev}">'
                f'<span class="badge">{sev}</span>'
                f'{render_text(p.get("text", ""), lang)}</li>'
            )
        prob_html = _detail("review-problems", "⚠️ Problems", f'<ul>{items}</ul>')

    replies = expl.get("replies") or []
    rep_html = ""
    if replies:
        threads = []
        for r in replies:
            mark = "✅" if r.get("status") == "addressed" else "💬"
            threads.append(
                f'<div class="thread"><div class="you">🗣 {html.escape(str(r.get("comment", "")))}</div>'
                f'<div class="claude">{mark} {render_text(r.get("reply", ""), lang)}</div></div>'
            )
        rep_html = f'<div class="replies">{"".join(threads)}</div>'

    return (
        f'<div class="hunk" id="{hid}">'
        f'<div class="hunk-head"><code>{html.escape(hunk["header"])}</code>'
        f'<button class="copy" data-hunk="{hid}">Copy for Codex</button></div>'
        f'<div class="diff">{diff_html}</div>'
        f'{desc_html}{prob_html}{rep_html}'
        f'<textarea class="comment" data-hunk="{hid}" '
        f'placeholder="comment for Codex…"></textarea>'
        f'</div>'
    )


_JS = r"""
(function(){
  var main=document.querySelector('main');
  var key=function(h){return 'rh:'+main.dataset.repo+':'+main.dataset.ref+':'+h;};
  // restore saved comments
  document.querySelectorAll('textarea.comment').forEach(function(t){
    var v=localStorage.getItem(key(t.dataset.hunk)); if(v)t.value=v;
    t.addEventListener('input',function(){localStorage.setItem(key(t.dataset.hunk),t.value);});
  });
  function copy(text){navigator.clipboard.writeText(text);}
  function block(h,comment){
    var hunk=document.getElementById(h);
    var head=hunk.querySelector('.hunk-head code').textContent;
    var file=hunk.closest('details.file').dataset.path;
    return '[review-html] '+main.dataset.repo+' @ '+main.dataset.ref+'\n'
      +'file: '+file+'  hunk: '+h+' ('+head+')\n'+'comment: '+comment;
  }
  // per-hunk Copy for Codex
  document.querySelectorAll('button.copy').forEach(function(b){
    b.addEventListener('click',function(){
      var h=b.dataset.hunk;
      var c=document.querySelector('textarea.comment[data-hunk="'+h+'"]').value||'(no comment)';
      copy(block(h,c)); b.textContent='Copied ✓'; setTimeout(function(){b.textContent='Copy for Codex';},1200);
    });
  });
  // Export for Codex: bundle all non-empty comments -> clipboard (+ download fallback)
  document.getElementById('export').addEventListener('click',function(){
    var out='# review-html comments — '+main.dataset.repo+' @ '+main.dataset.ref+'\n\n';
    var n=0;
    document.querySelectorAll('textarea.comment').forEach(function(t){
      if(t.value.trim()){n++;out+=block(t.dataset.hunk,t.value.trim())+'\n\n';}
    });
    if(!n){alert('No comments yet.');return;}
    copy(out);
    var a=document.createElement('a');
    a.href='data:text/markdown;charset=utf-8,'+encodeURIComponent(out);
    a.download='comments.md'; a.click();
    alert(n+' comment(s) copied to clipboard.\nThen run:  /review-html --reply\n(comments.md also downloaded as a fallback)');
  });
  // collapse / expand
  document.getElementById('expand-all').addEventListener('click',function(){
    document.querySelectorAll('details.file').forEach(function(d){d.open=true;});});
  document.getElementById('collapse-all').addEventListener('click',function(){
    document.querySelectorAll('details.file').forEach(function(d){d.open=false;});});
  // language toggle (only present in both mode)
  var lt=document.getElementById('lang-toggle');
  if(lt){var showUkr=true;lt.addEventListener('click',function(){
    showUkr=!showUkr;
    document.querySelectorAll('.L-ukr').forEach(function(e){e.hidden=!showUkr;});
    document.querySelectorAll('.L-eng').forEach(function(e){e.hidden=showUkr;});
  });}
})();
"""


_CSS = """
:root{--bg:#1e1e2e;--fg:#cdd6f4;--mut:#6c7086;--add:#1c3a1c;--del:#3a1c1c;
--addfg:#a6e3a1;--delfg:#f38ba8;--card:#181825;--acc:#89b4fa;--peach:#fab387;}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--fg);
font:14px/1.5 ui-monospace,SFMono-Regular,Menlo,monospace}
header{position:sticky;top:0;background:var(--card);padding:10px 16px;
border-bottom:1px solid #313244;display:flex;gap:12px;align-items:center;flex-wrap:wrap}
header .meta{color:var(--mut)}
button{background:#313244;color:var(--fg);border:1px solid #45475a;border-radius:6px;
padding:4px 10px;cursor:pointer;font:inherit}
button:hover{border-color:var(--acc)}
main{padding:16px;max-width:1100px;margin:0 auto}
details.file{background:var(--card);border:1px solid #313244;border-radius:8px;margin:0 0 14px}
details.file>summary{cursor:pointer;padding:10px 14px;font-weight:bold;color:var(--acc)}
.fstat{color:var(--mut);font-weight:normal;margin-left:8px}
.fsummary{padding:0 14px 8px;color:var(--fg)}
.hunk{border-top:1px solid #313244;padding:10px 14px}
.hunk-head{display:flex;justify-content:space-between;align-items:center;color:var(--mut)}
.diff{overflow-x:auto;margin:8px 0;border-radius:6px;background:#11111b}
.ln{white-space:pre;display:flex}
.ln .sign{width:1.4em;text-align:center;color:var(--mut)}
.ln.add{background:var(--add)} .ln.add .sign,.ln.add code{color:var(--addfg)}
.ln.del{background:var(--del)} .ln.del .sign,.ln.del code{color:var(--delfg)}
.ln code{background:none;padding:0}
details.review-desc>summary{color:var(--acc);cursor:pointer}
details.review-problems>summary{color:var(--peach);cursor:pointer}
.review-problems .badge{background:var(--peach);color:#1e1e2e;border-radius:4px;
padding:0 6px;margin-right:6px;font-size:.8em}
.replies{margin:8px 0;border-left:3px solid var(--acc);padding-left:10px}
.replies .you{color:var(--peach)} .replies .claude{color:var(--addfg)}
textarea.comment{width:100%;min-height:46px;margin-top:8px;background:#11111b;
color:var(--fg);border:1px solid #45475a;border-radius:6px;padding:6px;font:inherit}
.empty{text-align:center;color:var(--mut);padding:60px 20px}
.empty b{color:var(--addfg);font-size:1.3em}
"""


def _page(meta: dict, lang: str, body: str) -> str:
    toggle = ('<button id="lang-toggle">UK / EN</button>' if lang == "both" else "")
    title = f'{meta.get("base","?")} → {meta.get("head","?")}'
    return (
        "<!DOCTYPE html>\n<html lang=\"en\"><head><meta charset=\"utf-8\">"
        f"<title>review: {html.escape(title)}</title><style>{_CSS}</style></head><body>"
        "<header>"
        f"<strong>review</strong> <span class=\"meta\">{html.escape(title)} "
        f"· {html.escape(str(meta.get('mode','')))} · {html.escape(str(meta.get('generated','')))}</span>"
        "<span style=\"flex:1\"></span>"
        "<button id=\"expand-all\">Expand all</button>"
        "<button id=\"collapse-all\">Collapse all</button>"
        f"{toggle}"
        "<button id=\"export\">Export for Codex</button>"
        f"</header><main data-repo=\"{html.escape(str(meta.get('repo','')))}\" "
        f"data-ref=\"{html.escape(str(meta.get('head','')))}\">{body}</main>"
        f"<script>{_JS}</script></body></html>\n"
    )


def _nothing_to_review(meta: dict) -> str:
    return (
        '<div class="empty"><b>✓ Nothing to review.</b>'
        f'<p>No changes for {html.escape(str(meta.get("head","?")))} '
        f'vs {html.escape(str(meta.get("base","?")))}.</p></div>'
    )


def render_html(files: list[dict], expl: dict, lang: str, meta: dict) -> str:
    if not files:
        return _page(meta, lang, _nothing_to_review(meta))
    by_path = {f.get("path"): f for f in expl.get("files", [])}
    blocks = []
    for fi, f in enumerate(files):
        ef = by_path.get(f["path"], {})
        ehunks = ef.get("hunks", [])
        summary = render_text(ef.get("summary", ""), lang) if ef.get("summary") else ""
        hunks = "".join(
            render_hunk(hunk_id(fi, hi), h, ehunks[hi] if hi < len(ehunks) else {}, lang)
            for hi, h in enumerate(f["hunks"])
        )
        stat = f'<span class="fstat">+{f["added"]} -{f["removed"]}</span>'
        summ = f'<div class="fsummary">{summary}</div>' if summary else ""
        blocks.append(
            f'<details class="file" open data-path="{html.escape(f["path"])}">'
            f'<summary>{html.escape(f["path"])}{stat}</summary>'
            f'{summ}{hunks}</details>'
        )
    return _page(meta, lang, "".join(blocks))


def _atomic_write(path: str, content: str) -> None:
    d = os.path.dirname(os.path.abspath(path)) or "."
    os.makedirs(d, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=d, suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(content)
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.remove(tmp)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="Generate an HTML review page.")
    ap.add_argument("--diff", required=True)
    ap.add_argument("--explanations", required=True)
    ap.add_argument("--lang", default="ukr", choices=["ukr", "eng", "both"])
    ap.add_argument("--out", required=True)
    ap.add_argument("--meta", default=None)
    args = ap.parse_args(argv)

    with open(args.diff, encoding="utf-8") as f:
        diff_text = f.read()
    with open(args.explanations, encoding="utf-8") as f:
        expl = json.load(f)
    meta = {}
    if args.meta:
        with open(args.meta, encoding="utf-8") as f:
            meta_raw = json.load(f)
        meta = meta_raw.get("meta", meta_raw)
    files = parse_diff(diff_text)
    html_out = render_html(files, expl, args.lang, meta)
    _atomic_write(args.out, html_out)
    print(args.out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
