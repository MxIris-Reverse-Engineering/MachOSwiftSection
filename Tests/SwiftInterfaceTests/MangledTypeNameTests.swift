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
            let typeContextDescriptor = typeContextDescriptorWrapper.typeContextDescriptor.asPointerWrapper(in: machO)
            guard !typeContextDescriptor.layout.flags.isGeneric, typeContextDescriptorWrapper.isEnum else { continue }
            let fieldDescriptor = try typeContextDescriptor.fieldDescriptor()
            let records = try fieldDescriptor.records()
            
            var typeLayouts: [TypeLayout] = []
            
            for record in records {
                let mangledTypeName = try record.mangledTypeName()
                guard !mangledTypeName.isEmpty else { continue }
                defer { print("---------------------") }
                if let metatype = _typeByName(mangledTypeName.rawString) {
                    print(metatype)
                    let currentMetadata = try Metadata.createInProcess(metatype)
                    let typeLayout = try currentMetadata.asFullMetadata().valueWitnesses.resolve().typeLayout
                    print(typeLayout)
                    typeLayouts.append(typeLayout)
                } else {
                    let node = try MetadataReader.demangleType(for: mangledTypeName)
                    let mangledTypeNameString = try mangleAsString(node)
                    if let metatype = _typeByName(mangledTypeNameString) {
                        print(metatype)
                        let currentMetadata = try Metadata.createInProcess(metatype)
                        let typeLayout = try currentMetadata.asFullMetadata().valueWitnesses.resolve().typeLayout
                        print(typeLayout)
                        typeLayouts.append(typeLayout)
                    } else {
                        print("NotFound:", mangledTypeNameString, node.print(using: .default))
                    }
                }
            }
            
            let payloadSize = typeLayouts.reduce(0) { $0 + $1.size }
            print("PayloadSize:", payloadSize)
        }
    }
}

#endif
