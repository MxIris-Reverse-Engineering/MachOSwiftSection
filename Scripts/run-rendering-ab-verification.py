#!/usr/bin/env python3
"""A/B rendering-parity verification over real system frameworks.

Renders dump + interface output for a fixed framework set through all three
reader paths (dyld shared cache, plain Mach-O file, in-process MachOImage)
from TWO checkouts of this package, then byte-compares every output pair.
Run it before landing any large refactor that touches demangling, printing,
indexing, or the reader stack. See
Documentations/Internal/SystemFrameworkRenderingVerification.md for the
procedure, fallback rules, and the baseline run record.

Usage:
    Scripts/run-rendering-ab-verification.py <baseline-checkout> <candidate-checkout>
        [--output-root PATH] [--frameworks A,B,...]
        [--baseline-scratch PATH] [--candidate-scratch PATH] [--skip-image-part]

Input sources and fallbacks:
    - Dyld caches: prefers the archived caches under /Volumes/DyldSharedCaches/macOS
      (26.5.2_25F84 and 15.5_24F74). When none of them exists, falls back to the
      CURRENT system's dyld shared cache (--uses-system-dyld-shared-cache).
    - Simulator runtimes: prefers iOS 15.5 / 18.5 / 26.5; every installed iOS
      runtime discovered on this machine is used (they are enumerated, so absent
      preferred versions simply do not appear).
    - MachOImage: always the current system, via the RenderingVerificationTests
      harness (the documented IntegrationTests exception for this exact purpose).
"""

import argparse
import datetime
import filecmp
import os
import subprocess
import sys
import time
from pathlib import Path

DEFAULT_FRAMEWORK_NAMES = ["SwiftUI", "SwiftUICore", "SwiftData", "Combine", "ActivityKit", "WidgetKit"]

ARCHIVED_CACHE_DIRECTORIES = [
    Path("/Volumes/DyldSharedCaches/macOS/26.5.2_25F84"),
    Path("/Volumes/DyldSharedCaches/macOS/15.5_24F74"),
]

SIMULATOR_RUNTIME_SEARCH_DIRECTORIES = [
    Path("/Library/Developer/CoreSimulator/Profiles/Runtimes"),
    # Newer runtimes mount under per-runtime volumes.
    *sorted(Path("/Library/Developer/CoreSimulator/Volumes").glob("*/Library/Developer/CoreSimulator/Profiles/Runtimes")),
]

# expandedFieldOffsets stays off: the harness documents a pre-existing stack
# overflow over MachOImage of deeply generic frameworks (e.g. SwiftUI).
RENDERING_VERIFICATION_OPTIONS = "fieldOffset,typeLayout,enumLayout,spareBitAnalysis,memberAddress,vtableOffset,pwtOffset"


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="A/B rendering-parity verification over real system frameworks.")
    parser.add_argument("baseline_checkout", type=Path)
    parser.add_argument("candidate_checkout", type=Path)
    parser.add_argument("--output-root", type=Path,
                        default=Path("/tmp/rendering-ab-verification") / datetime.datetime.now().strftime("%Y%m%d-%H%M%S"))
    parser.add_argument("--frameworks", default=",".join(DEFAULT_FRAMEWORK_NAMES),
                        help="Comma-separated framework names to render.")
    parser.add_argument("--baseline-scratch", type=Path, default=None,
                        help="SwiftPM scratch path for the baseline build (default: <baseline>/.build).")
    parser.add_argument("--candidate-scratch", type=Path, default=None,
                        help="SwiftPM scratch path for the candidate build (default: <candidate>/.build).")
    parser.add_argument("--skip-image-part", action="store_true",
                        help="Skip the MachOImage (RenderingVerificationTests) part.")
    arguments = parser.parse_args()
    arguments.baseline_checkout = arguments.baseline_checkout.resolve()
    arguments.candidate_checkout = arguments.candidate_checkout.resolve()
    if arguments.baseline_scratch is None:
        arguments.baseline_scratch = arguments.baseline_checkout / ".build"
    if arguments.candidate_scratch is None:
        arguments.candidate_scratch = arguments.candidate_checkout / ".build"
    arguments.framework_names = [name.strip() for name in arguments.frameworks.split(",") if name.strip()]
    return arguments


