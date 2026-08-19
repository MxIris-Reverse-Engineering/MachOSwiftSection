# PR #103 Code Review Findings — Round Three

Review date: 2026-08-14
PR: `feature/node-store-migration` → `main`, head `b2eabe6`, merge base `aa38ff50`
Review depth: automated multi-agent review at `max` effort over the state left by round two, followed by a manual pass answering the four mandatory questions (reproduce / baseline / worth fixing / fixed before) for every finding, plus an independent cross-review by a second session.

Status: **Implemented (2026-08-14)** in three batches — see `Documentations/Internal/TaskReports/2026-08-14-pr103-review-round-three-fixes.md`. Findings adjudicated "won't fix" or "false positive" live in `Documentations/Internal/ReviewAdjudications.md` (A9–A12). This file records what is left OPEN, plus the round's revisions to its own write-up.

Earlier rounds: [2026-08-09](2026-08-09-pr103-review-findings.md) (round one), and round two in `Documentations/Internal/TaskReports/2026-08-13-pr103-review-round-two-fixes.md`.

---

## Open

### O1 — An out-of-bounds `ProtocolDescriptor` read segfaults instead of throwing

**Severity: Medium** (robustness / hostile input), **not** introduced by this PR.

Found while writing a test, not by the review: constructing a descriptor from a real layout re-wrapped at an out-of-file offset — the technique `DiffRendererHeaderFailureTests` and `PrintFailureEventTests` have used for a while — throws cleanly for a `StructDescriptor` but **crashes the process with SIGSEGV for a `ProtocolDescriptor`**.

- **Q1 — Reproducible?** Yes, deterministically. `ProtocolDefinition(protocolDescriptor: ProtocolDescriptor(layout: <real layout>, offset: 0x0FFF_FFF0), protocolName: <real name>)` followed by `materializedProtocol(in: machOFile)` takes the test runner down (signal 11), on the `SymbolTestsCore` fixture read as a `MachOFile`. The equivalent construction over `StructDescriptor` surfaces a thrown error, which is why every existing error-contract test uses that shape.
- **Q2 — Does the baseline have it?** Almost certainly — `Protocol.init(descriptor:in:)`'s read sequence is not touched by this PR. Not confirmed against `main` (confirming it means reproducing a crash on the baseline, which was not worth the cycles mid-batch).
- **Q3 — Worth fixing, blast radius?** Worth fixing. The library's stated posture is that binary-supplied geometry must never decide whether the host process lives — `PackedNameReference` degrades rather than traps for exactly this reason, and issue #102 is a whole workstream about surfacing rather than dying. A damaged or hostile binary reaching the protocol path takes the process with it instead of producing an error a caller can catch. The blast radius is every consumer that parses untrusted binaries (RuntimeViewer inspecting arbitrary apps, the CLI over a corrupt file).
- **Q4 — Fixed before?** Not for this path. The same *class* of hardening has been done twice elsewhere: `PackedNameReference`'s clamped geometry, and the legacy `LC_DYLD_INFO` bind opcode stream in `MachOKitExtensions` (bounds-checked per slot, repeat runs terminated at the segment end, "treated as hostile input"). The protocol descriptor read never got that treatment.

**Where to start**: `Sources/MachOSwiftSection/Models/Protocol/Protocol.swift` `init(descriptor:in:)` — the reads are `descriptor.name(in:)`, then `readWrapperElements` for the requirement-signature array, then `initialize(descriptor:currentOffset:in:)` for the requirement array (which also reads at `currentOffset - ProtocolRequirement.layoutSize`, i.e. it can compute a NEGATIVE offset when `currentOffset` is small). Compare against how the struct path bounds-checks, and add a test to the same suites once it throws.

**Blocked test**: `PrintFailureEventTests` carries a comment where the missing test would be — the event-ORDER half of the protocol print contract has no test because the only way to reach it crashes the runner. Landing this fix unblocks that test.

---

## Revisions this round made to its own findings

Recorded because the four questions changed three conclusions, and the corrections are more instructive than the originals:

1. **`OrderedMember.minSymbolOffset` was a false positive.** See `ReviewAdjudications.md` A10 for the full reasoning and the exhaustive census that replaced the original sampling.
2. **The diff renderer's dropped declarations do not affect the ABI verdict.** The original write-up claimed a dropped declaration disappears from the change list, `--json` and `--fail-on-breaking`. All three run through `ABIDiffer` over the indexed model; `SwiftDiffableInterfaceRenderer` only produces the annotated interface text. The defect is real but is a reporting defect, fixed by a stderr diagnostic rather than by changing the drop.
3. **The main interface path's enum cases were never silently degrading.** `printThrowingEnumCase` propagates and gates on `FieldFlags.hasMangledTypeName`; the silent `printEnumCase` serves the diff renderer only. Two of the three "context-less" `printCatchedThrowing` call sites are deliberate and documented.

Two wording corrections worth keeping: for the multi-payload-enum cache and the opaque-type rewriter, the *files* differ from `main` (both carry the `print(error)` → stderr change) — it is the *defect code* that is identical, and that is what the non-regression conclusion rests on. And `printCatchedThrowing` "has no failure event on `main`" holds only at DEFINITION level; `main`'s `dispatchingCatchedThrowing` already dispatched at member level.
