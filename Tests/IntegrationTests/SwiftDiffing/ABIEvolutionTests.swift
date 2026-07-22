import Foundation
import Testing
import SwiftDeclarationRendering
import MachOKit
import MachOExtensions
import MachOFixtureSupport
import MachOTestingSupport
@testable import MachOSwiftSection
@testable import SwiftInterface
@_spi(Support) @testable import SwiftIndexing
import SwiftDiffing

/// The N-version analogue of ``SwiftDiffableInterfaceBuilderTests``.
///
/// Where the diffable-interface tests index a *pair* of binaries and diff
/// them, these index an *ordered series* of versions of one module, freeze
/// each into an `ABISnapshotDocument` (round-tripping through the persisted
/// JSON form so the codec and the format-version gate run on real-world
/// data), and run the series through `ABIEvolutionBuilder` +
/// `ABIEvolutionReporter` — the `swift-section evolution` pipeline. Like its
/// siblings it is a maintainer-inspection dump: it prints / writes results
/// without assertions.
protocol ABIEvolutionDumpTests: SwiftInterfaceDumpTests {}

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension ABIEvolutionDumpTests {
    var indexConfiguration: SwiftDeclarationIndexConfiguration {
        .init(showCImportedTypes: false)
    }

    /// Indexes every version (oldest first) and freezes it into a labeled,
    /// persistence-round-tripped snapshot document. The timed step covers the
    /// whole preparation — indexing N binaries is the real cost; the lineage
    /// math afterwards is milliseconds.
    private func snapshotDocuments<MachO: FieldLayoutRenderable>(
        of versions: [(label: String, machO: MachO)]
    ) async throws -> [ABISnapshotDocument] {
        var documents: [ABISnapshotDocument] = []
        try await measuringPreparation {
            for version in versions {
                let builder = SwiftDiffableInterfaceBuilder(configuration: indexConfiguration, in: version.machO)
                try await builder.prepare()
                let document = ABISnapshotDocument(
                    provenance: ABIProvenance(
                        label: version.label,
                        binaryPath: version.machO.imagePath,
                        generatorVersion: "IntegrationTests",
                        createdAt: Date()
                    ),
                    snapshot: builder.snapshot()
                )
                // Round-trip through the persisted form: what the evolution
                // consumes is exactly what a saved baseline would decode to.
                documents.append(try ABISnapshotDocument.decode(from: document.encoded()))
            }
        }
        return documents
    }

    private func timelineReport(of documents: [ABISnapshotDocument]) throws -> String {
        let evolution = try ABIEvolutionBuilder().evolution(of: documents)
        var report = ABIEvolutionReporter().report(evolution)
        // For a two-version series the lineage events must match the
        // two-sided differ verbatim — print both verdicts so the manual
        // inspection can eyeball the consistency on real-world data.
        if documents.count == 2, let oldDocument = documents.first, let newDocument = documents.last {
            let diff = ABIDiffer().diff(old: oldDocument, new: newDocument)
            report += "\n\nPairwise cross-check — evolution ABI-breaking: \(evolution.hasBreakingChange) · diff ABI-breaking: \(diff.hasBreakingChange)"
        }
        return report
    }

    /// Console analogue of `diffString`: prepares every version, then prints
    /// the timeline report.
    func evolutionString<MachO: FieldLayoutRenderable>(versions: [(label: String, machO: MachO)]) async throws {
        let documents = try await snapshotDocuments(of: versions)
        printResult(try timelineReport(of: documents))
    }

    /// File analogue of `diffFile`: writes the timeline report
    /// (`-Evolution.txt`) and the machine-readable form (`-Evolution.json`)
    /// next to the interface/diff dumps, both named after the *newest*
    /// version.
    func evolutionFile<MachO: FieldLayoutRenderable>(versions: [(label: String, machO: MachO)]) async throws {
        let documents = try await snapshotDocuments(of: versions)
        guard let newestVersion = versions.last else { return }
        try write(try timelineReport(of: documents), for: newestVersion.machO, suffix: "Evolution", fileExtension: "txt")
        let evolution = try ABIEvolutionBuilder().evolution(of: documents)
        try write(String(decoding: ABIJSON.encoder().encode(evolution), as: UTF8.self), for: newestVersion.machO, suffix: "Evolution", fileExtension: "json")
    }
}

enum ABIEvolutionTestSuite {
    /// Extracts the same image from an *ordered series* of dyld shared caches —
    /// the N-version counterpart of
    /// `SwiftDiffableInterfaceBuilderTestSuite.CrossVersionDyldCacheImageTests`.
    /// The caches are retained because the extracted `MachOFile`s resolve
    /// cross-image references through them while indexing.
    @TestActor
    class MultiVersionDyldCacheImageTests: Sendable {
        let caches: [DyldCache]
        let versions: [(label: String, machO: MachOFile)]

        class var cachePaths: [DyldSharedCachePath] { [.macOS_15_5, .macOS_26_5_1, .macOS_27_0_beta_1] }
        class var cacheLabels: [String] { ["15.5", "26.5.1", "27.0-beta.1"] }
        class var cacheImageName: MachOImageName { .AppKit }

        init() async throws {
            var caches: [DyldCache] = []
            var versions: [(label: String, machO: MachOFile)] = []
            for (cachePath, cacheLabel) in zip(Self.cachePaths, Self.cacheLabels) {
                let cache = try DyldCache(path: cachePath)
                caches.append(cache)
                versions.append((cacheLabel, try #require(cache.machOFile(named: Self.cacheImageName))))
            }
            self.caches = caches
            self.versions = versions
        }
    }

    /// AppKit across three macOS caches (15.5 → 26.5.1 → 27.0 beta 1) — the
    /// flagship N == 3 lineage: introduced/modified/removed/re-added stories
    /// only visible with more than two versions.
    final class DyldCacheTests: MultiVersionDyldCacheImageTests, ABIEvolutionDumpTests, @unchecked Sendable {
        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func evolutionFile() async throws {
            try await evolutionFile(versions: versions)
        }

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func evolutionString() async throws {
            try await evolutionString(versions: versions)
        }
    }

    /// SwiftUICore across two simulator runtimes (iOS 18.5 → 26.5) — the
    /// N == 2 case, whose printed pairwise cross-check line must agree with
    /// the two-sided differ.
    final class SwiftUICoreTests: SwiftDiffableInterfaceBuilderTestSuite.CrossVersionMachOFileTests, ABIEvolutionDumpTests, @unchecked Sendable {
        override class var oldFileName: MachOFileName { .iOS_18_5_Simulator_SwiftUICore }
        override class var newFileName: MachOFileName { .iOS_26_5_Simulator_SwiftUICore }

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func evolutionFile() async throws {
            try await evolutionFile(versions: [("18.5", oldMachOFile), ("26.5", newMachOFile)])
        }

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func evolutionString() async throws {
            try await evolutionString(versions: [("18.5", oldMachOFile), ("26.5", newMachOFile)])
        }
    }
}
