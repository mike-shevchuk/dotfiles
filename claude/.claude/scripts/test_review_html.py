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


if __name__ == "__main__":
    unittest.main()
