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
    override class var imageName: MachOImageName { .SwiftUICore }

    private var multiPayloadEnumDescriptorByMangledName: [String: MultiPayloadEnumDescriptor] = [:]

    private var demangleOptions: DemangleOptions = .default

    override init() async throws {
        try await super.init()

        let machO = machOImage
        let descriptors = try machO.swift.multiPayloadEnumDescriptors
        for descriptor in descriptors {
            let inProcessDescriptor = descriptor.asPointerWrapper(in: machO)
            try multiPayloadEnumDescriptorByMangledName[MetadataReader.demangleType(for: inProcessDescriptor.mangledTypeName()).print(using: demangleOptions)] = inProcessDescriptor
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
            guard !typeContextDescriptor.layout.flags.isGeneric else { continue }
            guard case .enum(let enumDescriptor) = typeContextDescriptorWrapper else { continue }
            guard case .enum(let enumMetadata) = try typeContextDescriptor.metadataAccessorFunction()?(request: .init()).value.resolve() else { continue }

            let fieldDescriptor = try typeContextDescriptor.fieldDescriptor()
            let records = try fieldDescriptor.records()
            guard !records.isEmpty else { continue }

            let typeName = try MetadataReader.demangleContext(for: .type(.enum(typeContextDescriptor as! EnumDescriptor))).print(using: demangleOptions)

            print(typeName)
            print("")
            var emptyCases: UInt32 = 0
            var payloadCases: UInt32 = 0
            var payloadSize: UInt64 = 0
            var optionalSize = 0
            defer {
                do {
                    let enumTypeLayout = try enumMetadata.asFullMetadata().valueWitnesses.resolve().typeLayout
                    print(enumTypeLayout)
                    if enumDescriptor.isMultiPayload {
                        if let multiPayloadEnumDescriptor = multiPayloadEnumDescriptorByMangledName[typeName], multiPayloadEnumDescriptor.usesPayloadSpareBits {
                            try printMultiPayloadEnum(multiPayloadEnumDescriptor)
                            let spareBytes = try multiPayloadEnumDescriptor.payloadSpareBits()
                            let spareBytesOffset = try multiPayloadEnumDescriptor.payloadSpareBitMaskByteOffset()
                            try EnumLayoutCalculator.calculateMultiPayload( /* enumSize: enumTypeLayout.size.cast(), */ payloadSize: payloadSize.cast(), spareBytes: spareBytes, spareBytesOffset: spareBytesOffset.cast(), numPayloadCases: payloadCases.cast(), numEmptyCases: emptyCases.cast()).print()
                            if optionalSize > .zero {
                                EnumLayoutCalculator.calculateSinglePayload(size: optionalSize, payloadSize: payloadSize.cast(), numEmptyCases: 1, spareBytes: spareBytes, spareBytesOffset: spareBytesOffset.cast()).print()
                            }
                        } else {
                            EnumLayoutCalculator.calculateTaggedMultiPayload(payloadSize: payloadSize.cast(), numPayloadCases: payloadCases.cast(), numEmptyCases: emptyCases.cast()).print()
                        }
                    } else if enumDescriptor.isSinglePayload {
                        EnumLayoutCalculator.calculateSinglePayload(size: enumTypeLayout.size.cast(), payloadSize: payloadSize.cast(), numEmptyCases: emptyCases.cast()).print()
                    }

                } catch {
                    print(error)
                }
                print("---------------------")
            }
            for record in records {
                let mangledTypeName = try record.mangledTypeName()
                let isIndirectCase = record.flags.contains(.isIndirectCase)
                var indirectCaseString = ""
                if isIndirectCase {
                    indirectCaseString = "indirect "
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
                if let metatype = try RuntimeFunctions.getTypeByMangledNameInContext(mangledTypeName, genericContext: nil, genericArguments: nil) {
                    let currentMetadata = try Metadata.createInProcess(metatype)
                    try print("\(indirectCaseString)case \(record.fieldName())\(payloadString("\(node.print(using: .interfaceTypeBuilderOnly))"))")
                    let metadataWrapper = try currentMetadata.asMetadataWrapper()
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

                    payloadSize = isIndirectCase ? max(payloadSize, 8) : max(payloadSize, typeLayout.size)

                    let optionalMetadata = try Metadata.createInProcess(makeOptionalMetatype(metatype))
                    let optionalTypeLayout = try optionalMetadata.asFullMetadata().valueWitnesses.resolve().typeLayout
                    optionalSize = optionalTypeLayout.size.cast()

                } else {
                    try print("NotFound:", "case", record.fieldName(), mangledTypeNameString, node.print(using: .default))
                }
            }
            print("")
            guard payloadSize != .zero else {
                continue
            }
            print("PayloadSize:", payloadSize)
            print("OptionalSize:", optionalSize)
            print("TagCounts:", getEnumTagCounts(payloadSize: payloadSize, emptyCases: emptyCases, payloadCases: payloadCases))
        }
    }

//    @Test func test() async throws {
////        print(unsafeBitCast((any Equatable).self, to: UnsafeRawPointer.self))
////        try print(ProtocolDescriptor.createInProcess((any Equatable).self).name())
////        for protocolRef in try ExistentialTypeMetadata.createInProcess((any Equatable).self).protocols() {
////            try print(protocolRef.swiftProtocol(), protocolRef.swiftProtocol().name())
////        }
//        try print(RuntimeFunctions.conformsToProtocol(metadata: Int.self, existentialTypeMetadata: (any Equatable).self))
//    }
}

private func makeOptionalMetatype<T>(_ metatype: T.Type) -> Any.Type {
    return T?.self
}

extension String {
    static func * (lhs: Self, rhs: Int) -> Self {
        .init(repeating: lhs, count: rhs)
    }
}

#endif
