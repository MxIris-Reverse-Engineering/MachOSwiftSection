import Foundation
import Testing
import MachO
import Demangling
@_spi(Internals) @testable import MachOSymbols
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Stage 0 of the NodeStore migration plan: capture per-image baseline
/// metrics for `SymbolIndexStore.buildStorage` so Stage 1/4 can compare
/// like-for-like. Run this suite alone (`--filter SymbolIndexStoreBaselineTests`)
/// so no other test warms the global `NodeCache` or demangles symbols first.
@Suite
final class SymbolIndexStoreBaselineTests: MachOImageTests {
    override class var imageName: MachOImageName {
        .SwiftUI
    }

    @Test func baselineMetrics() async throws {
        let footprintBefore = ProcessMemory.value(of: .physicalFootprint)
        let leafCacheCountBefore = NodeCache.shared.count
        let subtreeCacheCountBefore = NodeCache.shared.subtreeCount

        let clock = ContinuousClock()
        var builtStorage: SymbolIndexStore.Storage?
        let buildDuration = clock.measure {
            builtStorage = SymbolIndexStore.shared.buildStorage(for: machOImage)
        }
        let footprintAfter = ProcessMemory.value(of: .physicalFootprint)
        let leafCacheCountAfter = NodeCache.shared.count
        let subtreeCacheCountAfter = NodeCache.shared.subtreeCount

        // Scope the strong reference so the release measurement below really
        // drops the storage.
        do {
        let storage = try #require(builtStorage)

        let demangledSymbolCount = storage.demangledNodeBySymbol.count
        let symbolsByKindEntryCount = storage.symbolsByKind.values.reduce(0) { $0 + $1.count }
        let memberEntryCount = storage.memberSymbolsByKind.values.reduce(0) { partialResult, memberSymbols in
            partialResult + memberSymbols.values.reduce(0) { $0 + $1.values.reduce(0) { $0 + $1.count } }
        }
        let methodDescriptorEntryCount = storage.methodDescriptorMemberSymbolsByKind.values.reduce(0) { partialResult, memberSymbols in
            partialResult + memberSymbols.values.reduce(0) { $0 + $1.values.reduce(0) { $0 + $1.count } }
        }
        let protocolWitnessEntryCount = storage.protocolWitnessMemberSymbolsByKind.values.reduce(0) { partialResult, memberSymbols in
            partialResult + memberSymbols.values.reduce(0) { $0 + $1.values.reduce(0) { $0 + $1.count } }
        }
        let globalEntryCount = storage.globalSymbolsByKind.values.reduce(0) { $0 + $1.count }

        let nodeStoreBytes = storage.nodeStore.storageByteCount
        let nodeStoreNodeCount = storage.nodeStore.nodeCount

        print("====== NodeStore migration Stage 0 baseline (\(Self.imageName)) ======")
        print("build time                         : \(buildDuration)")
        print("phys_footprint delta               : \((footprintAfter - footprintBefore) / 1_048_576) MB (\(footprintBefore / 1_048_576) -> \(footprintAfter / 1_048_576))")
        print("NodeCache leaf delta               : \(leafCacheCountAfter - leafCacheCountBefore) (\(leafCacheCountBefore) -> \(leafCacheCountAfter))")
        print("NodeCache subtree delta            : \(subtreeCacheCountAfter - subtreeCacheCountBefore) (\(subtreeCacheCountBefore) -> \(subtreeCacheCountAfter))")
        print("nodeStore storage                  : \(nodeStoreBytes / 1_048_576) MB (\(nodeStoreNodeCount) unique nodes)")
        print("demangledNodeBySymbol entries      : \(demangledSymbolCount)")
        print("symbolsByKind entries              : \(symbolsByKindEntryCount)")
        print("memberSymbols entries              : \(memberEntryCount)")
        print("methodDescriptorMember entries     : \(methodDescriptorEntryCount)")
        print("protocolWitnessMember entries      : \(protocolWitnessEntryCount)")
        print("globalSymbols entries              : \(globalEntryCount)")
        print("symbolsByOffset entries            : \(storage.symbolsByOffset.count)")
        print("opaqueTypeDescriptor entries       : \(storage.opaqueTypeDescriptorSymbolByNode.count)")
        print("typeInfoByName entries             : \(storage.typeInfoByName.count)")
        print("=====================================================================")

        #expect(demangledSymbolCount > 0)
        }

        // Reclaim check: the migration's headline property is that dropping a
        // Storage releases the whole per-image footprint (the old pipeline
        // pinned every canonical subtree in the process-global NodeCache
        // forever). Measure how far the footprint falls once the storage is
        // gone and the allocator is asked to return clean pages.
        builtStorage = nil
        malloc_zone_pressure_relief(nil, 0)
        let footprintAfterRelease = ProcessMemory.value(of: .physicalFootprint)
        print("phys_footprint after release       : \(footprintAfterRelease / 1_048_576) MB (reclaimed \((footprintAfter - min(footprintAfter, footprintAfterRelease)) / 1_048_576) MB of \((footprintAfter - footprintBefore) / 1_048_576) MB delta)")
    }
}
