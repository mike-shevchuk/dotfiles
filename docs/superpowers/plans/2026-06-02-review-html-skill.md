# `/review-html` Skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Claude Code slash command `/review-html` that produces the `prefix v` diff, has Claude explain each hunk (ukr/eng/both), and renders a self-contained interactive HTML review page with collapsible Description/Problems and a clipboard + `--reply` comment loop.

**Architecture:** A pure Python generator (`review_html.py`, stdlib only) turns a unified diff + a Claude-authored `explanations.json` into one self-contained `.html`. A markdown command (`review-html.md`) orchestrates: resolve the diff, write the JSON, run the generator, open the page, and handle `--reply`/`--help`.

**Tech Stack:** Python 3 stdlib (`argparse`, `html`, `json`, `tempfile`, `unittest`); a Markdown slash command; `git`/`gh`; `ruff` for lint.

**Spec:** `docs/superpowers/specs/2026-06-02-review-html-skill-design.md`

---

## File structure

| File | Responsibility |
|---|---|
| `claude/.claude/scripts/review_html.py` | Pure generator: parse diff → render HTML. CLI + importable functions. |
| `claude/.claude/scripts/test_review_html.py` | `unittest` tests for parsing + rendering (no browser). |
| `claude/.claude/commands/review-html.md` | The slash command (orchestration prompt). |
| `.gitignore` | Ignore `.claude-review/`. |

Run tests with: `python3 -m unittest discover -s claude/.claude/scripts -p 'test_*.py' -v`
(stdlib only — no pip install needed).

---

### Task 1: Scaffolding — module skeleton + `.gitignore` + first failing test

**Files:**
- Create: `claude/.claude/scripts/review_html.py`
- Create: `claude/.claude/scripts/test_review_html.py`
- Modify: `.gitignore`

- [ ] **Step 1: Add the gitignore entry**

Append to `.gitignore`:

```gitignore

# /review-html skill artifacts (generated HTML, explanations, comments)
.claude-review/
```

- [ ] **Step 2: Create the module skeleton**

Create `claude/.claude/scripts/review_html.py`:

```python
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
import sys
import tempfile


def hunk_id(file_idx: int, hunk_idx: int) -> str:
    """Stable anchor id for a hunk: file index + hunk index, e.g. 'F0H1'."""
    return f"F{file_idx}H{hunk_idx}"
```

- [ ] **Step 3: Write the first failing test**

Create `claude/.claude/scripts/test_review_html.py`:

```python
import unittest

import review_html as rh


class TestHunkId(unittest.TestCase):
    def test_format(self):
        self.assertEqual(rh.hunk_id(0, 1), "F0H1")
        self.assertEqual(rh.hunk_id(3, 12), "F3H12")


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 4: Run the test, expect PASS**

Run: `cd claude/.claude/scripts && python3 -m unittest test_review_html -v`
Expected: `test_format` PASS.

- [ ] **Step 5: Commit**

```bash
git add .gitignore claude/.claude/scripts/review_html.py claude/.claude/scripts/test_review_html.py
git commit -m "feat(review-html): scaffold generator module + gitignore"
```

---

### Task 2: `parse_diff` — unified diff → files/hunks

**Files:**
- Modify: `claude/.claude/scripts/review_html.py`
- Test: `claude/.claude/scripts/test_review_html.py`

- [ ] **Step 1: Write the failing test**

Add to `test_review_html.py`:

```python
SAMPLE_DIFF = """diff --git a/foo.py b/foo.py
index 111..222 100644
--- a/foo.py
+++ b/foo.py
@@ -1,3 +1,4 @@
 import os
-x = 1
+x = 2
+y = 3
 print(x)
diff --git a/new.txt b/new.txt
new file mode 100644
index 000..333
--- /dev/null
+++ b/new.txt
@@ -0,0 +1,1 @@
+hello
"""


class TestParseDiff(unittest.TestCase):
    def test_two_files(self):
        files = rh.parse_diff(SAMPLE_DIFF)
        self.assertEqual([f["path"] for f in files], ["foo.py", "new.txt"])

    def test_counts_and_tags(self):
        foo = rh.parse_diff(SAMPLE_DIFF)[0]
        self.assertEqual(foo["added"], 2)
        self.assertEqual(foo["removed"], 1)
        self.assertEqual(len(foo["hunks"]), 1)
        tags = [t for t, _ in foo["hunks"][0]["lines"]]
        self.assertEqual(tags, ["ctx", "del", "add", "add", "ctx"])

    def test_new_file_path_from_dev_null(self):
        new = rh.parse_diff(SAMPLE_DIFF)[1]
        self.assertEqual(new["path"], "new.txt")
        self.assertEqual(new["added"], 1)
