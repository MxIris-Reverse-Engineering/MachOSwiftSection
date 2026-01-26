import Foundation
import Demangling
import MachOSwiftSection
import SwiftInspection

extension OpaqueType {
    package func requirements(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> [GenericRequirementDescriptor] {
        guard let genericContext else { return [] }

        var usedRequirements = Set<Node>()

        if let symbol = try Symbol.resolve(from: descriptor.offset, in: machO), let node = try? symbol.demangledNode, let dependentGenericType = node.first(of: .dependentGenericType) {
            usedRequirements = .init(dependentGenericType.all(of: .dependentGenericSameTypeRequirement, .dependentGenericConformanceRequirement))
        }

        let currentRequirements = genericContext.uniqueCurrentRequirements(in: machO)
        var results: [GenericRequirementDescriptor] = []
        for currentRequirement in currentRequirements {
            if currentRequirement.content.isType {
                if let node = try MetadataReader.buildGenericSignature(for: currentRequirement, in: machO), let sameTypeRequirementNode = node.first(of: .dependentGenericSameTypeRequirement) {
                    let sameTypeRequirementCopy: Node
                    if let associatedTypeRefNode = sameTypeRequirementNode.first(of: .dependentAssociatedTypeRef) {
                        let modifiedAssociatedTypeRef = NodeBuilder(associatedTypeRefNode).removingChild(at: 1)
                        sameTypeRequirementCopy = NodeBuilder(sameTypeRequirementNode).replacingDescendant(associatedTypeRefNode, with: modifiedAssociatedTypeRef)
                    } else {
                        sameTypeRequirementCopy = NodeBuilder(sameTypeRequirementNode).copy()
                    }
                    if !usedRequirements.contains(sameTypeRequirementNode), !usedRequirements.contains(sameTypeRequirementCopy) {
                        results.append(currentRequirement)
                    }
                }
            } else if currentRequirement.content.isProtocol {
                if let node = try MetadataReader.buildGenericSignature(for: currentRequirement, in: machO), let conformanceRequirementNode = node.first(of: .dependentGenericConformanceRequirement), !usedRequirements.contains(conformanceRequirementNode) {
                    results.append(currentRequirement)
                }
            }
        }
        return results
    }
}
