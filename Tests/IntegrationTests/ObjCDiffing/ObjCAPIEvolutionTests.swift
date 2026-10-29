import Foundation
import Testing
import MachOKit
import MachOFixtureSupport
import MachOTestingSupport
@testable import MachOSwiftSection
import SwiftIndexing
import ObjCMetadataSource
import ObjCIndexing
import ObjCInterface
import ObjCDiffing

/// The Objective-C counterpart of ``ABIEvolutionDumpTests``.
///
/// These index an *ordered series* of versions of one image with
/// MachOObjCSection's `ObjCInterfaceIndexer`, freeze each into an
/// `ObjCAPISnapshotDocument` (round-tripping through the persisted JSON form
/// so the codec and the format-version gate run on real-world data), and run
/// the series through `ObjCAPIEvolutionBuilder` + `ObjCAPIEvolutionReporter` —
/// the `swift-section objc evolution` pipeline. The annotated union header of
/// the same axis is ``ObjCEvolutionInterfaceDumpTests``, below. Like its
/// siblings it is a maintainer-inspection dump: it prints / writes results
/// without assertions.
protocol ObjCAPIEvolutionDumpTests: SwiftInterfaceDumpTests {}

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension ObjCAPIEvolutionDumpTests {
    /// Indexes every version (oldest first) the way `swift-section objc
    /// snapshot` does — the Swift classes that have no class object supplied
    /// from Swift metadata — and freezes it into a labeled,
    /// persistence-round-tripped snapshot document. The timed step covers the
    /// whole preparation; the lineage math afterwards takes seconds at most.
    private func snapshotDocuments(of versions: [(label: String, machO: MachOFile)]) async throws -> [ObjCAPISnapshotDocument] {
        var documents: [ObjCAPISnapshotDocument] = []
        try await measuringPreparation {
            for version in versions {
                let indexer = ObjCInterfaceIndexer(
                    machO: version.machO,
                    imagePath: version.machO.imagePath,
                    suppliedClasses: ObjCSuppliedClass.swiftClassesWithoutClassObjects(in: version.machO)
                )
                try await indexer.prepare()
                let document = ObjCAPISnapshotDocument(
                    provenance: ObjCAPIProvenance(
                        label: version.label,
                        binaryPath: version.machO.imagePath,
                        generatorVersion: "IntegrationTests",
                        createdAt: Date()
                    ),
                    snapshot: ObjCAPISnapshotBuilder(indexer: indexer).snapshot()
                )
                // Round-trip through the persisted form: what the evolution
                // consumes is exactly what a saved baseline would decode to.
                documents.append(try ObjCAPISnapshotDocument.decode(from: document.encoded()))
            }
        }
        return documents
    }

    private func timelineReport(of evolution: ObjCAPIEvolution, documents: [ObjCAPISnapshotDocument]) -> String {
        var report = ObjCAPIEvolutionReporter().report(evolution)
        // For a two-version series the lineage events must match the
        // two-sided differ verbatim — print both verdicts so the manual
        // inspection can eyeball the consistency on real-world data.
        if documents.count == 2, let oldDocument = documents.first, let newDocument = documents.last {
            let diff = ObjCAPIDiffer().diff(old: oldDocument, new: newDocument)
            report += "\n\nPairwise cross-check — evolution API-breaking: \(evolution.hasBreakingChange) · diff API-breaking: \(diff.hasBreakingChange)"
        }
        return report
    }

    /// Console analogue of `evolutionFile`: prepares every version, then
    /// prints the timeline report.
    func evolutionString(versions: [(label: String, machO: MachOFile)]) async throws {
        let documents = try await snapshotDocuments(of: versions)
        let evolution = try ObjCAPIEvolutionBuilder().evolution(of: documents)
        printResult(timelineReport(of: evolution, documents: documents))
    }

    /// Writes the timeline report (`-ObjCEvolution.txt`) and the
    /// machine-readable form (`-ObjCEvolution.json`) next to the Swift
    /// evolution dumps, both named after the *newest* version.
    func evolutionFile(versions: [(label: String, machO: MachOFile)]) async throws {
        let documents = try await snapshotDocuments(of: versions)
        guard let newestVersion = versions.last else { return }
        let evolution = try ObjCAPIEvolutionBuilder().evolution(of: documents)
        try write(timelineReport(of: evolution, documents: documents), for: newestVersion.machO, suffix: "ObjCEvolution", fileExtension: "txt")
        try write(String(decoding: ObjCAPIJSON.encoder().encode(evolution), as: UTF8.self), for: newestVersion.machO, suffix: "ObjCEvolution", fileExtension: "json")
    }
}

