import Foundation
@_spi(Support) import MachOKit

public protocol TypeContextDescriptorProtocol: LayoutWrapperWithOffset where Layout: TypeContextDescriptorLayout {}

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

    public func name(in machO: MachOFile) -> String {
        layout.name.resolve(from: _offset(of: \.name).cast(), in: machO)
    }

    public func parent(in machO: MachOFile) -> ContextDescriptorWrapper? {
        guard layout.parent != 0 else { return nil }
        return machO.swift._readContextDescriptor(from: numericCast(_offset(of: \.parent) + Int(layout.parent)), in: machO)
    }

    public func fieldDescriptor(in machO: MachOFile) -> FieldDescriptor {
        layout.fieldDescriptor.resolve(from: _offset(of: \.fieldDescriptor).cast(), in: machO)
    }

    public func typeGenericContext(in machO: MachOFile) -> TypeGenericContext? {
        var genericContext: TypeGenericContext?
        if layout.flags.contains(.isGeneric) {
            var currentOffset = offset + layoutSize
            let genericContextOffset = currentOffset
            let headerLayout: TypeGenericContextDescriptorHeader.Layout = machO.fileHandle.read(offset: numericCast(currentOffset + machO.headerStartOffset))
            let header = TypeGenericContextDescriptorHeader(offset: currentOffset, layout: headerLayout)
            currentOffset += MemoryLayout<TypeGenericContextDescriptorHeader.Layout>.size
            let parameters: [GenericParamDescriptor] = machO.fileHandle.readDataSequence(offset: numericCast(currentOffset + machO.headerStartOffset), numberOfElements: Int(header.base.numParams)).map {
                let result = GenericParamDescriptor(offset: currentOffset, layout: $0)
                currentOffset += MemoryLayout<GenericParamDescriptor>.size
                return result
            }
            currentOffset = numericCast(align(address: numericCast(currentOffset), alignment: 4))
            let requirements: [GenericRequirementDescriptor] = machO.fileHandle.readDataSequence(offset: numericCast(currentOffset + machO.headerStartOffset), numberOfElements: Int(header.base.numRequirements)).map {
                let result = GenericRequirementDescriptor(offset: currentOffset, layout: $0)
                currentOffset += MemoryLayout<GenericRequirementDescriptor>.size
                return result
            }
            var typePacks: [GenericPackShapeDescriptor] = []
            if header.base.flags.contains(.hasTypePacks) {
                let typePackHeaderLayout: GenericPackShapeHeader.Layout = machO.fileHandle.read(offset: numericCast(currentOffset + machO.headerStartOffset))
                let typePackHeader = GenericPackShapeHeader(offset: currentOffset, layout: typePackHeaderLayout)
                currentOffset += MemoryLayout<GenericPackShapeHeader.Layout>.size
                typePacks = machO.fileHandle.readDataSequence(offset: numericCast(currentOffset + machO.headerStartOffset), numberOfElements: Int(typePackHeader.numPacks)).map {
                    let result = GenericPackShapeDescriptor(offset: currentOffset, layout: $0)
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
