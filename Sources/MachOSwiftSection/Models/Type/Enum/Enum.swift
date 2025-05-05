import Foundation
import MachOKit

//public struct Enum {
//    public let descriptor: EnumDescriptor
//    public let genericContext: TypeGenericContext?
//    public let foreignMetadataInitialization: ForeignMetadataInitialization?
//    public let singletonMetadataInitialization: SingletonMetadataInitialization?
//    public let canonicalSpecializedMetadatas: [Metadata]?
//    
//    public static func parse(from descriptor: EnumDescriptor, in machO: MachOFile) throws -> Enum {
//        let originOffset = try machO.fileHandle.offset()
//        var genericContext: TypeGenericContext? = nil
//        if descriptor.context.context.flags.contains(.isGeneric) {
//            var currentOffset = descriptor.offset + MemoryLayout<EnumDescriptor.Layout>.size
//            let genericContextOffset = currentOffset
//            let headerLayout: TypeGenericContextDescriptorHeader.Layout = machO.fileHandle.read(offset: numericCast(currentOffset + machO.headerStartOffset))
//            let header = TypeGenericContextDescriptorHeader(offset: currentOffset, layout: headerLayout)
//            currentOffset += MemoryLayout<TypeGenericContextDescriptorHeader.Layout>.size
//            let parameters: [GenericParamDescriptor] = machO.fileHandle.readDataSequence(offset: numericCast(currentOffset + machO.headerStartOffset), numberOfElements: Int(header.base.numParams)).map {
//                let result = GenericParamDescriptor(offset: currentOffset, layout: $0)
//                currentOffset += MemoryLayout<GenericParamDescriptor>.size
//                return result
//            }
//            let requirements: [GenericRequirementDescriptor] = machO.fileHandle.readDataSequence(offset: numericCast(currentOffset + machO.headerStartOffset), numberOfElements: Int(header.base.numRequirements)).map {
//                let result = GenericRequirementDescriptor(offset: currentOffset, layout: $0)
//                currentOffset += MemoryLayout<GenericRequirementDescriptor>.size
//                return result
//            }
//            var typePacks: [GenericPackShapeDescriptor] = []
//            if header.base.flags.contains(.hasTypePacks) {
//                let typePackHeaderLayout: GenericPackShapeHeader.Layout = machO.fileHandle.read(offset: numericCast(currentOffset + machO.headerStartOffset))
//                let typePackHeader = GenericPackShapeHeader(offset: currentOffset, layout: typePackHeaderLayout)
//                currentOffset += MemoryLayout<GenericPackShapeHeader.Layout>.size
//                typePacks = machO.fileHandle.readDataSequence(offset: numericCast(currentOffset + machO.headerStartOffset), numberOfElements: Int(typePackHeader.numPacks)).map {
//                    let result = GenericPackShapeDescriptor(offset: currentOffset, layout: $0)
//                    currentOffset += MemoryLayout<GenericPackShapeDescriptor>.size
//                    return result
//                }
//            }
//            genericContext = .init(offset: genericContextOffset, header: header, parameters: parameters, requirements: requirements, typePacks: typePacks)
//        }
//        
//        if descriptor.context.context.flags.kindSpecificFlags.hasForeignMetadataInitialization {
//            
//        }
//        
//        try machO.fileHandle.seek(toOffset: numericCast(originOffset))
//        return .init(descriptor: descriptor, genericContext: genericContext)
//    }
//}
