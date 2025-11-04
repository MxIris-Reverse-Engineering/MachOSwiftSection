import Foundation
import Testing
@testable import MachOSwiftSection
@testable import MachOTestingSupport

final class TypeMangledNameTests: DyldCacheTests, @unchecked Sendable {
    @Test func typeMangledNames() async throws {
        let machO = machOFileInMainCache
        for type in try machO.swift.typeContextDescriptors {
            let node = try MetadataReader.demangleContext(for: .type(type), in: machO)
//            node.description.print()
//            node.print().print()
            if let privateDeclName = node.first(of: .privateDeclName) {
                privateDeclName.print().print()
                "------------------------------".print()
            }
        }

        for proto in try machO.swift.protocolDescriptors {
            let node = try MetadataReader.demangleContext(for: .protocol(proto), in: machO)
//            node.description.print()
//            node.print().print()
            if let privateDeclName = node.first(of: .privateDeclName) {
                privateDeclName.print().print()
                "------------------------------".print()
            }
        }
    }
}
