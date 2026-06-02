import unittest

import review_html as rh


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


class TestHunkId(unittest.TestCase):
    def test_format(self):
        self.assertEqual(rh.hunk_id(0, 1), "F0H1")
        self.assertEqual(rh.hunk_id(3, 12), "F3H12")


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


class TestPageJs(unittest.TestCase):
    META = {"head": "h", "base": "b", "mode": "local", "generated": "t", "repo": "r"}

    def test_js_present_and_features(self):
        out = rh.render_html(rh.parse_diff(SAMPLE_DIFF), {"files": []}, "eng", self.META)
        for needle in ("localStorage", "clipboard", "comments.md",
                       "expand-all", "export"):
            self.assertIn(needle, out)


if __name__ == "__main__":
    unittest.main()
