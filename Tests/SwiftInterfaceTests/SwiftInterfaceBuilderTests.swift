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
        let builder = try SwiftInterfaceBuilder(configuration: .init(), eventHandlers: [], in: machO)
        let clock = ContinuousClock()
        let duration = try await clock.measure {
            try await builder.prepare()
        }
        print(duration)
        let result = try await builder.printRoot()
        try rootDirectory.createDirectoryIfNeeded()
        try result.string.write(to: rootDirectory.appending(path: "\(machO.imagePath.lastPathComponent)-FileDump.swiftinterface"), atomically: true, encoding: .utf8)

//        printNonConsumedSymbols(in: machO)
    }

    func buildFile(in machO: MachOImage) async throws {
        let builder = try SwiftInterfaceBuilder(configuration: .init(), eventHandlers: [], in: machO)
        let clock = ContinuousClock()
        let duration = try await clock.measure {
            try await builder.prepare()
        }
        print(duration)
        let result = try await builder.printRoot()
        try rootDirectory.createDirectoryIfNeeded()
        try result.string.write(to: rootDirectory.appending(path: "\(machO.imagePath.lastPathComponent)-ImageDump.swiftinterface"), atomically: true, encoding: .utf8)

//        printNonConsumedSymbols(in: machO)
    }

    func printNonConsumedSymbols<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) {
        @Dependency(\.symbolIndexStore)
        var symbolIndexStore

        if let memberSymbolsByKind = symbolIndexStore.entry(in: machO)?.memberSymbolsByKind {
            for (kind, memberSymbolsByName) in memberSymbolsByKind {
                for (name, memberSymbolsByNode) in memberSymbolsByName {
                    for (node, memberSymbols) in memberSymbolsByNode {
                        for memberSymbol in memberSymbols where !memberSymbol.isConsumed {
                            "Kind: \(kind.print())".print()
                            "Name: \(name.print())".print()
                            "Node: \(node.print())".print()
                            memberSymbol.wrappedValue.demangledNode.print().print()
                            memberSymbol.wrappedValue.demangledNode.description.print()
                            "---------------------".print()
                        }
                    }
                }
            }
        }
    }
}

@Suite
enum SwiftInterfaceBuilderTestSuite {
    class DyldCacheTests: MachOTestingSupport.DyldCacheTests, SwiftInterfaceBuilderTests, @unchecked Sendable {
        override class var platform: Platform { .macOS }

        override class var cacheImageName: MachOImageName { .SwiftUI }

        override class var cachePath: DyldSharedCachePath { .current }

        @Test func buildFile() async throws {
            try await buildFile(in: machOFileInCache)
        }
    }

    class MachOFileTests: MachOTestingSupport.MachOFileTests, SwiftInterfaceBuilderTests, @unchecked Sendable {
        override class var fileName: MachOFileName { .SymbolTestsCore }

        @Test func buildFile() async throws {
            try await buildFile(in: machOFile)
        }
    }

    class MachOImageTests: MachOTestingSupport.MachOImageTests, SwiftInterfaceBuilderTests, @unchecked Sendable {
        override class var imageName: MachOImageName { .SwiftUI }

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
