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
@_spi(Internals) import Demangling
@testable import MachOSwiftSection

/// The indexer's `deinit` cleans up three per-image caches (symbol store,
/// interned-name store, demangle memo). Two rules govern that cleanup:
///
/// 1. It is performed by the image's **LAST** live indexer — an earlier
///    indexer deinitializing while a second one still uses the same image must
///    not wipe the caches out from under it (the survivor's already-built names
///    would keep an orphaned store alive while new names land in a fresh one,
///    splitting the `store ===` fast paths for the rest of its lifetime).
///    PR #103 review, finding M6.
/// 2. Each cache is claimed **separately**. The symbol store is the only one an
///    indexer necessarily builds; the interned-name store and the demangle memo
///    are also populated by SwiftLayout, `SwiftDeclarationRendering` and
///    `SwiftSpecialization`. A single combined claim sampled from the symbol
///    store alone evicted caches that non-indexer work had built and was still
///    using — the follow-up round of the same finding.
///
/// Runs against `SymbolTestsHelper` under `ExclusiveImageAccess`, which
/// serializes every suite declaring that image — including ones in other test
/// targets. The prose this replaces claimed the image was one "no other suite
/// indexes", which was false: `SwiftLayoutTests.DependencyClosureLayoutTests`
/// resolves through the same binary, reaching it by a hand-built path rather
/// than through `MachOFileName`, so searching for the fixture case could not
/// find it. Without the exclusion these assertions race that suite's indexing —
/// in both directions, since clearing the caches here splits an interned store
/// it is reading mid-resolution.
///
/// `.serialized` on top of that is still needed, but for a different reason: it
/// orders tests *within* this suite, so a previous test's residue does not
/// decide the claims under test. It does nothing across suites — its own
/// documentation says it "does not affect the execution of a test relative to
/// its peers or to unrelated tests".
@Suite(.serialized, ExclusiveImageAccess(.SymbolTestsHelper))
final class PerImageCacheEvictionTests: MachOFileTests, @unchecked Sendable {
    override class var fileName: MachOFileName { .SymbolTestsHelper }

    private func clearAllPerImageCaches(for machOFile: MachOFile) {
        @Dependency(\.symbolIndexStore)
        var symbolIndexStore
        symbolIndexStore.remove(for: machOFile)
        InternedNodeReferenceCache.shared.remove(for: machOFile)
        MetadataReader.removeCache(for: machOFile)
    }

    /// Populates the interned-name store and the demangle memo the way a
    /// NON-indexer consumer does (SwiftLayout and the renderers reach
    /// `MetadataReader` directly), deliberately leaving the symbol store
    /// untouched.
    @discardableResult
    private func populateNonIndexerCaches(for machOFile: MachOFile) throws -> Bool {
        let typeDescriptor = try #require(try machOFile.swift.typeContextDescriptors.first)
        let typeNode = try MetadataReader.demangleContext(for: .type(typeDescriptor), in: machOFile)
        _ = InternedNodeReferenceCache.shared.reference(interning: typeNode, in: machOFile)
        return true
    }

