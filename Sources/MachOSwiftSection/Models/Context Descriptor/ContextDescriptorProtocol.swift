//
//  ContextDescriptorProtocol.swift
//  MachOSwiftSection
//
//  Created by JH on 2025/5/5.
//

import MachOKit

public protocol ContextDescriptorProtocol: LocatableLayoutWrapper where Layout: ContextDescriptorLayout {}

extension ContextDescriptorProtocol {
    public func parent(in machO: MachOFile) throws -> ContextDescriptorWrapper? {
        try layout.parent.resolve(from: offset + 4, in: machO)
    }

    public func genericContext(in machO: MachOFile) throws -> GenericContext? {
        if layout.flags.contains(.isGeneric) {
            var currentOffset = offset + layoutSize
            let genericContextOffset = currentOffset

            let header: GenericContextDescriptorHeader = try machO.readElement(offset: currentOffset)
            currentOffset.offset(of: TypeGenericContextDescriptorHeader.self)

            var genericContext: GenericContext = .init(offset: genericContextOffset, size: currentOffset - genericContextOffset, header: header)

            let parameters: [GenericParamDescriptor] = try machO.readElements(offset: currentOffset, numberOfElements: Int(header.numParams))
            currentOffset.offset(of: GenericParamDescriptor.self, numbersOfElements: Int(header.numParams))
            currentOffset = numericCast(align(address: numericCast(currentOffset), alignment: 4))
            genericContext.parameters = parameters

            let requirements: [GenericRequirementDescriptor] = try machO.readElements(offset: currentOffset, numberOfElements: Int(header.numRequirements))
            currentOffset.offset(of: GenericRequirementDescriptor.self, numbersOfElements: Int(header.numRequirements))
            genericContext.requirements = requirements

            if header.flags.contains(.hasTypePacks) {
                let typePackHeader: GenericPackShapeHeader = try machO.readElement(offset: currentOffset)
                currentOffset.offset(of: GenericPackShapeHeader.self)
                genericContext.typePackHeader = typePackHeader

                let typePacks: [GenericPackShapeDescriptor] = try machO.readElements(offset: currentOffset, numberOfElements: Int(typePackHeader.numPacks))
                currentOffset.offset(of: GenericPackShapeDescriptor.self, numbersOfElements: Int(typePackHeader.numPacks))
                genericContext.typePacks = typePacks
            }

            if header.flags.contains(.hasConditionalInvertedProtocols) {
                let conditionalInvertibleProtocolSet: InvertibleProtocolSet = try machO.readElement(offset: currentOffset)
                currentOffset.offset(of: InvertibleProtocolSet.self)
                genericContext.conditionalInvertibleProtocolSet = conditionalInvertibleProtocolSet

                let conditionalInvertibleProtocolsRequirementsCount: InvertibleProtocolsRequirementCount = try machO.readElement(offset: currentOffset)
                currentOffset.offset(of: InvertibleProtocolsRequirementCount.self)
                genericContext.conditionalInvertibleProtocolsRequirementsCount = conditionalInvertibleProtocolsRequirementsCount

                let conditionalInvertibleProtocolsRequirements: [GenericRequirementDescriptor] = try machO.readElements(offset: currentOffset, numberOfElements: Int(conditionalInvertibleProtocolsRequirementsCount.rawValue))
                currentOffset.offset(of: GenericRequirementDescriptor.self, numbersOfElements: Int(conditionalInvertibleProtocolsRequirementsCount.rawValue))
                genericContext.conditionalInvertibleProtocolsRequirements = conditionalInvertibleProtocolsRequirements
            }

            if header.flags.contains(.hasValues) {
                let valueHeader: GenericValueHeader = try machO.readElement(offset: currentOffset)
                currentOffset.offset(of: GenericValueHeader.self)
                genericContext.valueHeader = valueHeader

                let values: [GenericValueDescriptor] = try machO.readElements(offset: currentOffset, numberOfElements: Int(valueHeader.numValues))
                currentOffset.offset(of: GenericValueDescriptor.self, numbersOfElements: Int(valueHeader.numValues))
                genericContext.values = values
            }
            genericContext.size = currentOffset - genericContextOffset
            return genericContext
        }
        return nil
    }
}
