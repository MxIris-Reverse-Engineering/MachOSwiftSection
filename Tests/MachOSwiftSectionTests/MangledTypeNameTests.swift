import Foundation
import Testing
@testable import SwiftDump
@testable import MachOTestingSupport
import Demangling

final class MangledTypeNameTests: DyldCacheTests, @unchecked Sendable {
    @Test func fieldRecordMangledTypeNames() async throws {
        let machO = machOFileInMainCache
        let typeContextDescriptors = try machO.swift.typeContextDescriptors
        for typeContextDescriptor in typeContextDescriptors {
            guard !typeContextDescriptor.typeContextDescriptor.layout.flags.isGeneric else { continue }
            let fieldDescriptor = try typeContextDescriptor.typeContextDescriptor.fieldDescriptor(in: machO)
            let records = try fieldDescriptor.records(in: machO)
            for record in records {
                let mangledTypeName = try record.mangledTypeName(in: machO)
                if let metadata = _typeByName(mangledTypeName.rawString) {
                    print(metadata)
                } else {
                    let node = try MetadataReader.demangleType(for: mangledTypeName, in: machO)
                    let mangledTypeNameString = try mangleAsString(node)
                    if let metadata = _typeByName(mangledTypeNameString) {
                        print(metadata)
                    } else {
                        print("NotFound:", mangledTypeNameString, node.print(using: .default))
                    }
                }

                print("---------------------")
            }
        }
    }
}
