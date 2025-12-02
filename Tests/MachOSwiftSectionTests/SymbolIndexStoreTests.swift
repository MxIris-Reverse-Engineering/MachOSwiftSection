import Foundation
import Testing
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import Dependencies
@_private(sourceFile: "SymbolIndexStore.swift") @_spi(Internals) import MachOSymbols
@_spi(Internals) import MachOCaches

final class SymbolIndexStoreTests: DyldCacheTests, @unchecked Sendable {
    override class var cacheImageName: MachOImageName { .SwiftUICore }

    @Dependency(\.symbolIndexStore)
    var symbolIndexStore

//    @Test func memberSymbols() async throws {
//        let memberSymbols = SymbolIndexStore.shared.memberSymbols(of: .variableInExtension, in: machOFileInMainCache)
//        for memberSymbol in memberSymbols {
//            memberSymbol.demangledNode.print(using: .default).print()
//            memberSymbol.demangledNode.description.print()
//            print("----------------------------")
//        }
//    }
//
//
//    @Test func dependentGenericSignature() async throws {
//        for symbol in SymbolIndexStore.shared.memberSymbols(of: .allocatorInExtension, .variableInExtension, .functionInExtension, .staticVariableInExtension, .staticFunctionInExtension, in: machOFileInMainCache) {
//            guard let identifier = symbol.demangledNode.identifier else { continue }
//            guard let dependentGenericSignature = symbol.demangledNode.first(of: .dependentGenericSignature) else { continue }
//            identifier.print()
//            dependentGenericSignature.print(using: .default).print()
//            let nodes = dependentGenericSignature.all(of: .requirementKinds)
//            for node in nodes {
//                node.print(using: .default).print()
//                node.description.print()
//            }
//            print("----------------------------")
//        }
//    }

    @Test func globalSymbols() async throws {
        let symbols = symbolIndexStore.globalSymbols(of: .function, in: machOFileInCache)
        for symbol in symbols {
            symbol.demangledNode.print(using: .default).print()
            symbol.demangledNode.description.print()
            print("----------------------------")
        }
    }

    @Test func symbols() async throws {
        let clock = ContinuousClock()
        let machO = machOFileInCache
        let duration = clock.measure {
            _ = symbolIndexStore.allSymbols(in: machO)
        }
        print(duration)
        guard let memberSymbolsByKind = symbolIndexStore.entry(in: machO)?.memberSymbolsByKind else {
            return
        }
        for (kind, memberSymbolsByName) in memberSymbolsByKind {
            print("Kind: ", kind.description)
            for (name, memberSymbolsByNode) in memberSymbolsByName {
                print("Name: ", name)
                for (node, _) in memberSymbolsByNode {
                    print("Node: ")
                    print(node)
                    print(node.print())
                }
            }
            print("---------------------")
        }
    }
}
