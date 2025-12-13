import Foundation
import Testing
import MachOKit
@testable import Demangling
@testable import MachOSwiftSection
@testable import MachOTestingSupport
@testable import SwiftInspection

#if canImport(SwiftUI)

import SwiftUI

final class MultiPayloadEnumTests: MachOImageTests, @unchecked Sendable {
    override class var imageName: MachOImageName { .SwiftUI }

    private var multiPayloadEnumDescriptorByMangledName: [String: MultiPayloadEnumDescriptor] = [:]

    private var demangleOptions: DemangleOptions = .default

    override init() async throws {
        try await super.init()

        let machO = machOImage
        let descriptors = try machO.swift.multiPayloadEnumDescriptors
        for descriptor in descriptors {
            let inProcessDescriptor = descriptor.asPointerWrapper(in: machO)
            try multiPayloadEnumDescriptorByMangledName[MetadataReader.demangleType(for: inProcessDescriptor.typeName()).print(using: demangleOptions)] = inProcessDescriptor
        }
    }

    private func printMultiPayloadEnum(_ descriptor: MultiPayloadEnumDescriptor) throws {
        guard descriptor.usesPayloadSpareBits else { return }
        let offset = try descriptor.payloadSpareBitMaskByteOffset()
        let count = try descriptor.payloadSpareBitMaskByteCount()
        let payloadSpareBits = try descriptor.payloadSpareBits()
        print("SpareBitMaskByteOffset:", offset)
        print("SpareBitMaskByteCount:", count)
        SpareBitAnalyzer.analyze(bytes: payloadSpareBits, startOffset: offset.cast())
    }

    @Test func main() async throws {
        let machO = machOImage
        let typeContextDescriptorWrappers = try machO.swift.typeContextDescriptors
        for typeContextDescriptorWrapper in typeContextDescriptorWrappers {
            let typeContextDescriptor = typeContextDescriptorWrapper.typeContextDescriptor.asPointerWrapper(in: machO)
            guard !typeContextDescriptor.layout.flags.isGeneric, typeContextDescriptorWrapper.isEnum else { continue }

            guard case .enum(let currentMetadata) = try typeContextDescriptor.metadataAccessor()?.perform(request: .init()).value.resolve() else { continue }

            let fieldDescriptor = try typeContextDescriptor.fieldDescriptor()
            let records = try fieldDescriptor.records()
            guard !records.isEmpty else { continue }

            let typeName = try MetadataReader.demangleContext(for: .type(.enum(typeContextDescriptor as! EnumDescriptor))).print(using: demangleOptions)
            guard let multiPayloadEnumDescriptor = multiPayloadEnumDescriptorByMangledName[typeName], multiPayloadEnumDescriptor.usesPayloadSpareBits else { continue }
            print(typeName)
            print("")
            var typeLayouts: [TypeLayout] = []
            var emptyCases: UInt32 = 0
            var payloadCases: UInt32 = 0
            var payloadSize: UInt64 = 0
            defer {
                do {
                    let enumTypeLayout = try currentMetadata.asFullMetadata().valueWitnesses.resolve().typeLayout
                    print(enumTypeLayout)
                    try printMultiPayloadEnum(multiPayloadEnumDescriptor)
                    try EnumLayoutCalculator.calculateMultiPayload( /* enumSize: enumTypeLayout.size.cast(), */ payloadSize: payloadSize.cast(), spareBytes: multiPayloadEnumDescriptor.payloadSpareBits(), spareBytesOffset: multiPayloadEnumDescriptor.payloadSpareBitMaskByteOffset().cast(), numPayloadCases: payloadCases.cast(), numEmptyCases: emptyCases.cast()).print()

                } catch {
                    print(error)
                }
                print("---------------------")
            }
            var hasIndirectCase = false
            for record in records {
                let mangledTypeName = try record.mangledTypeName()

                var indirectCaseString = ""
                if record.flags.contains(.isIndirectCase) {
                    indirectCaseString = "indirect "
                    hasIndirectCase = true
                }
                guard !mangledTypeName.isEmpty else {
                    try print("\(indirectCaseString)case", record.fieldName())
                    emptyCases += 1
                    continue
                }

                defer {
                    payloadCases += 1
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
                    let indentLevel = 1
                    let indent = "    " * indentLevel
                    if let tupleMetadata = metadataWrapper.tuple {
                        for (index, element) in try tupleMetadata.elements().enumerated() {
                            let tupleElementMetadata = try element.type.resolve()
                            if let descriptor = try tupleElementMetadata.typeContextDescriptorWrapper()?.asContextDescriptorWrapper {
                                print(indent + "Index: " + index.description)
                                try print(indent + "Type: " + MetadataReader.demangleContext(for: descriptor).print(using: demangleOptions))
                            }
                            let tupleElementTypeLayout = try tupleElementMetadata.asFullMetadata().valueWitnesses.resolve().typeLayout
                            print(indent + "- " + tupleElementTypeLayout.description)
                        }
                        print(indent + "Total: ")
                    }
                    print(indent + "- " + typeLayout.description)
                    typeLayouts.append(typeLayout)

                } else {
                    try print("NotFound:", "case", record.fieldName(), mangledTypeNameString, node.print(using: .default))
                }
            }
            print("")
            guard !typeLayouts.isEmpty else {
                continue
            }
            payloadSize = hasIndirectCase ? 8 : typeLayouts.map(\.size).max() ?? 0
            print("PayloadSize:", payloadSize)
            print("TagCounts:", getEnumTagCounts(payloadSize: payloadSize, emptyCases: emptyCases, payloadCases: payloadCases))
        }
    }
}

extension String {
    static func * (lhs: Self, rhs: Int) -> Self {
        .init(repeating: lhs, count: rhs)
    }
}

#endif
