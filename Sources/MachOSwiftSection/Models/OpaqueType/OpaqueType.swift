import Foundation
import MachOKit

import MachOFoundation
import Demangle

public struct OpaqueType: TopLevelType, ContextProtocol {
    public let descriptor: OpaqueTypeDescriptor

    public let genericContext: GenericContext?

    public let underlyingTypeArgumentMangledNames: [MangledName]

    public let invertedProtocols: InvertibleProtocolSet?

    public init<MachO: MachOSwiftSectionRepresentableWithCache>(descriptor: OpaqueTypeDescriptor, in machO: MachO) throws {
        self.descriptor = descriptor
        var currentOffset = descriptor.offset + descriptor.layoutSize

        let genericContext = try descriptor.genericContext(in: machO)

        if let genericContext {
            currentOffset += genericContext.size
        }
        self.genericContext = genericContext

        if descriptor.numUnderlyingTypeArugments > 0 {
            let underlyingTypeArgumentMangledNamePointers: [RelativeDirectPointer<MangledName>] = try machO.readElements(offset: currentOffset, numberOfElements: descriptor.numUnderlyingTypeArugments)
            var underlyingTypeArgumentMangledNames: [MangledName] = []
            for underlyingTypeArgumentMangledNamePointer in underlyingTypeArgumentMangledNamePointers {
                try underlyingTypeArgumentMangledNames.append(underlyingTypeArgumentMangledNamePointer.resolve(from: currentOffset, in: machO))
                currentOffset += MemoryLayout<RelativeDirectPointer<MangledName>>.size
            }
            self.underlyingTypeArgumentMangledNames = underlyingTypeArgumentMangledNames
        } else {
            self.underlyingTypeArgumentMangledNames = []
        }

        if descriptor.flags.contains(.hasInvertibleProtocols) {
            self.invertedProtocols = try machO.readElement(offset: currentOffset) as InvertibleProtocolSet
            currentOffset.offset(of: InvertibleProtocolSet.self)
        } else {
            self.invertedProtocols = nil
        }
    }

    public func requirements(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> [GenericRequirementDescriptor] {
        guard let genericContext else { return [] }

        var usedRequirements = Set<Node>()

        if let symbol = try Symbol.resolve(from: descriptor.offset, in: machO), let node = try? symbol.demangledNode, let dependentGenericType = node.first(of: .dependentGenericType) {
            usedRequirements = .init(dependentGenericType.all(of: .dependentGenericSameTypeRequirement, .dependentGenericConformanceRequirement))
        }

        let currentRequirements = genericContext.currentRequirements(in: machO)
        var results: [GenericRequirementDescriptor] = []
        for currentRequirement in currentRequirements {
            if currentRequirement.content.isType {
                if let node = try MetadataReader.buildGenericSignature(for: currentRequirement, in: machO), let sameTypeRequirementNode = node.first(of: .dependentGenericSameTypeRequirement) {
                    let sameTypeRequirementCopy = sameTypeRequirementNode.copy()
                    if let associatedTypeRefNode = sameTypeRequirementCopy.first(of: .dependentAssociatedTypeRef) {
                        associatedTypeRefNode.removeChild(at: 1)
                    }
                    if !usedRequirements.contains(sameTypeRequirementNode) && !usedRequirements.contains(sameTypeRequirementCopy) {
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
