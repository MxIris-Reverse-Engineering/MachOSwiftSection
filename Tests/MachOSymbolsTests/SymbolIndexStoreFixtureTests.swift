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

    /// The migration's core invariant: the build pipeline stays off the
    /// global `NodeCache` (the old pipeline leaked every leaf and interned
    /// subtree into it, pinning them for the process lifetime).
    ///
    /// Asserted via leaf identity rather than global counters: every test
    /// target shares one process, so concurrent suites legitimately grow
    /// `NodeCache` and make counter deltas racy. The transient demangle the
    /// build sweep uses mints fresh leaf instances on every call, whereas
    /// any accidental cache participation would hand back the same canonical
    /// instance — so `!==` across two runs is deterministic evidence.
    /// (The process-global zero-growth measurement lives in the manually run
    /// `SymbolIndexStoreBaselineTests`.)
    @Test func buildPipelineStaysOffGlobalNodeCache() throws {
        let builtStorage = try #require(SymbolIndexStore.shared.buildStorage(for: machOFile))
        #expect(!builtStorage.symbolTable.isEmpty)

        let sampleRow = try #require(builtStorage.rootNodeIndexByTableRow.firstIndex(where: { $0 != nil }))
        let sampleSymbolName = builtStorage.symbolTable[sampleRow].name
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
        for (row, symbol) in storage.symbolTable.enumerated() {
            guard let rootNodeIndex = storage.rootNodeIndexByTableRow[row] else { continue }
            let reference = storage.nodeStore.reference(at: rootNodeIndex)
            let expected = try demangleAsNode(symbol.name, internsSubtrees: false).print(using: .default)
            if reference.print(using: .default) != expected {
                mismatchCount += 1
                if mismatchCount <= 3 {
                    Issue.record("Store print mismatch for \(symbol.name)")
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
    }

    /// Raw and cache-adjusted offset keys share one canonical table row, so
    /// `symbols(for:in:)` must rebuild each `Symbol` with the queried offset
    /// (matching the old per-offset-copy behavior byte for byte).
    @Test func offsetQueriesRebuildSymbolsWithQueriedOffset() throws {
        let storage = try storage
        #expect(!storage.symbolRowsByOffset.isEmpty)
        var checkedOffsetCount = 0
        for (offset, rows) in storage.symbolRowsByOffset {
            guard checkedOffsetCount < 500 else { break }
            let queried = try #require(SymbolIndexStore.shared.symbols(for: offset, in: machOFile))
            #expect(queried.count == rows.count)
            #expect(queried.allSatisfy { $0.offset == offset })
            for (queriedSymbol, row) in zip(queried, rows) {
                #expect(queriedSymbol.name == storage.symbolTable[Int(row)].name)
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
        for (typeName, expectedTypeInfo) in storage.typeInfoByName {
            let queried = try #require(SymbolIndexStore.shared.typeInfo(for: typeName, in: machOFile))
            #expect(queried.name == expectedTypeInfo.name)
        }
    }

    @Test func opaqueDescriptorQueryFindsEveryReferenceKey() throws {
        let storage = try storage
        for (nodeIndex, expectedRow) in storage.opaqueTypeDescriptorSymbolRowByNodeIndex {
            let keyReference = storage.nodeStore.reference(at: nodeIndex)
            let queried = try #require(SymbolIndexStore.shared.opaqueTypeDescriptorSymbol(for: keyReference.materialize(), in: machOFile))
            #expect(queried.symbol == storage.symbolTable[Int(expectedRow)])
        }
    }

    // MARK: - demangledNode / demangledNodeReference

    @Test func demangledNodeAndReferenceAgree() throws {
        let storage = try storage
        var checkedCount = 0
        for (row, symbol) in storage.symbolTable.enumerated() {
            guard checkedCount < 200 else { break }
            guard let rootNodeIndex = storage.rootNodeIndexByTableRow[row] else { continue }
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
}
