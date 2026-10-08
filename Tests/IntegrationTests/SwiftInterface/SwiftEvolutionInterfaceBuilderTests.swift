import Foundation
import Testing
import SwiftDeclarationRendering
import MachOKit
import MachOFixtureSupport
import MachOTestingSupport
@testable import MachOSwiftSection
@_spi(Support) @testable import SwiftInterface
@_spi(Support) @testable import SwiftIndexing
import SwiftDiffing

/// The annotated-union-interface analogue of ``ABIEvolutionDumpTests``.
///
/// Where the evolution dump tests run an ordered series of versions through
/// the lineage-report pipeline (`ABIEvolutionBuilder` + `ABIEvolutionReporter`),
/// these run the same series through `AnySwiftEvolutionInterfaceBuilder` —
/// the `swift-section evolution --interface` pipeline — and dump the union
/// interface with lifecycle annotations. Like its siblings it is a
/// maintainer-inspection dump: it prints / writes results without assertions.
/// Inspect the output against the lineage report the `ABIEvolutionTests`
/// dumps produce for the same axis — the two views must tell one story
/// (annotation facts are the same lineages).
///
/// Every axis here has three versions or more, on
/// `MultiVersionDyldCacheImageTests`: an evolution over fewer than three
/// images is what `diff --interface` already covers, and the stories this
/// view exists for — introduced mid-axis, removed mid-axis, modified twice,
/// gone-and-back bitmaps — only appear from three versions up.
protocol SwiftEvolutionInterfaceDumpTests: SwiftInterfaceDumpTests {}

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension SwiftEvolutionInterfaceDumpTests {
    var indexConfiguration: SwiftDeclarationIndexConfiguration {
        .init(showCImportedTypes: false)
    }

    /// Builds and `prepare()`s the whole axis in one timed step — indexing N
    /// binaries is the real cost; the lineage join and rendering afterwards
    /// are cheap by comparison.
    private func preparedBuilder(
        versions: [(label: String, machO: some MachOFieldLayoutRenderable)],
        availabilityAnnotationPlatform: String?
    ) async throws -> AnySwiftEvolutionInterfaceBuilder {
        let builder = try AnySwiftEvolutionInterfaceBuilder(
            configuration: indexConfiguration,
            versions: versions.map(\.machO),
            labels: versions.map(\.label),
            availabilityAnnotationPlatform: availabilityAnnotationPlatform
        )
        try await measuringPreparation {
            try await builder.prepare()
        }
        return builder
    }

    /// The annotated union interface plus the per-axis verdict line, so the
    /// manual inspection can eyeball the CI-gate input next to the rendering.
    private func annotatedInterfaceReport(of builder: AnySwiftEvolutionInterfaceBuilder) async throws -> String {
        var report = try await builder.printAnnotatedInterface().string
        if let evolution = builder.evolution {
            report += "\n\n// ABI-breaking on this axis: \(evolution.hasBreakingChange)"
        }
        return report
    }

    /// Console analogue of `evolutionString`: prepares every version, then
    /// prints the annotated union interface. A platform adds the genuine
    /// `@available` lines, as `evolution --interface --emit-available
    /// --platform` does.
    func evolutionInterfaceString(
        versions: [(label: String, machO: some MachOFieldLayoutRenderable)],
        availabilityAnnotationPlatform: String? = nil
    ) async throws {
        let builder = try await preparedBuilder(versions: versions, availabilityAnnotationPlatform: availabilityAnnotationPlatform)
        printResult(try await annotatedInterfaceReport(of: builder))
    }

    /// File analogue of `evolutionFile`: writes the annotated union interface
    /// (`-EvolutionInterface.swiftinterface`) next to the lineage-report and
    /// diff dumps, named after the *newest* version.
    func evolutionInterfaceFile(
        versions: [(label: String, machO: some MachOFieldLayoutRenderable)],
        availabilityAnnotationPlatform: String? = nil
    ) async throws {
        let builder = try await preparedBuilder(versions: versions, availabilityAnnotationPlatform: availabilityAnnotationPlatform)
        guard let newestVersion = versions.last else { return }
        try await write(annotatedInterfaceReport(of: builder), for: newestVersion.machO, suffix: "EvolutionInterface")
    }
}

