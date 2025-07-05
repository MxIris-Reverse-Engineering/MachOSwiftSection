import Foundation
import MachOKit
import MachOFoundation
import MachOMacro
import MemberwiseInit

public typealias GenericContext = TargetGenericContext<GenericContextDescriptorHeader>

public typealias TypeGenericContext = TargetGenericContext<TypeGenericContextDescriptorHeader>

@MemberwiseInit(.private)
public struct TargetGenericContext<Header: GenericContextDescriptorHeaderProtocol> {
    public let offset: Int
    public let size: Int
    public let header: Header
    
    public let parameters: [GenericParamDescriptor]
    public let requirements: [GenericRequirementDescriptor]
    public let typePackHeader: GenericPackShapeHeader?
    public let typePacks: [GenericPackShapeDescriptor]
    public let valueHeader: GenericValueHeader?
    public let values: [GenericValueDescriptor]
    
    public let parentParameters: [GenericParamDescriptor]
    public let parentRequirements: [GenericRequirementDescriptor]
    public let parentTypePacks: [GenericPackShapeDescriptor]
    public let parentValues: [GenericValueDescriptor]
    
    public let conditionalInvertibleProtocolSet: InvertibleProtocolSet?
    public let conditionalInvertibleProtocolsRequirementsCount: InvertibleProtocolsRequirementCount?
    public let conditionalInvertibleProtocolsRequirements: [GenericRequirementDescriptor]

    public let depth: Int
    
    public var currentParameters: [GenericParamDescriptor] {
        .init(parameters.dropFirst(parentParameters.count))
    }
    
    public var currentRequirements: [GenericRequirementDescriptor] {
        .init(requirements.dropFirst(parentRequirements.count))
    }
    
    public var currentTypePacks: [GenericPackShapeDescriptor] {
        .init(typePacks.dropFirst(parentTypePacks.count))
    }
    
    public var currentValues: [GenericValueDescriptor] {
        .init(values.dropFirst(parentValues.count))
    }
    
    
    public func asGenericContext() -> GenericContext {
        .init(
            offset: offset,
            size: size,
            header: .init(
                layout: .init(
                    numParams: header.numParams,
                    numRequirements: header.numRequirements,
                    numKeyArguments: header.numKeyArguments,
                    flags: header.flags
                ),
                offset: header.offset
            ),
            parameters: parameters,
            requirements: requirements,
            typePackHeader: typePackHeader,
            typePacks: typePacks,
            valueHeader: valueHeader,
            values: values,
            parentParameters: parentParameters,
            parentRequirements: parentRequirements,
            parentTypePacks: parentTypePacks,
            parentValues: parentValues,
            conditionalInvertibleProtocolSet: conditionalInvertibleProtocolSet,
            conditionalInvertibleProtocolsRequirementsCount: conditionalInvertibleProtocolsRequirementsCount,
            conditionalInvertibleProtocolsRequirements: conditionalInvertibleProtocolsRequirements,
            depth: depth
        )
    }

