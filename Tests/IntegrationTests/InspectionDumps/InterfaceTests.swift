import Foundation
import Testing
import MachOKit
import SwiftSectionFixtureSupport
@testable import SwiftSectionTestingSupport
@testable import MachOSwiftSection

/// Every single-version interface the maintainer inspects, one suite per
/// place an image is read from. Each suite runs both outputs on one image,
/// which is its configuration: point `cacheImageName`, `fileName` or
/// `imageName` at any image to look at it.
enum Interface {
    /// An image of this Mac's dyld shared cache.
    class SystemCache: SwiftSectionTestingSupport.DyldCacheTests, nonisolated InterfaceDumpTests, @unchecked Sendable {
        override class var cacheImageName: MachOImageName { .AppKit }

        override class var cachePath: DyldSharedCachePath { .current }

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func swiftInterfaceFile() async throws {
            try await dump(.swiftInterface, of: machOFileInCache, to: .file)
        }

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func swiftInterfaceString() async throws {
            try await dump(.swiftInterface, of: machOFileInCache, to: .console)
        }

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func objcInterfaceFile() async throws {
            try await dump(.objcInterface, of: machOFileInCache, to: .file)
        }

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func objcInterfaceString() async throws {
            try await dump(.objcInterface, of: machOFileInCache, to: .console)
        }
    }

    /// An image of an archived macOS cache, picked by version: point
    /// `cacheVersion` at any directory under `/Volumes/DyldSharedCaches/macOS`
    /// that holds a cache.
    class ArchivedCache: SwiftSectionTestingSupport.DyldCacheTests, nonisolated InterfaceDumpTests, @unchecked Sendable {
        class var cacheVersion: String { "26.6" }

        override class var cachePath: DyldSharedCachePath { .macOS(cacheVersion) }

        override class var cacheImageName: MachOImageName { .AppKit }

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func swiftInterfaceFile() async throws {
            try await dump(.swiftInterface, of: machOFileInCache, to: .file)
        }

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func swiftInterfaceString() async throws {
            try await dump(.swiftInterface, of: machOFileInCache, to: .console)
        }

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func objcInterfaceFile() async throws {
            try await dump(.objcInterface, of: machOFileInCache, to: .file)
        }

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func objcInterfaceString() async throws {
            try await dump(.objcInterface, of: machOFileInCache, to: .console)
        }
    }

    /// A file on disk.
    class File: SwiftSectionTestingSupport.MachOFileTests, nonisolated InterfaceDumpTests, @unchecked Sendable {
        override class var fileName: MachOFileName { .SymbolTestsCore }

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func swiftInterfaceFile() async throws {
            try await dump(.swiftInterface, of: machOFile, to: .file)
        }

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func swiftInterfaceString() async throws {
            try await dump(.swiftInterface, of: machOFile, to: .console)
        }

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func objcInterfaceFile() async throws {
            try await dump(.objcInterface, of: machOFile, to: .file)
        }

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func objcInterfaceString() async throws {
            try await dump(.objcInterface, of: machOFile, to: .console)
        }
    }

    /// An image this process loaded, read in process.
    class InProcessImage: SwiftSectionTestingSupport.MachOImageTests, nonisolated InterfaceDumpTests, @unchecked Sendable {
        override class var imageName: MachOImageName { .SwiftUICore }

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func swiftInterfaceFile() async throws {
            try await dump(.swiftInterface, of: machOImage, to: .file)
        }

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func swiftInterfaceString() async throws {
            try await dump(.swiftInterface, of: machOImage, to: .console)
        }

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func objcInterfaceFile() async throws {
            try await dump(.objcInterface, of: machOImage, to: .file)
        }

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func objcInterfaceString() async throws {
            try await dump(.objcInterface, of: machOImage, to: .console)
        }
    }

    /// A file inside Xcode, printed with only what it exports.
    class XcodeFile: SwiftSectionTestingSupport.XcodeMachOFileTests, InterfaceDumpTests {
        override class var fileName: XcodeMachOFileName { .sharedFrameworks(.SourceEditor) }

        var printsExportedDeclarationsOnly: Bool { true }

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func swiftInterfaceFile() async throws {
            try await dump(.swiftInterface, of: machOFile, to: .file)
        }

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func swiftInterfaceString() async throws {
            try await dump(.swiftInterface, of: machOFile, to: .console)
        }

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func objcInterfaceFile() async throws {
            try await dump(.objcInterface, of: machOFile, to: .file)
        }

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func objcInterfaceString() async throws {
            try await dump(.objcInterface, of: machOFile, to: .console)
        }
    }
}