enum SwiftEvolutionInterfaceBuilderTestSuite {
    /// AppKit across three macOS caches (15.5 → 26.5.1 → 27.0 beta 1) — the
    /// same axis as `ABIEvolutionTestSuite.DyldCacheTests`' lineage dumps, so
    /// the interface and the report can be inspected side by side.
    final class DyldCacheTests: ABIEvolutionTestSuite.MultiVersionDyldCacheImageTests, SwiftEvolutionInterfaceDumpTests, @unchecked Sendable {
        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func evolutionInterfaceFile() async throws {
            try await evolutionInterfaceFile(versions: versions)
        }

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func evolutionInterfaceString() async throws {
            try await evolutionInterfaceString(versions: versions)
        }

        /// The pack-generic façade on the same three real images: the axis
        /// through `SwiftEvolutionInterfaceBuilder<MachOFile, MachOFile,
        /// MachOFile>` (compile-time arity), dumped for eyeball comparison
        /// against the erased builder's output above — the two must be
        /// byte-identical.
        @available(macOS 14.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
        @Test func evolutionInterfaceStringViaPackFacade() async throws {
            let builder = try SwiftEvolutionInterfaceBuilder(
                configuration: indexConfiguration,
                versions: versions[0].machO, versions[1].machO, versions[2].machO,
                labels: versions.map(\.label)
            )
            // No `measuringPreparation` here: this @Test runs on the suite's
            // @TestActor, and handing it an actor-isolated closure trips
            // region-isolation checking (the extension helpers avoid this by
            // being nonisolated themselves).
            try await builder.prepare()
            printResult(try await builder.printAnnotatedInterface().string)
        }
    }

    /// SwiftUICore across the same three macOS caches — the Swift-rich axis
    /// (AppKit's Swift section is comparatively thin), exercising the union
    /// interface over heavy generics, opaque returns, and extension blocks.
    final class SwiftUICoreDyldCacheTests: ABIEvolutionTestSuite.MultiVersionDyldCacheImageTests, SwiftEvolutionInterfaceDumpTests, @unchecked Sendable {
        override class var cacheImageName: MachOImageName { .SwiftUICore }

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func evolutionInterfaceFile() async throws {
            try await evolutionInterfaceFile(versions: versions)
        }

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func evolutionInterfaceString() async throws {
            try await evolutionInterfaceString(versions: versions)
        }
    }

    /// The same image across archived macOS caches, picked by version: list
    /// in `cacheVersions` the directories under
    /// `/Volumes/DyldSharedCaches/macOS` that hold a cache, oldest first. A
    /// cache named by its version is labeled with it, so every label is a
    /// version number and the union interface also spells each lifecycle one
    /// attribute can express as `@available(macOS, …)`. A version whose image
    /// carries no Swift metadata drops off the axis (see
    /// `MultiVersionDyldCacheImageTests`).
    final class ArchivedDyldCacheTests: ABIEvolutionTestSuite.MultiVersionDyldCacheImageTests, SwiftEvolutionInterfaceDumpTests, @unchecked Sendable {
        
        class var cacheVersions: [String] { [
            "11.0.1",
            "11.1",
            "11.2",
            "11.3",
            "11.4",
            "11.5",
            "11.6",
            "11.7",
            "12.0.1",
            "12.1",
            "12.2",
            "12.3",
            "12.4",
            "12.5",
            "12.6",
            "12.7",
            "13.0",
            "13.1",
            "13.2",
            "13.3",
            "13.4",
            "13.5",
            "13.6",
            "13.7",
            "14.0",
            "14.1",
            "14.2",
            "14.3",
            "14.4",
            "14.5",
            "14.6",
            "14.7",
            "14.8",
            "15.0",
            "15.1",
            "15.2",
            "15.3",
            "15.4",
            "15.5",
            "15.6",
            "15.7",
            "15.8",
            "26.0",
            "26.1",
            "26.2",
            "26.3",
            "26.4",
            "26.5",
            "26.6",
            "26.7",
            "27.0",
        ] }
        
        override class var cachePaths: [DyldSharedCachePath] { cacheVersions.map { .macOS($0) } }
        
        override class var cacheImageName: MachOImageName { .SwiftUI }

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func evolutionInterfaceFile() async throws {
            try await evolutionInterfaceFile(versions: versions, availabilityAnnotationPlatform: "macOS")
        }

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func evolutionInterfaceString() async throws {
            try await evolutionInterfaceString(versions: versions, availabilityAnnotationPlatform: "macOS")
        }
    }
}
