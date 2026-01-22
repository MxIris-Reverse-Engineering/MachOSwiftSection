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

final class GenericSpecializationTests: MachOImageTests, @unchecked Sendable {
    override class var imageName: MachOImageName { .SwiftUICore }

    @Test func main() async throws {
        let machO = machOImage

        let indexer = SwiftInterfaceIndexer(in: machO)

        try await indexer.prepare()

        for typeWrapper in try machO.swift.types {
            switch typeWrapper {
            case .enum /* (let type) */:
                continue
            case .struct(let type):
                guard let genericContextInProcess = try type.descriptor.asPointerWrapper(in: machO).genericContext() else { continue }
                guard let genericContextInMachO = try type.descriptor.genericContext(in: machO) else { continue }
                guard !genericContextInProcess.parameters.contains(where: { $0.kind == .typePack || $0.kind == .value }) else { continue }
//                for (depth, depthParameter) in genericContext.allParameters.enumerated() {
//                    for (index, _) in depthParameter.enumerated() {
//                        try genericParameterName(depth: depth, index: index).print()
//                    }
//                }

                let requirements = try genericContextInProcess.requirements.map { try GenericRequirement(descriptor: $0) }
                var conformingTypeByGenericParam: [String: TypeContextWrapper] = [:]
                var conformancedProtocolsByGenericParam: [String: [MachOSwiftSection.`Protocol`]] = [:]
                
                for requirement in requirements {
                    guard let requirementProtocol = requirement.content.protocol?.resolved, let protocolDescriptor = requirementProtocol.swift else { continue }
                    
                    let proto = try Protocol(descriptor: protocolDescriptor)
                    

                    
                    let paramNode = try MetadataReader.demangleType(for: requirement.paramManagledName)
                    paramNode.description.print()
                    if let dependentMemberType = paramNode.first(of: .dependentMemberType) {
                        if let dependentGenericParamType = dependentMemberType.first(of: .dependentGenericParamType),
                           let genericParamType = dependentGenericParamType.text,
                           let conformingType = conformingTypeByGenericParam[genericParamType],
                           let associatedType = dependentMemberType.first(of: .dependentAssociatedTypeRef)?.first(of: .identifier)?.text,
                           let (associatedTypeIndex, conformancedProtocol) = try conformancedProtocolsByGenericParam[genericParamType]?.firstNonNil({ proto in try proto.descriptor.associatedTypes().firstIndex(of: associatedType).map { ($0, proto) } }) {

                            if let baseRequirement = conformancedProtocol.requirements.first.map({ ProtocolRequirement(layout: .init(flags: [], defaultImplementation: .init(relativeOffset: 0)), offset: $0.offset - 8) }),
                               let associatedTypeRequirement = conformancedProtocol.requirements.filter({ $0.flags.kind.isAssociatedTypeAccessFunction })[safe: associatedTypeIndex],
                               let conformingTypeMetadata = try conformingType.typeContextDescriptorWrapper.typeContextDescriptor.metadataAccessorFunction()?(request: .init()).value.resolve().metadata,
                               let pwt = try RuntimeFunctions.conformsToProtocol(metadata: conformingTypeMetadata, protocolDescriptor: conformancedProtocol.descriptor) {
                                print("AssociatedTypeMetadata:", try RuntimeFunctions.getAssociatedTypeWitness(request: .init(), protocolWitnessTable: pwt, conformingTypeMetadata: conformingTypeMetadata, baseRequirement: baseRequirement, associatedTypeRequirement: associatedTypeRequirement).value.resolve())
                            }
                            
                        }

                    } else if let dependentGenericParamType = paramNode.first(of: .dependentGenericParamType), let genericParamType = dependentGenericParamType.text {
//                        try await requirement.descriptor.dump(using: .default, in: machO).string.print()
                        if let conformingTypeName = try indexer.conformingTypesByProtocolName[proto.protocolName(), default: []].first(where: { !(indexer.allTypeDefinitions[$0]?.type.contextDescriptorWrapper.contextDescriptor.asPointerWrapper(in: machO).isGeneric ?? true) }), let conformingType = try indexer.allTypeDefinitions[conformingTypeName]?.type.asPointerWrapper(in: machO) {
                            conformingTypeName.name.print()
                            conformingTypeByGenericParam[genericParamType] = conformingType
                            conformancedProtocolsByGenericParam[genericParamType, default: []].append(proto)
                        }
                    }
                }
                
                try await genericContextInMachO.dumpGenericSignature(resolver: .using(options: .default), in: machO, isDumpCurrentLevelParams: false, isDumpCurrentLevelRequirements: false).string.print()
                
                "----------------".print()
//                try await typeWrapper.dumper(using: .demangleOptions(.default), genericParamSpecializations: [], in: machO).name.string.print()
            case .class /* (let type) */:
                continue
            }
        }
    }
}

extension OptionSet {
    func removing(_ current: Self.Element) -> Self {
        var copy = self
        copy.remove(current)
        return copy
    }
}
