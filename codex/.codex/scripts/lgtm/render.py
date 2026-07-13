"""Render the LGTM review page. UI contract: design.md §6; canonical asset:
rescue-serverless/.superpowers/brainstorm/87136-1783148079/content/lgtm-pr1651-v2.html"""
from __future__ import annotations
import html as H
import json
import re
from lgtm.model import FileDiff, Hunk, Finding, ReviewMeta

BIG_FILE_LINES = 400
FAVICON = ("data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' "
           "viewBox='0 0 100 100'><text y='.9em' font-size='90'>🤖</text></svg>")
LAYER_BADGE = {"claude": ("b-claude", "🟣"), "code-review": ("b-cr", "🔵"),
               "bot": ("b-bot", "🟢"), "coach": ("b-coach", "🎓")}
# cls, sign per diff-line kind — shared by unified/left/right row builders in _hunk_html
_KIND = {"add": ("add", "+"), "del": ("del", "-"), "ctx": ("ctx", " ")}

def slug(path: str) -> str:
    return re.sub(r"[^a-zA-Z0-9]+", "-", path).strip("-").lower()

def _jb2b_review_cmd(ref: str = "") -> str:
    """Single source for the copy-to-buffer run command (6 call sites across pages)."""
    return f"jb2b review {ref}".strip()


def _nvim_cmd(line: int, path: str) -> str:
    return f"nvim +{line} {path}"

def _cpy_attr(cmd: str) -> str:
    """Safe onclick attribute value for cpy(<cmd>): JSON-encode then HTML-escape.

    cmd may contain arbitrary user/data-controlled text (file paths, refs).
    json.dumps produces a valid JS string literal (double-quoted, escaped),
    then HTML-escape the whole onclick value so it can't break out of the
    surrounding double-quoted attribute (finding: raw path injection)."""
    return H.escape(f"cpy({json.dumps(cmd)})", quote=True)

def _js_str_attr(s: str) -> str:
    """JS string literal safe to embed inside an HTML attribute (same rules
    as _cpy_attr: JSON-encode → HTML-escape)."""
    return H.escape(json.dumps(s), quote=True)

def _t(d: dict | None, lang: str) -> str:
    if not d: return ""
    return d.get(lang) or d.get("ukr") or d.get("eng") or ""

def _first_new_line(f: FileDiff) -> int:
    for h in f.hunks:
        for l in h.lines:
            if l.new_ln:
                return h.first_new_line
    return 1

def _tree_html(files: list[FileDiff], sev_by_file: dict[str, str]) -> str:
    # group by top dirs, compress single-child chains (VS Code style)
    out = []
    bydir: dict[str, list[FileDiff]] = {}
    for f in files:
        d = str(f.path).rsplit("/", 1)[0] if "/" in f.path else "."
        bydir.setdefault(d, []).append(f)
    for d in sorted(bydir):
        out.append(f'<div class="dir">▾ {H.escape(d)}/</div><div style="padding-left:16px">')
        for f in bydir[d]:
            name = f.path.rsplit("/", 1)[-1]
            sid = slug(f.path); ln = _first_new_line(f)
            sev = sev_by_file.get(f.path, "")
            minus = f'<span class="minus">−{f.deletions}</span>' if f.deletions else ""
            sev_span = f'<span style="margin-left:4px">{sev}</span>' if sev else ""
            out.append(
              f'<div class="file" onclick="go(\'f-{sid}\')">'
              f'<span class="{f.status.lower()}">{f.status}</span>{H.escape(name)}'
              f'<span class="plus">+{f.additions}</span>{minus}'
              f'{sev_span}'
              f'<span class="cico" onclick="event.stopPropagation();'
              f'{_cpy_attr(_nvim_cmd(ln, f.path))}">📋</span></div>')
        out.append("</div>")
    return "".join(out)

def _row(cls: str, sign: str, ln, text: str) -> str:
    return (f'<span class="{cls}"><span class="ln">{ln}</span>'
            f'{sign}{H.escape(text)}</span>')

