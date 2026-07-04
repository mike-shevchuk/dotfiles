"""Tests for LGTM index page (indexpage.py)."""
from lgtm.indexpage import IndexEntry, _filter_worktrees, render_index


def _entries():
    return [IndexEntry("head", "main", "3 uncommitted файли", 0, 0, "", "jb2b review"),
            IndexEntry("pr", "pr1651", "recategorize re-fires 911", 304, 2, "13h",
                       "jb2b review 1651"),
            IndexEntry("branch", "webhook-auth-pun-1497", "", 0, 0, "23h",
                       "jb2b review webhook-auth-pun-1497")]


def test_sections_and_cards():
    html = render_index("rescue-serverless", _entries())
    for marker in ("поточний стан", "відкриті PR", "локальні гілки",
                   "pr1651", "jb2b review 1651", "ixFilter", "cpy("):
        assert marker in html


def test_search_data_attrs():
    html = render_index("x", _entries())
    assert 'data-k="' in html   # fuzzy keys present on cards


def test_empty_sections_omitted():
    html = render_index("x", [IndexEntry("pr", "pr9", "t", 1, 0, "1h", "jb2b review 9")])
    assert "відкриті PR" in html and "worktrees" not in html


def test_titles_escaped():
    html = render_index("x", [IndexEntry("pr", "pr9", "<script>alert(1)</script>", 1, 0, "", "c")])
    assert "<script>alert(1)" not in html


def test_filter_worktrees_excludes_agent_scratch_and_caps():
    pairs = [(f"/r/.claude/worktrees/agent-{i}", f"wt-agent-{i}") for i in range(3)] + \
            [(f"/r/.claude/worktrees/real-{i}", f"real-{i}") for i in range(10)]
    kept, hidden = _filter_worktrees(pairs)
    assert len(kept) == 8 and hidden == 2
    assert all("agent-" not in p for p, _ in kept)


def test_hidden_worktrees_line_not_clickable():
    entries = [IndexEntry("worktree", "real-1", "/r/wt/real-1", 0, 0, "", "jb2b review real-1"),
               IndexEntry("worktree", "", "…ще 2 приховано", 0, 0, "", "")]
    html = render_index("x", entries)
    assert "…ще 2 приховано" in html
    # the hidden-count line is a plain dim line: no card class, no onclick
    seg = html.split("…ще 2 приховано")[0].rsplit("<div", 1)[1]
    assert "pcard" not in seg and "onclick" not in seg
