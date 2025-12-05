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

            guard case .enum(let currentMetadata) = try typeContextDescriptor.metadataAccessor()?.perform(request: .init()).value.resolve() else { continue }

            let fieldDescriptor = try typeContextDescriptor.fieldDescriptor()
            let records = try fieldDescriptor.records()
            guard !records.isEmpty else { continue }

            try print(MetadataReader.demangleContext(for: .type(.enum(typeContextDescriptor as! EnumDescriptor))).print(using: .default))
            
            defer {
                try? print("TypeSize:", currentMetadata.asFullMetadata().valueWitnesses.resolve().typeLayout)
                print("---------------------")
            }
            
            var typeLayouts: [TypeLayout] = []
            for record in records {
                let mangledTypeName = try record.mangledTypeName()
                guard !mangledTypeName.isEmpty else { continue }
                if let metatype = _typeByName(mangledTypeName.rawString) {
                    try print("case", record.fieldName(), metatype)
                    let currentMetadata = try Metadata.createInProcess(metatype)
                    let typeLayout = try currentMetadata.asFullMetadata().valueWitnesses.resolve().typeLayout
                    print("   -\(typeLayout)")
                    typeLayouts.append(typeLayout)
                } else {
                    let node = try MetadataReader.demangleType(for: mangledTypeName)
                    let mangledTypeNameString = try mangleAsString(node)
                    if let metatype = _typeByName(mangledTypeNameString) {
                        try print("case", record.fieldName(), metatype)
                        let currentMetadata = try Metadata.createInProcess(metatype)
                        let typeLayout = try currentMetadata.asFullMetadata().valueWitnesses.resolve().typeLayout
                        print("   -\(typeLayout)")
                        typeLayouts.append(typeLayout)
                    } else {
                        try print("NotFound:", "case", record.fieldName(), mangledTypeNameString, node.print(using: .default))
                    }
                }
            }
            guard !typeLayouts.isEmpty else {
                continue
            }
            let payloadSize = typeLayouts.map(\.size).max() ?? 0
            print("PayloadSize:", payloadSize)
            
        }
    }
}

#endif
