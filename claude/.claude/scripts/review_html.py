#!/usr/bin/env python3
"""review_html.py — generate a self-contained HTML review page.

(unified diff text, explanations.json, lang) -> one standalone .html file.
Pure rendering, Python stdlib only. Driven by the /review-html Claude command.
"""
from __future__ import annotations

import argparse
import html
import json
import os
import tempfile
from itertools import zip_longest


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


def _diagram(spec, lang: str) -> str:
    """Render a Mermaid diagram from an explanation `diagram` field (str or {lang:str})."""
    if not spec:
        return ""
    code = _text(spec, lang)
    if not code.strip():
        return ""
    return (
        '<div class="diagram"><div class="panel-label">🗺 Diagram</div>'
        f'<pre class="mermaid">{html.escape(code)}</pre></div>'
    )


def _split_rows(lines: list) -> list:
    """Turn a unified hunk into aligned (left, right) rows for a side-by-side diff.

    Context lines appear in both columns on the same row. Runs of deletions and
    additions are zipped row-by-row (a `del` on the left lines up with the
    matching `add` on the right); the shorter side is padded with empty cells.
    """
    rows: list = []
    pend_del: list = []
    pend_add: list = []
    for tag, text in lines:
        if tag == "ctx":
            # zip_longest pads the shorter side with None (an empty cell).
            rows.extend(zip_longest(pend_del, pend_add))
            rows.append((("ctx", text), ("ctx", text)))
            pend_del, pend_add = [], []
        elif tag == "del":
            pend_del.append(("del", text))
        else:  # add
            pend_add.append(("add", text))
    rows.extend(zip_longest(pend_del, pend_add))
    return rows


_SIGN = {"add": "+", "del": "-", "ctx": " "}


def _cell(side: str, cell) -> str:
    if cell is None:
        return f'<div class="ln empty {side}"></div>'
    tag, text = cell
    return (
        f'<div class="ln {tag} {side}"><span class="sign">{_SIGN[tag]}</span>'
        f'<code>{html.escape(text)}</code></div>'
    )


def _uni(tag: str, text: str) -> str:
    return (
        f'<div class="ln {tag}"><span class="sign">{_SIGN[tag]}</span>'
        f'<code>{html.escape(text)}</code></div>'
    )


