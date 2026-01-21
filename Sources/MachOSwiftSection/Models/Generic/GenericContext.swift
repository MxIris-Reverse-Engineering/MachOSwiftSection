import Foundation
import MachOKit
import MachOFoundation
import MemberwiseInit

public typealias GenericContext = TargetGenericContext<GenericContextDescriptorHeader>

public typealias TypeGenericContext = TargetGenericContext<TypeGenericContextDescriptorHeader>

@MemberwiseInit(.private)
public struct TargetGenericContext<Header: GenericContextDescriptorHeaderProtocol>: Sendable {
    public let offset: Int
    public private(set) var size: Int = 0
    public private(set) var header: Header

    public private(set) var parameters: [GenericParamDescriptor] = []
    public private(set) var requirements: [GenericRequirementDescriptor] = []
    public private(set) var typePackHeader: GenericPackShapeHeader?
    public private(set) var typePacks: [GenericPackShapeDescriptor] = []
    public private(set) var valueHeader: GenericValueHeader?
    public private(set) var values: [GenericValueDescriptor] = []

    public private(set) var parentParameters: [[GenericParamDescriptor]] = []
    public private(set) var parentRequirements: [[GenericRequirementDescriptor]] = []
    public private(set) var parentTypePacks: [[GenericPackShapeDescriptor]] = []
    public private(set) var parentValues: [[GenericValueDescriptor]] = []

    public private(set) var conditionalInvertibleProtocolSet: InvertibleProtocolSet?
    public private(set) var conditionalInvertibleProtocolsRequirementsCount: InvertibleProtocolsRequirementCount?
    public private(set) var conditionalInvertibleProtocolsRequirements: [GenericRequirementDescriptor] = []

    public private(set) var depth: Int = 0

    public var currentParameters: [GenericParamDescriptor] {
        .init(parameters.dropFirst(parentParameters.flatMap { $0 }.count))
    }

