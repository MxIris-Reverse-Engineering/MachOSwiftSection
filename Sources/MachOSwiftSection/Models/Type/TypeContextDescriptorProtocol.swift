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
            let headerLayout: TypeGenericContextDescriptorHeader.Layout = try machO.fileHandle.read(offset: numericCast(currentOffset + machO.headerStartOffset))
            let header = TypeGenericContextDescriptorHeader(layout: headerLayout, offset: currentOffset)
            currentOffset += MemoryLayout<TypeGenericContextDescriptorHeader.Layout>.size
            let parameters: [GenericParamDescriptor] = try machO.fileHandle.readDataSequence(offset: numericCast(currentOffset + machO.headerStartOffset), numberOfElements: Int(header.base.numParams)).map {
                let result = GenericParamDescriptor(layout: $0, offset: currentOffset)
                currentOffset += MemoryLayout<GenericParamDescriptor>.size
                return result
            }
            currentOffset = numericCast(align(address: numericCast(currentOffset), alignment: 4))
            let requirements: [GenericRequirementDescriptor] = try machO.fileHandle.readDataSequence(offset: numericCast(currentOffset + machO.headerStartOffset), numberOfElements: Int(header.base.numRequirements)).map {
                let result = GenericRequirementDescriptor(layout: $0, offset: currentOffset)
                currentOffset += MemoryLayout<GenericRequirementDescriptor>.size
                return result
            }
            var typePacks: [GenericPackShapeDescriptor] = []
            if header.base.flags.contains(.hasTypePacks) {
                let typePackHeaderLayout: GenericPackShapeHeader.Layout = try machO.fileHandle.read(offset: numericCast(currentOffset + machO.headerStartOffset))
                let typePackHeader = GenericPackShapeHeader(layout: typePackHeaderLayout, offset: currentOffset)
                currentOffset += MemoryLayout<GenericPackShapeHeader.Layout>.size
                typePacks = try machO.fileHandle.readDataSequence(offset: numericCast(currentOffset + machO.headerStartOffset), numberOfElements: Int(typePackHeader.numPacks)).map {
                    let result = GenericPackShapeDescriptor(layout: $0, offset: currentOffset)
                    currentOffset += MemoryLayout<GenericPackShapeDescriptor>.size
                    return result
                }
            }
            genericContext = .init(offset: genericContextOffset, header: header, parameters: parameters, requirements: requirements, typePacks: typePacks)
        }
        return genericContext
    }
}

func align(address: UInt64, alignment: UInt64) -> UInt64 {
    (address + alignment - 1) & ~(alignment - 1)
}
