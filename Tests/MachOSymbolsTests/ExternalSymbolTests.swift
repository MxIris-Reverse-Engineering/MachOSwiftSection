import Foundation
import Testing
@testable import MachOSwiftSection
@testable import MachOTestingSupport

final class ExternalSymbolTests: MachOFileTests, @unchecked Sendable {
    override class var fileName: MachOFileName { .iOS_18_5_Simulator_SwiftUI }

    @Test func machOSections() async throws {
        for symbol in machOFile.symbols where symbol.nlist.isExternal && symbol.name.isSwiftSymbol {
            let demangledNode = try symbol.demangledNode
            demangledNode.print(using: .default).print()
            demangledNode.description.print()
            "-----------------------------".print()
        }
    }
}
