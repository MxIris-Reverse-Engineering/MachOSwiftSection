import Foundation
import MachOFoundation
import SwiftStdlibToolbox

@CaseCheckable(.public)
@AssociatedValue(.public)
public enum MetadataWrapper: Resolvable {
    case `class`(ClassMetadataObjCInterop)
    case `struct`(StructMetadata)
    case `enum`(EnumMetadata)
    case optional(EnumMetadata)
    case foreignClass(ForeignClassMetadata)
    case foreignReferenceType(ForeignReferenceTypeMetadata)
    case opaque(OpaqueMetadata)
    case tuple(TupleTypeMetadata)
    case function(FunctionTypeMetadata)
    case existential(ExistentialTypeMetadata)
    case metatype(MetatypeMetadata)
    case objcClassWrapper(ObjCClassWrapperMetadata)
    case existentialMetatype(ExistentialMetatypeMetadata)
    case extendedExistential(ExtendedExistentialTypeMetadata)
    case fixedArray(FixedArrayTypeMetadata)
    case heapLocalVariable(HeapLocalVariableMetadata)
    case heapGenericLocalVariable(GenericBoxHeapMetadata)
    case errorObject(EnumMetadata)
    case task(DispatchClassMetadata)
    case job(DispatchClassMetadata)

    public var anyMetadata: any MetadataProtocol {
        switch self {
        case .class(let classMetadataObjCInterop):
            return classMetadataObjCInterop
        case .struct(let structMetadata):
            return structMetadata
        case .enum(let enumMetadata):
            return enumMetadata
        case .optional(let enumMetadata):
            return enumMetadata
        case .foreignClass(let foreignClassMetadata):
            return foreignClassMetadata
        case .foreignReferenceType(let foreignReferenceTypeMetadata):
            return foreignReferenceTypeMetadata
        case .opaque(let opaqueMetadata):
            return opaqueMetadata
        case .tuple(let tupleTypeMetadata):
            return tupleTypeMetadata
        case .function(let functionTypeMetadata):
            return functionTypeMetadata
        case .existential(let existentialTypeMetadata):
            return existentialTypeMetadata
        case .metatype(let metatypeMetadata):
            return metatypeMetadata
        case .objcClassWrapper(let objCClassWrapperMetadata):
            return objCClassWrapperMetadata
        case .existentialMetatype(let existentialMetatypeMetadata):
            return existentialMetatypeMetadata
        case .extendedExistential(let extendedExistentialTypeMetadata):
            return extendedExistentialTypeMetadata
        case .fixedArray(let fixedArrayTypeMetadata):
            return fixedArrayTypeMetadata
        case .heapLocalVariable(let heapLocalVariableMetadata):
            return heapLocalVariableMetadata
        case .heapGenericLocalVariable(let genericBoxHeapMetadata):
            return genericBoxHeapMetadata
        case .errorObject(let enumMetadata):
            return enumMetadata
        case .task(let dispatchClassMetadata):
            return dispatchClassMetadata
        case .job(let dispatchClassMetadata):
            return dispatchClassMetadata
        }
    }
    
    public static func resolve<MachO: MachORepresentableWithCache & Readable>(from offset: Int, in machO: MachO) throws -> Self {
        let metadata = try machO.readWrapperElement(offset: offset) as Metadata
        switch metadata.kind {
        case .class:
            return try .class(machO.readWrapperElement(offset: offset))
        case .struct:
            return try .struct(machO.readWrapperElement(offset: offset))
        case .enum:
            return try .enum(machO.readWrapperElement(offset: offset))
        case .optional:
            return try .optional(machO.readWrapperElement(offset: offset))
        case .foreignClass:
            return try .foreignClass(machO.readWrapperElement(offset: offset))
        case .foreignReferenceType:
            return try .foreignReferenceType(machO.readWrapperElement(offset: offset))
        case .opaque:
            return try .opaque(machO.readWrapperElement(offset: offset))
        case .tuple:
            return try .tuple(machO.readWrapperElement(offset: offset))
        case .function:
            return try .function(machO.readWrapperElement(offset: offset))
        case .existential:
            return try .existential(machO.readWrapperElement(offset: offset))
        case .metatype:
            return try .metatype(machO.readWrapperElement(offset: offset))
        case .objcClassWrapper:
            return try .objcClassWrapper(machO.readWrapperElement(offset: offset))
        case .existentialMetatype:
            return try .existentialMetatype(machO.readWrapperElement(offset: offset))
        case .extendedExistential:
            return try .extendedExistential(machO.readWrapperElement(offset: offset))
        case .fixedArray:
            return try .fixedArray(machO.readWrapperElement(offset: offset))
        case .heapLocalVariable:
            return try .heapLocalVariable(machO.readWrapperElement(offset: offset))
        case .heapGenericLocalVariable:
            return try .heapGenericLocalVariable(machO.readWrapperElement(offset: offset))
        case .errorObject:
            return try .errorObject(machO.readWrapperElement(offset: offset))
        case .task:
            return try .task(machO.readWrapperElement(offset: offset))
        case .job:
            return try .job(machO.readWrapperElement(offset: offset))
        case .lastEnumerated:
            fatalError()
        }
    }

    public static func resolve(from ptr: UnsafeRawPointer) throws -> Self {
        let metadata = try Metadata.resolve(from: ptr)
        switch metadata.kind {
        case .class:
            return try .class(.resolve(from: ptr))
        case .struct:
            return try .struct(.resolve(from: ptr))
        case .enum:
            return try .enum(.resolve(from: ptr))
        case .optional:
            return try .optional(.resolve(from: ptr))
        case .foreignClass:
            return try .foreignClass(.resolve(from: ptr))
        case .foreignReferenceType:
            return try .foreignReferenceType(.resolve(from: ptr))
        case .opaque:
            return try .opaque(.resolve(from: ptr))
        case .tuple:
            return try .tuple(.resolve(from: ptr))
        case .function:
            return try .function(.resolve(from: ptr))
        case .existential:
            return try .existential(.resolve(from: ptr))
        case .metatype:
            return try .metatype(.resolve(from: ptr))
        case .objcClassWrapper:
            return try .objcClassWrapper(.resolve(from: ptr))
        case .existentialMetatype:
            return try .existentialMetatype(.resolve(from: ptr))
        case .extendedExistential:
            return try .extendedExistential(.resolve(from: ptr))
        case .fixedArray:
            return try .fixedArray(.resolve(from: ptr))
        case .heapLocalVariable:
            return try .heapLocalVariable(.resolve(from: ptr))
        case .heapGenericLocalVariable:
            return try .heapGenericLocalVariable(.resolve(from: ptr))
        case .errorObject:
            return try .errorObject(.resolve(from: ptr))
        case .task:
            return try .task(.resolve(from: ptr))
        case .job:
            return try .job(.resolve(from: ptr))
        case .lastEnumerated:
            fatalError()
        }
    }
}
