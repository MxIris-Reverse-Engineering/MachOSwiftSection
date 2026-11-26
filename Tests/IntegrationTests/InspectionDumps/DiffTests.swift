import Foundation
import Testing
import MachOKit
import SwiftSectionFixtureSupport
import SwiftSectionTestingSupport
@testable import MachOSwiftSection

/// Every diff the maintainer inspects, one suite per pair of versions. A
/// suite names its two versions once and diffs them through each output it
/// is read for, one test per output and destination. The pairs come from the
/// version axis base classes the evolution suites read too (see
/// `VersionAxis.swift`); AppKit's suites also diff its Objective-C API, the
/// larger half of it.
enum DiffTestSuite {
    /// SwiftUICore across two simulator runtimes (iOS 18.5 → 26.5).
    final class SwiftUICoreTests: CrossVersionMachOFileTests, nonisolated DiffDumpTests, @unchecked Sendable {
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

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func swiftInterfaceFile() async throws {
            try await dump(.swiftInterface, to: .file)
        }

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func swiftInterfaceString() async throws {
            try await dump(.swiftInterface, to: .console)
        }
    }

    /// SwiftUI across two simulator runtimes (iOS 18.5 → 26.5).
    final class SwiftUITests: CrossVersionMachOFileTests, nonisolated DiffDumpTests, @unchecked Sendable {
        override class var oldFileName: MachOFileName { .iOS_18_5_Simulator_SwiftUI }
        override class var newFileName: MachOFileName { .iOS_26_5_Simulator_SwiftUI }

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
    }

    /// AppKit from two dyld shared caches (macOS 26.5.1 → 27.0), each opened
    /// whole the way `swift-section --dyld-shared-cache` opens it.
    /// Cross-image references resolve through each cache.
    final class DyldCacheTests: MultiVersionDyldCacheImageTests, nonisolated DiffDumpTests, @unchecked Sendable {
        override class var cachePaths: [DyldSharedCachePath] { [.macOS_26_5_1, .macOS_27_0] }
        override class var cacheImageName: MachOImageName { .AppKit }

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
    final class ArchivedDyldCacheTests: MultiVersionDyldCacheImageTests, nonisolated DiffDumpTests, @unchecked Sendable {
        class var oldCacheVersion: String { "26.6" }
        class var newCacheVersion: String { "27.0" }
        override class var cachePaths: [DyldSharedCachePath] { [.macOS(oldCacheVersion), .macOS(newCacheVersion)] }
        override class var cacheImageName: MachOImageName { .AppKit }

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

    /// The DVTProductsUI shared framework across two installed Xcodes
    /// (26.3.0 → 26.4.0).
    final class XcodeFrameworkTests: CrossVersionXcodeFrameworkTests, nonisolated DiffDumpTests, @unchecked Sendable {
        override class var oldXcodeVersion: String { "26.3.0" }
        override class var newXcodeVersion: String { "26.4.0" }
        override class var sharedFrameworkName: String { "DVTProductsUI" }

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
    }
}
