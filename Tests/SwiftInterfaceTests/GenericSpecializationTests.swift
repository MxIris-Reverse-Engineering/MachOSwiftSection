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
                guard let genericContext = type.genericContext else { continue }
                guard !genericContext.parameters.contains(where: { $0.kind == .typePack || $0.kind == .value }) else { continue }
//                for (depth, depthParameter) in genericContext.allParameters.enumerated() {
//                    for (index, _) in depthParameter.enumerated() {
//                        try genericParameterName(depth: depth, index: index).print()
//                    }
//                }

                let requirements = try genericContext.requirements.map { try GenericRequirement(descriptor: $0, in: machO) }
                var typeByGenericParam: [String: TypeName] = [:]
                for requirement in requirements {
                    guard let requirementProtocol = requirement.content.protocol?.resolved, let protocolDescriptor = requirementProtocol.swift else { continue }
                    let proto = try Protocol(descriptor: protocolDescriptor, in: machO)
                    if let baseRequirement = proto.requirements.first(where: { $0.flags.kind.isBaseProtocol }),
                       let associatedTypeRequirement = proto.requirements.first(where: { $0.flags.kind.isAssociatedTypeAccessFunction }) {
                        
                    }
                    
                    let paramNode = try MetadataReader.demangleType(for: requirement.paramManagledName, in: machO)
                    if let dependentMemberType = paramNode.first(of: .dependentMemberType) {
                        
                    } else if let dependentGenericParamType = paramNode.first(of: .dependentGenericParamType), let genericParamType = dependentGenericParamType.text {
                        try await requirement.descriptor.dump(using: .default, in: machO).string.print()
                        if let conformingType = try indexer.conformingTypesByProtocolName[proto.protocolName(in: machO), default: []].first {
                            conformingType.name.print()
                            typeByGenericParam[genericParamType] = conformingType
                        }
                    }
                }

                try await genericContext.dumpGenericSignature(resolver: .using(options: .default), in: machO, isDumpCurrentLevelParams: false, isDumpCurrentLevelRequirements: false).string.print()
                
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
