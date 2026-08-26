import Foundation
import Testing
@_spi(Internals) import Demangling
@_spi(Internals) @testable import MachOSymbols
@_spi(Internals) import MachOCaches
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based unit coverage for `SymbolIndexStore` against the
/// `SymbolTestsCore` framework (self-built fixture, no external Xcode
/// dependency). Complements the heavyweight integration/baseline tests:
/// these assert the NodeStore-backed pipeline's invariants — cache-free
/// building, byte-identical printing versus the `Node` pipeline, the
/// `structurallyEquals` bridge behind every `Node`-taking query API, and
/// the Stage 3 flat-symbol-table row indirection.
///
/// Serialized: several tests share the cached per-file storage.
@Suite(.serialized)
final class SymbolIndexStoreFixtureTests: MachOFileTests, @unchecked Sendable {
    override class var fileName: MachOFileName { .SymbolTestsCore }

    private var storage: SymbolIndexStore.Storage {
        get throws {
            try #require(SymbolIndexStore.shared.storage(in: machOFile))
        }
    }

    // MARK: - Build invariants

    /// Pins the property the build sweep RELIES on: `demangleAsNodeTransient`
    /// is genuinely non-interning, so two demangles of one name yield equal but
    /// distinct trees.
    ///
    /// Scope, stated honestly: the assertions below are about **this test's own**
    /// two `demangleAsNodeTransient` calls, so this does **not** verify that the
    /// build sweep uses that entry point. It cannot: `Storage` holds
    /// `NodeReference`s into a frozen arena, so materializing the sweep's trees
    /// twice yields distinct instances regardless of which demangle built them,
    /// and process-global `NodeCache` counters are racy because every test target
    /// shares one process. The migration invariant itself ("Sources carries zero
    /// cached `demangleAsNode(` call sites") is enforced by source scan in
    /// `NodeStoreMigrationInvariantTests`, which is the check that actually fails
    /// when it is broken. (The process-global zero-growth measurement lives in
    /// the manually run `SymbolIndexStoreBaselineTests`.)
    @Test func buildPipelineStaysOffGlobalNodeCache() throws {
        let builtStorage = try #require(SymbolIndexStore.shared.buildStorage(for: machOFile))
        #expect(builtStorage.symbolTable.rowCount > 0)

        let sampleRow = try #require(builtStorage.rootNodeIndexByTableRow.firstIndex(where: { $0 != nil }))
        let sampleSymbolName = builtStorage.symbolTable.materializedName(atRow: UInt32(sampleRow))
        let firstTransientTree = try demangleAsNodeTransient(sampleSymbolName)
        let secondTransientTree = try demangleAsNodeTransient(sampleSymbolName)
        let firstLeaf = try #require(firstTransientTree.first { $0.children.isEmpty })
        let secondLeaf = try #require(secondTransientTree.first { $0.children.isEmpty })
        #expect(firstLeaf == secondLeaf)
        #expect(firstLeaf !== secondLeaf)
    }

    /// Every symbol's zero-materialization print must be byte-identical to
    /// the classic `demangleAsNode` + `Node.print` pipeline.
    @Test func printedSymbolsMatchNodePipeline() throws {
        let storage = try storage
        var checkedCount = 0
        var mismatchCount = 0
        for row in 0 ..< storage.symbolTable.rowCount {
            guard let rootNodeIndex = storage.rootNodeIndexByTableRow[row] else { continue }
            let symbolName = storage.symbolTable.materializedName(atRow: UInt32(row))
            let reference = storage.nodeStore.reference(at: rootNodeIndex)
            let expected = try demangleAsNode(symbolName, internsSubtrees: false).print(using: .default)
            if reference.print(using: .default) != expected {
                mismatchCount += 1
                if mismatchCount <= 3 {
                    Issue.record("Store print mismatch for \(symbolName)")
                }
            }
            checkedCount += 1
        }
        #expect(mismatchCount == 0)
        #expect(checkedCount > 0)
    }

