import Foundation
import MachOKit

public typealias GenericContext = TargetGenericContext<GenericContextDescriptorHeader>

public typealias TypeGenericContext = TargetGenericContext<TypeGenericContextDescriptorHeader>

public struct TargetGenericContext<Header: GenericContextDescriptorHeaderProtocol> {
    public var offset: Int
    public var size: Int
    public var header: Header
    public var parameters: [GenericParamDescriptor] = []
    public var requirements: [GenericRequirementDescriptor] = []
    public var typePackHeader: GenericPackShapeHeader?
    public var typePacks: [GenericPackShapeDescriptor] = []
    public var conditionalInvertibleProtocolSet: InvertibleProtocolSet?
    public var conditionalInvertibleProtocolsRequirementsCount: InvertibleProtocolsRequirementCount?
    public var conditionalInvertibleProtocolsRequirements: [GenericRequirementDescriptor] = []
    public var valueHeader: GenericValueHeader?
    public var values: [GenericValueDescriptor] = []

    init(offset: Int, size: Int, header: Header) {
        self.offset = offset
        self.size = size
        self.header = header
    }

    public init?(contextDescriptor: any ContextDescriptorProtocol, in machO: MachOFile) throws {
        guard contextDescriptor.layout.flags.contains(.isGeneric) else { return nil }
        var currentOffset = contextDescriptor.offset + contextDescriptor.layoutSize
        let genericContextOffset = currentOffset

        let header: Header = try machO.readElement(offset: currentOffset)
        currentOffset.offset(of: Header.self)

        self.init(offset: genericContextOffset, size: currentOffset - genericContextOffset, header: header)

        let parameters: [GenericParamDescriptor] = try machO.readElements(offset: currentOffset, numberOfElements: Int(header.numParams))
        currentOffset.offset(of: GenericParamDescriptor.self, numbersOfElements: Int(header.numParams))
        currentOffset = numericCast(align(address: numericCast(currentOffset), alignment: 4))
        self.parameters = parameters

        let requirements: [GenericRequirementDescriptor] = try machO.readElements(offset: currentOffset, numberOfElements: Int(header.numRequirements))
        currentOffset.offset(of: GenericRequirementDescriptor.self, numbersOfElements: Int(header.numRequirements))
        self.requirements = requirements

        if header.flags.contains(.hasTypePacks) {
            let typePackHeader: GenericPackShapeHeader = try machO.readElement(offset: currentOffset)
            currentOffset.offset(of: GenericPackShapeHeader.self)
            self.typePackHeader = typePackHeader

            let typePacks: [GenericPackShapeDescriptor] = try machO.readElements(offset: currentOffset, numberOfElements: Int(typePackHeader.numPacks))
            currentOffset.offset(of: GenericPackShapeDescriptor.self, numbersOfElements: Int(typePackHeader.numPacks))
            self.typePacks = typePacks
        }

        if header.flags.contains(.hasConditionalInvertedProtocols) {
            let conditionalInvertibleProtocolSet: InvertibleProtocolSet = try machO.readElement(offset: currentOffset)
            currentOffset.offset(of: InvertibleProtocolSet.self)
            self.conditionalInvertibleProtocolSet = conditionalInvertibleProtocolSet

            let conditionalInvertibleProtocolsRequirementsCount: InvertibleProtocolsRequirementCount = try machO.readElement(offset: currentOffset)
            currentOffset.offset(of: InvertibleProtocolsRequirementCount.self)
            self.conditionalInvertibleProtocolsRequirementsCount = conditionalInvertibleProtocolsRequirementsCount

            let conditionalInvertibleProtocolsRequirements: [GenericRequirementDescriptor] = try machO.readElements(offset: currentOffset, numberOfElements: Int(conditionalInvertibleProtocolsRequirementsCount.rawValue))
            currentOffset.offset(of: GenericRequirementDescriptor.self, numbersOfElements: Int(conditionalInvertibleProtocolsRequirementsCount.rawValue))
            self.conditionalInvertibleProtocolsRequirements = conditionalInvertibleProtocolsRequirements
        }

        if header.flags.contains(.hasValues) {
            let valueHeader: GenericValueHeader = try machO.readElement(offset: currentOffset)
            currentOffset.offset(of: GenericValueHeader.self)
            self.valueHeader = valueHeader

            let values: [GenericValueDescriptor] = try machO.readElements(offset: currentOffset, numberOfElements: Int(valueHeader.numValues))
            currentOffset.offset(of: GenericValueDescriptor.self, numbersOfElements: Int(valueHeader.numValues))
            self.values = values
        }
        self.size = currentOffset - genericContextOffset
    }
}
