# Cross-reference recall benchmark

Measures how many of the code references in two real Apple binaries `swift-section refs` finds, against a ground truth built without any of the tools measured, and puts the result next to IDA's on the same targets. It is the acceptance gate of evolution proposal [`cross-reference-recall-gaps`](../../Documentations/Evolutions/0113-cross-reference-recall-gaps.md), and the numbers are kept in the vision [Reverse engineering without IDA](../../Documentations/Visions/ReverseEngineeringWithoutIDA.md).

## Samples

| Binary | Path (default) | arm64e UUID |
|---|---|---|
| Finder 26.5.2 (mostly Objective-C) | `/Volumes/RE/Finder/26.5.2/Finder` | `1E2E81F7-9B9D-317A-A102-F55ADAF6A0A0` |
| ControlCenter 26.7 (mostly Swift) | `/Volumes/RE/ControlCenter/26.7/ControlCenter` | `5782ED6B-471B-3CAC-9258-93734B6009C3` |

Override the paths with `CROSS_REFERENCE_RECALL_FINDER` and `CROSS_REFERENCE_RECALL_CONTROL_CENTER`; the slices must have these UUIDs, or the targets and the IDA baseline no longer apply.

## Running

```sh
SWIFT_SECTION=/path/to/swift-section Scripts/CrossReferenceRecall/run_all.sh
```

About 30 seconds. Everything is written to `CROSS_REFERENCE_RECALL_WORK` (default `/tmp/cross-reference-recall`). Needs `otool`, `dyld_info`, `lipo` and `dwarfdump` from the Xcode command-line tools, and the system `python3`.

| Script | What it does |
|---|---|
| `prepare.sh` | Thins both binaries to arm64e and writes their `otool -tV`, section and `dyld_info -fixups` listings. |
| `ground_truth.py` | Builds the ground truth — `otool -tV` plus a linear `adrp` register tracker, the fixups, the relative method lists and `__swift5_types` — and picks the 120 targets, seeded, in the order the 2026-11-18 run did. |
| `verify_reproduction.py` | Checks the totals and target lists against that run's printed output; fails when they differ. |
| `query_swift_section.py` | Asks `$SWIFT_SECTION refs` once per target, as an agent would. |
| `score.py` | Scores with the 2026-11-18 rules and prints the table beside `ida-2026-11-18.txt`; every miss and extra goes to `swift-section.details.txt` with its disassembly line. |

`ground_truth.py` is the 2026-11-18 run's code, recovered from that session's transcript and rewritten with full names; `verify_reproduction.py` is what shows the rewrite changed nothing. `ida-2026-11-18.txt` is that run's scoring output (`ida1` one query, `ida2` two hops; the `bn` rows are Binary Ninja through its MCP server).

## Categories

A selector sends · B Objective-C class references · C imported functions through stubs · D internal functions called with `bl` · E string literals · F instance variable offsets (Finder only) · G Swift metadata accessors, and functions only Swift tables point at (ControlCenter only) · H method implementations and function pointers. G-tableonly and H are data references, which `refs` does not report.

## Results

| Date | Tool | Code references found (of 527) |
|---|---|---|
| 2026-11-18 | IDA, one query / two hops | 97.0% / 99.4% |
| 2026-11-18 | Binary Ninja 6 through its MCP server | 67.6% |
| 2026-11-26 | `swift-section` 0.25.0 | 90.3% (476) |
| 2026-11-26 | `swift-section` with proposal `cross-reference-recall-gaps` | 97.5% (514), no extras |

0.25.0's 51 misses: 27 Swift metadata accessors whose address is taken rather than called, 13 loads from `__objc_superrefs` (not class references by design), 8 class GOT slots whose address Swift code hands to the metadata helper, 2 selectors used as arguments, 1 instance variable offset whose address two paths build differently before one load. The proposal fixes all but the 13; with it the 13 are the only misses.
