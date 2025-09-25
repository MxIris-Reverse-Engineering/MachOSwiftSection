import Foundation
import MachOKit
import MachOMacro
import MachOFoundation
import Demangle

public struct OpaqueType: TopLevelType, ContextProtocol {
    public let descriptor: OpaqueTypeDescriptor

    public let genericContext: GenericContext?
    
    public let underlyingTypeArgumentMangledNames: [MangledName]

    public let invertedProtocols: InvertibleProtocolSet?

    public init<MachO: MachORepresentableWithCache & MachOReadable>(descriptor: OpaqueTypeDescriptor, in machO: MachO) throws {
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
    
    public func requirements(in machO: some MachORepresentableWithCache & MachOReadable) throws -> [GenericRequirementDescriptor] {
        guard let genericContext else { return [] }
        
        var usedGenericParams = Set<String>()
        
        if let symbol = try Symbol.resolve(from: descriptor.offset, in: machO), let node = try? symbol.demangledNode, let dependentGenericType = node.first(of: .dependentGenericType) {
            let numberOfGenericParams = dependentGenericType.all(of: .dependentGenericParamCount).count
            let depthByIndex = dependentGenericType.findGenericParamsDepth()
            
            for index in 0..<numberOfGenericParams {
                let index = UInt64(index)
                if let depth = depthByIndex?[index] {
                    usedGenericParams.insert(genericParameterName(depth: depth, index: index))
                } else {
                    usedGenericParams.insert(genericParameterName(depth: 0, index: index))
                }
            }
        }
        
        let currentRequirements = genericContext.currentRequirements(in: machO)
        var results: [GenericRequirementDescriptor] = []
        for currentRequirement in currentRequirements {
            let paramMangledName = try currentRequirement.paramMangledName(in: machO)
            let paramString = try MetadataReader.demangle(for: paramMangledName, in: machO).print()
            
            if !usedGenericParams.contains(paramString) {
                results.append(currentRequirement)
            }
        }
        return results
    }
}