enum ObjCAPIEvolutionTestSuite {
    /// AppKit's Objective-C metadata across an ordered series of dyld shared
    /// caches. A version joins the axis when its image carries an `__objc_*`
    /// section, which AppKit does in every cache — unlike its Swift sections,
    /// which the Swift suites need and which only appear from macOS 14.
    class MultiVersionDyldCacheImageTests: ABIEvolutionTestSuite.MultiVersionDyldCacheImageTests, @unchecked Sendable {
        override class var cacheImageName: MachOImageName { .AppKit }

        override class func isOnAxis(_ machOFile: MachOFile) -> Bool {
            machOFile.sections.contains(where: { $0.sectionName.hasPrefix("__objc_") })
        }
    }

    /// AppKit across the three macOS caches the Swift evolution suites
    /// default to (15.5 → 26.5.2 → 27.0), so the Objective-C report can be
    /// read beside theirs.
    final class DyldCacheTests: MultiVersionDyldCacheImageTests, ObjCAPIEvolutionDumpTests, @unchecked Sendable {
        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func evolutionFile() async throws {
            try await evolutionFile(versions: versions)
        }

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func evolutionString() async throws {
            try await evolutionString(versions: versions)
        }
    }

    /// AppKit across every archived macOS cache, on the axis of the Swift
    /// `SwiftEvolutionInterfaceBuilderTestSuite.ArchivedDyldCacheTests`: the
    /// same versions under the same labels, listed there once for both.
    ///
    /// The method names of a macOS 11 cache read correctly only from
    /// MachOObjCSection 0.8.202. Its relative method lists count a selector
    /// from the name field itself, where later caches count it from a
    /// selector base, and an earlier reader made every class and category
    /// method of 11.x garbage — 11.7 → 12.0.1 then reported about 47,000
    /// removals and 53,000 additions instead of about 1,200 and 1,400.
    final class ArchivedDyldCacheTests: MultiVersionDyldCacheImageTests, ObjCAPIEvolutionDumpTests, @unchecked Sendable {
        override class var cachePaths: [DyldSharedCachePath] {
            SwiftEvolutionInterfaceBuilderTestSuite.ArchivedDyldCacheTests.cachePaths
        }

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func evolutionFile() async throws {
            try await evolutionFile(versions: versions)
        }

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func evolutionString() async throws {
            try await evolutionString(versions: versions)
        }
    }
}

