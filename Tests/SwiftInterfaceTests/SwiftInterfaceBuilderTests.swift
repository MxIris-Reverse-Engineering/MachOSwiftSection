import Foundation
import Testing
import MachOKit
@testable import MachOSwiftSection
@testable import MachOTestingSupport
@testable import SwiftInterface

protocol SwiftInterfaceBuilderTests {}

extension SwiftInterfaceBuilderTests {
    func buildFile(in machO: MachOFile) async throws {
        let builder = try SwiftInterfaceBuilder(configuration: .init(isEnabledTypeIndexing: false), eventHandlers: [OSLogEventHandler()], in: machO)
        builder.setDependencyPaths([.usesSystemDyldSharedCache])
        try await builder.prepare()
        let result = try builder.build()
        try result.string.write(to: .desktopDirectory.appending(path: "\(machO.imagePath.lastPathComponent)-FileDump.swiftinterface"), atomically: true, encoding: .utf8)
    }

    func buildFile(in machO: MachOImage) async throws {
        let builder = try SwiftInterfaceBuilder(configuration: .init(isEnabledTypeIndexing: false), eventHandlers: [OSLogEventHandler()], in: machO)
        builder.setupDependencies()
        try await builder.prepare()
        let result = try builder.build()
        try result.string.write(to: .desktopDirectory.appending(path: "\(machO.imagePath.lastPathComponent)-ImageDump.swiftinterface"), atomically: true, encoding: .utf8)
    }
}

@Suite
enum SwiftInterfaceBuilderTestSuite {
    class DyldCacheTests: MachOTestingSupport.DyldCacheTests, SwiftInterfaceBuilderTests {
        override class var platform: Platform { .macOS }

        override class var cacheImageName: MachOImageName { .SwiftUICore }

        override class var cachePath: DyldSharedCachePath { .current }

        @Test func buildFile() async throws {
            try await buildFile(in: machOFileInCache)
        }
    }

    class MachOFileTests: MachOTestingSupport.MachOFileTests, SwiftInterfaceBuilderTests {
        override class var fileName: MachOFileName { .SymbolTestsCore }

        @Test func buildFile() async throws {
            try await buildFile(in: machOFile)
        }
    }

    class MachOImageTests: MachOTestingSupport.MachOImageTests, SwiftInterfaceBuilderTests {
        override class var imageName: MachOImageName { .SwiftUICore }

        @Test func buildFile() async throws {
            try await buildFile(in: machOImage)
        }
    }

    class XcodeMachOFileTests: MachOTestingSupport.XcodeMachOFileTests, SwiftInterfaceBuilderTests {
        override class var fileName: XcodeMachOFileName { .sharedFrameworks(.CombineXPC) }

        @Test func buildFile() async throws {
            try await buildFile(in: machOFile)
        }
    }
}