```

- [ ] **Step 2: Run, expect FAIL**

Run: `python3 -m unittest test_review_html.TestParseDiff -v`
Expected: FAIL (`module 'review_html' has no attribute 'parse_diff'`).

- [ ] **Step 3: Implement `parse_diff`**

Add to `review_html.py` (after `hunk_id`):

```python
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
            cur = {"path": path, "added": 0, "removed": 0, "hunks": []}
            files.append(cur)
        elif line.startswith("+++ "):
            p = line[4:].strip()
            if cur is not None and p != "/dev/null":
                cur["path"] = p[2:] if p.startswith("b/") else p
        elif line.startswith("--- "):
            p = line[4:].strip()
            if cur is not None and p != "/dev/null" and cur["path"] == "/dev/null":
                cur["path"] = p[2:] if p.startswith("a/") else p
        elif line.startswith("@@"):
            if cur is None:
                cur = {"path": "?", "added": 0, "removed": 0, "hunks": []}
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
```

- [ ] **Step 4: Run, expect PASS**

Run: `python3 -m unittest test_review_html.TestParseDiff -v`
Expected: all 3 PASS.

- [ ] **Step 5: Commit**

```bash
git add claude/.claude/scripts/
git commit -m "feat(review-html): parse unified diff into files/hunks"
```

---

### Task 3: Language helper `render_text` (ukr/eng/both)

**Files:**
- Modify: `claude/.claude/scripts/review_html.py`
- Test: `claude/.claude/scripts/test_review_html.py`

- [ ] **Step 1: Write the failing test**

Add to `test_review_html.py`:

```python
class TestRenderText(unittest.TestCase):
    OBJ = {"ukr": "Привіт", "eng": "Hello"}

    def test_single_lang_escapes(self):
        self.assertEqual(rh.render_text({"eng": "a<b"}, "eng"), "a&lt;b")

    def test_single_lang_picks_lang(self):
        self.assertEqual(rh.render_text(self.OBJ, "ukr"), "Привіт")

    def test_plain_string(self):
        self.assertEqual(rh.render_text("plain", "ukr"), "plain")

    def test_both_emits_two_spans(self):
        out = rh.render_text(self.OBJ, "both")
        self.assertIn('class="L L-ukr"', out)
        self.assertIn('class="L L-eng" hidden', out)
        self.assertIn("Привіт", out)
        self.assertIn("Hello", out)
```

- [ ] **Step 2: Run, expect FAIL**

Run: `python3 -m unittest test_review_html.TestRenderText -v`
Expected: FAIL (no attribute `render_text`).

- [ ] **Step 3: Implement the helpers**

Add to `review_html.py`:

```python
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
        u = html.escape(_text(obj, "ukr"))
        e = html.escape(_text(obj, "eng"))
        return f'<span class="L L-ukr">{u}</span><span class="L L-eng" hidden>{e}</span>'
    return html.escape(_text(obj, lang))