    @Test func survivingIndexerKeepsPerImageCaches() async throws {
        let unsafeMachOFile = machOFile
        clearAllPerImageCaches(for: unsafeMachOFile)

        var firstIndexer: SwiftDeclarationIndexer<MachOFile>? = SwiftDeclarationIndexer(in: unsafeMachOFile)
        try await firstIndexer?.prepare()
        let secondIndexer = SwiftDeclarationIndexer(in: unsafeMachOFile)
        try await secondIndexer.prepare()

        // All three must genuinely be populated, or the survivor assertions
        // below degrade to `false == false` and pin nothing.
        try #require(SymbolIndexStore.shared.contains(in: unsafeMachOFile))
        try #require(InternedNodeReferenceCache.shared.contains(in: unsafeMachOFile))
        try #require(MetadataReader.cacheExists(for: unsafeMachOFile))

        // The first indexer populated the caches, so under a per-indexer
        // ownership flag its deinit would evict all three out from under
        // the still-live second indexer.
        firstIndexer = nil

        #expect(
            SymbolIndexStore.shared.contains(in: unsafeMachOFile),
            "the first indexer's deinit evicted the symbol store while a second live indexer was using the image"
        )
        #expect(
            InternedNodeReferenceCache.shared.contains(in: unsafeMachOFile),
            "the first indexer's deinit evicted the interned-name store while a second live indexer was using the image"
        )
        #expect(
            MetadataReader.cacheExists(for: unsafeMachOFile),
            "the first indexer's deinit evicted the demangle memo while a second live indexer was using the image"
        )

        withExtendedLifetime(secondIndexer) {}
    }

    @Test func lastIndexerEvictsPerImageCaches() async throws {
        let unsafeMachOFile = machOFile
        clearAllPerImageCaches(for: unsafeMachOFile)

        var firstIndexer: SwiftDeclarationIndexer<MachOFile>? = SwiftDeclarationIndexer(in: unsafeMachOFile)
        try await firstIndexer?.prepare()
        var secondIndexer: SwiftDeclarationIndexer<MachOFile>? = SwiftDeclarationIndexer(in: unsafeMachOFile)
        try await secondIndexer?.prepare()

        try #require(SymbolIndexStore.shared.contains(in: unsafeMachOFile))
        try #require(InternedNodeReferenceCache.shared.contains(in: unsafeMachOFile))
        try #require(MetadataReader.cacheExists(for: unsafeMachOFile))

        firstIndexer = nil
        secondIndexer = nil

        #expect(
            !SymbolIndexStore.shared.contains(in: unsafeMachOFile),
            "the image's LAST live indexer must still perform the eviction — otherwise the per-image caches leak for the rest of the process lifetime"
        )
        #expect(!InternedNodeReferenceCache.shared.contains(in: unsafeMachOFile))
        #expect(!MetadataReader.cacheExists(for: unsafeMachOFile))
    }

    /// Caches an indexer did NOT build must survive its deinit.
    ///
    /// The realistic sequence this reproduces: a host does static layout work
    /// or a dump over an image (populating the interned-name store and the
    /// demangle memo through `MetadataReader`, never touching the symbol
    /// store), then separately creates and destroys an indexer for the same
    /// image. Sampling one combined claim from the symbol store alone answers
    /// "nobody had this, so I claim it" for all three, and the indexer's deinit
    /// then wipes two caches the still-live non-indexer work is using: names
    /// minted before the wipe stay in the dropped arena via their live
    /// `NodeReference`s while later names land in a fresh one, so the
    /// documented `store ===` fast path stops firing permanently.
    @Test func indexerDoesNotEvictCachesItDidNotBuild() async throws {
        let unsafeMachOFile = machOFile
        clearAllPerImageCaches(for: unsafeMachOFile)

        try populateNonIndexerCaches(for: unsafeMachOFile)

        // The precondition that makes this test meaningful: the two caches are
        // populated, the symbol store is not — exactly the state a combined
        // claim reads backwards.
        try #require(InternedNodeReferenceCache.shared.contains(in: unsafeMachOFile))
        try #require(MetadataReader.cacheExists(for: unsafeMachOFile))
        try #require(!SymbolIndexStore.shared.contains(in: unsafeMachOFile))

        var indexer: SwiftDeclarationIndexer<MachOFile>? = SwiftDeclarationIndexer(in: unsafeMachOFile)
        try await indexer?.prepare()
        indexer = nil

        #expect(
            InternedNodeReferenceCache.shared.contains(in: unsafeMachOFile),
            "the indexer evicted an interned-name store that non-indexer work had built and may still be using"
        )
        #expect(
            MetadataReader.cacheExists(for: unsafeMachOFile),
            "the indexer evicted a demangle memo that non-indexer work had built and may still be using"
        )
        // The symbol store IS the indexer's to reclaim: it built that one.
        #expect(
            !SymbolIndexStore.shared.contains(in: unsafeMachOFile),
            "the symbol store the indexer built must still be reclaimed"
        )
    }
}
