#!/usr/bin/env python3
"""Unit tests for the rendering A/B verification harness's verdict logic.

Run with:

    python3 Scripts/test-run-rendering-ab-verification.py

Standard library only — the harness itself has no third-party dependencies and
neither do these tests, so they run anywhere the harness does.

The harness is what AGENTS.md makes acceptance evidence for any refactor
touching demangling / printing / indexing / the reader stack, so its verdict
path is exactly the code that must not be able to pass over an incomplete
comparison. These tests pin that property directly: they drive
`compare_all_pairs` over hand-built output trees and assert the counts, rather
than running the (minutes-long, machine-dependent) real comparison.
"""

import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace

HARNESS_PATH = Path(__file__).resolve().parent / "run-rendering-ab-verification.py"


def load_harness():
    specification = importlib.util.spec_from_file_location("rendering_ab_harness", HARNESS_PATH)
    module = importlib.util.module_from_spec(specification)
    specification.loader.exec_module(module)
    return module


HARNESS = load_harness()


class CompareAllPairsTests(unittest.TestCase):
    """`compare_all_pairs` reads only `self.output_root`, so a namespace stub is
    a complete stand-in for a real `VerificationRun` here."""

    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.output_root = Path(self.temporary_directory.name)
        self.baseline_directory = self.output_root / "scenario" / "baseline"
        self.candidate_directory = self.output_root / "scenario" / "candidate"
        self.baseline_directory.mkdir(parents=True)
        self.candidate_directory.mkdir(parents=True)

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def compare(self) -> tuple[int, int]:
        stub = SimpleNamespace(output_root=self.output_root)
        return HARNESS.VerificationRun.compare_all_pairs(stub)

    def writeBaselineSkip(self, framework_name: str, exit_code: int) -> None:
        (self.baseline_directory / f"{framework_name}.dump.skip").write_text(f"exit={exit_code}\n")

    def writeCandidateSkip(self, framework_name: str, exit_code: int) -> None:
        (self.candidate_directory / f"{framework_name}.dump.skip").write_text(f"exit={exit_code}\n")

    def writeIdenticalPair(self, framework_name: str) -> None:
        (self.baseline_directory / f"{framework_name}.dump.txt").write_text("same\n")
        (self.candidate_directory / f"{framework_name}.dump.txt").write_text("same\n")

    def testBothSidesFailingWithDifferentExitCodesCountsAsADifference(self) -> None:
        """The regression this suite exists for.

        The baseline exits 1 on a pre-existing unsupported case while the
        candidate traps (134) — a refactor-introduced crash. Both legs unlink
        their .txt and write a .skip, so the pair is invisible to both .txt
        globs. Before the fix the skip loop printed nothing for a mismatched
        pair, leaving both counters at zero: with any other framework
        identical, the harness printed `all N pairs byte-identical.` and exited
        0 over a candidate that crashed.
        """
        self.writeBaselineSkip("SwiftUI", 1)
        self.writeCandidateSkip("SwiftUI", 134)

        difference_count, examined_pair_count = self.compare()

        self.assertEqual(difference_count, 1)
        self.assertEqual(examined_pair_count, 1)

    def testDifferingExitCodesFailARunWhoseOtherPairsAreIdentical(self) -> None:
        """End-to-end shape of the same defect: one healthy pair alongside the
        mismatched one must not let the run read as a pass."""
        self.writeIdenticalPair("Combine")
        self.writeBaselineSkip("SwiftUI", 1)
        self.writeCandidateSkip("SwiftUI", 134)

        difference_count, examined_pair_count = self.compare()

        self.assertEqual(examined_pair_count, 2)
        self.assertGreater(difference_count, 0)

    def testBothSidesFailingIdenticallyIsStillASkip(self) -> None:
        """A framework absent from the cache on both sides is a legitimate
        skip: the fix must not turn those into false failures."""
        self.writeBaselineSkip("ActivityKit", 1)
        self.writeCandidateSkip("ActivityKit", 1)

        difference_count, examined_pair_count = self.compare()

        self.assertEqual(difference_count, 0)
        self.assertEqual(examined_pair_count, 0)

    def testBaselineSkipAgainstCandidateOutputIsCountedExactlyOnce(self) -> None:
        """The candidate produced output where the baseline refused. The
        candidate-only .txt glob already counts that as MISSING-ON-BASELINE, so
        the skip loop must not double-count it."""
        self.writeBaselineSkip("WidgetKit", 1)
        (self.candidate_directory / "WidgetKit.dump.txt").write_text("candidate output\n")

        difference_count, examined_pair_count = self.compare()

        self.assertEqual(difference_count, 1)
        self.assertEqual(examined_pair_count, 1)

    def testIdenticalPairsPass(self) -> None:
        self.writeIdenticalPair("SwiftData")

        difference_count, examined_pair_count = self.compare()

        self.assertEqual(difference_count, 0)
        self.assertEqual(examined_pair_count, 1)


if __name__ == "__main__":
    unittest.main(verbosity=2)
