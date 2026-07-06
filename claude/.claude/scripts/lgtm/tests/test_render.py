from lgtm.model import DiffLine, Hunk, FileDiff, Finding, ReviewMeta
from lgtm.render import render_page, slug

META = ReviewMeta(ref="pr1651", base="(github)", mode="pr",
                  generated="2026-07-04", repo="rescue-serverless", lang="ukr")

def _files():
    mixed = Hunk("F0H0", "@@ -1,2 +1,2 @@", 1, 1,
                 [DiffLine("del", 1, None, "old"), DiffLine("add", None, 1, "new")])
    addonly = Hunk("F1H0", "@@ -0,0 +1,1 @@", 0, 1, [DiffLine("add", None, 1, "x")])
    return [FileDiff("a/b.py", "M", [mixed]), FileDiff("c/new.py", "A", [addonly])]

def _finding():
    return Finding(id="f1", layer="claude", source="claude-deep", file="a/b.py",
                   line=1, hunk="F0H0", severity_emoji="🟠", severity_score=65,
                   problem={"ukr": "Проблема тут"}, harm={"ukr": "Шкода"},
                   fix={"ukr": "Фікс", "code": "y = 2"}, agrees_with=[], coach=None)

def test_all_files_all_hunks_present():
    html = render_page(META, _files(), [], None)
    for marker in ("a/b.py", "c/new.py", "F0H0", "F1H0", "old", "new"):
        assert marker in html

def test_tree_and_copy_separation():
    html = render_page(META, _files(), [], None)
    assert f"go('f-{slug('a/b.py')}')" in html
    # cpy() attrs are JSON-encoded then HTML-escaped for XSS safety (see
    # test_cpy_attr_escapes_quotes); un-escape the quotes before matching the raw JS call.
    assert 'cpy("nvim +1 a/b.py")' in html.replace("&quot;", '"')

def test_split_toggle_only_on_mixed_hunks():
    html = render_page(META, _files(), [], None)
    assert html.count("fMode(") >= 2          # working toggle on the mixed hunk
    assert "split недоступний" in html         # disabled tooltip on add-only

def test_split_views_per_hunk_unique_ids():
    m1 = Hunk("F0H0", "@@ -1 +1 @@", 1, 1, [DiffLine("del", 1, None, "a"), DiffLine("add", None, 1, "b")])
    m2 = Hunk("F0H1", "@@ -5 +5 @@", 5, 5, [DiffLine("del", 5, None, "c"), DiffLine("add", None, 5, "d")])
    html = render_page(META, [FileDiff("x.py", "M", [m1, m2])], [], None)
    for vid in ("x-py-f0h0", "x-py-f0h1"):
        assert html.count(f'id="u-{vid}"') == 1 and html.count(f'id="s-{vid}"') == 1
    assert "fMode(this,'u','x-py-f0h0')" in html.replace("&#x27;", "'")
    assert "було" in html and "стало" in html

def test_cpy_attr_escapes_quotes():
    f = FileDiff("we'ird\".py", "M", [Hunk("F0H0","@@ -1 +1 @@",1,1,[DiffLine("add",None,1,"x")])])
    html = render_page(META, [f], [], None)
    # raw double-quote from the path must never appear unescaped (would break out
    # of the onclick="..." attribute); cpy() is now json.dumps-encoded then HTML-escaped.
    assert 'we\'ird".py")"' not in html
    assert "we&#x27;ird" in html          # single quote HTML-escaped
    assert "&quot;.py&quot;" in html       # JSON-escaped double quote, then HTML-escaped

def test_finding_pinned_with_score():
    html = render_page(META, _files(), [_finding()], None)
    assert "65/100" in html and "Проблема тут" in html and "Шкода" in html

def test_js_and_favicon_present():
    html = render_page(META, _files(), [], None)
    for marker in ("function cpy(", "function go(", "function tg(",
                   "cpToast", "data:image/svg+xml", "<html lang="):
        assert marker in html

def test_big_file_collapsed_by_default():
    big = FileDiff("big.py", "M", [Hunk("F0H0", "@@ -1 +1,500 @@", 1, 1,
                   [DiffLine("add", None, i, f"l{i}") for i in range(1, 501)])])
    html = render_page(META, [big], [], None)
    assert "display:none" in html and "▸" in html

def test_help_overlay_present():
    html = render_page(META, _files(), [], None)
    assert 'id="helpOv"' in html and "helpTg" in html and "keydown" in html

def test_finding_source_escaped():
    """XSS check: Finding.source must be HTML-escaped in badge."""
    f = Finding(id="f1", layer="claude", source="<img src=x onerror=alert(1)>",
                file="a.py", line=1, hunk="F0H0", severity_emoji="🟠", severity_score=1,
                problem={"ukr": "p"}, harm={"ukr": "h"}, fix={"ukr": "f"},
                agrees_with=[], coach=None)
    html = render_page(META, _files(), [f], None)
    # Raw unescaped XSS payload must not appear in output
    assert "<img src=x onerror" not in html
    # Escaped form must be present
    assert "&lt;img" in html or "&#x3c;" in html

def test_finding_severity_emoji_escaped():
    """XSS check: severity_emoji is data-controlled (findings.json) and must be
    HTML-escaped both in the finding badge and in the file-tree severity summary
    (sev_by_file)."""
    f = Finding(id="f1", layer="claude", source="claude-deep",
                file="a/b.py", line=1, hunk="F0H0",
                severity_emoji="<img src=x onerror=1>", severity_score=1,
                problem={"ukr": "p"}, harm={"ukr": "h"}, fix={"ukr": "f"},
                agrees_with=[], coach=None)
    html = render_page(META, _files(), [f], None)
    assert "<img src=x onerror" not in html
    assert "&lt;img" in html or "&#x3c;" in html
