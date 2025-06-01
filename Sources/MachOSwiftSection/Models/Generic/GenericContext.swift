import Foundation
import MachOKit
import MachOFoundation
import MachOSwiftSectionMacro

public typealias GenericContext = TargetGenericContext<GenericContextDescriptorHeader>

public typealias TypeGenericContext = TargetGenericContext<TypeGenericContextDescriptorHeader>

public struct TargetGenericContext<Header: GenericContextDescriptorHeaderProtocol> {
    public let offset: Int
    public let size: Int
    public let header: Header
    public let parameters: [GenericParamDescriptor]
    public let requirements: [GenericRequirementDescriptor]
    public let typePackHeader: GenericPackShapeHeader?
    public let typePacks: [GenericPackShapeDescriptor]
    public let conditionalInvertibleProtocolSet: InvertibleProtocolSet?
    public let conditionalInvertibleProtocolsRequirementsCount: InvertibleProtocolsRequirementCount?
    public let conditionalInvertibleProtocolsRequirements: [GenericRequirementDescriptor]
    public let valueHeader: GenericValueHeader?
    public let values: [GenericValueDescriptor]

    private init(
        offset: Int,
        size: Int,
        header: Header,
        parameters: [GenericParamDescriptor],
        requirements: [GenericRequirementDescriptor],
        typePackHeader: GenericPackShapeHeader?,
        typePacks: [GenericPackShapeDescriptor],
        conditionalInvertibleProtocolSet: InvertibleProtocolSet?,
        conditionalInvertibleProtocolsRequirementsCount: InvertibleProtocolsRequirementCount?,
        conditionalInvertibleProtocolsRequirements: [GenericRequirementDescriptor],
        valueHeader: GenericValueHeader?,
        values: [GenericValueDescriptor]
    ) {
        self.offset = offset
        self.size = size
        self.header = header
        self.parameters = parameters
        self.requirements = requirements
        self.typePackHeader = typePackHeader
        self.typePacks = typePacks
        self.conditionalInvertibleProtocolSet = conditionalInvertibleProtocolSet
        self.conditionalInvertibleProtocolsRequirementsCount = conditionalInvertibleProtocolsRequirementsCount
        self.conditionalInvertibleProtocolsRequirements = conditionalInvertibleProtocolsRequirements
        self.valueHeader = valueHeader
        self.values = values
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
            conditionalInvertibleProtocolSet: conditionalInvertibleProtocolSet,
            conditionalInvertibleProtocolsRequirementsCount: conditionalInvertibleProtocolsRequirementsCount,
            conditionalInvertibleProtocolsRequirements: conditionalInvertibleProtocolsRequirements,
            valueHeader: valueHeader,
            values: values
        )
    }

    @MachOImageGenerator
    public init(contextDescriptor: any ContextDescriptorProtocol, in machOFile: MachOFile) throws {
        var currentOffset = contextDescriptor.offset + contextDescriptor.layoutSize
        let genericContextOffset = currentOffset

        let header: Header = try machOFile.readElement(offset: currentOffset)
        currentOffset.offset(of: Header.self)
        self.offset = genericContextOffset
        self.header = header

        if header.numParams > 0 {
            let parameters: [GenericParamDescriptor] = try machOFile.readElements(offset: currentOffset, numberOfElements: Int(header.numParams))
            currentOffset.offset(of: GenericParamDescriptor.self, numbersOfElements: Int(header.numParams))
            currentOffset = numericCast(align(address: numericCast(currentOffset), alignment: 4))
            self.parameters = parameters
        } else {
            self.parameters = []
        }

        if header.numRequirements > 0 {
            let requirements: [GenericRequirementDescriptor] = try machOFile.readElements(offset: currentOffset, numberOfElements: Int(header.numRequirements))
            currentOffset.offset(of: GenericRequirementDescriptor.self, numbersOfElements: Int(header.numRequirements))
            self.requirements = requirements
        } else {
            self.requirements = []
        }

        if header.flags.contains(.hasTypePacks) {
            let typePackHeader: GenericPackShapeHeader = try machOFile.readElement(offset: currentOffset)
            currentOffset.offset(of: GenericPackShapeHeader.self)
            self.typePackHeader = typePackHeader

            let typePacks: [GenericPackShapeDescriptor] = try machOFile.readElements(offset: currentOffset, numberOfElements: Int(typePackHeader.numPacks))
            currentOffset.offset(of: GenericPackShapeDescriptor.self, numbersOfElements: Int(typePackHeader.numPacks))
            self.typePacks = typePacks
        } else {
            self.typePackHeader = nil
            self.typePacks = []
        }

        if header.flags.contains(.hasConditionalInvertedProtocols) {
            let conditionalInvertibleProtocolSet: InvertibleProtocolSet = try machOFile.readElement(offset: currentOffset)
            currentOffset.offset(of: InvertibleProtocolSet.self)
            self.conditionalInvertibleProtocolSet = conditionalInvertibleProtocolSet

            let conditionalInvertibleProtocolsRequirementsCount: InvertibleProtocolsRequirementCount = try machOFile.readElement(offset: currentOffset)
            currentOffset.offset(of: InvertibleProtocolsRequirementCount.self)
            self.conditionalInvertibleProtocolsRequirementsCount = conditionalInvertibleProtocolsRequirementsCount

            let conditionalInvertibleProtocolsRequirements: [GenericRequirementDescriptor] = try machOFile.readElements(offset: currentOffset, numberOfElements: Int(conditionalInvertibleProtocolsRequirementsCount.rawValue))
            currentOffset.offset(of: GenericRequirementDescriptor.self, numbersOfElements: Int(conditionalInvertibleProtocolsRequirementsCount.rawValue))
            self.conditionalInvertibleProtocolsRequirements = conditionalInvertibleProtocolsRequirements
        } else {
            self.conditionalInvertibleProtocolSet = nil
            self.conditionalInvertibleProtocolsRequirementsCount = nil
            self.conditionalInvertibleProtocolsRequirements = []
        }

        if header.flags.contains(.hasValues) {
            let valueHeader: GenericValueHeader = try machOFile.readElement(offset: currentOffset)
            currentOffset.offset(of: GenericValueHeader.self)
            self.valueHeader = valueHeader

            let values: [GenericValueDescriptor] = try machOFile.readElements(offset: currentOffset, numberOfElements: Int(valueHeader.numValues))
            currentOffset.offset(of: GenericValueDescriptor.self, numbersOfElements: Int(valueHeader.numValues))
            self.values = values
        } else {
            self.valueHeader = nil
            self.values = []
        }
        self.size = currentOffset - genericContextOffset
    }
}