    public init<MachO: MachORepresentableWithCache & MachOReadable>(contextDescriptor: any ContextDescriptorProtocol, in machO: MachO) throws {
        var currentOffset = contextDescriptor.offset + contextDescriptor.layoutSize
        let genericContextOffset = currentOffset

        let header: Header = try machO.readWrapperElement(offset: currentOffset)
        currentOffset.offset(of: Header.self)
        self.offset = genericContextOffset
        self.header = header

        if header.numParams > 0 {
            let parameters: [GenericParamDescriptor] = try machO.readWrapperElements(offset: currentOffset, numberOfElements: Int(header.numParams))
            currentOffset.offset(of: GenericParamDescriptor.self, numbersOfElements: Int(header.numParams))
            currentOffset = numericCast(align(address: numericCast(currentOffset), alignment: 4))
            self.parameters = parameters
        } else {
            self.parameters = []
        }

        if header.numRequirements > 0 {
            let requirements: [GenericRequirementDescriptor] = try machO.readWrapperElements(offset: currentOffset, numberOfElements: Int(header.numRequirements))
            currentOffset.offset(of: GenericRequirementDescriptor.self, numbersOfElements: Int(header.numRequirements))
            self.requirements = requirements
        } else {
            self.requirements = []
        }

        if header.flags.contains(.hasTypePacks) {
            let typePackHeader: GenericPackShapeHeader = try machO.readWrapperElement(offset: currentOffset)
            currentOffset.offset(of: GenericPackShapeHeader.self)
            self.typePackHeader = typePackHeader

            let typePacks: [GenericPackShapeDescriptor] = try machO.readWrapperElements(offset: currentOffset, numberOfElements: Int(typePackHeader.numPacks))
            currentOffset.offset(of: GenericPackShapeDescriptor.self, numbersOfElements: Int(typePackHeader.numPacks))
            self.typePacks = typePacks
        } else {
            self.typePackHeader = nil
            self.typePacks = []
        }

        if header.flags.contains(.hasConditionalInvertedProtocols) {
            let conditionalInvertibleProtocolSet: InvertibleProtocolSet = try machO.readElement(offset: currentOffset)
            currentOffset.offset(of: InvertibleProtocolSet.self)
            self.conditionalInvertibleProtocolSet = conditionalInvertibleProtocolSet

            let conditionalInvertibleProtocolsRequirementsCount: InvertibleProtocolsRequirementCount = try machO.readElement(offset: currentOffset)
            currentOffset.offset(of: InvertibleProtocolsRequirementCount.self)
            self.conditionalInvertibleProtocolsRequirementsCount = conditionalInvertibleProtocolsRequirementsCount

            let conditionalInvertibleProtocolsRequirements: [GenericRequirementDescriptor] = try machO.readWrapperElements(offset: currentOffset, numberOfElements: Int(conditionalInvertibleProtocolsRequirementsCount.rawValue))
            currentOffset.offset(of: GenericRequirementDescriptor.self, numbersOfElements: Int(conditionalInvertibleProtocolsRequirementsCount.rawValue))
            self.conditionalInvertibleProtocolsRequirements = conditionalInvertibleProtocolsRequirements
        } else {
            self.conditionalInvertibleProtocolSet = nil
            self.conditionalInvertibleProtocolsRequirementsCount = nil
            self.conditionalInvertibleProtocolsRequirements = []
        }

        if header.flags.contains(.hasValues) {
            let valueHeader: GenericValueHeader = try machO.readWrapperElement(offset: currentOffset)
            currentOffset.offset(of: GenericValueHeader.self)
            self.valueHeader = valueHeader

            let values: [GenericValueDescriptor] = try machO.readWrapperElements(offset: currentOffset, numberOfElements: Int(valueHeader.numValues))
            currentOffset.offset(of: GenericValueDescriptor.self, numbersOfElements: Int(valueHeader.numValues))
            self.values = values
        } else {
            self.valueHeader = nil
            self.values = []
        }
        self.size = currentOffset - genericContextOffset
        var depth = 0
        var parent = try contextDescriptor.parent(in: machO)?.resolved
        var parentParameters: [GenericParamDescriptor] = []
        var parentRequirements: [GenericRequirementDescriptor] = []
        var parentTypePacks: [GenericPackShapeDescriptor] = []
        var parentValues: [GenericValueDescriptor] = []
        while let currentParent = parent {
            if let genericContext = try currentParent.typeContextDescriptor?.genericContext(in: machO) {
                parentParameters.append(contentsOf: genericContext.parameters)
                parentRequirements.append(contentsOf: genericContext.requirements)
                parentTypePacks.append(contentsOf: genericContext.typePacks)
                parentValues.append(contentsOf: genericContext.values)
                depth += 1
            }
            parent = try currentParent.parent(in: machO)?.resolved
        }
        self.parentParameters = parentParameters.reversed()
        self.parentRequirements = parentRequirements.reversed()
        self.parentTypePacks = parentTypePacks.reversed()
        self.parentValues = parentValues.reversed()
        self.depth = depth
    }
}


