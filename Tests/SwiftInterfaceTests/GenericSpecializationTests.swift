import Foundation
import Testing
import MachOKit
import Dependencies
@_spi(Internals) import MachOSymbols
@_spi(Internals) import MachOCaches
@_spi(Support) @testable import SwiftInterface
@testable import MachOSwiftSection
@testable import MachOTestingSupport
@testable import SwiftDump
@testable import SwiftInspection
@testable import Demangling
import OrderedCollections

struct TestGenericStruct<A, B, C> where A: Collection, B: Equatable, C: Hashable, A.Element: Hashable, A.Element: Decodable, A.Element: Encodable {
    let a: A
    let b: B
    let c: C
}

final class GenericSpecializationTests: MachOImageTests, @unchecked Sendable {
    override class var imageName: MachOImageName { .SwiftUICore }

    @Test func main() async throws {
        let machO = MachOImage.current()

        let indexer = SwiftInterfaceIndexer(in: machO)

        try indexer.addSubIndexer(SwiftInterfaceIndexer(in: #require(MachOImage(name: "Foundation"))))
        try indexer.addSubIndexer(SwiftInterfaceIndexer(in: #require(MachOImage(name: "libswiftCore"))))

        try await indexer.prepare()

        let descriptor = try #require(try machO.swift.typeContextDescriptors.first { try $0.struct?.name(in: machO) == "TestGenericStruct" }?.struct)

        let genericContext = try #require(try descriptor.genericContext(in: machO))

        #expect(genericContext.header.numKeyArguments == 9)

        let AMetatype = [Int].self
        let AProtocol = (any Collection).self

        let BMetatype = Double.self
        let BProtocol = (any Equatable).self

        let CMetatype = Data.self
        let CProtocol = (any Hashable).self

        let AMetadata = try Metadata.createInProcess(AMetatype)
        let BMetadata = try Metadata.createInProcess(BMetatype)
        let CMetadata = try Metadata.createInProcess(CMetatype)

        let associatedTypeWitnesses = try await indexer.resolveAssociatedTypeWitnesses(for: .struct(descriptor), substituting: [
            "A": AMetadata,
            "B": BMetadata,
            "C": CMetadata,
        ], in: machO)

        let metadataAccessorFunction = try #require(try descriptor.asPointerWrapper(in: machO).metadataAccessorFunction())
        let metadata = try metadataAccessorFunction(
            request: .completeAndBlocking, metadatas: [
                AMetadata,
                BMetadata,
                CMetadata,
            ], witnessTables: [
                #require(try RuntimeFunctions.conformsToProtocol(metatype: AMetatype, protocolType: AProtocol)),
                #require(try RuntimeFunctions.conformsToProtocol(metatype: BMetatype, protocolType: BProtocol)),
                #require(try RuntimeFunctions.conformsToProtocol(metatype: CMetatype, protocolType: CProtocol)),
            ] + associatedTypeWitnesses.values.flatMap { $0 }
        )
        try #expect(#require(metadata.value.resolve().struct).fieldOffsets() == [0, 8, 16])
    }
}

extension SwiftInterfaceIndexer {
    enum AssociatedTypeResolutionError: LocalizedError {
        case missingGenericContext(typeDescriptor: TypeContextDescriptorWrapper)
        case unsupportedGenericParameter(parameterKind: GenericParamKind)
        case missingDependentGenericParamType(dependentMemberType: Node)
        case missingGenericParamTypeText(dependentGenericParamType: Node)
        case missingConformingTypeMetadata(genericParam: String, availableParams: [String])
        case missingDependentAssociatedTypeRef(dependentMemberType: Node)
        case missingAssociatedTypeName(dependentAssociatedTypeRef: Node)
        case missingAssociatedTypeRefProtocolTypeNode(dependentAssociatedTypeRef: Node)
        case missingAssociatedTypeRefMachOAndProtocol(protocolTypeNode: Node)
        case associatedTypeRefMachONotMachOImage(machOType: String)
        case failedToCreateAssociatedTypeRefProtocol(underlyingError: Error)
        case missingAssociatedTypeIndex(associatedTypeName: String, protocolName: ProtocolName, availableAssociatedTypes: [String])
        case missingAssociatedTypeBaseRequirement(protocolName: ProtocolName)
        case missingAssociatedTypeAccessFunctionRequirement(index: Int, protocolName: ProtocolName, requirementCount: Int)
        case conformingTypeDoesNotConformToProtocol(conformingType: Metadata, protocolName: ProtocolName)
        case failedToGetAssociatedTypeWitness(conformingType: Metadata, protocolName: ProtocolName, associatedTypeName: String)
        case associatedTypeDoesNotConformToProtocol(associatedType: Metadata, protocolName: ProtocolName)
        case unknownParamNodeStructure(paramNode: Node)

        var errorDescription: String? {
            switch self {
            case .missingGenericContext(let typeDescriptor):
                return "Missing generic context for type descriptor: \(typeDescriptor)"
            case .unsupportedGenericParameter(let parameterKind):
                return "Unsupported generic parameter kind: \(parameterKind)"
            case .missingDependentGenericParamType(let dependentMemberType):
                return "Missing dependent generic param type in dependent member type: \(dependentMemberType)"
            case .missingGenericParamTypeText(let dependentGenericParamType):
                return "Missing text in dependent generic param type: \(dependentGenericParamType)"
            case .missingConformingTypeMetadata(let genericParam, let availableParams):
                return "Missing conforming type metadata for generic param '\(genericParam)'. Available params: \(availableParams.joined(separator: ", "))"
            case .missingDependentAssociatedTypeRef(let dependentMemberType):
                return "Missing dependent associated type ref in dependent member type: \(dependentMemberType)"
            case .missingAssociatedTypeName(let dependentAssociatedTypeRef):
                return "Missing associated type name in dependent associated type ref: \(dependentAssociatedTypeRef)"
            case .missingAssociatedTypeRefProtocolTypeNode(let dependentAssociatedTypeRef):
                return "Missing protocol type node in dependent associated type ref: \(dependentAssociatedTypeRef)"
            case .missingAssociatedTypeRefMachOAndProtocol(let protocolTypeNode):
                return "Missing MachO and protocol definition for protocol type node: \(protocolTypeNode)"
            case .associatedTypeRefMachONotMachOImage(let machOType):
                return "Associated type ref MachO is not MachOImage, actual type: \(machOType)"
            case .failedToCreateAssociatedTypeRefProtocol(let underlyingError):
                return "Failed to create associated type ref protocol: \(underlyingError.localizedDescription)"
            case .missingAssociatedTypeIndex(let associatedTypeName, let protocolName, let availableAssociatedTypes):
                return "Associated type '\(associatedTypeName)' not found in protocol '\(protocolName.name)'. Available associated types: \(availableAssociatedTypes.joined(separator: ", "))"
            case .missingAssociatedTypeBaseRequirement(let protocolName):
                return "Missing base requirement for protocol '\(protocolName.name)'"
            case .missingAssociatedTypeAccessFunctionRequirement(let index, let protocolName, let requirementCount):
                return "Missing associated type access function requirement at index \(index) for protocol '\(protocolName.name)'. Total requirements: \(requirementCount)"
            case .conformingTypeDoesNotConformToProtocol(let conformingType, let protocolName):
                return "Conforming type '\(conformingType)' does not conform to protocol '\(protocolName.name)'"
            case .failedToGetAssociatedTypeWitness(let conformingType, let protocolName, let associatedTypeName):
                return "Failed to get associated type witness for '\(associatedTypeName)' from conforming type '\(conformingType)' to protocol '\(protocolName.name)'"
            case .associatedTypeDoesNotConformToProtocol(let associatedType, let protocolName):
                return "Associated type '\(associatedType)' does not conform to protocol '\(protocolName.name)'"
            case .unknownParamNodeStructure(let paramNode):
                return "Unknown param node structure: \(paramNode)"
            }
        }
    }

    func resolveAssociatedTypeWitnesses(for type: TypeContextDescriptorWrapper, substituting genericArguments: [String: Metadata], in machO: MachOImage) async throws -> OrderedDictionary<Metadata, [ProtocolWitnessTable]> {
        typealias Result = OrderedDictionary<Metadata, [ProtocolWitnessTable]>
        var results: Result = [:]
        guard let genericContextInProcess = try type.asPointerWrapper(in: machO).genericContext() else {
            throw AssociatedTypeResolutionError.missingGenericContext(typeDescriptor: type)
        }

        if let unsupportedParameter = genericContextInProcess.parameters.first(where: { $0.kind == .typePack || $0.kind == .value }) {
            throw AssociatedTypeResolutionError.unsupportedGenericParameter(parameterKind: unsupportedParameter.kind)
        }

        let requirements = try genericContextInProcess.requirements.map { try GenericRequirement(descriptor: $0) }
        var conformingTypeMetadataByGenericParam: [String: Metadata] = [:]
        let allProtocolDefinitions = allAllProtocolDefinitions

        for requirement in requirements {
            guard let requirementProtocolDescriptor = requirement.content.protocol?.resolved, let protocolDescriptor = requirementProtocolDescriptor.swift, requirement.flags.contains(.hasKeyArgument) else { continue }

            let requirementProtocol = try Protocol(descriptor: protocolDescriptor)

            let paramNode = try MetadataReader.demangleType(for: requirement.paramManagledName)

            if let dependentMemberType = paramNode.first(of: .dependentMemberType) {
                guard let dependentGenericParamType = dependentMemberType.first(of: .dependentGenericParamType) else {
                    throw AssociatedTypeResolutionError.missingDependentGenericParamType(dependentMemberType: dependentMemberType)
                }

                guard let genericParamType = dependentGenericParamType.text else {
                    throw AssociatedTypeResolutionError.missingGenericParamTypeText(dependentGenericParamType: dependentGenericParamType)
                }

                guard let conformingTypeMetadata = conformingTypeMetadataByGenericParam[genericParamType] else {
                    throw AssociatedTypeResolutionError.missingConformingTypeMetadata(genericParam: genericParamType, availableParams: Array(conformingTypeMetadataByGenericParam.keys))
                }

                guard let dependentAssociatedTypeRef = dependentMemberType.first(of: .dependentAssociatedTypeRef) else {
                    throw AssociatedTypeResolutionError.missingDependentAssociatedTypeRef(dependentMemberType: dependentMemberType)
                }

                guard let associatedTypeName = dependentAssociatedTypeRef.children.first?.text else {
                    throw AssociatedTypeResolutionError.missingAssociatedTypeName(dependentAssociatedTypeRef: dependentAssociatedTypeRef)
                }

                guard let associatedTypeRefProtocolTypeNode = dependentAssociatedTypeRef.children.second else {
                    throw AssociatedTypeResolutionError.missingAssociatedTypeRefProtocolTypeNode(dependentAssociatedTypeRef: dependentAssociatedTypeRef)
                }

                guard let associatedTypeRefMachOAndProtocol = allProtocolDefinitions[.init(node: associatedTypeRefProtocolTypeNode)] else {
                    throw AssociatedTypeResolutionError.missingAssociatedTypeRefMachOAndProtocol(protocolTypeNode: associatedTypeRefProtocolTypeNode)
                }

                guard let associatedTypeRefMachOImage = associatedTypeRefMachOAndProtocol.machO as? MachOImage else {
                    throw AssociatedTypeResolutionError.associatedTypeRefMachONotMachOImage(machOType: String(describing: Swift.type(of: associatedTypeRefMachOAndProtocol.machO)))
                }

                let associatedTypeRefProtocol: MachOSwiftSection.`Protocol`
                do {
                    associatedTypeRefProtocol = try MachOSwiftSection.`Protocol`(descriptor: associatedTypeRefMachOAndProtocol.value.protocol.descriptor.asPointerWrapper(in: associatedTypeRefMachOImage))
                } catch {
                    throw AssociatedTypeResolutionError.failedToCreateAssociatedTypeRefProtocol(underlyingError: error)
                }

                let associatedTypeRefProtocolName = try associatedTypeRefProtocol.protocolName()
                let availableAssociatedTypes = try associatedTypeRefProtocol.descriptor.associatedTypes()

                guard let associatedTypeIndex = availableAssociatedTypes.firstIndex(of: associatedTypeName) else {
                    throw AssociatedTypeResolutionError.missingAssociatedTypeIndex(associatedTypeName: associatedTypeName, protocolName: associatedTypeRefProtocolName, availableAssociatedTypes: availableAssociatedTypes)
                }

                guard let associatedTypeBaseRequirement = associatedTypeRefProtocol.baseRequirement else {
                    throw AssociatedTypeResolutionError.missingAssociatedTypeBaseRequirement(protocolName: associatedTypeRefProtocolName)
                }

                let associatedTypeAccessFunctionRequirements = associatedTypeRefProtocol.requirements.filter { $0.flags.kind.isAssociatedTypeAccessFunction }

                guard let associatedTypeAccessFunctionRequirement = associatedTypeAccessFunctionRequirements[safe: associatedTypeIndex] else {
                    throw AssociatedTypeResolutionError.missingAssociatedTypeAccessFunctionRequirement(index: associatedTypeIndex, protocolName: associatedTypeRefProtocolName, requirementCount: associatedTypeAccessFunctionRequirements.count)
                }

                guard let conformingTypePWT = try RuntimeFunctions.conformsToProtocol(metadata: conformingTypeMetadata, protocolDescriptor: associatedTypeRefProtocol.descriptor) else {
                    throw AssociatedTypeResolutionError.conformingTypeDoesNotConformToProtocol(conformingType: conformingTypeMetadata, protocolName: associatedTypeRefProtocolName)
                }

                guard let associatedTypeMetadata = try? RuntimeFunctions.getAssociatedTypeWitness(request: .init(), protocolWitnessTable: conformingTypePWT, conformingTypeMetadata: conformingTypeMetadata, baseRequirement: associatedTypeBaseRequirement, associatedTypeRequirement: associatedTypeAccessFunctionRequirement).value.resolve().metadata else {
                    throw AssociatedTypeResolutionError.failedToGetAssociatedTypeWitness(conformingType: conformingTypeMetadata, protocolName: associatedTypeRefProtocolName, associatedTypeName: associatedTypeName)
                }

                let currentProtocolName = try requirementProtocol.protocolName()

                guard let associatedTypePWT = try? RuntimeFunctions.conformsToProtocol(metadata: associatedTypeMetadata, protocolDescriptor: requirementProtocol.descriptor) else {
                    throw AssociatedTypeResolutionError.associatedTypeDoesNotConformToProtocol(associatedType: associatedTypeMetadata, protocolName: currentProtocolName)
                }

                results[associatedTypeMetadata, default: []].append(associatedTypePWT)
            } else if let dependentGenericParamType = paramNode.first(of: .dependentGenericParamType) {
                guard let genericParamType = dependentGenericParamType.text else {
                    throw AssociatedTypeResolutionError.missingGenericParamTypeText(dependentGenericParamType: dependentGenericParamType)
                }

                guard let conformingTypeMetadata = genericArguments[genericParamType] else {
                    throw AssociatedTypeResolutionError.missingConformingTypeMetadata(genericParam: genericParamType, availableParams: Array(genericArguments.keys))
                }

                conformingTypeMetadataByGenericParam[genericParamType] = conformingTypeMetadata
            } else {
                throw AssociatedTypeResolutionError.unknownParamNodeStructure(paramNode: paramNode)
            }
        }

        return results
    }
}

extension OptionSet {
    func removing(_ current: Self.Element) -> Self {
        var copy = self
        copy.remove(current)
        return copy
    }
}

// let conformingTypesByProtocolName = currentIndexer.allConformingTypesByProtocolName
// let allTypeDefinitions = currentIndexer.allAllTypeDefinitions
//
// for typeWrapper in try machO.swift.types {
//     switch typeWrapper {
//     case .enum (let type):
//         continue
//     case .struct(let type):
//         guard let genericContextInProcess = try type.descriptor.asPointerWrapper(in: machO).genericContext() else { continue }
//         guard let genericContextInMachO = try type.descriptor.genericContext(in: machO) else { continue }
//         guard !genericContextInProcess.parameters.contains(where: { $0.kind == .typePack || $0.kind == .value }) else { continue }
//
// //                let typeName = try MetadataReader.demangleContext(for: .type(.struct(type.descriptor)), in: machO).print(using: .default).string
// //                typeName.print()
//
//         let requirements = try genericContextInProcess.requirements.map { try GenericRequirement(descriptor: $0) }
//         var conformingTypeByGenericParam: [String: TypeContextWrapper] = [:]
//         var conformancedProtocolsByGenericParam: [String: [MachOSwiftSection.`Protocol`]] = [:]
//
//         for requirement in requirements {
//             guard let requirementProtocol = requirement.content.protocol?.resolved, let protocolDescriptor = requirementProtocol.swift else { continue }
//
//             let proto = try Protocol(descriptor: protocolDescriptor)
//
//             let paramNode = try MetadataReader.demangleType(for: requirement.paramManagledName)
// //                    paramNode.description.print()
//             if let dependentMemberType = paramNode.first(of: .dependentMemberType) {
//                 if let dependentGenericParamType = dependentMemberType.first(of: .dependentGenericParamType),
//                    let genericParamType = dependentGenericParamType.text,
//                    let conformingType = conformingTypeByGenericParam[genericParamType],
//                    let associatedType = dependentMemberType.first(of: .dependentAssociatedTypeRef)?.first(of: .identifier)?.text,
//                    let (associatedTypeIndex, conformancedProtocol) = try conformancedProtocolsByGenericParam[genericParamType]?.firstNonNil({ proto in try proto.descriptor.associatedTypes().firstIndex(of: associatedType).map { ($0, proto) } }) {
//                     if let baseRequirement = conformancedProtocol.baseRequirement,
//                        let associatedTypeRequirement = conformancedProtocol.requirements.filter({ $0.flags.kind.isAssociatedTypeAccessFunction })[safe: associatedTypeIndex],
//                        let conformingTypeMetadata = try conformingType.typeContextDescriptorWrapper.typeContextDescriptor.metadataAccessorFunction()?(request: .init()).value.resolve().metadata,
//                        let pwt = try RuntimeFunctions.conformsToProtocol(metadata: conformingTypeMetadata, protocolDescriptor: conformancedProtocol.descriptor) {
//                         try print("AssociatedTypeMetadata:", RuntimeFunctions.getAssociatedTypeWitness(request: .init(), protocolWitnessTable: pwt, conformingTypeMetadata: conformingTypeMetadata, baseRequirement: baseRequirement, associatedTypeRequirement: associatedTypeRequirement).value.resolve())
//                     }
//                 }
//
//             } else if let dependentGenericParamType = paramNode.first(of: .dependentGenericParamType), let genericParamType = dependentGenericParamType.text {
// //                        try await requirement.descriptor.dump(using: .default, in: machO).string.print()
//                 if let conformingTypeName = try conformingTypesByProtocolName[proto.protocolName(), default: []].first(where: { !(currentIndexer.allTypeDefinitions[$0]?.type.contextDescriptorWrapper.contextDescriptor.asPointerWrapper(in: machO).isGeneric ?? true) }), let conformingType = try allTypeDefinitions[conformingTypeName]?.type.asPointerWrapper(in: machO) {
// //                            conformingTypeName.name.print()
//                     conformingTypeByGenericParam[genericParamType] = conformingType
//                     conformancedProtocolsByGenericParam[genericParamType, default: []].append(proto)
//                 }
//             }
//         }
//
// //                try await genericContextInMachO.dumpGenericSignature(resolver: .using(options: .default), in: machO, isDumpCurrentLevelParams: false, isDumpCurrentLevelRequirements: false).string.print()
//
// //                "----------------".print()
// //                try await typeWrapper.dumper(using: .demangleOptions(.default), genericParamSpecializations: [], in: machO).name.string.print()
//     case .class (let type):
//         continue
//     }
// }
//
