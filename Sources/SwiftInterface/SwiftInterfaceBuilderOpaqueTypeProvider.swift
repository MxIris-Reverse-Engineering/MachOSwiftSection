import Demangling
import MachOKit
import MachOSwiftSection
import Dependencies
import OrderedCollections
@_spi(Internals) import MachOSymbols

public final class SwiftInterfaceBuilderOpaqueTypeProvider<MachO: MachOSwiftSectionRepresentableWithCache & Sendable>: SwiftInterfaceBuilderExtraDataProvider, Sendable {
    public let machO: MachO

    public init(machO: MachO) {
        self.machO = machO
    }

    public func opaqueType(forNode node: Node, index: Int?) -> String? {
        do {
            @Dependency(\.symbolIndexStore)
            var symbolIndexStore

            guard let opaqueTypeDescriptorSymbol = symbolIndexStore.opaqueTypeDescriptorSymbol(for: node, in: machO) else { return nil }

            let opaqueType = try OpaqueType(descriptor: OpaqueTypeDescriptor.resolve(from: opaqueTypeDescriptorSymbol.offset, in: machO), in: machO)
            let requirements = try opaqueType.requirements(in: machO)
            var protocolRequirementsByParamType: OrderedDictionary<String, [GenericRequirementDescriptor]> = [:]
            var protocolRequirements = requirements.filter(\.content.isProtocol)
            for protocolRequirement in protocolRequirements {
                let param = try protocolRequirement.dumpParameterName(resolver: .using(options: .opaqueTypeBuilderOnly), in: machO).string
                protocolRequirementsByParamType[param, default: []].append(protocolRequirement)
            }
            if let index {
                protocolRequirements = protocolRequirementsByParamType.elements[index + 1].value
            } else {
                protocolRequirements = protocolRequirementsByParamType.elements[0].value
            }
            let typeRequirements = requirements.filter(\.content.isType)
            let typeRequirementNodes = try typeRequirements.compactMap { try MetadataReader.buildGenericSignature(for: $0, in: machO) }
            var substitutionMap: SubstitutionMap<Node> = .init()
            var associatedTypeByParamType: [String: [Node]] = [:]
            var witnessTypeByParamType: [String: [Node]] = [:]
            for typeRequirementNode in typeRequirementNodes {
                guard let sameTypeRequirementNode = typeRequirementNode.first(of: .dependentGenericSameTypeRequirement) else { continue }
                guard let firstType = sameTypeRequirementNode.children.at(0), let secondType = sameTypeRequirementNode.children.at(1) else { continue }
                if secondType.children.first?.isKind(of: .dependentMemberType) ?? false {
                    substitutionMap.add(original: firstType, substitution: secondType)
                    if let paramTypeNode = secondType.first(of: .dependentGenericParamType), let paramType = paramTypeNode.text {
                        associatedTypeByParamType[paramType, default: []].append(secondType)
                    }
                } else if let paramTypeNode = firstType.first(of: .dependentGenericParamType), let paramType = paramTypeNode.text {
                    witnessTypeByParamType[paramType, default: []].append(secondType)
                }
            }

            var results: [String] = []
            for protocolRequirement in protocolRequirements {
                var result = ""
                let param = try protocolRequirement.dumpParameterName(resolver: .using(options: .opaqueTypeBuilderOnly), in: machO).string
                let proto = try protocolRequirement.dumpContent(resolver: .using(options: .opaqueTypeBuilderOnly), in: machO).string
                result.write(proto)
                var primaryAssociatedTypes: [String] = []
                if let associatedTypes = associatedTypeByParamType[param] {
                    for associatedType in associatedTypes {
                        let primaryAssociatedTypeNode = substitutionMap.rootOriginal(for: associatedType)
                        primaryAssociatedTypes.append(primaryAssociatedTypeNode.print(using: .opaqueTypeBuilderOnly))
                    }
                }

                if let witnessTypes = witnessTypeByParamType[param] {
                    for witnessType in witnessTypes {
                        primaryAssociatedTypes.append(witnessType.print(using: .opaqueTypeBuilderOnly))
                    }
                }

                if !primaryAssociatedTypes.isEmpty {
                    result.write("<")
                    result.write(primaryAssociatedTypes.joined(separator: ", "))
                    result.write(">")
                }

                results.append(result)
            }

            return results.joined(separator: " & ")
        } catch {
            return nil
        }
    }
}