    public func currentRequirements<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) -> [GenericRequirementDescriptor] {
        let parentRequirements = parentRequirements.flatMap { $0 }
        var currentRequirements: [GenericRequirementDescriptor] = []
        for requirement in requirements {
            if !parentRequirements.contains(where: { $0.isContentEqual(to: requirement, in: machO) }) {
                currentRequirements.append(requirement)
            }
        }
        return currentRequirements
    }

    public var currentTypePacks: [GenericPackShapeDescriptor] {
        .init(typePacks.dropFirst(parentTypePacks.flatMap { $0 }.count))
    }

    public var currentValues: [GenericValueDescriptor] {
        .init(values.dropFirst(parentValues.flatMap { $0 }.count))
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

    public init<MachO: MachOSwiftSectionRepresentableWithCache>(contextDescriptor: some ContextDescriptorProtocol, in machO: MachO) throws {
        var currentOffset = contextDescriptor.offset + contextDescriptor.layoutSize
        let genericContextOffset = currentOffset
        self.offset = genericContextOffset

        let header: Header = try machO.readWrapperElement(offset: currentOffset)
        currentOffset.offset(of: Header.self)
        self.header = header

        try initialize(contextDescriptor: contextDescriptor, currentOffset: &currentOffset, in: machO)

        var depth = 0
        var parent = try contextDescriptor.parent(in: machO)?.resolved
        var parentParameters: [[GenericParamDescriptor]] = []
        var parentRequirements: [[GenericRequirementDescriptor]] = []
        var parentTypePacks: [[GenericPackShapeDescriptor]] = []
        var parentValues: [[GenericValueDescriptor]] = []
        while let currentParent = parent {
            if let genericContext = try currentParent.validParentGenericContextDescriptor?.genericContext(in: machO) {
                parentParameters.append(genericContext.parameters)
                parentRequirements.append(genericContext.requirements)
                parentTypePacks.append(genericContext.typePacks)
                parentValues.append(genericContext.values)
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

    public init(contextDescriptor: some ContextDescriptorProtocol) throws {
        var currentOffset = contextDescriptor.layoutSize
        let pointer = try contextDescriptor.asPointer
        let genericContextOffset = pointer.bitPattern.int + currentOffset
        self.offset = genericContextOffset

        let header: Header = try pointer.readWrapperElement(offset: currentOffset)
        currentOffset.offset(of: Header.self)
        self.header = header

        try initialize(contextDescriptor: contextDescriptor, currentOffset: &currentOffset, in: pointer)

        var depth = 0
        var parent = try contextDescriptor.parent()?.resolved
        var parentParameters: [[GenericParamDescriptor]] = []
        var parentRequirements: [[GenericRequirementDescriptor]] = []
        var parentTypePacks: [[GenericPackShapeDescriptor]] = []
        var parentValues: [[GenericValueDescriptor]] = []
        while let currentParent = parent {
            if let genericContext = try currentParent.validParentGenericContextDescriptor?.genericContext() {
                parentParameters.append(genericContext.parameters)
                parentRequirements.append(genericContext.requirements)
                parentTypePacks.append(genericContext.typePacks)
                parentValues.append(genericContext.values)
                depth += 1
            }
            parent = try currentParent.parent()?.resolved
        }
        self.parentParameters = parentParameters.reversed()
        self.parentRequirements = parentRequirements.reversed()
        self.parentTypePacks = parentTypePacks.reversed()
        self.parentValues = parentValues.reversed()
        self.depth = depth
    }

    private mutating func initialize<Reader: Readable>(contextDescriptor: some ContextDescriptorProtocol, currentOffset: inout Int, in reader: Reader) throws {
        if header.numParams > 0 {
            let parameters: [GenericParamDescriptor] = try reader.readWrapperElements(offset: currentOffset, numberOfElements: Int(header.numParams))
            currentOffset.offset(of: GenericParamDescriptor.self, numbersOfElements: Int(header.numParams))
            currentOffset.align(to: 4)
            self.parameters = parameters
        } else {
            parameters = []
        }

        if header.numRequirements > 0 {
            let requirements: [GenericRequirementDescriptor] = try reader.readWrapperElements(offset: currentOffset, numberOfElements: Int(header.numRequirements))
            currentOffset.offset(of: GenericRequirementDescriptor.self, numbersOfElements: Int(header.numRequirements))
            self.requirements = requirements
        } else {
            requirements = []
        }

        if header.flags.contains(.hasTypePacks) {
            let typePackHeader: GenericPackShapeHeader = try reader.readWrapperElement(offset: currentOffset)
            currentOffset.offset(of: GenericPackShapeHeader.self)
            self.typePackHeader = typePackHeader

            let typePacks: [GenericPackShapeDescriptor] = try reader.readWrapperElements(offset: currentOffset, numberOfElements: Int(typePackHeader.numPacks))
            currentOffset.offset(of: GenericPackShapeDescriptor.self, numbersOfElements: Int(typePackHeader.numPacks))
            self.typePacks = typePacks
        } else {
            typePackHeader = nil
            typePacks = []
        }

        if header.flags.contains(.hasConditionalInvertedProtocols) {
            let conditionalInvertibleProtocolSet: InvertibleProtocolSet = try reader.readElement(offset: currentOffset)
            currentOffset.offset(of: InvertibleProtocolSet.self)
            self.conditionalInvertibleProtocolSet = conditionalInvertibleProtocolSet

            let conditionalInvertibleProtocolsRequirementsCount: InvertibleProtocolsRequirementCount = try reader.readElement(offset: currentOffset)
            currentOffset.offset(of: InvertibleProtocolsRequirementCount.self)
            self.conditionalInvertibleProtocolsRequirementsCount = conditionalInvertibleProtocolsRequirementsCount

            let conditionalInvertibleProtocolsRequirements: [GenericRequirementDescriptor] = try reader.readWrapperElements(offset: currentOffset, numberOfElements: Int(conditionalInvertibleProtocolsRequirementsCount.rawValue))
            currentOffset.offset(of: GenericRequirementDescriptor.self, numbersOfElements: Int(conditionalInvertibleProtocolsRequirementsCount.rawValue))
            self.conditionalInvertibleProtocolsRequirements = conditionalInvertibleProtocolsRequirements
        } else {
            conditionalInvertibleProtocolSet = nil
            conditionalInvertibleProtocolsRequirementsCount = nil
            conditionalInvertibleProtocolsRequirements = []
        }

        if header.flags.contains(.hasValues) {
            let valueHeader: GenericValueHeader = try reader.readWrapperElement(offset: currentOffset)
            currentOffset.offset(of: GenericValueHeader.self)
            self.valueHeader = valueHeader

            let values: [GenericValueDescriptor] = try reader.readWrapperElements(offset: currentOffset, numberOfElements: Int(valueHeader.numValues))
            currentOffset.offset(of: GenericValueDescriptor.self, numbersOfElements: Int(valueHeader.numValues))
            self.values = values
        } else {
            valueHeader = nil
            values = []
        }
        size = currentOffset - offset
    }
}

extension ContextDescriptorWrapper {
    fileprivate var validParentGenericContextDescriptor: (any ContextDescriptorProtocol)? {
        switch self {
        case .type:
            return typeContextDescriptor
        case .extension(let extensionContextDescriptor):
            return extensionContextDescriptor
        default:
            return nil
        }
    }
}
