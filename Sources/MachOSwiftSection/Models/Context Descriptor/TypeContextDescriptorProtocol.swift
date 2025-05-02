import Foundation
@_spi(Support) import MachOKit

public protocol TypeContextDescriptorLayoutProtocol {
    var context: ContextDescriptor.Layout { get }
    var name: RelativeDirectPointer { get }
    var accessFunctionPtr: RelativeDirectPointer { get }
    var fieldDescriptor: RelativeDirectPointer { get }
}

public protocol TypeContextDescriptorProtocol: LayoutWrapperWithOffset where Layout: TypeContextDescriptorLayoutProtocol {}

extension TypeContextDescriptorProtocol {
    public func typeGenericContext(in machO: MachOFile) -> TypeGenericContext? {
        var genericContext: TypeGenericContext?
        if layout.context.flags.contains(.isGeneric) {
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