def _hunk_html(sid: str, h: Hunk, findings: list[Finding], lang: str,
               path: str = "") -> str:
    rows = "".join(_row(*_KIND[l.kind], l.new_ln or l.old_ln or "", l.text) for l in h.lines)
    vid = f"{sid}-{h.hunk_id.lower()}"
    if h.has_add and h.has_del:
        seg = ('<span class="seg" onclick="event.stopPropagation()">'
               f'<span class="on" onclick="fMode(this,\'u\',\'{vid}\')">unified</span>'
               f'<span onclick="fMode(this,\'s\',\'{vid}\')">split</span></span>')
        left_rows = "".join(_row(*_KIND[l.kind], l.old_ln or "", l.text)
                            for l in h.lines if l.kind in ("del", "ctx"))
        right_rows = "".join(_row(*_KIND[l.kind], l.new_ln or "", l.text)
                             for l in h.lines if l.kind in ("add", "ctx"))
        views = (
            f'<div class="codeblk" id="u-{vid}" style="padding:5px 0">{rows}</div>'
            f'<div class="split2" id="s-{vid}" style="display:none">'
            f'<div><div style="padding:2px 6px;color:var(--dim);font-size:.8em">було</div>'
            f'<div class="codeblk" style="padding:5px 0">{left_rows}</div></div>'
            f'<div><div style="padding:2px 6px;color:var(--dim);font-size:.8em">стало</div>'
            f'<div class="codeblk" style="padding:5px 0">{right_rows}</div></div></div>')
    else:
        kind = "add-only" if h.has_add else "del-only"
        seg = (f'<span class="seg off" title="split недоступний: '
               f'{kind} ханк — друга колонка порожня">'
               '<span>unified</span><span style="text-decoration:line-through">split</span></span>')
        views = f'<div class="codeblk" style="padding:5px 0">{rows}</div>'
    finds = "".join(_finding_html(x, lang, vid) for x in findings)
    # live-loop surface (design §3): thread container + ask-Codex form.
    # Hidden on file:// (static mode) — JS reveals it only when served over http.
    thread = (
        f'<div class="lthread" id="th-{vid}"></div>'
        f'<div class="ask" id="ask-{vid}" style="display:none" '
        f'data-hunk="{H.escape(h.hunk_id, quote=True)}" '
        f'data-file="{H.escape(path, quote=True)}" '
        f'data-line="{h.first_new_line}">'
        f'<textarea rows="2" placeholder="💬 запитати Codex про цей ханк… '
        f'(Ctrl-Enter — надіслати)"></textarea>'
        f'<button onclick="askSend(\'{vid}\')">▶</button>'
        f'<input type="hidden" class="fid" value="">'
        f'</div>')
    return (f'<div style="padding:6px 12px;background:var(--panel2);font-size:.85em;'
            f'color:var(--dim)">{H.escape(h.header)} · {h.hunk_id} {seg}</div>'
            f'{views}{finds}{thread}')

def _finding_html(x: Finding, lang: str, vid: str = "") -> str:
    cls, emoji = LAYER_BADGE.get(x.layer, ("b-claude", "🟣"))
    agrees = "".join(f'<span class="badge b-bot">🟢 {H.escape(a)}</span>' for a in x.agrees_with)
    code = f'<div class="codeblk">{H.escape(x.fix.get("code",""))}</div>' if x.fix.get("code") else ""
    cmd = _nvim_cmd(x.line, x.file)
    # 💬 pre-targets the hunk's ask form at THIS finding (live mode only)
    ask = (f'<span class="cico ask-live" style="display:none" title="запитати Codex '
           f'про цю знахідку" onclick="event.stopPropagation();'
           f'askFor(\'{vid}\',{_js_str_attr(x.id)})">💬</span>') if vid else ""
    # bugfix: .find.coach / .find.ok CSS existed but the class was never applied
    extra = " coach" if x.layer == "coach" else (" ok" if x.severity_score <= 5 else "")
    return (f'<div class="find{extra}" data-fid="{H.escape(x.id, quote=True)}" '
            f'onclick="{_cpy_attr(cmd)}">'
            f'<span class="badge {cls}">{emoji} {H.escape(x.source)} · {H.escape(x.severity_emoji)} '
            f'{H.escape(str(x.severity_score))}/100</span>{agrees}{ask}'
            f'<div style="margin-top:5px"><b>Проблема:</b> {H.escape(_t(x.problem, lang))}</div>'
            f'<div><b>Шкода:</b> {H.escape(_t(x.harm, lang))}</div>'
            f'<div><b>Фікс:</b> {H.escape(_t(x.fix, lang))}</div>{code}</div>')