```

- [ ] **Step 4: Run, expect PASS**

Run: `python3 -m unittest test_review_html.TestRenderText -v`
Expected: all 4 PASS.

- [ ] **Step 5: Commit**

```bash
git add claude/.claude/scripts/
git commit -m "feat(review-html): bilingual render_text helper"
```

---

### Task 4: Hunk rendering — diff coloring, Description, Problems, replies, comment box

**Files:**
- Modify: `claude/.claude/scripts/review_html.py`
- Test: `claude/.claude/scripts/test_review_html.py`

- [ ] **Step 1: Write the failing test**

Add to `test_review_html.py`:

```python
class TestRenderHunk(unittest.TestCase):
    def setUp(self):
        self.hunk = {"header": "@@ -1,3 +1,4 @@",
                     "lines": [("ctx", "import os"), ("del", "x = 1"),
                               ("add", "x = 2")]}

    def test_diff_line_classes_and_escape(self):
        out = rh.render_hunk("F0H0", {"header": "@@ x @@",
                                      "lines": [("add", "a<b")]}, {}, "eng")
        self.assertIn('class="ln add"', out)
        self.assertIn("a&lt;b", out)

    def test_anchor_and_comment_box(self):
        out = rh.render_hunk("F0H0", self.hunk, {}, "eng")
        self.assertIn('id="F0H0"', out)
        self.assertIn('data-hunk="F0H0"', out)          # comment box + copy button bind here
        self.assertIn("Copy for Claude", out)

    def test_description_and_problems(self):
        eh = {"description": {"eng": "renames x"},
              "problems": [{"severity": "warn", "text": {"eng": "shadowing"}}]}
        out = rh.render_hunk("F0H0", self.hunk, eh, "eng")
        self.assertIn("renames x", out)
        self.assertIn("shadowing", out)
        self.assertIn("warn", out)

    def test_problems_omitted_when_none(self):
        out = rh.render_hunk("F0H0", self.hunk, {"description": {"eng": "d"}}, "eng")
        self.assertNotIn("review-problems", out)

    def test_replies_rendered(self):
        eh = {"replies": [{"comment": "why?", "reply": {"eng": "because"},
                           "status": "addressed"}]}
        out = rh.render_hunk("F0H0", self.hunk, eh, "eng")
        self.assertIn("why?", out)
        self.assertIn("because", out)
        self.assertIn("✅", out)
```

- [ ] **Step 2: Run, expect FAIL**

Run: `python3 -m unittest test_review_html.TestRenderHunk -v`
Expected: FAIL (no attribute `render_hunk`).

- [ ] **Step 3: Implement `render_hunk`**

Add to `review_html.py`:

```python
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
        desc_html = (
            '<details class="review-desc" open><summary>📝 Description</summary>'
            f'<div class="body">{render_text(desc, lang)}</div></details>'
        )

    problems = expl.get("problems") or []
    prob_html = ""
    if problems:
        items = "".join(
            f'<li class="sev-{html.escape(str(p.get("severity", "info")))}">'
            f'<span class="badge">{html.escape(str(p.get("severity", "info")))}</span>'
            f'{render_text(p.get("text", ""), lang)}</li>'
            for p in problems
        )
        prob_html = (
            '<details class="review-problems" open><summary>⚠️ Problems</summary>'
            f'<ul>{items}</ul></details>'
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

    return (
        f'<div class="hunk" id="{hid}">'
        f'<div class="hunk-head"><code>{html.escape(hunk["header"])}</code>'
        f'<button class="copy" data-hunk="{hid}">Copy for Claude</button></div>'
        f'<div class="diff">{diff_html}</div>'
        f'{desc_html}{prob_html}{rep_html}'
        f'<textarea class="comment" data-hunk="{hid}" '
        f'placeholder="comment for Claude…"></textarea>'
        f'</div>'
    )
```

- [ ] **Step 4: Run, expect PASS**

Run: `python3 -m unittest test_review_html.TestRenderHunk -v`
Expected: all 5 PASS.

- [ ] **Step 5: Commit**

```bash
git add claude/.claude/scripts/
git commit -m "feat(review-html): render hunk (diff, description, problems, replies, comment)"
```

---

### Task 5: Page assembly — `render_html` (files, empty state, head/title)

**Files:**
- Modify: `claude/.claude/scripts/review_html.py`
- Test: `claude/.claude/scripts/test_review_html.py`

- [ ] **Step 1: Write the failing test**

Add to `test_review_html.py`:

```python
class TestRenderHtml(unittest.TestCase):
    META = {"head": "feat-x", "base": "origin/master", "mode": "local",
            "generated": "2026-06-02 10:00", "repo": "dotfiles"}

    def test_empty_diff_nothing_to_review(self):
        out = rh.render_html([], {}, "eng", self.META)
        self.assertIn("Nothing to review", out)
        self.assertTrue(out.strip().startswith("<!DOCTYPE html>"))

    def test_full_page_has_file_and_hunk(self):
        files = rh.parse_diff(SAMPLE_DIFF)
        expl = {"files": [{"path": "foo.py", "summary": {"eng": "edits"},
                           "hunks": [{"description": {"eng": "change x"}}]}]}
        out = rh.render_html(files, expl, "eng", self.META)
        self.assertIn("foo.py", out)
        self.assertIn('id="F0H0"', out)
        self.assertIn("change x", out)
        self.assertIn("Export for Claude", out)

    def test_both_mode_shows_toggle(self):
        files = rh.parse_diff(SAMPLE_DIFF)
        out = rh.render_html(files, {"files": []}, "both", self.META)
        self.assertIn('id="lang-toggle"', out)

    def test_single_mode_hides_toggle(self):
        files = rh.parse_diff(SAMPLE_DIFF)
        out = rh.render_html(files, {"files": []}, "eng", self.META)
        self.assertNotIn('id="lang-toggle"', out)
```

- [ ] **Step 2: Run, expect FAIL**

Run: `python3 -m unittest test_review_html.TestRenderHtml -v`
Expected: FAIL (no attribute `render_html`).

- [ ] **Step 3: Implement `render_html` + page chrome**

Add to `review_html.py`:

```python
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
        "<button id=\"export\">Export for Claude</button>"
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
            f'<details class="file" open><summary>{html.escape(f["path"])}{stat}</summary>'
            f'{summ}{hunks}</details>'
        )
    return _page(meta, lang, "".join(blocks))
