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
    assert "cpy('nvim +1 a/b.py')" in html

def test_split_toggle_only_on_mixed_hunks():
    html = render_page(META, _files(), [], None)
    assert html.count("fMode(") >= 2          # working toggle on the mixed hunk
    assert "split недоступний" in html         # disabled tooltip on add-only

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
