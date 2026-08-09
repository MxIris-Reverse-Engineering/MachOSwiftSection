@_spi(Support) @testable import SwiftIndexing
import Foundation
import Testing
import MachOKit
import Dependencies
@_spi(Internals) import MachOSymbols
@_spi(Internals) import MachOCaches
@testable import MachOTestingSupport
import MachOFixtureSupport
@_spi(Internals) @testable import SwiftInspection

/// The indexer's `deinit` cleans up three per-image caches (symbol store,
/// interned-name store, demangle memo). That cleanup must be performed by
/// the image's LAST live indexer — an earlier indexer deinitializing while
/// a second one still uses the same image must not wipe the caches out from
/// under it (the survivor's already-built names would keep an orphaned
/// store alive while new names land in a fresh one, splitting the
/// `store ===` fast paths for the rest of its lifetime). PR #103 review,
/// finding M6.
///
/// Runs against `SymbolTestsHelper` — an image no other suite indexes — so
/// the cache-membership assertions cannot race a concurrently-running
/// suite's indexer lifecycle.
@Suite(.serialized)
final class PerImageCacheEvictionTests: MachOFileTests, @unchecked Sendable {
    override class var fileName: MachOFileName { .SymbolTestsHelper }

    @Test func survivingIndexerKeepsPerImageCaches() async throws {
        let unsafeMachOFile = machOFile

        var firstIndexer: SwiftDeclarationIndexer<MachOFile>? = SwiftDeclarationIndexer(in: unsafeMachOFile)
        try await firstIndexer?.prepare()
        let secondIndexer = SwiftDeclarationIndexer(in: unsafeMachOFile)
        try await secondIndexer.prepare()

        try #require(SymbolIndexStore.shared.contains(in: unsafeMachOFile))
        let internedNameCacheWasPresent = InternedNodeReferenceCache.shared.contains(in: unsafeMachOFile)
        let demangleMemoWasPresent = MetadataReader.cacheExists(for: unsafeMachOFile)

        // The first indexer populated the caches, so under a per-indexer
        // ownership flag its deinit would evict all three out from under
        // the still-live second indexer.
        firstIndexer = nil

        #expect(
            SymbolIndexStore.shared.contains(in: unsafeMachOFile),
            "the first indexer's deinit evicted the symbol store while a second live indexer was using the image"
        )
        #expect(InternedNodeReferenceCache.shared.contains(in: unsafeMachOFile) == internedNameCacheWasPresent)
        #expect(MetadataReader.cacheExists(for: unsafeMachOFile) == demangleMemoWasPresent)

        withExtendedLifetime(secondIndexer) {}
    }

    @Test func lastIndexerEvictsPerImageCaches() async throws {
        let unsafeMachOFile = machOFile

        var firstIndexer: SwiftDeclarationIndexer<MachOFile>? = SwiftDeclarationIndexer(in: unsafeMachOFile)
        try await firstIndexer?.prepare()
        var secondIndexer: SwiftDeclarationIndexer<MachOFile>? = SwiftDeclarationIndexer(in: unsafeMachOFile)
        try await secondIndexer?.prepare()
        try #require(SymbolIndexStore.shared.contains(in: unsafeMachOFile))

        firstIndexer = nil
        secondIndexer = nil

        #expect(
            !SymbolIndexStore.shared.contains(in: unsafeMachOFile),
            "the image's LAST live indexer must still perform the eviction — otherwise the per-image caches leak for the rest of the process lifetime"
        )
        #expect(!InternedNodeReferenceCache.shared.contains(in: unsafeMachOFile))
        #expect(!MetadataReader.cacheExists(for: unsafeMachOFile))
    }
}
