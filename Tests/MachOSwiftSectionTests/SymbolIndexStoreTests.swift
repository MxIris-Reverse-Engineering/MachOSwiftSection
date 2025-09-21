import Foundation
import Testing
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import Dependencies

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
}
