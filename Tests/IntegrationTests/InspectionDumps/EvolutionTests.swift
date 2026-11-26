import Foundation
import Testing
import MachOKit
import SwiftSectionFixtureSupport
import SwiftSectionTestingSupport
@testable import MachOSwiftSection
@_spi(Support) @testable import SwiftInterface
@_spi(Support) @testable import SwiftIndexing
import Semantic

/// Every evolution axis the maintainer inspects, one suite per axis. A suite
/// declares its caches and images once and runs on them each evolution
/// output it is read for — the Swift and Objective-C reports and interfaces
/// alike — with one test per output and destination. Each language's
/// pipelines see only the versions whose images carry their metadata (see
/// `MultiVersionDyldCacheImageTests`).
///
/// Read an interface against the report of the same axis: the two views
/// must tell one story. An annotated interface is worth reading only from
/// three versions up — introduced mid-axis, removed mid-axis, modified
/// twice, gone-and-back bitmaps; for two, `diff --interface` already covers
/// it.
enum EvolutionTestSuite {
    /// SwiftUI across the default three caches (15.5 → 26.5.2 → 27.0) — the
    /// flagship N == 3 lineage: introduced / modified / removed / re-added
    /// stories only visible with more than two versions.
    final class SwiftUIDyldCacheTests: MultiVersionDyldCacheImageTests, nonisolated EvolutionDumpTests, @unchecked Sendable {
        override class var cacheImageName: MachOImageName { .SwiftUI }

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