def render_hunk(hid: str, hunk: dict, expl: dict, lang: str) -> str:
    tags = {t for t, _ in hunk["lines"]}
    # Side-by-side only when the hunk actually changes both sides. A new file,
    # a pure-addition, or a pure-deletion hunk has one empty column — render it
    # full-width in a single column instead of wasting half the screen.
    if "del" in tags and "add" in tags:
        diff_cls = "diff split"
        # Each (left, right) pair is its own flex row so the row height is the
        # height of one code line. Relying on grid auto-flow (2 columns) instead
        # mis-sized rows when a hunk had a large pure-addition tail, leaving huge
        # vertical gaps between the added lines on the right.
        diff_rows = "".join(
            f'<div class="drow">{_cell("L", lo)}{_cell("R", ro)}</div>'
            for lo, ro in _split_rows(hunk["lines"])
        )
    else:
        diff_cls = "diff unified"
        diff_rows = "".join(_uni(t, x) for t, x in hunk["lines"])

    desc = expl.get("description")
    desc_html = ""
    if desc:
        desc_html = (
            '<div class="panel desc"><div class="panel-label">📝 What &amp; why</div>'
            f'<div class="body">{render_text(desc, lang)}</div></div>'
        )

    diagram_html = _diagram(expl.get("diagram"), lang)

    problems = expl.get("problems") or []
    prob_html = ""
    if problems:
        items = ""
        for p in problems:
            sev = html.escape(str(p.get("severity", "info")))
            items += (
                f'<li class="sev-{sev}"><span class="badge {sev}">{sev}</span>'
                f'{render_text(p.get("text", ""), lang)}</li>'
            )
        prob_html = (
            '<div class="panel problems"><div class="panel-label">⚠️ Notes</div>'
            f'<ul>{items}</ul></div>'
        )

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

    expl_inner = f"{desc_html}{diagram_html}{prob_html}{rep_html}"
    expl_html = f'<div class="expl">{expl_inner}</div>' if expl_inner else ""

    return (
        f'<div class="hunk" id="{hid}">'
        f'<div class="hunk-head"><code>{html.escape(hunk["header"])}</code>'
        f'<button class="copy" data-hunk="{hid}">Copy for Claude</button></div>'
        f'<div class="{diff_cls}">{diff_rows}</div>'
        f'{expl_html}'
        f'<textarea class="comment" data-hunk="{hid}" '
        f'placeholder="comment for Claude…"></textarea>'
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
  // per-hunk Copy for Claude
  document.querySelectorAll('button.copy').forEach(function(b){
    b.addEventListener('click',function(){
      var h=b.dataset.hunk;
      var c=document.querySelector('textarea.comment[data-hunk="'+h+'"]').value||'(no comment)';
      copy(block(h,c)); b.textContent='Copied ✓'; setTimeout(function(){b.textContent='Copy for Claude';},1200);
    });
  });
  // Export for Claude: bundle all non-empty comments -> clipboard (+ download fallback)
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
:root{--bg:#1e1e2e;--fg:#cdd6f4;--mut:#9399b2;--add:#1c3a1c;--del:#3a1c1c;
--addfg:#a6e3a1;--delfg:#f38ba8;--card:#181825;--card2:#11111b;--line:#262636;
--acc:#89b4fa;--peach:#fab387;
--mono:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;
--sans:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--fg);font:15px/1.65 var(--sans)}
header{position:sticky;top:0;z-index:10;background:var(--card);padding:12px 24px;
border-bottom:1px solid #313244;display:flex;gap:12px;align-items:center;flex-wrap:wrap}
header strong{font-size:16px}
header .meta{color:var(--mut);font-family:var(--mono);font-size:13px}
button{background:#313244;color:var(--fg);border:1px solid #45475a;border-radius:6px;
padding:6px 12px;cursor:pointer;font:inherit;font-size:13px}
button:hover{border-color:var(--acc)}
/* full-width: use the whole screen, only cap on ultra-wide */
main{padding:24px 32px;max-width:2200px;margin:0 auto}
.overview{background:var(--card);border:1px solid #313244;border-left:3px solid var(--peach);
border-radius:10px;padding:16px 20px;margin:0 0 22px}
.overview .body{font-size:15.5px;line-height:1.75}
details.file{background:var(--card);border:1px solid #313244;border-radius:10px;
margin:0 0 22px;overflow:hidden}
details.file>summary{cursor:pointer;padding:14px 18px;font-weight:700;color:var(--acc);
font-family:var(--mono);font-size:15px;background:#1a1a29}
.fstat{color:var(--mut);font-weight:400;margin-left:10px;font-size:13px}
.fsummary{padding:12px 18px;color:var(--fg);font-size:15px;
border-bottom:1px solid #313244;background:#15151f}
.file-diagram{padding:14px 18px;border-bottom:1px solid #313244}
.hunk{border-top:1px solid var(--line);padding:16px 18px}
.hunk:first-of-type{border-top:none}
.hunk-head{display:flex;justify-content:space-between;align-items:center;color:var(--mut);
font-family:var(--mono);font-size:12.5px;margin-bottom:8px;gap:10px}
/* side-by-side diff: old | new */
.diff{margin:0 0 12px;border-radius:8px;background:var(--card2);overflow:hidden;
border:1px solid var(--line)}
.diff.split{display:block}
.drow{display:flex}
.drow>.ln{flex:1 1 50%}
.diff.split .ln.L{border-right:1px solid var(--line)}
.ln{white-space:pre;display:flex;font-family:var(--mono);font-size:13px;line-height:1.55;min-width:0}
.ln code{background:none;padding:0;overflow-x:auto}
.ln .sign{width:1.6em;text-align:center;color:var(--mut);flex:none}
.ln.add{background:var(--add)} .ln.add .sign,.ln.add code{color:var(--addfg)}
.ln.del{background:var(--del)} .ln.del .sign,.ln.del code{color:var(--delfg)}
.ln.ctx code{color:var(--fg)}
.ln.empty{background:#15151f}
@media(max-width:1000px){.drow{flex-direction:column}
.diff.split .ln.L{border-right:none}}
/* explanation panels — always visible, sans-serif, readable */
.expl{display:flex;flex-direction:column;gap:12px;margin:4px 0 10px}
.panel{background:#15151f;border:1px solid var(--line);border-left:3px solid var(--acc);
border-radius:8px;padding:12px 14px}
.panel.problems{border-left-color:var(--peach)}
.panel-label{font-weight:700;font-size:12px;text-transform:uppercase;letter-spacing:.04em;
color:var(--mut);margin-bottom:6px}
.panel .body{font-size:15px;line-height:1.7}
.panel ul{margin:0;padding-left:0;list-style:none}
.panel.problems li{margin:6px 0}
.badge{border-radius:5px;padding:1px 7px;margin-right:8px;font-size:11px;font-weight:700;
text-transform:uppercase}
.badge.warn{background:var(--peach);color:#1e1e2e}
.badge.info{background:var(--acc);color:#1e1e2e}
.diagram{background:#15151f;border:1px solid var(--line);border-radius:8px;padding:10px 14px}
.diagram .mermaid{margin:0;text-align:center;background:none;overflow-x:auto}
.replies{margin:4px 0;border-left:3px solid var(--acc);padding-left:12px}
.replies .thread{margin:8px 0}
.replies .you{color:var(--peach)} .replies .claude{color:var(--addfg)}
textarea.comment{width:100%;min-height:50px;margin-top:4px;background:var(--card2);
color:var(--fg);border:1px solid #45475a;border-radius:8px;padding:8px 10px;
font:inherit;font-family:var(--mono);font-size:13px}
.empty{text-align:center;color:var(--mut);padding:60px 20px}
.empty b{color:var(--addfg);font-size:1.3em}
"""


def _page(meta: dict, lang: str, body: str) -> str:
    toggle = ('<button id="lang-toggle">UK / EN</button>' if lang == "both" else "")
    title = f'{meta.get("base","?")} → {meta.get("head","?")}'
    # Only pull the Mermaid CDN when the page actually has a diagram.
    mermaid = (
        '<script src="https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js"></script>'
        "<script>try{mermaid.initialize({startOnLoad:true,theme:'dark',"
        "securityLevel:'loose',flowchart:{useMaxWidth:true}});}catch(e){}</script>"
    ) if 'class="mermaid"' in body else ""
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
        "<button id=\"export\">Export for Claude</button>"
        f"</header><main data-repo=\"{html.escape(str(meta.get('repo','')))}\" "
        f"data-ref=\"{html.escape(str(meta.get('head','')))}\">{body}</main>"
        f"{mermaid}"
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

    # Optional top-level overview (text + diagram) describing the whole change set.
    overview = expl.get("overview")
    if overview:
        ov_diag = _diagram(expl.get("diagram"), lang)
        blocks.append(
            '<div class="overview"><div class="panel-label">🔎 Overview</div>'
            f'<div class="body">{render_text(overview, lang)}</div>{ov_diag}</div>'
        )

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
        fdiag = _diagram(ef.get("diagram"), lang)
        fdiag_html = f'<div class="file-diagram">{fdiag}</div>' if fdiag else ""
        blocks.append(
            f'<details class="file" open data-path="{html.escape(f["path"])}">'
            f'<summary>{html.escape(f["path"])}{stat}</summary>'
            f'{summ}{fdiag_html}{hunks}</details>'
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
