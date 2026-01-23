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

struct TestGenericStruct<A, B, C> where A: Collection, B: Equatable, C: Hashable, A.Element: Hashable {
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
        let wrapper = try machO.swift.typeContextDescriptors.first { try $0.struct?.name(in: machO) == "TestGenericStruct" }?.struct
        let descriptor = try #require(wrapper)

        let associatedTypeMetadatasAndPWTs = try await indexer.associatedTypeMetadatasAndPWTs(for: .struct(descriptor), genericParamMetadataByParamName: [
            "A": try .createInProcess([Int].self),
            "B": try .createInProcess(Double.self),
            "C": try .createInProcess(Data.self),
        ], in: machO)
        
        try print(#require(associatedTypeMetadatasAndPWTs))
//        try #require(descriptor.metadataAccessorFunction())(request: .init(), args: <#T##any Any.Type...##any Any.Type#>)
    }
}

extension SwiftInterfaceIndexer {
    func associatedTypeMetadatasAndPWTs(for typeDescriptor: TypeContextDescriptorWrapper, genericParamMetadataByParamName: [String: Metadata], in machO: MachOImage) async throws -> [(Metadata, ProtocolWitnessTable)]? {
        typealias Result = (Metadata, ProtocolWitnessTable)
        var results: [Result] = []
        guard let genericContextInProcess = try typeDescriptor.asPointerWrapper(in: machO).genericContext() else { return nil }
//        guard let genericContextInMachO = try typeDescriptor.genericContext(in: machO) else { return nil }
        guard !genericContextInProcess.parameters.contains(where: { $0.kind == .typePack || $0.kind == .value }) else { return nil }

        let requirements = try genericContextInProcess.requirements.map { try GenericRequirement(descriptor: $0) }
        var conformingTypeMetadataByGenericParam: [String: Metadata] = [:]
        var conformancedProtocolsByGenericParam: [String: [MachOSwiftSection.`Protocol`]] = [:]
        let allProtocolDefinitions = allAllProtocolDefinitions
        for requirement in requirements {
            guard let requirementProtocol = requirement.content.protocol?.resolved, let protocolDescriptor = requirementProtocol.swift else { continue }

            let currentProtocol = try Protocol(descriptor: protocolDescriptor)

            let paramNode = try MetadataReader.demangleType(for: requirement.paramManagledName)

            if let dependentMemberType = paramNode.first(of: .dependentMemberType) {
                if let dependentGenericParamType = dependentMemberType.first(of: .dependentGenericParamType),
                   let genericParamType = dependentGenericParamType.text,
                   let conformingTypeMetadata = conformingTypeMetadataByGenericParam[genericParamType],
                   let dependentAssociatedTypeRef = dependentMemberType.first(of: .dependentAssociatedTypeRef),
                   let associatedTypeName = dependentAssociatedTypeRef.children.first?.text,
                   let associatedTypeRefProtocolTypeNode = dependentAssociatedTypeRef.children.second,
                   let associatedTypeRefMachOAndProtocol = allProtocolDefinitions[.init(node: associatedTypeRefProtocolTypeNode)],
                   let associatedTypeRefProtocol = try (associatedTypeRefMachOAndProtocol.machO as? MachOImage).map({ try Protocol(descriptor: associatedTypeRefMachOAndProtocol.value.protocol.descriptor.asPointerWrapper(in: $0)) }),
                   let associatedTypeIndex = try associatedTypeRefProtocol.descriptor.associatedTypes().firstIndex(of: associatedTypeName),
                   let associatedTypeBaseRequirement = associatedTypeRefProtocol.baseRequirement,
                   let associatedTypeAccessFunctionRequirement = associatedTypeRefProtocol.requirements.filter({ $0.flags.kind.isAssociatedTypeAccessFunction })[safe: associatedTypeIndex],
                   let conformingTypePWT = try RuntimeFunctions.conformsToProtocol(metadata: conformingTypeMetadata, protocolDescriptor: associatedTypeRefProtocol.descriptor),
                   let associatedTypeMetadata = try? RuntimeFunctions.getAssociatedTypeWitness(request: .init(), protocolWitnessTable: conformingTypePWT, conformingTypeMetadata: conformingTypeMetadata, baseRequirement: associatedTypeBaseRequirement, associatedTypeRequirement: associatedTypeAccessFunctionRequirement).value.resolve().metadata,
                   let associatedTypePWT = try? RuntimeFunctions.conformsToProtocol(metadata: associatedTypeMetadata, protocolDescriptor: currentProtocol.descriptor) {
                    results.append((associatedTypeMetadata, associatedTypePWT))
                } else {
                    return nil
                }
            } else if let dependentGenericParamType = paramNode.first(of: .dependentGenericParamType), let genericParamType = dependentGenericParamType.text {
                if let conformingTypeMetadata = genericParamMetadataByParamName[genericParamType] {
                    conformingTypeMetadataByGenericParam[genericParamType] = conformingTypeMetadata
                    conformancedProtocolsByGenericParam[genericParamType, default: []].append(currentProtocol)
                } else {
                    return nil
                }
            } else {
                return nil
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

/**
 
 let conformingTypesByProtocolName = currentIndexer.allConformingTypesByProtocolName
 let allTypeDefinitions = currentIndexer.allAllTypeDefinitions

 for typeWrapper in try machO.swift.types {
     switch typeWrapper {
     case .enum /* (let type) */:
         continue
     case .struct(let type):
         guard let genericContextInProcess = try type.descriptor.asPointerWrapper(in: machO).genericContext() else { continue }
         guard let genericContextInMachO = try type.descriptor.genericContext(in: machO) else { continue }
         guard !genericContextInProcess.parameters.contains(where: { $0.kind == .typePack || $0.kind == .value }) else { continue }

//                let typeName = try MetadataReader.demangleContext(for: .type(.struct(type.descriptor)), in: machO).print(using: .default).string
//                typeName.print()

         let requirements = try genericContextInProcess.requirements.map { try GenericRequirement(descriptor: $0) }
         var conformingTypeByGenericParam: [String: TypeContextWrapper] = [:]
         var conformancedProtocolsByGenericParam: [String: [MachOSwiftSection.`Protocol`]] = [:]

         for requirement in requirements {
             guard let requirementProtocol = requirement.content.protocol?.resolved, let protocolDescriptor = requirementProtocol.swift else { continue }

             let proto = try Protocol(descriptor: protocolDescriptor)

             let paramNode = try MetadataReader.demangleType(for: requirement.paramManagledName)
//                    paramNode.description.print()
             if let dependentMemberType = paramNode.first(of: .dependentMemberType) {
                 if let dependentGenericParamType = dependentMemberType.first(of: .dependentGenericParamType),
                    let genericParamType = dependentGenericParamType.text,
                    let conformingType = conformingTypeByGenericParam[genericParamType],
                    let associatedType = dependentMemberType.first(of: .dependentAssociatedTypeRef)?.first(of: .identifier)?.text,
                    let (associatedTypeIndex, conformancedProtocol) = try conformancedProtocolsByGenericParam[genericParamType]?.firstNonNil({ proto in try proto.descriptor.associatedTypes().firstIndex(of: associatedType).map { ($0, proto) } }) {
                     if let baseRequirement = conformancedProtocol.baseRequirement,
                        let associatedTypeRequirement = conformancedProtocol.requirements.filter({ $0.flags.kind.isAssociatedTypeAccessFunction })[safe: associatedTypeIndex],
                        let conformingTypeMetadata = try conformingType.typeContextDescriptorWrapper.typeContextDescriptor.metadataAccessorFunction()?(request: .init()).value.resolve().metadata,
                        let pwt = try RuntimeFunctions.conformsToProtocol(metadata: conformingTypeMetadata, protocolDescriptor: conformancedProtocol.descriptor) {
                         try print("AssociatedTypeMetadata:", RuntimeFunctions.getAssociatedTypeWitness(request: .init(), protocolWitnessTable: pwt, conformingTypeMetadata: conformingTypeMetadata, baseRequirement: baseRequirement, associatedTypeRequirement: associatedTypeRequirement).value.resolve())
                     }
                 }

             } else if let dependentGenericParamType = paramNode.first(of: .dependentGenericParamType), let genericParamType = dependentGenericParamType.text {
//                        try await requirement.descriptor.dump(using: .default, in: machO).string.print()
                 if let conformingTypeName = try conformingTypesByProtocolName[proto.protocolName(), default: []].first(where: { !(currentIndexer.allTypeDefinitions[$0]?.type.contextDescriptorWrapper.contextDescriptor.asPointerWrapper(in: machO).isGeneric ?? true) }), let conformingType = try allTypeDefinitions[conformingTypeName]?.type.asPointerWrapper(in: machO) {
//                            conformingTypeName.name.print()
                     conformingTypeByGenericParam[genericParamType] = conformingType
                     conformancedProtocolsByGenericParam[genericParamType, default: []].append(proto)
                 }
             }
         }

//                try await genericContextInMachO.dumpGenericSignature(resolver: .using(options: .default), in: machO, isDumpCurrentLevelParams: false, isDumpCurrentLevelRequirements: false).string.print()

//                "----------------".print()
//                try await typeWrapper.dumper(using: .demangleOptions(.default), genericParamSpecializations: [], in: machO).name.string.print()
     case .class /* (let type) */:
         continue
     }
 }
 */
