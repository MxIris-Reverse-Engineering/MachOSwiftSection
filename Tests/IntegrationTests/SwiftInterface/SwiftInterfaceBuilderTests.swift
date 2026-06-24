@_spi(Support) @testable import SwiftDeclaration
@_spi(Support) @testable import SwiftIndexing
@_spi(Support) @testable import SwiftPrinting
import Foundation
import Testing
import SwiftDeclarationRendering
import MachOKit
import Dependencies
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport
@testable import SwiftInterface
@_spi(Internals) @testable import MachOSymbols
@_spi(Internals) @testable import MachOCaches

protocol SwiftInterfaceBuilderTests: SwiftInterfaceDumpTests {}

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension SwiftInterfaceBuilderTests {
    var builderConfiguration: SwiftInterfaceBuilderConfiguration {
        SwiftInterfaceBuilderConfiguration(
            indexConfiguration: .init(
                showCImportedTypes: false
            ),
            printConfiguration: .init(
                printStrippedSymbolicItem: true,
                printFieldOffset: true,
                printExpandedFieldOffsets: true,
                printMemberAddress: true,
                printVTableOffset: true,
                printPWTOffset: true,
                memberSortOrder: .byOffset,
                printTypeLayout: true,
                printEnumLayout: true,
            )
        )
    }

    private func makeBuilder<MachO: FieldLayoutRenderable>(in machO: MachO) throws -> SwiftInterfaceBuilder<MachO> {
        let builder = try SwiftInterfaceBuilder(configuration: builderConfiguration, eventHandlers: [], in: machO)
        builder.addExtraDataProvider(SwiftInterfaceBuilderOpaqueTypeProvider(machO: machO))
        return builder
    }

    /// Builds the interface (timed) and returns the rendered source. The two
    /// `@Test` entry points below only differ in where they send this string.
    private func buildInterfaceString<MachO: FieldLayoutRenderable>(in machO: MachO) async throws -> String {
        let builder = try makeBuilder(in: machO)
        try await measuringPreparation { try await builder.prepare() }
        return try await builder.printRoot().string
    }

    func buildString<MachO: FieldLayoutRenderable>(in machO: MachO) async throws {
        printResult(try await buildInterfaceString(in: machO))
    }

    func buildFile<MachO: FieldLayoutRenderable>(in machO: MachO) async throws {
        // Preserve the historical `-FileDump` / `-ImageDump` naming so the file
        // tells you which reader produced it.
        let suffix = machO is MachOImage ? "ImageDump" : "FileDump"
        try write(try await buildInterfaceString(in: machO), for: machO, suffix: suffix)
    }
}

@Suite
enum SwiftInterfaceBuilderTestSuite {
    class DyldCacheTests: MachOTestingSupport.DyldCacheTests, SwiftInterfaceBuilderTests, @unchecked Sendable {
        override class var cacheImageName: MachOImageName {
            .SwiftUICore
        }

        override class var cachePath: DyldSharedCachePath {
            .current
        }

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func buildFile() async throws {
            try await buildFile(in: machOFileInCache)
        }

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func buildString() async throws {
            try await buildString(in: machOFileInCache)
        }
    }

    class MachOFileTests: MachOTestingSupport.MachOFileTests, SwiftInterfaceBuilderTests, @unchecked Sendable {
        override class var fileName: MachOFileName {
            .iOS_18_5_Simulator_SwiftUICore
        }

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func buildFile() async throws {
            try await buildFile(in: machOFile)
        }

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func buildString() async throws {
            try await buildString(in: machOFile)
        }
    }

    class MachOImageTests: MachOTestingSupport.MachOImageTests, SwiftInterfaceBuilderTests, @unchecked Sendable {
        override class var imageName: MachOImageName {
            .SwiftUICore
        }

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func buildFile() async throws {
            try await buildFile(in: machOImage)
        }

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func buildString() async throws {
            try await buildString(in: machOImage)
        }
    }

    class XcodeMachOFileTests: MachOTestingSupport.XcodeMachOFileTests, SwiftInterfaceBuilderTests {
        override class var fileName: XcodeMachOFileName {
            .sharedFrameworks(.DVTProductsUI)
        }

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func buildFile() async throws {
            try await buildFile(in: machOFile)
        }

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func buildString() async throws {
            try await buildString(in: machOFile)
        }
    }
}