```

Note: `_JS` is defined in Task 6; this step references it. Add a temporary `_JS = ""` line directly above `_CSS` now so the module imports; Task 6 replaces it.

```python
_JS = ""  # replaced in Task 6
```

- [ ] **Step 4: Run, expect PASS**

Run: `python3 -m unittest test_review_html.TestRenderHtml -v`
Expected: all 4 PASS.

- [ ] **Step 5: Commit**

```bash
git add claude/.claude/scripts/
git commit -m "feat(review-html): assemble full page + empty state"
```

---

### Task 6: Page JavaScript — collapse, lang toggle, copy, comments, export

**Files:**
- Modify: `claude/.claude/scripts/review_html.py`
- Test: `claude/.claude/scripts/test_review_html.py`

- [ ] **Step 1: Write the failing test**

Add to `test_review_html.py`:

```python
class TestPageJs(unittest.TestCase):
    META = {"head": "h", "base": "b", "mode": "local", "generated": "t", "repo": "r"}

    def test_js_present_and_features(self):
        out = rh.render_html(rh.parse_diff(SAMPLE_DIFF), {"files": []}, "eng", self.META)
        for needle in ("localStorage", "clipboard", "comments.md",
                       "expand-all", "export"):
            self.assertIn(needle, out)
```

- [ ] **Step 2: Run, expect FAIL**

Run: `python3 -m unittest test_review_html.TestPageJs -v`
Expected: FAIL (`_JS` is empty, needles missing).

- [ ] **Step 3: Replace the `_JS` placeholder with the real script**

In `review_html.py`, replace the `_JS = ""  # replaced in Task 6` line with:

```python
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
    var file=hunk.closest('details.file').querySelector('summary').textContent.trim();
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
```

- [ ] **Step 4: Run, expect PASS**

Run: `python3 -m unittest test_review_html.TestPageJs -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add claude/.claude/scripts/
git commit -m "feat(review-html): page JS (collapse, toggle, copy, comments, export)"
```

---

### Task 7: CLI entry point + atomic write

**Files:**
- Modify: `claude/.claude/scripts/review_html.py`
- Test: `claude/.claude/scripts/test_review_html.py`

- [ ] **Step 1: Write the failing test**

Add to `test_review_html.py`:

```python
import os
import tempfile


class TestCli(unittest.TestCase):
    def test_generate_file(self):
        d = tempfile.mkdtemp()
        diff_f = os.path.join(d, "d.diff"); open(diff_f, "w").write(SAMPLE_DIFF)
        expl_f = os.path.join(d, "e.json")
        open(expl_f, "w").write('{"files":[{"path":"foo.py","summary":{"eng":"x"},"hunks":[]}]}')
        out_f = os.path.join(d, "r.html")
        meta_f = os.path.join(d, "m.json")
        open(meta_f, "w").write('{"head":"h","base":"b","mode":"local","generated":"t","repo":"r"}')
        rc = rh.main(["--diff", diff_f, "--explanations", expl_f,
                      "--lang", "eng", "--out", out_f, "--meta", meta_f])
        self.assertEqual(rc, 0)
        body = open(out_f).read()
        self.assertIn("foo.py", body)
        self.assertTrue(body.startswith("<!DOCTYPE html>"))
```

- [ ] **Step 2: Run, expect FAIL**

Run: `python3 -m unittest test_review_html.TestCli -v`
Expected: FAIL (no attribute `main`).

