import Foundation
import Testing
@testable import MachOSwiftSection
@testable import MachOTestingSupport

final class SymbolIndexStoreTests: DyldCacheTests {
    
    @Test func memberSymbols() async throws {
        let memberSymbols = SymbolIndexStore.shared.memberSymbols(of: .staticVariableInExtension, in: machOFileInMainCache)
        for memberSymbol in memberSymbols {
            memberSymbol.demangledNode.print(using: .default).print()
            memberSymbol.demangledNode.description.print()
            print("----------------------------")
        }
    }
    
}