class VerificationRun:
    def __init__(self, arguments: argparse.Namespace) -> None:
        self.arguments = arguments
        self.output_root: Path = arguments.output_root
        self.command_line_interfaces: dict[str, Path] = {}
        # Invocation failures that must fail the whole run regardless of the
        # diff outcome (a swallowed non-zero swift-test exit once let a green
        # verdict stand over an incomplete matrix — PR #103 review, H4).
        self.hard_failure_messages: list[str] = []

    # --- Building -----------------------------------------------------------

    def build_both_sides(self) -> None:
        for side, checkout, scratch in self.sides():
            print(f"Building release swift-section for {checkout} ...")
            completed = subprocess.run([
                "swift", "build", "-c", "release",
                "--package-path", str(checkout),
                "--scratch-path", str(scratch),
                "--product", "swift-section",
            ])
            if completed.returncode != 0:
                sys.exit(f"error: release build failed for {side} ({checkout})")
            self.command_line_interfaces[side] = scratch / "release" / "swift-section"

    def sides(self) -> list[tuple[str, Path, Path]]:
        return [
            ("baseline", self.arguments.baseline_checkout, self.arguments.baseline_scratch),
            ("candidate", self.arguments.candidate_checkout, self.arguments.candidate_scratch),
        ]

    # --- One rendered pair --------------------------------------------------

    def run_pair(self, scenario_name: str, framework_name: str, command_name: str, extra_arguments: list[str]) -> None:
        """Run one dump/interface command through both sides' CLIs."""
        for side in ("baseline", "candidate"):
            output_directory = self.output_root / scenario_name / side
            output_directory.mkdir(parents=True, exist_ok=True)
            output_file = output_directory / f"{framework_name}.{command_name}.txt"
            log_file = output_directory / f"{framework_name}.{command_name}.log"
            started_at = time.monotonic()
            with open(log_file, "w") as log_handle:
                completed = subprocess.run(
                    [str(self.command_line_interfaces[side]), command_name, *extra_arguments, "-o", str(output_file)],
                    stdout=log_handle, stderr=subprocess.STDOUT,
                )
            elapsed_seconds = time.monotonic() - started_at
            if completed.returncode != 0:
                # Record the failure as a skip marker; the diff phase treats a
                # pair of equal markers as SKIPPED and anything else as a difference.
                output_file.unlink(missing_ok=True)
                (output_directory / f"{framework_name}.{command_name}.skip").write_text(f"exit={completed.returncode}\n")
            print(f"[{side}] {scenario_name}/{framework_name} {command_name} "
                  f"exit={completed.returncode} {elapsed_seconds:.0f}s")

    # --- Part 1: dyld shared caches -----------------------------------------

    def image_path_inside_cache(self, cache_directory: Path, framework_name: str) -> str | None:
        """Resolve the framework's in-cache image path via the cache's .map file.

        The full canonical path disambiguates frameworks that also ship a
        Mac Catalyst copy under /System/iOSSupport (SwiftUI, WidgetKit, ...);
        the iOSSupport copy is used only when it is the sole one (e.g.
        ActivityKit on macOS 15).
        """
        map_file = cache_directory / "dyld_shared_cache_arm64e.map"
        if not map_file.is_file():
            return None
        # Line-anchored: every .map line IS one full image path. A plain
        # containment test can never reach the iOSSupport fallback below, because
        # the canonical path is a literal SUBSTRING of the iOSSupport one — so an
        # image that ships ONLY under /System/iOSSupport (ActivityKit on macOS 15)
        # resolved to a path that is not in the cache, both sides failed, the pair
        # was written as two equal `.skip` markers, and `compare_all_pairs`
        # reported `SKIPPED (both sides)` without counting it. The run then
        # claimed byte-for-byte parity over a framework it never compared — the
        # same "harness that cannot fail" class as the H4 zero-pairs hole.
        map_image_paths = set(map_file.read_text(errors="replace").splitlines())
        canonical_path = f"/System/Library/Frameworks/{framework_name}.framework/Versions/A/{framework_name}"
        for candidate_path in (canonical_path, "/System/iOSSupport" + canonical_path):
            if candidate_path in map_image_paths:
                return candidate_path
        return None

    def run_dyld_cache_part(self) -> None:
        available_cache_directories = [directory for directory in ARCHIVED_CACHE_DIRECTORIES
                                       if (directory / "dyld_shared_cache_arm64e").is_file()]
        if not available_cache_directories:
            print("No archived cache found - falling back to the current system's dyld shared cache.")
            for framework_name in self.arguments.framework_names:
                image_path = f"/System/Library/Frameworks/{framework_name}.framework/Versions/A/{framework_name}"
                for command_name in ("dump", "interface"):
                    self.run_pair("cache-current-system", framework_name, command_name,
                                  ["--uses-system-dyld-shared-cache", "-p", image_path])
            return
        for cache_directory in available_cache_directories:
            scenario_name = f"cache-{cache_directory.name}"
            for framework_name in self.arguments.framework_names:
                image_path = self.image_path_inside_cache(cache_directory, framework_name)
                if image_path is None:
                    print(f"[skip] {scenario_name}/{framework_name}: not in cache")
                    continue
                for command_name in ("dump", "interface"):
                    self.run_pair(scenario_name, framework_name, command_name,
                                  [str(cache_directory / "dyld_shared_cache_arm64e"), "--dyld-shared-cache", "-p", image_path])

    # --- Part 2: simulator runtime Mach-O files -----------------------------

    def discover_simulator_runtime_roots(self) -> dict[str, Path]:
        runtime_roots_by_label: dict[str, Path] = {}
        for search_directory in SIMULATOR_RUNTIME_SEARCH_DIRECTORIES:
            if not search_directory.is_dir():
                continue
            for runtime_bundle in sorted(search_directory.glob("*.simruntime")):
                label = runtime_bundle.stem
                if not label.startswith("iOS") or label in runtime_roots_by_label:
                    continue
                runtime_roots_by_label[label] = runtime_bundle / "Contents/Resources/RuntimeRoot"
        return runtime_roots_by_label

    def run_simulator_part(self) -> None:
        for label, runtime_root in self.discover_simulator_runtime_roots().items():
            scenario_name = "sim-" + label.replace(" ", "-")
            for framework_name in self.arguments.framework_names:
                framework_binary = runtime_root / f"System/Library/Frameworks/{framework_name}.framework/{framework_name}"
                if not framework_binary.is_file():
                    print(f"[skip] {scenario_name}/{framework_name}: not in runtime")
                    continue
                for command_name in ("dump", "interface"):
                    # Older runtimes ship fat (x86_64 + arm64) binaries; the slice must be explicit.
                    self.run_pair(scenario_name, framework_name, command_name, [str(framework_binary), "-a", "arm64"])

    # --- Part 3: in-process MachOImage (current system) ---------------------

    def run_macho_image_part(self) -> None:
        """RenderingVerificationTests is the maintainer harness designed for exactly
        this two-checkout diff; running it here is the documented exception to the
        "agents must not run IntegrationTests" rule. Both sides MUST run within the
        same boot session: memberAddress comments depend on the per-boot dyld
        shared cache slide."""
        for side, checkout, scratch in self.sides():
            output_directory = self.output_root / "machoimage-current" / side
            output_directory.mkdir(parents=True, exist_ok=True)
            environment = os.environ.copy()
            environment.update({
                "RV_OUT": str(output_directory),
                "RV_FRAMEWORKS": ",".join(self.arguments.framework_names),
                "RV_OPTS": RENDERING_VERIFICATION_OPTIONS,
                "MACHO_SWIFT_SECTION_SILENT_TEST": "1",
            })
            log_file = self.output_root / "machoimage-current" / f"{side}.test.log"
            with open(log_file, "w") as log_handle:
                completed = subprocess.run([
                    "swift", "test", "-c", "release",
                    "--package-path", str(checkout),
                    "--scratch-path", str(scratch),
                    "--filter", "RenderingVerificationTests",
                ], env=environment, stdout=log_handle, stderr=subprocess.STDOUT)
            print(f"[{side}] machoimage-current exit={completed.returncode}")
            if completed.returncode != 0:
                # Unlike the CLI scenarios (which degrade to paired .skip
                # markers), a failed test invocation silently thins the
                # comparison matrix — propagate it as a run-level failure.
                self.hard_failure_messages.append(
                    f"machoimage-current[{side}]: swift test exited {completed.returncode} (log: {log_file})")

    # --- Diff phase ---------------------------------------------------------

    def compare_all_pairs(self) -> tuple[int, int]:
        """Returns (difference_count, examined_pair_count).

        The examined count exists so the verdict can refuse to pass on an
        empty comparison: with no cache archive, no installed runtime, or a
        mistyped --frameworks, every scenario degrades to paired .skip
        markers, the glob yields nothing, and a difference count of 0 would
        otherwise read as success (PR #103 review, H4 — a harness that
        cannot fail is worse than no harness).
        """
        print("\n=== A/B comparison ===")
        difference_count = 0
        examined_pair_count = 0
        baseline_files = sorted(self.output_root.glob("**/baseline/*.txt"))
        for baseline_file in baseline_files:
            candidate_file = Path(str(baseline_file).replace("/baseline/", "/candidate/"))
            relative_name = baseline_file.relative_to(self.output_root)
            examined_pair_count += 1
            if not candidate_file.is_file():
                print(f"MISSING-ON-CANDIDATE  {relative_name}")
                difference_count += 1
            elif filecmp.cmp(baseline_file, candidate_file, shallow=False):
                print(f"IDENTICAL  {relative_name}")
            else:
                print(f"DIFFERS    {relative_name}")
                difference_count += 1
        for candidate_file in sorted(self.output_root.glob("**/candidate/*.txt")):
            baseline_file = Path(str(candidate_file).replace("/candidate/", "/baseline/"))
            if not baseline_file.is_file():
                print(f"MISSING-ON-BASELINE  {candidate_file.relative_to(self.output_root)}")
                examined_pair_count += 1
                difference_count += 1
        for skip_file in sorted(self.output_root.glob("**/baseline/*.skip")):
            candidate_skip = Path(str(skip_file).replace("/baseline/", "/candidate/"))
            relative_name = skip_file.relative_to(self.output_root)
            if not candidate_skip.is_file():
                # Baseline refused while the candidate produced output: the
                # candidate .txt already counted as MISSING-ON-BASELINE above.
                continue
            baseline_marker = skip_file.read_text().strip()
            candidate_marker = candidate_skip.read_text().strip()
            if baseline_marker == candidate_marker:
                print(f"SKIPPED (both sides, {baseline_marker})  {relative_name}")
            else:
                # Both sides failed, but DIFFERENTLY — e.g. the baseline exits 1
                # on a pre-existing unsupported case while the candidate traps
                # (134). Neither side leaves a .txt, so this pair is invisible to
                # both globs above; counting it here is what stops a
                # candidate-introduced crash from being reported as a pass. Same
                # class as the zero-pairs hole (PR #103 review, H4).
                print(f"EXIT-CODE-DIFFERS  {relative_name}  "
                      f"baseline={baseline_marker} candidate={candidate_marker}")
                examined_pair_count += 1
                difference_count += 1
        return difference_count, examined_pair_count