- [ ] **Step 3: Implement `main` + atomic write**

Add to `review_html.py`:

```python
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

    diff_text = open(args.diff, encoding="utf-8").read()
    expl = json.load(open(args.explanations, encoding="utf-8"))
    meta = json.load(open(args.meta, encoding="utf-8")) if args.meta else {}
    files = parse_diff(diff_text)
    html_out = render_html(files, expl, args.lang, meta)
    _atomic_write(args.out, html_out)
    print(args.out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

- [ ] **Step 4: Run the full suite, expect PASS**

Run: `cd claude/.claude/scripts && python3 -m unittest discover -p 'test_*.py' -v`
Expected: every test PASSES.

- [ ] **Step 5: Lint**

Run: `ruff check claude/.claude/scripts/review_html.py`
Expected: no errors (fix any with `ruff check --fix`).

- [ ] **Step 6: Commit**

```bash
git add claude/.claude/scripts/
git commit -m "feat(review-html): CLI entry point with atomic write"
```

---

### Task 8: The slash command `review-html.md`

**Files:**
- Create: `claude/.claude/commands/review-html.md`

- [ ] **Step 1: Write the command file**

Create `claude/.claude/commands/review-html.md` with this exact content:

````markdown
---
description: Render the current branch's changes (prefix-v diff) as an interactive HTML review page with per-hunk explanations (ukr/eng/both) and a comment-back-to-Claude loop.
argument-hint: "[eng|ukr|both] [ <base> <head> | <PR#> ] [--reply] [--help]"
---

# /review-html

Turn the changes under review into a self-contained HTML page the user can browse,
collapse, comment on, and discuss with you.

`$ARGUMENTS` may contain: a language (`eng|ukr|both`, default `ukr`), either two
git refs `<base> <head>` or a single integer `<PR#>`, and the flags `--reply` / `--help`.

## Step 0 — `--help`
If `--help` or the bare word `help` is present, print the contents of the
"Usage examples" section of
`docs/superpowers/specs/2026-06-02-review-html-skill-design.md` (§11) and STOP.

## Step 1 — resolve paths
- `GEN=~/dotfiles/claude/.claude/scripts/review_html.py`
- `DIR=.claude-review` (create it). All artifacts go here.
- Confirm you are inside a git repo (`git rev-parse --is-inside-work-tree`); if not,
  tell the user and STOP.

## Step 2 — `--reply` mode
If `--reply` is present:
1. Obtain the comments, trying in order until non-empty:
   `pbpaste` (macOS) → `xclip -selection clipboard -o` / `wl-paste` (Linux) →
   `.claude-review/comments.md` → newest `~/Downloads/comments.md`.
2. Save them verbatim to `.claude-review/comments.md`.
3. Read the existing `.claude-review/explanations.json`. For each comment (it carries
   `file:` and `hunk:` lines), find the matching file+hunk and append to that hunk's
   `replies` array an object: `{"comment": "<user text>", "reply": {"<lang>": "<your answer>"}, "status": "addressed"}`.
   Answer in the same language the page was generated with (read `meta.lang`).
4. Re-run the generator (Step 4) to regenerate the page, then open it (Step 5). STOP.

## Step 3 — compute the diff (normal mode)
Decide the mode from `$ARGUMENTS`:
- **PR number** (a lone integer, e.g. `28`): `gh pr diff <N> > .claude-review/diff.txt`
  (if `gh` is missing or the PR is invalid, tell the user and STOP). meta.mode=`pr`,
  head=`pr<N>`, base=`(github)`.
- **Two refs** `<base> <head>`: `git diff "<base>...<head>" > .claude-review/diff.txt`.
  meta.mode=`refs`.
- **No refs** (default): detect the base like git-compare.sh
  (`git symbolic-ref refs/remotes/origin/HEAD` → else `origin/main`→`origin/master`→`origin/develop`),
  then `BASE=$(git merge-base <default> HEAD)` and
  `git diff "$BASE" > .claude-review/diff.txt` (includes uncommitted work, = `prefix v`).
  meta.mode=`local`, head=current branch, base=the default ref.
If `.claude-review/diff.txt` is empty, still proceed — the generator renders a clear
"Nothing to review" page.

## Step 4 — write explanations + generate
1. Read `.claude-review/diff.txt`. Split it into files → hunks **in the same order
   `review_html.py` does** (hunks counted top-to-bottom per file; hunk ids `F<fileIdx>H<hunkIdx>`).
