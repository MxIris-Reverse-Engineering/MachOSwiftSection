import Foundation
import Testing
@testable import MachOSwiftSection
@testable import MachOTestingSupport

final class TypeMangledNameTests: DyldCacheTests {
    @Test func typeMangledNames() async throws {
        let machO = machOFileInMainCache
        for type in try machO.swift.typeContextDescriptors {
            let node = try MetadataReader.demangleContext(for: .type(type), in: machO)
            node.description.print()
            node.print().print()
            "------------------------------".print()
        }
    }
}
