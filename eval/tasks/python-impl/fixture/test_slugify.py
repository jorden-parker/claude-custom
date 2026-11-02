import unittest

from slugify import slugify


class SlugifyTest(unittest.TestCase):
    def test_lowercases_and_joins_words_with_hyphens(self):
        self.assertEqual(slugify("Hello World"), "hello-world")

    def test_drops_punctuation(self):
        self.assertEqual(slugify("What's new, in 2024?"), "whats-new-in-2024")

    def test_collapses_runs_of_separators(self):
        self.assertEqual(slugify("  too   many -- spaces  "), "too-many-spaces")

    def test_empty_title_gives_empty_slug(self):
        self.assertEqual(slugify(""), "")


if __name__ == "__main__":
    unittest.main()