2. Write `.claude-review/explanations.json`:
   ```json
   {"meta":{"head":"…","base":"…","mode":"…","generated":"<YYYY-MM-DD HH:MM>","repo":"<basename of toplevel>","lang":"<ukr|eng|both>"},
    "files":[{"path":"…","summary":{"<lang>":"…"},
      "hunks":[{"description":{"<lang>":"…"},"problems":[{"severity":"warn|info","text":{"<lang>":"…"}}]}]}]}
   ```
   - Fill only the requested language key(s); for `both`, fill both `ukr` and `eng`.
   - `summary`: one line per file. `description`: what changed & why, per hunk.
   - `problems`: ONLY when you actually see a risk/bug/smell; otherwise omit the key.
   - Keep order aligned with the diff so hunk ids match.
3. Generate:
   ```bash
   python3 "$GEN" --diff .claude-review/diff.txt \
     --explanations .claude-review/explanations.json \
     --lang <lang> --meta .claude-review/explanations.json \
     --out ".claude-review/review-<ref>.html"
   ```
   `<ref>` = head ref with `/`→`-`, or `pr<N>`. (`--meta` reads the `meta` block from the
   same JSON.)

## Step 5 — open
`open .claude-review/review-<ref>.html` (macOS) or `xdg-open …` (Linux). Print the path.
Tell the user: comment in the page, then either "Copy for Claude" (paste here) or
"Export for Claude" → `/review-html --reply`.
````

- [ ] **Step 2: Verify it's recognized (manual)**

After stow/symlink, `/review-html --help` should print the usage examples. (During dev,
the file lives in `claude/.claude/commands/`; it is stowed to `~/.claude/commands/`.)

- [ ] **Step 3: Commit**

```bash
git add claude/.claude/commands/review-html.md
git commit -m "feat(review-html): add the /review-html slash command"
```

---

### Task 9: End-to-end smoke test + PR

**Files:** none (verification)

- [ ] **Step 1: Generate a page from a real diff**

```bash
cd ~/dotfiles/.claude/worktrees/review-html
mkdir -p .claude-review
git diff "$(git merge-base origin/master HEAD)" > .claude-review/diff.txt
printf '{"meta":{"head":"feat-review-html","base":"origin/master","mode":"local","generated":"2026-06-02 10:00","repo":"dotfiles","lang":"ukr"},"files":[]}' > .claude-review/explanations.json
python3 claude/.claude/scripts/review_html.py --diff .claude-review/diff.txt \
  --explanations .claude-review/explanations.json --lang ukr \
  --meta .claude-review/explanations.json --out .claude-review/review-test.html
```
Expected: prints the out path; `.claude-review/review-test.html` exists and starts with `<!DOCTYPE html>`.

- [ ] **Step 2: Open and eyeball**

Run: `open .claude-review/review-test.html`
Verify: files collapse/expand, diff is red/green, a comment box + "Copy for Claude" per hunk, "Export for Claude" copies + downloads, no console errors.

- [ ] **Step 3: Clean the smoke artifacts (they're git-ignored anyway)**

Run: `rm -rf .claude-review`

- [ ] **Step 4: Push + open PR**

```bash
git push -u origin feat-review-html
gh pr create --base master --head feat-review-html \
  --title "feat: /review-html — interactive HTML PR-review skill" \
  --body "Implements docs/superpowers/specs/2026-06-02-review-html-skill-design.md. See plan: docs/superpowers/plans/2026-06-02-review-html-skill.md"
```

---

## Self-review notes
- **Spec coverage:** diff modes (local/refs/PR) → Task 8 Step1 §Step3; per-file/hunk + Description/Problems → Tasks 4–5; ukr/eng/both + toggle → Tasks 3,5,6; comment loop A(clipboard+download)+C(per-hunk copy) + `--reply` → Tasks 4,6,8; empty state → Task 5; atomic write → Task 7; help → Task 8 Step0; gitignore → Task 1.
- **Types consistent:** `hunk_id`, `parse_diff` shape (`path/added/removed/hunks[{header,lines:[(tag,text)]}]`), `render_text`, `render_hunk`, `render_html`, `main` used identically across tasks and tests.
- **No placeholders:** every code step is complete; `_JS=""` is an explicit, documented two-phase definition (set in Task 5, replaced in Task 6), not a TODO.