def main() -> None:
    arguments = parse_arguments()
    run = VerificationRun(arguments)
    run.output_root.mkdir(parents=True, exist_ok=True)
    print(f"Output root: {run.output_root}")

    run.build_both_sides()
    run.run_dyld_cache_part()
    run.run_simulator_part()
    if not arguments.skip_image_part:
        run.run_macho_image_part()

    difference_count, examined_pair_count = run.compare_all_pairs()
    if run.hard_failure_messages:
        for hard_failure_message in run.hard_failure_messages:
            print(f"HARD-FAILURE  {hard_failure_message}")
        print("\nRESULT: FAILED — a test invocation exited non-zero, so the comparison matrix is incomplete "
              "and no verdict over it is trustworthy.")
        sys.exit(1)
    if examined_pair_count == 0:
        print("\nRESULT: FAILED — zero pairs were compared. Every scenario fell back to a skip marker "
              "(no cache archive, no installed simulator runtime, or a mistyped --frameworks?); "
              "a green verdict over nothing is meaningless.")
        sys.exit(1)
    if difference_count == 0:
        print(f"\nRESULT: all {examined_pair_count} pairs byte-identical.")
    else:
        print(f"\nRESULT: {difference_count} differing pair(s) out of {examined_pair_count}. "
              f"Re-run the differing scenario twice on one side "
              f"first to rule out nondeterminism before attributing.")
        sys.exit(1)


if __name__ == "__main__":
    main()
