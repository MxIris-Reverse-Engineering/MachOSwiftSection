import Foundation
import Testing
import MachOKit
import SwiftSectionFixtureSupport
@testable import SwiftSectionTestingSupport
@testable import MachOSwiftSection

/// Every diff the maintainer inspects, one suite per place the two versions
/// come from. Each suite runs every diff output on one pair, which its
/// `configuration` names; the pairs come from the version axis base classes
/// the evolution suites read too (`MultiVersionDyldCacheImageTests`,
/// `CrossVersionMachOFileTests`, `CrossVersionXcodeFrameworkTests`). To diff
/// another framework, add a configuration and point the suite at it.
enum Diff {
    /// The same file in two simulator runtimes (iOS 18.5 → 26.5).
    final class SimulatorFiles: CrossVersionMachOFileTests, nonisolated DiffDumpTests, @unchecked Sendable {
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
    }

    /// The same image from two dyld shared caches (macOS 26.5.1 → 27.0),
    /// each opened whole the way `swift-section --dyld-shared-cache` opens
    /// it. Cross-image references resolve through each cache.
    final class Caches: MultiVersionDyldCacheImageTests, nonisolated DiffDumpTests, @unchecked Sendable {
        override class var cachePaths: [DyldSharedCachePath] { [.macOS_26_5_1, .macOS_27_0] }

        override class var configuration: CacheImagesConfiguration { .appKit }

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
    }

    /// The same image from two archived macOS caches, picked by version:
    /// point the two versions at any directories under
    /// `/Volumes/DyldSharedCaches/macOS` that hold a cache.
    final class ArchivedCaches: MultiVersionDyldCacheImageTests, nonisolated DiffDumpTests, @unchecked Sendable {
        class var oldCacheVersion: String { "26.6" }

        class var newCacheVersion: String { "27.0" }

        override class var cachePaths: [DyldSharedCachePath] { [.macOS(oldCacheVersion), .macOS(newCacheVersion)] }

        override class var configuration: CacheImagesConfiguration { .appKit }

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
    }

    /// The same shared framework in two installed Xcodes (26.3.0 → 26.4.0).
    final class XcodeFrameworks: CrossVersionXcodeFrameworkTests, nonisolated DiffDumpTests, @unchecked Sendable {
        override class var configuration: XcodeFrameworkPairConfiguration { .dvtProductsUI }

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
    }
}
