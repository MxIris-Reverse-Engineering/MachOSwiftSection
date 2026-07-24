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
/// building, byte-identical printing versus the `Node` pipeline, and the
/// `structurallyEquals` bridge behind every `Node`-taking query API.
///
/// Serialized: the NodeCache-growth test snapshots process-global counters,
/// and several tests share the cached per-file storage.
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
        #expect(!builtStorage.demangledNodeBySymbol.isEmpty)

        let sampleSymbolName = try #require(builtStorage.demangledNodeBySymbol.keys.first?.name)
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
        var mismatchCount = 0
        for (symbol, reference) in storage.demangledNodeBySymbol {
            let expected = try demangleAsNode(symbol.name, internsSubtrees: false).print(using: .default)
            if reference.print(using: .default) != expected {
                mismatchCount += 1
                if mismatchCount <= 3 {
                    Issue.record("Store print mismatch for \(symbol.name)")
                }
            }
        }
        #expect(mismatchCount == 0)
        #expect(!storage.demangledNodeBySymbol.isEmpty)
    }

    // MARK: - Query APIs

    /// `memberSymbols(of:for:node:)` takes an externally demangled `Node` and
    /// must find the `NodeReference`-keyed bucket via `structurallyEquals`.
    /// Exercise it for every bucket the index actually built.
    @Test func memberQueryByNodeFindsEveryBucket() throws {
        let storage = try storage
        var checkedBucketCount = 0
        for (memberKind, memberSymbols) in storage.memberSymbolsByKind {
            for (typeName, symbolsByTypeNode) in memberSymbols {
                for (typeNodeReference, expectedSymbols) in symbolsByTypeNode {
                    let externalNode = typeNodeReference.materialize()
                    let queried = SymbolIndexStore.shared.memberSymbols(of: memberKind, for: typeName, node: externalNode, in: machOFile)
                    #expect(queried.count == expectedSymbols.count, "bucket \(memberKind) / \(typeName)")
                    checkedBucketCount += 1
                }
            }
        }
        #expect(checkedBucketCount > 0)
    }

    @Test func symbolKindQueriesMatchStorageBuckets() throws {
        let storage = try storage
        #expect(!storage.symbolsByKind.isEmpty)
        for (kind, expectedSymbols) in storage.symbolsByKind {
            let queried = SymbolIndexStore.shared.symbols(of: kind, in: machOFile)
            #expect(queried.count == expectedSymbols.count)
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
        for (keyReference, expectedSymbol) in storage.opaqueTypeDescriptorSymbolByNode {
            let queried = try #require(SymbolIndexStore.shared.opaqueTypeDescriptorSymbol(for: keyReference.materialize(), in: machOFile))
            #expect(queried.symbol == expectedSymbol.symbol)
        }
    }

    // MARK: - demangledNode / demangledNodeReference

    @Test func demangledNodeAndReferenceAgree() throws {
        let storage = try storage
        var checkedCount = 0
        for (symbol, reference) in storage.demangledNodeBySymbol {
            guard checkedCount < 200 else { break }
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
