import Foundation
import MachOKit

public protocol TypeContextDescriptorProtocol: NamedContextDescriptorProtocol where Layout: TypeContextDescriptorLayout {}

extension TypeContextDescriptorProtocol {
    func _offset<T>(of keyPath: KeyPath<Layout, T>) -> Int {
        let memberOffset = switch keyPath {
        case \.flags:
            0
        case \.parent:
            4
        case \.name:
            8
        case \.accessFunctionPtr:
            12
        case \.fieldDescriptor:
            16
        default:
            fatalError("KeyPath: \(keyPath) not supported")
        }
        return offset + memberOffset
    }

    public func fieldDescriptor(in machO: MachOFile) throws -> FieldDescriptor {
        try layout.fieldDescriptor.resolve(from: _offset(of: \.fieldDescriptor).cast(), in: machO)
    }

    public func typeGenericContext(in machO: MachOFile) throws -> TypeGenericContext? {
        var genericContext: TypeGenericContext?
        if layout.flags.contains(.isGeneric) {
            var currentOffset = offset + layoutSize
            let genericContextOffset = currentOffset
            let header: TypeGenericContextDescriptorHeader = try machO.readElement(offset: currentOffset)
            currentOffset.offset(of: TypeGenericContextDescriptorHeader.self)
            let parameters: [GenericParamDescriptor] = try machO.readElements(offset: currentOffset, numberOfElements: Int(header.base.numParams))
            currentOffset.offset(of: GenericParamDescriptor.self, numbersOfElements: Int(header.base.numParams))
            currentOffset = numericCast(align(address: numericCast(currentOffset), alignment: 4))
            let requirements: [GenericRequirementDescriptor] = try machO.readElements(offset: currentOffset, numberOfElements: Int(header.base.numRequirements))
            currentOffset.offset(of: GenericRequirementDescriptor.self, numbersOfElements: Int(header.base.numRequirements))
            var typePacks: [GenericPackShapeDescriptor] = []
            if header.base.flags.contains(.hasTypePacks) {
                let typePackHeader: GenericPackShapeHeader = try machO.readElement(offset: currentOffset)
                currentOffset.offset(of: GenericPackShapeHeader.self)
                typePacks = try machO.readElements(offset: currentOffset, numberOfElements: Int(typePackHeader.numPacks))
            }
            genericContext = .init(offset: genericContextOffset, header: header, parameters: parameters, requirements: requirements, typePacks: typePacks)
        }
        return genericContext
    }
}

func align(address: UInt64, alignment: UInt64) -> UInt64 {
    (address + alignment - 1) & ~(alignment - 1)
}
