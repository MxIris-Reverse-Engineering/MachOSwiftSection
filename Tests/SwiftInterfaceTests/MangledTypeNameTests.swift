import Foundation
import Testing
@testable import Demangling
@testable import MachOSwiftSection
@testable import SwiftDump
@testable import MachOTestingSupport

#if canImport(SwiftUI)

import SwiftUI

final class MangledTypeNameTests: MachOImageTests, @unchecked Sendable {
    override class var imageName: MachOImageName { .SwiftUI }

    @Test func mangledTypeNames() async throws {
        let machO = machOImage
        let typeContextDescriptorWrappers = try machO.swift.typeContextDescriptors
        for typeContextDescriptorWrapper in typeContextDescriptorWrappers {
            guard !typeContextDescriptorWrapper.typeContextDescriptor.layout.flags.isGeneric, typeContextDescriptorWrapper.isEnum else { continue }
            let fieldDescriptor = try typeContextDescriptorWrapper.typeContextDescriptor.fieldDescriptor(in: machO)
            let records = try fieldDescriptor.records(in: machO)
            for record in records {
                let mangledTypeName = try record.mangledTypeName(in: machO)
                guard !mangledTypeName.isEmpty else { continue }
                defer { print("---------------------") }
                if let metatype = _typeByName(mangledTypeName.rawString) {
                    print(metatype)
                    let currentMetadata = try Metadata.createInProcess(metatype)
                    let typeLayout = try currentMetadata.asFullMetadata().valueWitnesses.resolve().typeLayout
                    print(typeLayout)
                } else {
                    let node = try MetadataReader.demangleType(for: mangledTypeName, in: machO)
                    let mangledTypeNameString = try mangleAsString(node)
                    if let metatype = _typeByName(mangledTypeNameString) {
                        print(metatype)
                        let currentMetadata = try Metadata.createInProcess(metatype)
                        let typeLayout = try currentMetadata.asFullMetadata().valueWitnesses.resolve().typeLayout
                        print(typeLayout)

                    } else {
                        print("NotFound:", mangledTypeNameString, node.print(using: .default))
                    }
                }
            }
        }
    }
}

#endif