    // MARK: - Flat symbol table (Stage 3)

    /// The whole point of the Stage 3 compaction: vended values stay small.
    /// `Symbol` drops the 40-byte `nlist` existential; `DemangledSymbol`
    /// stores a shared-table row instead of an inline `Symbol` copy.
    @Test func compactValueLayouts() {
        #expect(MemoryLayout<Symbol>.stride <= 32)
        #expect(MemoryLayout<DemangledSymbol>.stride <= 32)
        #expect(MemoryLayout<SymbolRow>.stride == 16)
        // Proposal 0003: the row bucket must stay a compact inline value —
        // widening it erodes the single-row savings across every dictionary
        // slot that holds one.
        #expect(MemoryLayout<SymbolRowBucket>.stride <= 16)
    }

    // MARK: - Row buckets (proposal 0003)

    /// The bucket's whole contract: first append stays inline, the second
    /// spills to an array, iteration preserves insertion order (the
    /// byte-identical-output guarantee), and `contains` answers both forms.
    @Test func symbolRowBucketAppendMigrationAndIterationOrder() {
        var bucket = SymbolRowBucket.empty
        #expect(bucket.isEmpty)
        #expect(bucket.count == 0)
        #expect(!bucket.contains(7))

        bucket.append(7)
        #expect(bucket == .single(7))
        #expect(bucket.count == 1)
        #expect(Array(bucket) == [7])
        #expect(bucket.contains(7))
        #expect(!bucket.contains(9))

        bucket.append(9)
        #expect(bucket == .multiple([7, 9]))

        bucket.append(5)
        #expect(bucket == .multiple([7, 9, 5]))
        #expect(Array(bucket) == [7, 9, 5])
        #expect(bucket.count == 3)
        #expect(bucket.contains(5))
        #expect(!bucket.contains(6))
    }