/// The annotated-union-header analogue of ``ObjCAPIEvolutionDumpTests``, and
/// the Objective-C counterpart of ``SwiftEvolutionInterfaceDumpTests``.
///
/// These run the same series through MachOObjCSection's
/// `ObjCEvolutionInterfaceBuilder` — the `swift-section objc evolution
/// --interface` pipeline: every declaration rendered the way `objc dump`
/// renders it, the versions merged into one header, and each declaration's
/// lifecycle annotated. Read the header against the lineage report of the
/// same axis — the annotations are the same lineages. Like its siblings it is
/// a maintainer-inspection dump: it prints / writes results without
/// assertions.
protocol ObjCEvolutionInterfaceDumpTests: SwiftInterfaceDumpTests {}

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension ObjCEvolutionInterfaceDumpTests {
    /// Indexes every version (oldest first) the way `objc evolution
    /// --interface` does and hands it to the builder, which keeps what it
    /// rendered and snapshotted, never the indexer. The timed step covers the
    /// indexing and rendering of every version.
    private func evolutionInterface(
        of versions: [(label: String, machO: MachOFile)],
        availabilityPlatform: String?
    ) async throws -> ObjCEvolutionInterface {
        var builder = ObjCEvolutionInterfaceBuilder()
        try await measuringPreparation {
            for version in versions {
                let indexer = ObjCInterfaceIndexer(
                    machO: version.machO,
                    imagePath: version.machO.imagePath,
                    suppliedClasses: ObjCSuppliedClass.swiftClassesWithoutClassObjects(in: version.machO)
                )
                try await indexer.prepare()
                builder.addVersion(indexer: indexer, machO: version.machO, version: ObjCAPIVersionDescriptor(label: version.label))
            }
        }
        return try builder.build(availabilityPlatform: availabilityPlatform)
    }

    /// The annotated header plus the per-axis verdict line, so the manual
    /// inspection can eyeball the CI-gate input next to the rendering.
    private func annotatedHeaderReport(of evolutionInterface: ObjCEvolutionInterface) -> String {
        evolutionInterface.interface.string + "\n\n// API-breaking on this axis: \(evolutionInterface.evolution.hasBreakingChange)"
    }

    /// Console analogue of `evolutionInterfaceFile`. A platform adds the
    /// availability macros, as `objc evolution --interface --emit-available
    /// --platform` does.
    func evolutionInterfaceString(versions: [(label: String, machO: MachOFile)], availabilityPlatform: String? = nil) async throws {
        let evolutionInterface = try await evolutionInterface(of: versions, availabilityPlatform: availabilityPlatform)
        printResult(annotatedHeaderReport(of: evolutionInterface))
    }

    /// Writes the annotated header (`-ObjCEvolutionInterface.h`) next to the
    /// lineage report, named after the *newest* version.
    func evolutionInterfaceFile(versions: [(label: String, machO: MachOFile)], availabilityPlatform: String? = nil) async throws {
        let evolutionInterface = try await evolutionInterface(of: versions, availabilityPlatform: availabilityPlatform)
        guard let newestVersion = versions.last else { return }
        try write(annotatedHeaderReport(of: evolutionInterface), for: newestVersion.machO, suffix: "ObjCEvolutionInterface", fileExtension: "h")
    }
}

enum ObjCEvolutionInterfaceTestSuite {
    /// AppKit across the three macOS caches the evolution suites default to
    /// (15.5 → 26.5.2 → 27.0) — the axis of
    /// `ObjCAPIEvolutionTestSuite.DyldCacheTests`, so the header and the
    /// report can be read side by side.
    final class DyldCacheTests: ObjCAPIEvolutionTestSuite.MultiVersionDyldCacheImageTests, ObjCEvolutionInterfaceDumpTests, @unchecked Sendable {
        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func evolutionInterfaceFile() async throws {
            try await evolutionInterfaceFile(versions: versions)
        }

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func evolutionInterfaceString() async throws {
            try await evolutionInterfaceString(versions: versions)
        }
    }

    /// AppKit across every archived macOS cache, on the axis of
    /// `ObjCAPIEvolutionTestSuite.ArchivedDyldCacheTests`. Every label is a
    /// version number, so the header also spells each lifecycle one macro can
    /// express as `API_AVAILABLE` / `API_OBSOLETED`.
    final class ArchivedDyldCacheTests: ObjCAPIEvolutionTestSuite.MultiVersionDyldCacheImageTests, ObjCEvolutionInterfaceDumpTests, @unchecked Sendable {
        override class var cachePaths: [DyldSharedCachePath] {
            ObjCAPIEvolutionTestSuite.ArchivedDyldCacheTests.cachePaths
        }

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func evolutionInterfaceFile() async throws {
            try await evolutionInterfaceFile(versions: versions, availabilityPlatform: "macos")
        }

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func evolutionInterfaceString() async throws {
            try await evolutionInterfaceString(versions: versions, availabilityPlatform: "macos")
        }
    }
}
