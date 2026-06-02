import unittest

import review_html as rh


class TestHunkId(unittest.TestCase):
    def test_format(self):
        self.assertEqual(rh.hunk_id(0, 1), "F0H1")
        self.assertEqual(rh.hunk_id(3, 12), "F3H12")


if __name__ == "__main__":
    unittest.main()