def _coach_panel(findings: list[Finding], stats: dict | None, lang: str) -> str:
    """🎓 right column (design §6): per-file patterns from THIS codebase +
    progress between reviews. Empty string when there is nothing to show."""
    coach = [x for x in findings if x.layer == "coach" or x.coach]
    cards = []
    for x in coach:
        c = x.coach or {}
        ref = c.get("ref", "")
        read = c.get("read", "")
        parts = [f'<div class="ccard" onclick="go(\'f-{slug(x.file)}\')">'
                 f'<b>{H.escape(c.get("pattern") or _t(x.problem, lang)[:80])}</b>']
        if ref:
            parts.append(f'<div class="cref" onclick="event.stopPropagation();'
                         f'{_cpy_attr(_nvim_cmd(1, ref))}">📋 {H.escape(ref)}</div>')
        if read:
            parts.append(f'<div style="color:var(--dim)">📖 {H.escape(read)}</div>')
        parts.append("</div>")
        cards.append("".join(parts))
    stat_html = ""
    if stats:
        rows = []
        for pat, pts in stats.items():
            counts = [c for _, c in pts]
            mark = " 🎉" if counts and counts[-1] == 0 and any(counts[:-1]) else ""
            rows.append(f'<div class="srow"><span>{H.escape(pat)}</span>'
                        f'<span>{" → ".join(str(c) for c in counts)}{mark}</span></div>')
        stat_html = ('<div class="label" style="margin-top:12px">📈 прогрес між рев\'ю</div>'
                     + "".join(rows))
    if not cards and not stat_html:
        return ""
    return (f'<div class="coach"><div class="label">🎓 coach</div>'
            f'{"".join(cards)}{stat_html}</div>')

def render_page(meta: ReviewMeta, files: list[FileDiff],
                findings: list[Finding], summary: dict | None,
                stats: dict | None = None) -> str:
    lang = meta.lang
    sev_by_file = {}
    by_hunk: dict[str, list[Finding]] = {}
    for x in findings:
        sev_by_file[x.file] = sev_by_file.get(x.file, "") + H.escape(x.severity_emoji)
        by_hunk.setdefault(x.hunk, []).append(x)
    cards = []
    for f in files:
        big = f.additions + f.deletions > BIG_FILE_LINES
        body_style = ' style="display:none"' if big else ""
        arrow = "▸" if big else "▾"
        sid = slug(f.path)
        hunks = "".join(_hunk_html(sid, h, by_hunk.get(h.hunk_id, []), lang, f.path)
                        for h in f.hunks)
        cards.append(
          f'<div class="card" id="f-{sid}">'
          f'<div class="fhead" onclick="tg(this)"><span class="arrow">{arrow}</span>'
          f'<b>{H.escape(f.path)}</b><span style="color:var(--dim)">· {len(f.hunks)} ханків '
          f'· +{f.additions} −{f.deletions}{" · згорнуто (великий)" if big else ""}</span>'
          f'{sev_by_file.get(f.path, "")}</div>'
          f'<div class="cbody"{body_style}>{hunks}</div></div>')
    summary_html = ""
    if summary:
        summary_html = (f'<div class="prsum"><div class="label">📋 що робить цей PR</div>'
                        f'<div>{H.escape(_t(summary.get("what"), lang))}</div>'
                        f'<div style="color:var(--dim)">🧒 {H.escape(_t(summary.get("simple"), lang))}</div></div>')
    total_f = len(files)
    header = (f'<b>LGTM</b> <span class="pill">⎇ {H.escape(meta.ref)}</span>'
              f'<span class="pill">base: {H.escape(meta.base)}</span>'
              f'<span class="pill" onclick="{_cpy_attr(_jb2b_review_cmd(meta.ref))}">'
              f'📋 jb2b review</span>'
              f'<span class="pill" onclick="helpTg()">❓ довідка</span>'
              f'<span class="pill" id="liveDot" title="live-петля з Codex: '
              f'запусти jb2b review-serve + /lgtm-listen">○ static</span>'
              f'<span class="pill" style="margin-left:auto">{total_f}/{total_f} файлів · '
              f'{sum(f.additions for f in files)}+ {sum(f.deletions for f in files)}−</span>')
    help_overlay = """<div id="helpOv" style="display:none;position:fixed;inset:0;background:rgba(0,0,0,.6);z-index:98" onclick="helpTg()">
  <div style="max-width:520px;margin:8vh auto;background:var(--panel);border:1px solid var(--acc);border-radius:12px;padding:18px" onclick="event.stopPropagation()">
    <b>❓ Як користуватись</b>
    <ul style="line-height:2;margin:8px 0 0 18px">
      <li>клік по файлу в дереві → перейти до його ханків</li>
      <li>📋 → повна команда в буфер (nvim/rg/jb2b)</li>
      <li>клік по шапці ханка → згорнути/розгорнути</li>
      <li>unified ⇄ split (недоступний на add-only ханках)</li>
      <li><code>?</code> → ця довідка · <code>Esc</code> → закрити</li>
    </ul>
  </div>
</div>"""
    coach_html = _coach_panel(findings, stats, lang)
    lay_cls = "lay with-coach" if coach_html else "lay"
    body = (f'<div class="rv">'
            f'<div class="topbar">{header}</div>'
            f'<div class="{lay_cls}"><div class="nav">{_tree_html(files, sev_by_file)}</div>'
            f'<div class="center">{summary_html}{"".join(cards)}</div>'
            f'{coach_html}</div>'
            f'</div>{help_overlay}')
    return _page_shell(f"LGTM · {H.escape(meta.ref)} · {H.escape(meta.repo)}",
                        'uk' if lang == 'ukr' else 'en', body)

