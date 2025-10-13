import Foundation
import Testing
import MachOKit
@testable import MachOSwiftSection
@testable import MachOTestingSupport
@testable import SwiftInterface
import Dependencies
@_private(sourceFile: "SymbolIndexStore.swift") @_spi(Internals) import MachOSymbols
@_spi(Internals) import MachOCaches

protocol SwiftInterfaceBuilderTests {}

extension SwiftInterfaceBuilderTests {
    var rootDirectory: URL {
        .documentsDirectory.appending(path: "SwiftInterfaceTests")
    }

    func buildFile(in machO: MachOFile) async throws {
        let builder = try SwiftInterfaceBuilder(configuration: .init(isEnabledTypeIndexing: false), eventHandlers: [], in: machO)
        builder.setDependencyPaths([.usesSystemDyldSharedCache])
        try await builder.prepare()
        let result = try builder.build()
        try rootDirectory.createDirectoryIfNeeded()
        try result.string.write(to: rootDirectory.appending(path: "\(machO.imagePath.lastPathComponent)-FileDump.swiftinterface"), atomically: true, encoding: .utf8)

        printNonConsumedSymbols(in: machO)
    }

    func buildFile(in machO: MachOImage) async throws {
        let builder = try SwiftInterfaceBuilder(configuration: .init(isEnabledTypeIndexing: false), eventHandlers: [OSLogEventHandler()], in: machO)
        builder.setupDependencies()
        try await builder.prepare()
        let result = try builder.build()
        try rootDirectory.createDirectoryIfNeeded()
        try result.string.write(to: rootDirectory.appending(path: "\(machO.imagePath.lastPathComponent)-ImageDump.swiftinterface"), atomically: true, encoding: .utf8)

        printNonConsumedSymbols(in: machO)
    }

    func printNonConsumedSymbols<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) {
        @Dependency(\.symbolIndexStore)
        var symbolIndexStore

        if let memberSymbolsByKind = symbolIndexStore.entry(in: machO)?.memberSymbolsByKind {
            for (kind, memberSymbolsByName) in memberSymbolsByKind {
                for (name, memberSymbolsByNode) in memberSymbolsByName {
                    for (node, memberSymbols) in memberSymbolsByNode {
                        for memberSymbol in memberSymbols where !memberSymbol.isConsumed {
                            print("Kind:", kind)
                            print("Name:", name)
                            print("Node:", node.print())
                            print(memberSymbol.wrappedValue.demangledNode)
                            print(memberSymbol.wrappedValue.demangledNode.print())
                            print("---------------------")
                        }
                    }
                }
            }
        }
    }
}

@Suite
enum SwiftInterfaceBuilderTestSuite {
    class DyldCacheTests: MachOTestingSupport.DyldCacheTests, SwiftInterfaceBuilderTests {
        override class var platform: Platform { .macOS }

        override class var cacheImageName: MachOImageName { .SwiftUI }

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
        override class var fileName: XcodeMachOFileName { .sharedFrameworks(.SourceEditor) }

        @Test func buildFile() async throws {
            try await buildFile(in: machOFile)
        }
    }
}
