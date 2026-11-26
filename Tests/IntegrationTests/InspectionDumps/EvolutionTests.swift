import Foundation
import Testing
import MachOKit
import SwiftSectionFixtureSupport
@testable import SwiftSectionTestingSupport
@testable import MachOSwiftSection
@_spi(Support) @testable import SwiftInterface
@_spi(Support) @testable import SwiftIndexing
import Semantic

/// Every evolution the maintainer inspects, one suite per place the versions
/// come from. Each suite runs every evolution output — the Swift and
/// Objective-C reports and interfaces alike — on one series of versions,
/// which its `configuration` names; each language's pipelines see only the
/// versions whose images carry their metadata (see
/// `MultiVersionDyldCacheImageTests`). To follow another framework or group
/// of images, add a configuration and point the suite at it.
///
/// Read an interface against the report of the same axis: the two views
/// must tell one story. An annotated interface is worth reading only from
/// three versions up — introduced mid-axis, removed mid-axis, modified
/// twice, gone-and-back bitmaps; for two, `diff --interface` already covers
/// it.
enum Evolution {
    /// The default three macOS caches (15.5 → 26.5.2 → 27.0) — the N == 3
    /// lineage: introduced / modified / removed / re-added stories only
    /// visible with more than two versions.
    final class Caches: MultiVersionDyldCacheImageTests, nonisolated EvolutionDumpTests, @unchecked Sendable {
        override class var configuration: CacheImagesConfiguration { .swiftUIGroup }

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func swiftReportFile() async throws {
            try await dump(.swiftReport, to: .file)
        }

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func swiftReportString() async throws {
            try await dump(.swiftReport, to: .console)
        }

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func swiftInterfaceFile() async throws {
            try await dump(.swiftInterface, to: .file)
        }

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func swiftInterfaceString() async throws {
            try await dump(.swiftInterface, to: .console)
        }

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func objcReportFile() async throws {
            try await dump(.objcReport, to: .file)
        }

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func objcReportString() async throws {
            try await dump(.objcReport, to: .console)
        }

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func objcInterfaceFile() async throws {
            try await dump(.objcInterface, to: .file)
        }

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func objcInterfaceString() async throws {
            try await dump(.objcInterface, to: .console)
        }

        /// The pack-generic façade on the first three versions' primary
        /// images: the axis through `SwiftEvolutionInterfaceBuilder<MachOFile,
        /// MachOFile, MachOFile>` (compile-time arity), dumped for eyeball
        /// comparison against `swiftInterfaceString()` — byte-identical when
        /// the configuration reads one image per version.
        @available(macOS 14.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
        @Test func swiftInterfaceStringViaPackFacade() async throws {
            let versions = versionAxis(for: .swift).versions
            guard versions.count >= 3 else {
                printResult("No pack façade dump: \(versions.count) version(s) carry Swift metadata")
                return
            }
            let builder = try SwiftEvolutionInterfaceBuilder(
                configuration: indexConfiguration,
                versions: versions[0].primaryImage.machOFile, versions[1].primaryImage.machOFile, versions[2].primaryImage.machOFile,
                labels: versions.prefix(3).map(\.label)
            )
            // No `measuringPreparation` here: this @Test runs on the suite's
            // @TestActor, and handing it an actor-isolated closure trips
            // region-isolation checking (the extension helpers avoid this by
            // being nonisolated themselves).
            try await builder.prepare()
            printResult(try await builder.printAnnotatedInterface().string)
        }
    }

    /// Every archived macOS cache, 11.0 → 27.0. Every label is a version
    /// number, so both interfaces also spell each lifecycle one attribute or
    /// macro can express (`@available(macOS, …)`, `API_AVAILABLE(macos(…))`).
    /// A group whose other images join late reads them from where they
    /// appear: SwiftUICore joins SwiftUI in 15.0, where an evolution of
    /// SwiftUI alone reads every declaration moved into SwiftUICore as
    /// removed.
    final class ArchivedCaches: MultiVersionDyldCacheImageTests, nonisolated EvolutionDumpTests, @unchecked Sendable {
        override class var cachePaths: [DyldSharedCachePath] { archivedMacOSCachePaths }

        override class var availabilityPlatform: AvailabilityPlatform? { .macOS }

        override class var configuration: CacheImagesConfiguration { .swiftUIGroup }

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func swiftReportFile() async throws {
            try await dump(.swiftReport, to: .file)
        }

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func swiftReportString() async throws {
            try await dump(.swiftReport, to: .console)
        }

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func swiftInterfaceFile() async throws {
            try await dump(.swiftInterface, to: .file)
        }

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func swiftInterfaceString() async throws {
            try await dump(.swiftInterface, to: .console)
        }

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func objcReportFile() async throws {
            try await dump(.objcReport, to: .file)
        }

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func objcReportString() async throws {
            try await dump(.objcReport, to: .console)
        }

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func objcInterfaceFile() async throws {
            try await dump(.objcInterface, to: .file)
        }

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func objcInterfaceString() async throws {
            try await dump(.objcInterface, to: .console)
        }
    }

    /// The same file in two simulator runtimes (iOS 18.5 → 26.5) — the
    /// N == 2 case, whose printed pairwise cross-check line must agree with
    /// the two-sided differ.
    final class SimulatorFiles: CrossVersionMachOFileTests, nonisolated EvolutionDumpTests, @unchecked Sendable {
        override class var configuration: SimulatorFilePairConfiguration { .swiftUICore }

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func swiftReportFile() async throws {
            try await dump(.swiftReport, to: .file)
        }

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func swiftReportString() async throws {
            try await dump(.swiftReport, to: .console)
        }

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func swiftInterfaceFile() async throws {
            try await dump(.swiftInterface, to: .file)
        }

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func swiftInterfaceString() async throws {
            try await dump(.swiftInterface, to: .console)
        }

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func objcReportFile() async throws {
            try await dump(.objcReport, to: .file)
        }

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func objcReportString() async throws {
            try await dump(.objcReport, to: .console)
        }

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func objcInterfaceFile() async throws {
            try await dump(.objcInterface, to: .file)
        }

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func objcInterfaceString() async throws {
            try await dump(.objcInterface, to: .console)
        }
    }
}