def _page_shell(title: str, lang_attr: str, body: str,
                extra_css: str = "", extra_js: str = "") -> str:
    """Shared DOCTYPE/head/meta/viewport/favicon/style/toast/script skeleton
    for both the review page (render_page) and the index page (indexpage.render_index)."""
    return f"""<!DOCTYPE html>
<html lang="{lang_attr}"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title}</title>
<link rel="icon" href="{FAVICON}">
<style>{CSS}{extra_css}</style></head>
<body>{body}<div class="toast" id="cpToast"></div>
<script>{JS}{extra_js}</script></body></html>"""

# CSS and JS: copied verbatim from the canonical mockup (see module docstring),
# with .lay/.nav/.center/.topbar/.prsum grid classes added to match this template.
CSS = r"""
  .rv * { box-sizing:border-box; }
  :root{--bg:#0d1117;--panel:#161b22;--panel2:#1c2330;--line:#30363d;--txt:#e6edf3;--dim:#8b949e;--acc:#58a6ff;--grn:#3fb950;--red:#f85149;--org:#d29922;--purple:#a371f7}
  .rv,.ix{background:var(--bg);color:var(--txt);border:1px solid var(--line);border-radius:12px;overflow:hidden;font-size:clamp(13px,.5vw + 11px,15px);line-height:1.55}
  .rv code{font-family:ui-monospace,monospace}
  .rv .codeblk{font-family:ui-monospace,monospace;font-size:.85em;white-space:pre;overflow-x:auto;line-height:1.45}
  .rv .ln{opacity:.35;display:inline-block;width:36px;text-align:right;margin-right:10px;user-select:none}
  .rv .del{background:rgba(248,81,73,.13);color:#ff9a94;display:block;padding:0 6px}
  .rv .add{background:rgba(63,185,80,.13);color:#7ee787;display:block;padding:0 6px}
  .rv .ctx{display:block;opacity:.7;padding:0 6px}
  .pill{background:var(--panel2);border:1px solid var(--line);border-radius:20px;padding:2px 10px;font-size:.8em;cursor:pointer}
  .pill:hover{border-color:var(--acc)}
  .rv .badge{padding:2px 9px;border-radius:20px;font-size:.78em;display:inline-block;margin:2px 3px 0 0}
  .rv .b-claude{background:rgba(163,113,247,.18);color:#d2b8ff;border:1px solid rgba(163,113,247,.4)}
  .rv .b-coach{background:rgba(210,153,34,.16);color:#f0d48a;border:1px solid rgba(210,153,34,.4)}
  .rv .b-cr{background:rgba(88,166,255,.16);color:#a9d4ff;border:1px solid rgba(88,166,255,.4)}
  .rv .b-bot{background:rgba(63,185,80,.16);color:#8ff0a0;border:1px solid rgba(63,185,80,.4)}
  .rv .find{border-left:3px solid var(--org);background:rgba(210,153,34,.07);padding:8px 12px;cursor:pointer}
  .rv .find:hover{background:rgba(210,153,34,.13)}
  .rv .find.coach{border-left-color:var(--purple);background:rgba(163,113,247,.06)}
  .rv .find.ok{border-left-color:var(--grn);background:rgba(63,185,80,.06)}
  .rv .card{background:var(--panel);border:1px solid var(--line);border-radius:10px;overflow:hidden;margin-bottom:12px}
  .rv .fhead{display:flex;gap:8px;align-items:center;flex-wrap:wrap;background:var(--panel2);padding:8px 12px;border-bottom:1px solid var(--line);cursor:pointer;user-select:none}
  .rv .arrow{width:14px;display:inline-block}
  .rv .tree{font-family:ui-monospace,monospace;font-size:.88em;line-height:1.9}
  .rv .file{cursor:pointer;padding:1px 6px;border-radius:6px;display:flex;gap:7px;align-items:center}
  .rv .file:hover{background:rgba(88,166,255,.1)}
  .rv .m{color:var(--org);font-weight:700}.rv .a{color:var(--grn);font-weight:700}
  .rv .d{color:var(--red);font-weight:700}
  .rv .plus{color:var(--grn);font-size:.82em}.rv .minus{color:var(--red);font-size:.82em}
  .rv .dir{color:var(--dim)}
  .rv .cico{margin-left:auto;cursor:pointer;opacity:.7}.rv .cico:hover{opacity:1}
  .rv .toast{position:fixed;bottom:18px;left:50%;transform:translateX(-50%);background:var(--panel);border:1px solid var(--grn);border-radius:10px;padding:10px 18px;z-index:99;display:none;box-shadow:0 12px 40px rgba(0,0,0,.6);font-family:ui-monospace,monospace;font-size:.9em;max-width:90vw;overflow-x:auto;white-space:nowrap}
  @media(max-width:900px){.rv .lay{grid-template-columns:1fr!important}.rv .nav{border-right:none!important;border-bottom:1px solid var(--line)}}
  .rv .topbar{display:flex;align-items:center;gap:10px;padding:11px 16px;border-bottom:1px solid var(--line);background:var(--panel);flex-wrap:wrap}
  .rv .lay{display:grid;grid-template-columns:minmax(250px,320px) minmax(0,1fr)}
  .rv .nav{border-right:1px solid var(--line);background:var(--panel);padding:12px;overflow:auto;position:sticky;top:0;align-self:start;max-height:100vh}
  .rv .center{padding:14px;overflow:auto;min-width:0}
  .rv .prsum{background:rgba(88,166,255,.07);border:1px solid rgba(88,166,255,.3);border-radius:10px;padding:11px 13px;margin-bottom:12px}
  .rv .label{font-size:.76em;text-transform:uppercase;color:var(--dim)}
  @media(max-width:900px){.rv .lay{grid-template-columns:1fr}.rv .nav{border-right:none;border-bottom:1px solid var(--line);position:static;max-height:none}}
  .rv .seg{display:inline-flex;border:1px solid var(--line);border-radius:8px;overflow:hidden;font-size:.78em;margin-left:auto}
  .rv .seg span{padding:2px 9px;cursor:pointer;color:var(--dim)}
  .rv .seg span.on{background:rgba(88,166,255,.15);color:var(--txt)}
  .rv .seg.off{opacity:.45}
  .rv .split2{display:grid;grid-template-columns:1fr 1fr}
  .rv .split2>div{min-width:0;border-right:1px solid var(--line)}
  @media(max-width:800px){.rv .split2{grid-template-columns:1fr}}
  /* coach panel (design §6 right column) */
  .rv .lay.with-coach{grid-template-columns:minmax(250px,320px) minmax(0,1fr) minmax(220px,280px)}
  .rv .coach{border-left:1px solid var(--line);background:var(--panel);padding:12px;overflow:auto;position:sticky;top:0;align-self:start;max-height:100vh}
  .rv .ccard{border:1px solid rgba(210,153,34,.4);background:rgba(210,153,34,.07);border-radius:10px;padding:8px 11px;margin:8px 0;cursor:pointer;font-size:.9em}
  .rv .ccard:hover{border-color:var(--org)}
  .rv .cref{font-family:ui-monospace,monospace;font-size:.85em;color:var(--acc);cursor:pointer}
  .rv .srow{display:flex;justify-content:space-between;gap:8px;font-size:.85em;padding:3px 0;border-bottom:1px dashed var(--line)}
  @media(max-width:1100px){.rv .lay.with-coach{grid-template-columns:minmax(250px,320px) minmax(0,1fr)}.rv .coach{grid-column:1/-1;border-left:none;border-top:1px solid var(--line);position:static;max-height:none}}
  /* live loop (design §3) */
  .rv .lthread{padding:0 12px}
  .rv .msg{border:1px solid var(--line);border-radius:10px;padding:7px 11px;margin:7px 0;max-width:92%;white-space:pre-wrap}
  .rv .msg.mike{border-color:rgba(88,166,255,.5);background:rgba(88,166,255,.08);margin-left:auto}
  .rv .msg.claude{border-color:rgba(163,113,247,.5);background:rgba(163,113,247,.07)}
  .rv .msg .mwho{font-size:.75em;color:var(--dim);margin-bottom:3px}
  .rv .msg .codeblk{margin-top:6px;padding:6px;border-radius:6px;background:var(--bg)}
  .rv .msg.thinking{opacity:.65;font-style:italic}
  .rv .ask{display:flex;gap:8px;padding:8px 12px;align-items:flex-end}
  .rv .ask textarea{flex:1;background:var(--panel2);color:var(--txt);border:1px solid var(--line);border-radius:8px;padding:7px 10px;font:inherit;resize:vertical;min-width:0}
  .rv .ask textarea:focus{border-color:var(--acc);outline:none}
  .rv .ask button{background:rgba(88,166,255,.15);color:var(--acc);border:1px solid var(--acc);border-radius:8px;padding:7px 14px;cursor:pointer}
  .rv .ask button:hover{background:rgba(88,166,255,.3)}
  #liveDot.on{border-color:var(--grn);color:var(--grn)}
"""
JS = r"""
  function cpy(cmd){
    var ok = false;
    try {
      var ta = document.createElement('textarea');
      ta.value = cmd; ta.style.position='fixed'; ta.style.opacity='0';
      document.body.appendChild(ta); ta.select();
      ok = document.execCommand('copy');
      document.body.removeChild(ta);
    } catch(e){}
    if (!ok && navigator.clipboard) { navigator.clipboard.writeText(cmd); ok = true; }
    var t = document.getElementById('cpToast');
    t.textContent = (ok ? '📋 в буфері: ' : '⚠️ скопіюй вручну: ') + cmd;
    t.style.display='block'; clearTimeout(t._t); t._t=setTimeout(function(){t.style.display='none'},3200);
    if (window.event) window.event.stopPropagation();
  }
  function cpy2(msg){
    var t = document.getElementById('cpToast');
    t.textContent = 'ℹ️ ' + msg;
    t.style.display='block'; clearTimeout(t._t); t._t=setTimeout(function(){t.style.display='none'},3000);
    if (window.event) window.event.stopPropagation();
  }
  function go(id){
    var el = document.getElementById(id);
    if (!el) return;
    var body = el.querySelector('.cbody');
    var arrow = el.querySelector('.arrow');
    if (body && body.style.display === 'none') { body.style.display=''; if (arrow) arrow.textContent='▾'; }
    el.scrollIntoView({behavior:'smooth', block:'start'});
    el.style.outline='2px solid var(--acc)';
    setTimeout(function(){ el.style.outline='none'; }, 1600);
  }
  function tg(head){
    var body = head.parentElement.querySelector('.cbody');
    var arrow = head.querySelector('.arrow');
    if (!body) return;
    var hidden = body.style.display === 'none';
    body.style.display = hidden ? '' : 'none';
    if (arrow) arrow.textContent = hidden ? '▾' : '▸';
  }
  function fMode(el,m,vid){
    el.parentElement.querySelectorAll('span').forEach(function(s){s.classList.remove('on');});
    el.classList.add('on');
    document.getElementById('u-'+vid).style.display = m==='u' ? '' : 'none';
    document.getElementById('s-'+vid).style.display = m==='s' ? '' : 'none';
  }
  function helpTg(){var o=document.getElementById('helpOv');o.style.display=o.style.display==='none'?'':'none';}
  document.addEventListener('keydown',function(e){
    if(e.key==='?'&&!/INPUT|TEXTAREA/.test(document.activeElement.tagName))helpTg();
    if(e.key==='Escape')document.getElementById('helpOv').style.display='none';});

  /* ===== live loop (design §3): SSE thread + ask-Codex forms ===== */
  var LIVE = location.protocol.indexOf('http') === 0 && document.querySelector('.ask');
  function thBox(hunk, file){
    // hunk container id = th-<file-slug>-<hunkid lower>; find by data-attrs
    var forms = document.querySelectorAll('.ask');
    for (var k = 0; k < forms.length; k++)
      if (forms[k].dataset.hunk === hunk && (!file || forms[k].dataset.file === file))
        return document.getElementById('th-' + forms[k].id.slice(4));
    return null;
  }
  function msgHtml(m){
    var d = document.createElement('div');
    d.className = 'msg ' + (m.who === 'claude' ? 'claude' : 'mike');
    d.dataset.mid = m.id || '';
    var who = document.createElement('div'); who.className = 'mwho';
    who.textContent = (m.who === 'claude' ? '🟣 claude' : '💬 mike') + ' · ' + (m.ts || '');
    var tx = document.createElement('div'); tx.textContent = m.text || '';
    d.appendChild(who); d.appendChild(tx);
    if (m.code){ var c = document.createElement('div'); c.className = 'codeblk';
                 c.textContent = m.code; d.appendChild(c); }
    return d;
  }
  function addMsg(m){
    if (m.id && document.querySelector('[data-mid="' + m.id + '"]')) return; // echo dedup
    var box = thBox(m.hunk || '', m.file || '') || document.querySelector('.lthread');
    if (!box) return;
    var th = box.querySelector('.msg.thinking');
    if (m.who === 'claude' && th) th.remove();
    box.appendChild(msgHtml(m));
  }
  function askFor(vid, fid){
    var f = document.getElementById('ask-' + vid);
    if (!f) return;
    f.querySelector('.fid').value = fid || '';
    var ta = f.querySelector('textarea');
    ta.placeholder = '💬 запитати Codex про знахідку ' + fid + '…';
    ta.focus();
  }
  function askSend(vid){
    var f = document.getElementById('ask-' + vid);
    var ta = f.querySelector('textarea');
    var text = ta.value.trim();
    if (!text) return;
    var payload = {text: text, hunk: f.dataset.hunk, file: f.dataset.file,
                   line: parseInt(f.dataset.line || '0', 10),
                   finding_id: f.querySelector('.fid').value};
    fetch('/comment', {method: 'POST', headers: {'Content-Type': 'application/json'},
                       body: JSON.stringify(payload)})
      .then(function(r){ if (!r.ok) throw new Error(r.status);
        ta.value = ''; f.querySelector('.fid').value = '';
        var box = document.getElementById('th-' + vid);
        var th = document.createElement('div');
        th.className = 'msg claude thinking'; th.textContent = '🟣 Codex думає…';
        box.appendChild(th); })
      .catch(function(e){ cpy2('не надіслалось: ' + e + ' — сервер живий? jb2b review-serve'); });
  }
  if (LIVE){
    document.querySelectorAll('.ask').forEach(function(f){ f.style.display = 'flex';
      f.querySelector('textarea').addEventListener('keydown', function(e){
        if (e.key === 'Enter' && (e.ctrlKey || e.metaKey)) askSend(f.id.slice(4)); }); });
    document.querySelectorAll('.ask-live').forEach(function(b){ b.style.display = ''; });
    var dot = document.getElementById('liveDot');
    var es = new EventSource('/events?after=0.0');
    es.onopen = function(){ if (dot){ dot.textContent = '● live'; dot.classList.add('on'); } };
    es.onerror = function(){ if (dot){ dot.textContent = '○ reconnect…'; dot.classList.remove('on'); } };
    es.onmessage = function(e){
      try { addMsg(JSON.parse(e.data)); } catch(err) {}
    };
  }
"""
