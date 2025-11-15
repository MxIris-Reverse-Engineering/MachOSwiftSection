import Foundation
import Testing
@testable import SwiftDump
@testable import MachOTestingSupport

final class MangledTypeNameTests: DyldCacheTests, @unchecked Sendable {
    @Test func fieldRecordMangledTypeNames() async throws {
        let machO = machOFileInMainCache
        let typeContextDescriptors = try machO.swift.typeContextDescriptors
        for typeContextDescriptor in typeContextDescriptors {
            let fieldDescriptor = try typeContextDescriptor.typeContextDescriptor.fieldDescriptor(in: machO)
            let records = try fieldDescriptor.records(in: machO)
            for record in records {
                let mangledTypeName = try record.mangledTypeName(in: machO)
                let node = try MetadataReader.demangleType(for: mangledTypeName, in: machO)
                node.print(using: .interface).print()
                print(node)
                print("---------------------")
            }
        }
    }
}
