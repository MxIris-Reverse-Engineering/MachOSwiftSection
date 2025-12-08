import Foundation
import Testing
@testable import Demangling
@testable import MachOSwiftSection
@testable import SwiftDump
@testable import MachOTestingSupport
@testable import SwiftInspection

#if canImport(SwiftUI)

import SwiftUI
@testable @_spi(Support) import SwiftInterface

final class MangledTypeNameTests: MachOImageTests, @unchecked Sendable {
    override class var imageName: MachOImageName { .SwiftUICore }

    @Test func multiPayloadEnums() async throws {
        let machO = machOImage
        let descriptors = try machO.swift.multiPayloadEnumDescriptors
        for descriptor in descriptors {
            try print(MetadataReader.demangleType(for: descriptor.typeName(in: machO), in: machO).print())
            let offset = try descriptor.payloadSpareBitMaskByteOffset(in: machO)
            let count = try descriptor.payloadSpareBitMaskByteCount(in: machO)
            let payloadSpareBits = try descriptor.payloadSpareBits(in: machO)
            let bitMask = BitMask(bytes: payloadSpareBits)
            print("offset:", offset)
            print("count:", count)
            print("numBits:", bitMask.numBits, "numSetBits:", bitMask.numSetBits, "numZeroBits:", bitMask.numZeroBits)
        }
    }

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
            print("")
            defer {
                try? print(currentMetadata.asFullMetadata().valueWitnesses.resolve().typeLayout)
                print("---------------------")
            }

            var typeLayouts: [TypeLayout] = []
            var emptyCases: UInt32 = 0
            for record in records {
                let mangledTypeName = try record.mangledTypeName()

                var indirectCaseString = ""
                var isIndirectCase = false
                if record.flags.contains(.isIndirectCase) {
                    indirectCaseString = "indirect "
                    isIndirectCase = true
                }
                guard !mangledTypeName.isEmpty else {
                    try print("\(indirectCaseString)case", record.fieldName())
                    emptyCases += 1
                    continue
                }

                let node = try MetadataReader.demangleType(for: mangledTypeName)
                var isTuplePayload = false
                if node.firstChild?.isKind(of: .tuple) ?? false {
                    isTuplePayload = true
                }

                func payloadString(_ payloadType: String) -> String {
                    if isTuplePayload {
                        return "\(payloadType)"
                    } else {
                        return "(\(payloadType))"
                    }
                }

                let mangledTypeNameString = try mangleAsString(node)
                if let metatype = try _getTypeByMangledNameInContext(mangledTypeName, genericContext: nil, genericArguments: nil) {
                    let currentMetadata = try Metadata.createInProcess(metatype)
                    try print("\(indirectCaseString)case \(record.fieldName())\(payloadString("\(node.print(using: .interfaceTypeBuilderOnly))"))")
                    let metadataWrapper = try currentMetadata.metadataWrapper()
                    let typeLayout = try currentMetadata.asFullMetadata().valueWitnesses.resolve().typeLayout
                    if let tupleMetadata = metadataWrapper.tuple {
                        for element in try tupleMetadata.elements() {
                            let tupleElementMetadata = try element.type.resolve()
                            if let descriptor = try tupleElementMetadata.typeContextDescriptorWrapper()?.asContextDescriptorWrapper {
                                try print("   ", MetadataReader.demangleContext(for: descriptor).print(using: .default))
                            }
                            let tupleElementTypeLayout = try tupleElementMetadata.asFullMetadata().valueWitnesses.resolve().typeLayout
                            print("   -", tupleElementTypeLayout)
                        }
                        print("")
                    }
                    print("   -", typeLayout)
                    if !isIndirectCase {
                        typeLayouts.append(typeLayout)
                    }
                } else {
                    try print("NotFound:", "case", record.fieldName(), mangledTypeNameString, node.print(using: .default))
                }
            }
            print("")
            guard !typeLayouts.isEmpty else {
                continue
            }
            let payloadSize = typeLayouts.map(\.size).max() ?? 0
            print("PayloadSize:", payloadSize)
            print("TagCounts:", getEnumTagCounts(payloadSize: payloadSize, emptyCases: emptyCases, payloadCases: typeLayouts.count.uint32))
        }
    }
}

#endif
