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
        [--output-root PATH] [--frameworks A,B,...] [--scenarios cache-15.5,sim-iOS-18.5,...]
        [--baseline-scratch PATH] [--candidate-scratch PATH] [--skip-image-part]
        [--jobs N] [--baseline-cache PATH | --no-baseline-cache]

Wall clock:
    - The two release builds run concurrently, and the CLI render pairs run
      through a pool of --jobs workers (each pair is an independent process
      writing its own file; a SwiftUI interface render takes 1-2 GB, size the
      pool by memory). The MachOImage part stays one `swift test` per side.
    - The BASELINE side's CLI renders are cached under --baseline-cache, keyed
      by the baseline checkout's HEAD commit plus the input file's identity
      (path, size, mtime) and the exact command line: a baseline that has not
      changed is never rendered twice across rounds. A dirty baseline checkout
      disables the cache. The candidate side is what is under test and is
      always rendered; the MachOImage part is never cached (its member
      addresses carry the per-boot cache slide).
    - --scenarios restricts the run to the named legs (`cache-<version>`,
      `cache-current-system`, `sim-iOS-<version>`, `machoimage-current`), for
      re-checking one leg after a fix without paying for the others.

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
import concurrent.futures
import datetime
import filecmp
import hashlib
import json
import os
import platform
import shutil
import subprocess
import sys
import time
from pathlib import Path

DEFAULT_FRAMEWORK_NAMES = ["SwiftUI", "SwiftUICore", "SwiftData", "Combine", "ActivityKit", "WidgetKit"]

