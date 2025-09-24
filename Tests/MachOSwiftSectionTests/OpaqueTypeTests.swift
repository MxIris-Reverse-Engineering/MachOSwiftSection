import Foundation
import Testing
import Demangle
@testable import MachOTestingSupport
import MachOSwiftSection
@testable import SwiftDump

final class OpaqueTypeTests: MachOFileTests {
    override class var fileName: MachOFileName { .SymbolTestsCore }

    @Test func opaqueTypes() async throws {
        let machO = machOFile
        let symbols = SymbolIndexStore.shared.symbols(of: .opaqueTypeDescriptor, in: machO)
        for symbol in symbols {
            let opaqueTypeDescriptor = try OpaqueTypeDescriptor.resolve(from: symbol.offset, in: machO)
            let opaqueType = try OpaqueType(descriptor: opaqueTypeDescriptor, in: machO)
            if let genericContext = opaqueType.genericContext {
                for requirement in genericContext.requirements {
                    try requirement.dump(using: .default, in: machO).string.print()
                }
            }
            for underlyingTypeArgumentMangledName in opaqueType.underlyingTypeArgumentMangledNames {
                let node = try MetadataReader.demangleType(for: underlyingTypeArgumentMangledName, in: machO)
                node.print(using: .interface).print()
            }
            print("--------------------")
        }
    }
}