    /// Single-row dominance is what proposal 0003's memory estimate rests
    /// on; assert the direction on the fixture and surface the exact ratio
    /// as acceptance evidence (the framework-scale ratio is re-measured by
    /// the RuntimeViewer heap step).
    @Test func rowBucketsAreDominatedBySingleRowForm() throws {
        let storage = try storage
        let statistics = storage.bucketFormStatisticsForTesting()
        let totalBucketCount = statistics.singleRowBucketCount + statistics.multipleRowBucketCount
        try #require(totalBucketCount > 0)
        let singleRowRatio = Double(statistics.singleRowBucketCount) / Double(totalBucketCount)
        print("SymbolRowBucket forms — single: \(statistics.singleRowBucketCount), multiple: \(statistics.multipleRowBucketCount), single ratio: \(singleRowRatio)")
        #expect(
            statistics.singleRowBucketCount > statistics.multipleRowBucketCount,
            "single: \(statistics.singleRowBucketCount), multiple: \(statistics.multipleRowBucketCount), ratio: \(singleRowRatio)"
        )
    }

    /// File-leg counterpart of `SymbolTableImageEquivalenceTests`: a
    /// `MachOFile` table's names live in the private byte buffer, so this
    /// pins the same binary-search and vend-materialization behavior over
    /// that name source.
    @Test func fileLegBinarySearchAndDetachedMaterializationAgree() throws {
        let storage = try storage
        let symbolTable = storage.symbolTable
        try #require(symbolTable.rowCount > 0)

        var mismatchCount = 0
        for row in 0 ..< symbolTable.rowCount {
            let materializedName = symbolTable.materializedName(atRow: UInt32(row))
            if symbolTable.row(forName: materializedName) != UInt32(row) {
                mismatchCount += 1
                if mismatchCount <= 3 {
                    Issue.record("binary search failed to find row \(row) (\(materializedName))")
                }
            }
        }
        #expect(mismatchCount == 0)

        let sampleRow = try #require(storage.rootNodeIndexByTableRow.firstIndex(where: { $0 != nil }))
        let vended = try #require(storage.demangledSymbol(atRow: UInt32(sampleRow)))
        #expect(vended.retainedSymbolTableRowCount == symbolTable.rowCount)
        let detached = vended.detachedFromSharedTable()
        #expect(detached.retainedSymbolTableRowCount == 1)
        #expect(detached.symbol == vended.symbol)
        #expect(detached.demangledNode == vended.demangledNode)
        #expect(detached.symbol.name == symbolTable.materializedName(atRow: UInt32(sampleRow)))
    }

    /// Raw and cache-adjusted offset keys share one canonical table row, so
    /// `symbols(for:in:)` must rebuild each `Symbol` with the queried offset
    /// (matching the old per-offset-copy behavior byte for byte).
    @Test func offsetQueriesRebuildSymbolsWithQueriedOffset() throws {
        let storage = try storage
        #expect(!storage.symbolRowsByOffset.isEmpty)
        // Complete and deterministic: `symbolRowsByOffset` is deliberately
        // unordered (nothing production iterates it), and Swift dictionary
        // iteration order is seeded per process — a capped raw iteration
        // once sampled a DIFFERENT 500 offsets every run, giving this pin
        // unstable coverage. Sorting and checking every offset makes a
        // regression on cache-adjusted keys reproducible.
        var checkedOffsetCount = 0
        for (offset, rows) in storage.symbolRowsByOffset.sorted(by: { $0.key < $1.key }) {
            let queried = try #require(SymbolIndexStore.shared.symbols(for: offset, in: machOFile))
            #expect(queried.count == rows.count)
            #expect(queried.allSatisfy { $0.offset == offset })
            for (queriedSymbol, row) in zip(queried, rows) {
                #expect(queriedSymbol.name == storage.symbolTable.materializedName(atRow: row))
            }
            checkedOffsetCount += 1
        }
        #expect(checkedOffsetCount > 0)
    }

    // MARK: - Query APIs

    /// `memberSymbols(of:for:node:)` takes an externally demangled `Node` and
    /// must find the node-index-keyed bucket via `structurallyEquals`.
    /// Exercise it for every bucket the index actually built.
    @Test func memberQueryByNodeFindsEveryBucket() throws {
        let storage = try storage
        var checkedBucketCount = 0
        for (memberKind, memberRows) in storage.memberSymbolRowsByKind {
            for (typeName, rowsByTypeNodeIndex) in memberRows {
                for (typeNodeIndex, expectedRows) in rowsByTypeNodeIndex {
                    let externalNode = storage.nodeStore.reference(at: typeNodeIndex).materialize()
                    let queried = SymbolIndexStore.shared.memberSymbols(of: memberKind, for: typeName, node: externalNode, in: machOFile)
                    #expect(queried.count == expectedRows.count, "bucket \(memberKind) / \(typeName)")
                    checkedBucketCount += 1
                }
            }
        }
        #expect(checkedBucketCount > 0)
    }

    @Test func symbolKindQueriesMatchStorageBuckets() throws {
        let storage = try storage
        #expect(!storage.symbolRowsByKind.isEmpty)
        for (kind, expectedRows) in storage.symbolRowsByKind {
            let queried = SymbolIndexStore.shared.symbols(of: kind, in: machOFile)
            #expect(queried.count == expectedRows.count)
            #expect(queried.allSatisfy { $0.demangledNode.children.first?.kind == kind })
        }
    }

    @Test func typeInfoLookupMatchesIndexedNames() throws {
        let storage = try storage
        #expect(!storage.typeInfoByName.isEmpty)
        for (typeName, typeInfoByTypeNodeIndex) in storage.typeInfoByName {
            // Name-only lookup answers first-wins across the (rare)
            // same-named private types sharing the stripped name bucket.
            let queriedByNameOnly = try #require(SymbolIndexStore.shared.typeInfo(for: typeName, in: machOFile))
            #expect(queriedByNameOnly.name == typeInfoByTypeNodeIndex.values.first?.name)
            // The node-matched overload resolves each context node's own
            // entry (issue #115's family).
            for (typeNodeIndex, expectedTypeInfo) in typeInfoByTypeNodeIndex {
                let keyReference = storage.nodeStore.reference(at: typeNodeIndex)
                let queried = try #require(SymbolIndexStore.shared.typeInfo(for: typeName, node: keyReference, in: machOFile))
                #expect(queried.name == expectedTypeInfo.name)
                #expect(queried.kind == expectedTypeInfo.kind)
            }
        }
    }

    @Test func opaqueDescriptorQueryFindsEveryReferenceKey() throws {
        let storage = try storage
        for (nodeIndex, expectedRow) in storage.opaqueTypeDescriptorSymbolRowByNodeIndex {
            let keyReference = storage.nodeStore.reference(at: nodeIndex)
            let queried = try #require(SymbolIndexStore.shared.opaqueTypeDescriptorSymbol(for: keyReference.materialize(), in: machOFile))
            #expect(queried.symbol == storage.symbolTable.symbol(atRow: expectedRow))
        }
    }

    /// The BULK opaque query must be probable the same way the single-item one
    /// is: with a tree the caller demangled itself.
    ///
    /// Its keys are references into this image's frozen arena, so under a bare
    /// `NodeReference` key — store-identity `==` and `hash` — every such probe
    /// missed, silently and with no compile error. That is the same failure that
    /// dropped `override` keywords and vtable-offset comments in the Stage 5a
    /// regression, which is why the single-item `opaqueTypeDescriptorSymbol(for:)`
    /// next door was converted to a structural key; this form was left behind.
    /// (Before the fix this test could not even be written: the API had no way
    /// to express a lookup by a caller-side tree.)
    @Test func bulkOpaqueQueryIsProbableWithACallerDemangledTree() throws {
        let storage = try storage
        let bulkSymbols = try #require(SymbolIndexStore.shared.allOpaqueTypeDescriptorSymbols(in: machOFile))
        try #require(!bulkSymbols.isEmpty, "fixture must carry opaque type descriptors for this test to be meaningful")

        for (nodeIndex, expectedRow) in storage.opaqueTypeDescriptorSymbolRowByNodeIndex {
            // `materialize()` mints a fresh tree that belongs to no store — the
            // same position any external caller is in.
            let callerSideTree = storage.nodeStore.reference(at: nodeIndex).materialize()
            let probed = try #require(
                bulkSymbols[StructuralNodeReferenceKey(querying: callerSideTree)],
                "a caller-demangled tree must find its entry in the bulk result"
            )
            #expect(probed.symbol == storage.symbolTable.symbol(atRow: expectedRow))
        }
    }

    // MARK: - demangledNode / demangledNodeReference

    @Test func demangledNodeAndReferenceAgree() throws {
        let storage = try storage
        var checkedCount = 0
        for row in 0 ..< storage.symbolTable.rowCount {
            guard checkedCount < 200 else { break }
            guard let rootNodeIndex = storage.rootNodeIndexByTableRow[row] else { continue }
            let symbol = storage.symbolTable.symbol(atRow: UInt32(row))
            let reference = storage.nodeStore.reference(at: rootNodeIndex)
            let materialized = try #require(SymbolIndexStore.shared.demangledNode(for: symbol, in: machOFile))
            #expect(reference.structurallyEquals(materialized))
            let referenceAgain = try #require(SymbolIndexStore.shared.demangledNodeReference(for: symbol, in: machOFile))
            #expect(referenceAgain == reference)
            checkedCount += 1
        }
        #expect(checkedCount > 0)
    }

    /// Symbols outside the build sweep fall back to a per-symbol mini store:
    /// the returned reference prints identically to the classic pipeline and
    /// repeat lookups hit the late cache (same store identity).
    @Test func lateSymbolFallsBackToMiniStore() throws {
        _ = try storage

        let lateSymbol = Symbol(offset: -1, name: "$s7SwiftUI4ViewP")
        let reference = try #require(SymbolIndexStore.shared.demangledNodeReference(for: lateSymbol, in: machOFile))
        let expected = try demangleAsNode(lateSymbol.name, internsSubtrees: false).print(using: .default)
        #expect(reference.print(using: .default) == expected)

        let referenceAgain = try #require(SymbolIndexStore.shared.demangledNodeReference(for: lateSymbol, in: machOFile))
        #expect(referenceAgain == reference)

        let materialized = try #require(SymbolIndexStore.shared.demangledNode(for: lateSymbol, in: machOFile))
        #expect(reference.structurallyEquals(materialized))
    }

    /// A late name the demangler rejects caches its rejection: the verdict
    /// slot exists and holds `nil`, so repeat queries answer from the cache
    /// instead of re-paying the demangle (previously every query on a
    /// rejected name re-entered the demangler).
    @Test func rejectedLateNameCachesItsFailure() throws {
        let storage = try storage
        let bogusSymbol = Symbol(offset: -1, name: "$s999999999999")
        #expect(storage.symbolTable.row(forName: bogusSymbol.name) == nil)

        #expect(SymbolIndexStore.shared.demangledNodeReference(for: bogusSymbol, in: machOFile) == nil)
        let verdict = try #require(storage.lateDemangleVerdictForTesting(forName: bogusSymbol.name))
        #expect(verdict == nil)

        #expect(SymbolIndexStore.shared.demangledNodeReference(for: bogusSymbol, in: machOFile) == nil)
    }

    /// A name the build sweep covered answers from the table verdict — hit
    /// or rejection — without ever minting a late mini store. Guarded via
    /// the late cache: now that rejections are cached too, a regression that
    /// re-routes table-covered names through the late path would leave a
    /// verdict slot behind and fail this test.
    @Test func tableCoveredNameNeverEntersLateCache() throws {
        let storage = try storage

        let demangledRow = try #require(storage.rootNodeIndexByTableRow.firstIndex(where: { $0 != nil }))
        let demangledSymbol = storage.symbolTable.symbol(atRow: UInt32(demangledRow))
        _ = try #require(SymbolIndexStore.shared.demangledNodeReference(for: demangledSymbol, in: machOFile))
        #expect(storage.lateDemangleVerdictForTesting(forName: demangledSymbol.name) == nil)

        if let rejectedRow = storage.rootNodeIndexByTableRow.firstIndex(where: { $0 == nil }) {
            let rejectedSymbol = storage.symbolTable.symbol(atRow: UInt32(rejectedRow))
            #expect(SymbolIndexStore.shared.demangledNodeReference(for: rejectedSymbol, in: machOFile) == nil)
            #expect(storage.lateDemangleVerdictForTesting(forName: rejectedSymbol.name) == nil)
        }
    }

    /// Concurrent first-time queries for one late name must agree on a single
    /// store: insert-if-absent hands every caller the winner's reference
    /// (store-identity `==`), never references into different mini stores.
    /// This pins the one-store-per-name guarantee the former
    /// demangle-inside-the-lock design existed for, now that the demangle
    /// runs outside the critical section.
    @Test func concurrentLateQueriesShareOneStore() async throws {
        _ = try storage

        let lateSymbol = Symbol(offset: -1, name: "$s7SwiftUI4TextV")
        let references = await withTaskGroup(of: NodeReference?.self) { group in
            for _ in 0 ..< 16 {
                group.addTask { [machOFile] in
                    SymbolIndexStore.shared.demangledNodeReference(for: lateSymbol, in: machOFile)
                }
            }
            var collected: [NodeReference?] = []
            for await reference in group {
                collected.append(reference)
            }
            return collected
        }

        let winner = try #require(references.first ?? nil)
        for reference in references {
            #expect(reference == winner)
        }
    }
}