# The archive names its directories by plain OS version. Both entries are
# checked for an arm64e cache and silently skipped when absent, so a machine
# carrying only one of them still runs that leg.
ARCHIVED_CACHE_DIRECTORIES = [
    Path("/Volumes/DyldSharedCaches/macOS/26.6"),
    Path("/Volumes/DyldSharedCaches/macOS/15.5"),
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
    parser.add_argument("--scenarios", default="",
                        help="Comma-separated scenario names to run (cache-15.5, cache-current-system, "
                             "sim-iOS-18.5, machoimage-current, ...); default: every scenario.")
    parser.add_argument("--jobs", type=int, default=min(6, os.cpu_count() or 1),
                        help="Concurrent CLI render processes (default: min(6, CPU count)).")
    parser.add_argument("--baseline-cache", type=Path,
                        default=Path.home() / "Library/Caches/MachOSwiftSection/RenderingABBaseline",
                        help="Directory caching the baseline side's CLI renders across runs.")
    parser.add_argument("--no-baseline-cache", action="store_true",
                        help="Render the baseline side even when a cached render exists.")
    arguments = parser.parse_args()
    arguments.baseline_checkout = arguments.baseline_checkout.resolve()
    arguments.candidate_checkout = arguments.candidate_checkout.resolve()
    if arguments.baseline_scratch is None:
        arguments.baseline_scratch = arguments.baseline_checkout / ".build"
    if arguments.candidate_scratch is None:
        arguments.candidate_scratch = arguments.candidate_checkout / ".build"
    arguments.framework_names = [name.strip() for name in arguments.frameworks.split(",") if name.strip()]
    arguments.scenario_names = {name.strip() for name in arguments.scenarios.split(",") if name.strip()}
    if arguments.jobs < 1:
        arguments.jobs = 1
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
        # CLI render jobs are collected by the scenario parts and executed
        # together through the worker pool (`execute_pending_jobs`).
        self.pending_jobs: list[tuple[str, str, str, list[str]]] = []
        self.baseline_cache_key_prefix: str | None = None
        self.baseline_cache_hit_count = 0
        self.baseline_cache_store_count = 0

    def runs_scenario(self, scenario_name: str) -> bool:
        selected = getattr(self.arguments, "scenario_names", set())
        return not selected or scenario_name in selected

    # --- Building -----------------------------------------------------------

    def build_both_sides(self) -> None:
        """The two sides build concurrently: separate checkouts, separate
        scratch paths, no shared state."""
        def build(side: str, checkout: Path, scratch: Path) -> tuple[str, int]:
            print(f"Building release swift-section for {checkout} ...")
            log_file = self.output_root / f"build-{side}.log"
            with open(log_file, "w") as log_handle:
                completed = subprocess.run([
                    "swift", "build", "-c", "release",
                    "--package-path", str(checkout),
                    "--scratch-path", str(scratch),
                    "--product", "swift-section",
                ], stdout=log_handle, stderr=subprocess.STDOUT)
            return side, completed.returncode

        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(lambda entry: build(*entry), self.sides()))
        for side, return_code in results:
            if return_code != 0:
                sys.exit(f"error: release build failed for {side} (log: {self.output_root / f'build-{side}.log'})")
        for side, _, scratch in self.sides():
            self.command_line_interfaces[side] = scratch / "release" / "swift-section"
            print(f"Built {side}: {self.command_line_interfaces[side]}")

    def sides(self) -> list[tuple[str, Path, Path]]:
        return [
            ("baseline", self.arguments.baseline_checkout, self.arguments.baseline_scratch),
            ("candidate", self.arguments.candidate_checkout, self.arguments.candidate_scratch),
        ]

    # --- One rendered pair --------------------------------------------------

    def run_pair(self, scenario_name: str, framework_name: str, command_name: str, extra_arguments: list[str]) -> None:
        """Queue one dump/interface command for both sides' CLIs (see
        `execute_pending_jobs`); a scenario outside --scenarios is dropped here,
        so every part can stay ignorant of the filter."""
        if not self.runs_scenario(scenario_name):
            return
        self.pending_jobs.append((scenario_name, framework_name, command_name, list(extra_arguments)))

    def execute_pending_jobs(self) -> None:
        """Render every queued pair, both sides, through the worker pool.
        Output files are per (scenario, side, framework, command), so the
        order of completion is irrelevant to the diff phase."""
        self.prepare_baseline_cache()
        work_items = [(side, *job) for job in self.pending_jobs for side in ("baseline", "candidate")]
        if not work_items:
            return
        print(f"Rendering {len(self.pending_jobs)} pair(s) with {self.arguments.jobs} worker(s) ...")
        with concurrent.futures.ThreadPoolExecutor(max_workers=self.arguments.jobs) as pool:
            for line in pool.map(lambda item: self.render_one_side(*item), work_items):
                print(line, flush=True)
        if self.baseline_cache_key_prefix is not None:
            print(f"Baseline cache: {self.baseline_cache_hit_count} hit(s), "
                  f"{self.baseline_cache_store_count} stored, under {self.arguments.baseline_cache}")

    def render_one_side(self, side: str, scenario_name: str, framework_name: str, command_name: str, extra_arguments: list[str]) -> str:
        output_directory = self.output_root / scenario_name / side
        output_directory.mkdir(parents=True, exist_ok=True)
        output_file = output_directory / f"{framework_name}.{command_name}.txt"
        skip_file = output_directory / f"{framework_name}.{command_name}.skip"
        log_file = output_directory / f"{framework_name}.{command_name}.log"
        cache_directory = self.baseline_cache_directory(side, scenario_name, framework_name, command_name, extra_arguments)
        if cache_directory is not None and self.restore_from_baseline_cache(cache_directory, output_file, skip_file, log_file):
            self.baseline_cache_hit_count += 1
            marker = skip_file.read_text().strip() if skip_file.is_file() else "exit=0"
            return f"[{side}] {scenario_name}/{framework_name} {command_name} {marker} cached"
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
            skip_file.write_text(f"exit={completed.returncode}\n")
        if cache_directory is not None:
            self.store_in_baseline_cache(cache_directory, output_file, skip_file, log_file)
            self.baseline_cache_store_count += 1
        return (f"[{side}] {scenario_name}/{framework_name} {command_name} "
                f"exit={completed.returncode} {elapsed_seconds:.0f}s")

    # --- Baseline render cache ---------------------------------------------

    def prepare_baseline_cache(self) -> None:
        """The cache is keyed by the baseline checkout's HEAD commit; a dirty
        checkout (anything `git status --porcelain` lists) has no stable
        identity and disables it."""
        if self.arguments.no_baseline_cache:
            return
        checkout = self.arguments.baseline_checkout
        head = subprocess.run(["git", "-C", str(checkout), "rev-parse", "HEAD"], capture_output=True, text=True)
        status = subprocess.run(["git", "-C", str(checkout), "status", "--porcelain"], capture_output=True, text=True)
        if head.returncode != 0 or status.returncode != 0:
            print("Baseline cache: disabled (the baseline checkout is not a git checkout).")
            return
        if status.stdout.strip():
            print("Baseline cache: disabled (the baseline checkout has uncommitted changes).")
            return
        self.baseline_cache_key_prefix = head.stdout.strip()

    def baseline_cache_directory(self, side: str, scenario_name: str, framework_name: str, command_name: str, extra_arguments: list[str]) -> Path | None:
        if side != "baseline" or self.baseline_cache_key_prefix is None:
            return None
        identities: list[list] = []
        for argument in extra_arguments:
            path = Path(argument)
            if argument.startswith("/") and path.is_file():
                stat = path.stat()
                identities.append([argument, stat.st_size, stat.st_mtime_ns])
        if "--uses-system-dyld-shared-cache" in extra_arguments:
            # The running system's cache has no path on the command line;
            # its identity is the OS build.
            identities.append(["system-cache", platform.mac_ver()[0], os.uname().version])
        key_material = json.dumps([self.baseline_cache_key_prefix, scenario_name, framework_name, command_name, extra_arguments, identities])
        key = hashlib.sha256(key_material.encode("utf-8")).hexdigest()[:24]
        return self.arguments.baseline_cache / self.baseline_cache_key_prefix / f"{scenario_name}-{framework_name}-{command_name}-{key}"

    @staticmethod
    def restore_from_baseline_cache(cache_directory: Path, output_file: Path, skip_file: Path, log_file: Path) -> bool:
        cached_output = cache_directory / output_file.name
        cached_skip = cache_directory / skip_file.name
        if not cached_output.is_file() and not cached_skip.is_file():
            return False
        output_file.unlink(missing_ok=True)
        skip_file.unlink(missing_ok=True)
        if cached_output.is_file():
            shutil.copyfile(cached_output, output_file)
        if cached_skip.is_file():
            shutil.copyfile(cached_skip, skip_file)
        cached_log = cache_directory / log_file.name
        if cached_log.is_file():
            shutil.copyfile(cached_log, log_file)
        return True

    @staticmethod
    def store_in_baseline_cache(cache_directory: Path, output_file: Path, skip_file: Path, log_file: Path) -> None:
        cache_directory.mkdir(parents=True, exist_ok=True)
        for file in (output_file, skip_file, log_file):
            if file.is_file():
                shutil.copyfile(file, cache_directory / file.name)

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
            if not self.runs_scenario(scenario_name):
                continue
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
            if not self.runs_scenario(scenario_name):
                continue
            for framework_name in self.arguments.framework_names:
                framework_binary = runtime_root / f"System/Library/Frameworks/{framework_name}.framework/{framework_name}"
                if not framework_binary.is_file():
                    print(f"[skip] {scenario_name}/{framework_name}: not in runtime")
                    continue
                for command_name in ("dump", "interface"):
                    # Older runtimes ship fat (x86_64 + arm64) binaries; the slice must be explicit.
                    # The runtime root is the system root the framework's dependencies
                    # resolve under (UIKit, Foundation, libobjc as files): the ObjC ancestor
                    # chain, the property-wrapper catalog and the static layout engine all
                    # read cross-image facts through it, and the host's macOS cache is no
                    # substitute for an iOS binary's images. Passed to BOTH sides, so the two
                    # CLIs see the same inputs and only their own behavior differs.
                    self.run_pair(scenario_name, framework_name, command_name,
                                  [str(framework_binary), "-a", "arm64", "--dependency-search-path", str(runtime_root)])

    # --- Part 3: in-process MachOImage (current system) ---------------------

    def run_macho_image_part(self) -> None:
        """RenderingVerificationTests is the maintainer harness designed for exactly
        this two-checkout diff; running it here is the documented exception to the
        "agents must not run IntegrationTests" rule. Both sides MUST run within the
        same boot session: memberAddress comments depend on the per-boot dyld
        shared cache slide — which is also why this part is never served from
        the baseline cache. The two sides run concurrently (separate scratch
        paths; the renders happen inside each `swift test` process)."""
        if not self.runs_scenario("machoimage-current"):
            return
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            list(pool.map(lambda entry: self.run_macho_image_side(*entry), self.sides()))

    def run_macho_image_side(self, side: str, checkout: Path, scratch: Path) -> None:
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
    run.execute_pending_jobs()
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