        /// The pack-generic façade on the same three images: the axis
        /// through `SwiftEvolutionInterfaceBuilder<MachOFile, MachOFile,
        /// MachOFile>` (compile-time arity), dumped for eyeball comparison
        /// against `swiftInterfaceString()` — the two must be
        /// byte-identical.
        @available(macOS 14.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
        @Test func swiftInterfaceStringViaPackFacade() async throws {
            let versions = versionAxis(for: .swift).versions
            let builder = try SwiftEvolutionInterfaceBuilder(
                configuration: indexConfiguration,
                versions: versions[0].primaryImage.machOFile, versions[1].primaryImage.machOFile, versions[2].primaryImage.machOFile,
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

    /// SwiftUICore across the default three caches — the Swift-rich axis,
    /// exercising the union interface over heavy generics, opaque returns
    /// and extension blocks.
    final class SwiftUICoreDyldCacheTests: MultiVersionDyldCacheImageTests, nonisolated EvolutionDumpTests, @unchecked Sendable {
        override class var cacheImageName: MachOImageName { .SwiftUICore }

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func swiftInterfaceFile() async throws {
            try await dump(.swiftInterface, to: .file)
        }

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func swiftInterfaceString() async throws {
            try await dump(.swiftInterface, to: .console)
        }
    }

    /// AppKit's Objective-C metadata across the default three caches.
    final class AppKitDyldCacheTests: MultiVersionDyldCacheImageTests, nonisolated EvolutionDumpTests, @unchecked Sendable {
        override class var cacheImageName: MachOImageName { .AppKit }

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

    /// SwiftUI across every archived macOS cache, 11.0 → 27.0. Every label
    /// is a version number, so the interface also spells each lifecycle one
    /// attribute can express as `@available(macOS, …)`.
    final class SwiftUIArchivedDyldCacheTests: MultiVersionDyldCacheImageTests, nonisolated EvolutionDumpTests, @unchecked Sendable {
        override class var cachePaths: [DyldSharedCachePath] { archivedMacOSCachePaths }
        override class var cacheImageName: MachOImageName { .SwiftUI }
        override class var availabilityPlatform: AvailabilityPlatform? { .macOS }

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func swiftInterfaceFile() async throws {
            try await dump(.swiftInterface, to: .file)
        }

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func swiftInterfaceString() async throws {
            try await dump(.swiftInterface, to: .console)
        }
    }

    /// AppKit's Objective-C metadata across every archived macOS cache, with
    /// the header's `API_AVAILABLE` / `API_OBSOLETED` macros.
    ///
    /// The method names of a macOS 11 cache read correctly only from
    /// MachOObjCSection 0.8.202. Its relative method lists count a selector
    /// from the name field itself, where later caches count it from a
    /// selector base, and an earlier reader made every class and category
    /// method of 11.x garbage — 11.7 → 12.0.1 then reported about 47,000
    /// removals and 53,000 additions instead of about 1,200 and 1,400.
    final class AppKitArchivedDyldCacheTests: MultiVersionDyldCacheImageTests, nonisolated EvolutionDumpTests, @unchecked Sendable {
        override class var cachePaths: [DyldSharedCachePath] { archivedMacOSCachePaths }
        override class var cacheImageName: MachOImageName { .AppKit }
        override class var availabilityPlatform: AvailabilityPlatform? { .macOS }

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

    /// SwiftUI together with SwiftUICore across the default three caches,
    /// each version one group of images (evolution proposal
    /// `image-group-evolution`): what moved between the two images after the
    /// split reads as moved, not as removed and added.
    final class SwiftUIImageGroupDyldCacheTests: MultiVersionDyldCacheImageTests, nonisolated EvolutionDumpTests, @unchecked Sendable {
        override class var cacheImageNames: [MachOImageName] { [.SwiftUI, .SwiftUICore] }

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

    /// The same group across every archived macOS cache: SwiftUI alone until
    /// 14.8, SwiftUICore joining it in 15.0 — where an evolution of SwiftUI
    /// alone reads every declaration moved into SwiftUICore as removed. Every
    /// label is a version number, so both interfaces spell availability.
    final class SwiftUIImageGroupArchivedDyldCacheTests: MultiVersionDyldCacheImageTests, nonisolated EvolutionDumpTests, @unchecked Sendable {
        override class var cachePaths: [DyldSharedCachePath] { archivedMacOSCachePaths }
        override class var cacheImageNames: [MachOImageName] { [.SwiftUI, .SwiftUICore] }
        override class var availabilityPlatform: AvailabilityPlatform? { .macOS }

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

    /// AppKit together with the frameworks Apple moved its classes into —
    /// UIFoundation, CollectionViewCore, CoreAutoLayout — across the default
    /// three caches, each version one group of images.
    final class AppKitImageGroupDyldCacheTests: MultiVersionDyldCacheImageTests, nonisolated EvolutionDumpTests, @unchecked Sendable {
        override class var cacheImageNames: [MachOImageName] { [.AppKit, .UIFoundation, .CollectionViewCore, .CoreAutoLayout] }

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

    /// The same group across every archived macOS cache: the classes that
    /// moved between AppKit, UIFoundation and CollectionViewCore in 13.0 and
    /// 15.0 — where an evolution of AppKit alone reads them as removed or
    /// added — read as moved. CollectionViewCore joins the group in 13.0.
    final class AppKitImageGroupArchivedDyldCacheTests: MultiVersionDyldCacheImageTests, nonisolated EvolutionDumpTests, @unchecked Sendable {
        override class var cachePaths: [DyldSharedCachePath] { archivedMacOSCachePaths }
        override class var cacheImageNames: [MachOImageName] { [.AppKit, .UIFoundation, .CollectionViewCore, .CoreAutoLayout] }
        override class var availabilityPlatform: AvailabilityPlatform? { .macOS }

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

    /// SwiftUICore across two simulator runtimes (iOS 18.5 → 26.5) — the
    /// N == 2 case, whose printed pairwise cross-check line must agree with
    /// the two-sided differ.
    final class SwiftUICoreSimulatorTests: CrossVersionMachOFileTests, nonisolated EvolutionDumpTests, @unchecked Sendable {
        override class var oldFileName: MachOFileName { .iOS_18_5_Simulator_SwiftUICore }
        override class var newFileName: MachOFileName { .iOS_26_5_Simulator_SwiftUICore }

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func swiftReportFile() async throws {
            try await dump(.swiftReport, to: .file)
        }

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func swiftReportString() async throws {
            try await dump(.swiftReport, to: .console)
        }
    }
}
