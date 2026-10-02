#!/usr/bin/env python3
"""Vérifie l'intégrité du cache et des téléchargements sans accès réseau."""
import hashlib
import io
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import urllib.error

from runtime_bottles import retrieve_bottle


class RuntimeBottleTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.cache = Path(self.directory.name)
        self.content = b"official runtime bottle fixture"
        self.bottle = {
            "reference": "1.0.arm64_sonoma",
            "sha256": hashlib.sha256(self.content).hexdigest(),
            "size": len(self.content),
        }
        self.destination = self.cache / (self.bottle["sha256"] + ".tar.gz")

    def test_valid_cache_is_reused_without_network(self):
        self.destination.write_bytes(self.content)
        with patch("runtime_bottles.urllib.request.urlopen") as download:
            self.assertEqual(retrieve_bottle("libplist", self.bottle, self.cache), self.destination)
            download.assert_not_called()

    def test_same_size_corrupt_cache_is_replaced_only_after_verification(self):
        self.destination.write_bytes(b"x" * len(self.content))
        with patch("runtime_bottles.urllib.request.urlopen", return_value=io.BytesIO(self.content)):
            retrieve_bottle("libplist", self.bottle, self.cache)
        self.assertEqual(self.destination.read_bytes(), self.content)
        self.assertEqual(list(self.cache.glob("*.partial")), [])

    def test_wrong_checksum_does_not_replace_cache_or_leave_partial(self):
        previous = b"previous cached content"
        self.destination.write_bytes(previous)
        with patch("runtime_bottles.urllib.request.urlopen", return_value=io.BytesIO(b"x" * len(self.content))):
            with self.assertRaisesRegex(RuntimeError, "checksum or size mismatch"):
                retrieve_bottle("libplist", self.bottle, self.cache)
        self.assertEqual(self.destination.read_bytes(), previous)
        self.assertEqual(list(self.cache.glob("*.partial")), [])

    def test_wrong_size_is_rejected_even_with_matching_checksum(self):
        self.bottle["size"] += 1
        with patch("runtime_bottles.urllib.request.urlopen", return_value=io.BytesIO(self.content)):
            with self.assertRaisesRegex(RuntimeError, "checksum or size mismatch"):
                retrieve_bottle("libplist", self.bottle, self.cache)
        self.assertEqual(list(self.cache.iterdir()), [])

    def test_network_failure_removes_partial(self):
        with patch("runtime_bottles.urllib.request.urlopen", side_effect=urllib.error.URLError("interrupted")):
            with self.assertRaises(urllib.error.URLError):
                retrieve_bottle("libplist", self.bottle, self.cache)
        self.assertEqual(list(self.cache.iterdir()), [])

    def test_cache_symlink_is_rejected(self):
        target = self.cache / "other-file"
        target.write_bytes(self.content)
        self.destination.symlink_to(target)
        with patch("runtime_bottles.urllib.request.urlopen") as download:
            with self.assertRaisesRegex(RuntimeError, "cache link"):
                retrieve_bottle("libplist", self.bottle, self.cache)
            download.assert_not_called()
        self.assertEqual(target.read_bytes(), self.content)


if __name__ == "__main__":
    unittest.main()
