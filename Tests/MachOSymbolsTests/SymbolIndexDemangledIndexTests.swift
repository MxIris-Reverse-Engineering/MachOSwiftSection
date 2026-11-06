import Foundation
import Testing
import MachOResolving
@_spi(Internals) import Demangling
@_spi(Internals) @testable import MachOSymbols
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Pins when a symbol index demangles its names (evolution proposal
/// `machofile-performance`): the storage's first stage — the symbol table,
/// the offset index, the symbolic-mangling table and the export facts —
/// demangles nothing, and the demangled index is built on the first query
/// that needs a tree, once, however many threads ask at the same time.
///
/// The layout engine names a dependency image's private types through the
/// symbol on each anonymous context descriptor. When looking that symbol up
/// demangled the whole image, laying out SwiftUI spent 7.7 of its 27.8
/// seconds demangling every name of every dependency it named a type in.
///
/// Each test builds a storage of its own outside the cache, so no other
/// suite's queries can have built its demangled index already.
@Suite
final class SymbolIndexDemangledIndexTests: MachOFileTests, @unchecked Sendable {
    override class var fileName: MachOFileName { .SymbolTestsCore }

    @Test func offsetLookupsLeaveTheNamesUndemangled() throws {
        let storage = try #require(SymbolIndexStore.shared.buildStorageWithoutDemangledIndexForTesting(for: machOFile))
        let (offset, rows) = try #require(storage.symbolRowsByOffset.first)
        #expect(!rows.isEmpty)
        #expect(storage.symbolTable.rowCount > 0)
        #expect(storage.isExported(name: storage.symbolTable.materializedName(atRow: 0)) != nil)
        _ = storage.symbolicManglingSymbolTable.rowCount
        _ = storage.hasLocalSwiftSymbols
        _ = offset
        #expect(!storage.hasBuiltDemangledIndex)

        // The first query that needs a tree builds the index.
        _ = storage.demangledSymbols(atRows: rows)
        #expect(storage.hasBuiltDemangledIndex)
    }

    /// The index built on demand holds what a full build holds: the same
    /// rows demangle to the same trees.
    @Test func theIndexBuiltOnDemandMatchesAFullBuild() throws {
        let onDemandStorage = try #require(SymbolIndexStore.shared.buildStorageWithoutDemangledIndexForTesting(for: machOFile))
        let fullStorage = try #require(SymbolIndexStore.shared.buildStorage(for: machOFile))
        #expect(fullStorage.hasBuiltDemangledIndex)
        #expect(onDemandStorage.symbolTable.rowCount == fullStorage.symbolTable.rowCount)

        let onDemandIndex = onDemandStorage.demangledIndex
        let fullIndex = fullStorage.demangledIndex
        #expect(onDemandIndex.rootNodeIndexByTableRow.count == fullIndex.rootNodeIndexByTableRow.count)
        var comparedTreeCount = 0
        for row in 0 ..< onDemandIndex.rootNodeIndexByTableRow.count {
            switch (onDemandIndex.rootNodeIndexByTableRow[row], fullIndex.rootNodeIndexByTableRow[row]) {
            case (nil, nil):
                continue
            case (let onDemandRootNodeIndex?, let fullRootNodeIndex?):
                let onDemandTree = onDemandIndex.nodeStore.reference(at: onDemandRootNodeIndex)
                let fullTree = fullIndex.nodeStore.reference(at: fullRootNodeIndex)
                #expect(onDemandTree.structurallyEquals(fullTree))
                comparedTreeCount += 1
            default:
                Issue.record("row \(row) demangled in one build and not in the other")
            }
        }
        #expect(comparedTreeCount > 0)
        #expect(Array(onDemandIndex.symbolRowsByKind.keys) == Array(fullIndex.symbolRowsByKind.keys))
        #expect(Array(onDemandIndex.memberSymbolRowsByKind.keys) == Array(fullIndex.memberSymbolRowsByKind.keys))
    }

    /// The sweep demangles a wave of rows ahead on several threads at once
    /// and interns each wave in row order (`DemanglingWave`). Every row must
    /// still hold the tree its own name demangles to, and a name the
    /// demangler rejects none — across a wave boundary, and through the
    /// last, partial wave.
    @Test func everyRowHoldsTheTreeOfItsOwnName() throws {
        let storage = try #require(SymbolIndexStore.shared.buildStorageWithoutDemangledIndexForTesting(for: machOFile))
        let symbolTable = storage.symbolTable
        #expect(symbolTable.rowCount > DemanglingWave.size)
        #expect(symbolTable.rowCount % DemanglingWave.size != 0)

        let index = storage.demangledIndex
        #expect(index.rootNodeIndexByTableRow.count == symbolTable.rowCount)
        var comparedTreeCount = 0
        var mismatchedRows: [Int] = []
        for row in 0 ..< symbolTable.rowCount {
            let expectedTree = try? demangleAsNodeTransient(symbolTable.materializedName(atRow: UInt32(row)))
            switch (index.rootNodeIndexByTableRow[row], expectedTree) {
            case (nil, nil):
                continue
            case (let rootNodeIndex?, let expectedTree?):
                if index.nodeStore.reference(at: rootNodeIndex).structurallyEquals(expectedTree) {
                    comparedTreeCount += 1
                } else {
                    mismatchedRows.append(row)
                }
            default:
                mismatchedRows.append(row)
            }
        }
        #expect(comparedTreeCount > DemanglingWave.size)
        #expect(mismatchedRows.isEmpty, "rows whose tree is not their own name's: \(mismatchedRows.prefix(20))")
    }

    /// Threads asking for the index at once wait for one build and all get
    /// it. Each asks from a thread of its own, so a blocked asker never holds
    /// a cooperative pool thread the build might need.
    @Test func concurrentFirstReadersShareOneBuild() async throws {
        let storage = try #require(SymbolIndexStore.shared.buildStorageWithoutDemangledIndexForTesting(for: machOFile))
        let askerCount = 8
        let indexes = await withCheckedContinuation { (continuation: CheckedContinuation<[ObjectIdentifier], Never>) in
            let collected = Collected()
            for _ in 0 ..< askerCount {
                Thread {
                    let identifier = ObjectIdentifier(storage.demangledIndex)
                    if let all = collected.append(identifier, expecting: askerCount) {
                        continuation.resume(returning: all)
                    }
                }.start()
            }
        }
        #expect(indexes.count == askerCount)
        #expect(Set(indexes).count == 1)
    }

    private final class Collected: @unchecked Sendable {
        private let lock = NSLock()
        private var identifiers: [ObjectIdentifier] = []

        /// Appends `identifier`; returns every identifier once the expected
        /// number has arrived, `nil` before that.
        func append(_ identifier: ObjectIdentifier, expecting expectedCount: Int) -> [ObjectIdentifier]? {
            lock.lock()
            defer { lock.unlock() }
            identifiers.append(identifier)
            return identifiers.count == expectedCount ? identifiers : nil
        }
    }
}
