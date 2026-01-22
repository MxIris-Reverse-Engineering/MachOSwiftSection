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
    
    public var metadata: Metadata {
        get throws {
            switch self {
            case .class(let classMetadataObjCInterop):
                return try classMetadataObjCInterop.asMetadata()
            case .struct(let structMetadata):
                return try structMetadata.asMetadata()
            case .enum(let enumMetadata):
                return try enumMetadata.asMetadata()
            case .optional(let enumMetadata):
                return try enumMetadata.asMetadata()
            case .foreignClass(let foreignClassMetadata):
                return try foreignClassMetadata.asMetadata()
            case .foreignReferenceType(let foreignReferenceTypeMetadata):
                return try foreignReferenceTypeMetadata.asMetadata()
            case .opaque(let opaqueMetadata):
                return try opaqueMetadata.asMetadata()
            case .tuple(let tupleTypeMetadata):
                return try tupleTypeMetadata.asMetadata()
            case .function(let functionTypeMetadata):
                return try functionTypeMetadata.asMetadata()
            case .existential(let existentialTypeMetadata):
                return try existentialTypeMetadata.asMetadata()
            case .metatype(let metatypeMetadata):
                return try metatypeMetadata.asMetadata()
            case .objcClassWrapper(let objCClassWrapperMetadata):
                return try objCClassWrapperMetadata.asMetadata()
            case .existentialMetatype(let existentialMetatypeMetadata):
                return try existentialMetatypeMetadata.asMetadata()
            case .extendedExistential(let extendedExistentialTypeMetadata):
                return try extendedExistentialTypeMetadata.asMetadata()
            case .fixedArray(let fixedArrayTypeMetadata):
                return try fixedArrayTypeMetadata.asMetadata()
            case .heapLocalVariable(let heapLocalVariableMetadata):
                return try heapLocalVariableMetadata.asMetadata()
            case .heapGenericLocalVariable(let genericBoxHeapMetadata):
                return try genericBoxHeapMetadata.asMetadata()
            case .errorObject(let enumMetadata):
                return try enumMetadata.asMetadata()
            case .task(let dispatchClassMetadata):
                return try dispatchClassMetadata.asMetadata()
            case .job(let dispatchClassMetadata):
                return try dispatchClassMetadata.asMetadata()
            }
        }
    }
    
    public func valueWitnessTable(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> ValueWitnessTable {
        switch self {
        case .class(let classMetadataObjCInterop):
            return try classMetadataObjCInterop.asFullMetadata(in: machO).valueWitnesses.resolve(in: machO)
        case .struct(let structMetadata):
            return try structMetadata.asFullMetadata(in: machO).valueWitnesses.resolve(in: machO)
        case .enum(let enumMetadata):
            return try enumMetadata.asFullMetadata(in: machO).valueWitnesses.resolve(in: machO)
        case .optional(let enumMetadata):
            return try enumMetadata.asFullMetadata(in: machO).valueWitnesses.resolve(in: machO)
        case .foreignClass(let foreignClassMetadata):
            return try foreignClassMetadata.asFullMetadata(in: machO).valueWitnesses.resolve(in: machO)
        case .foreignReferenceType(let foreignReferenceTypeMetadata):
            return try foreignReferenceTypeMetadata.asFullMetadata(in: machO).valueWitnesses.resolve(in: machO)
        case .opaque(let opaqueMetadata):
            return try opaqueMetadata.asFullMetadata(in: machO).valueWitnesses.resolve(in: machO)
        case .tuple(let tupleTypeMetadata):
            return try tupleTypeMetadata.asFullMetadata(in: machO).valueWitnesses.resolve(in: machO)
        case .function(let functionTypeMetadata):
            return try functionTypeMetadata.asFullMetadata(in: machO).valueWitnesses.resolve(in: machO)
        case .existential(let existentialTypeMetadata):
            return try existentialTypeMetadata.asFullMetadata(in: machO).valueWitnesses.resolve(in: machO)
        case .metatype(let metatypeMetadata):
            return try metatypeMetadata.asFullMetadata(in: machO).valueWitnesses.resolve(in: machO)
        case .objcClassWrapper(let objCClassWrapperMetadata):
            return try objCClassWrapperMetadata.asFullMetadata(in: machO).valueWitnesses.resolve(in: machO)
        case .existentialMetatype(let existentialMetatypeMetadata):
            return try existentialMetatypeMetadata.asFullMetadata(in: machO).valueWitnesses.resolve(in: machO)
        case .extendedExistential(let extendedExistentialTypeMetadata):
            return try extendedExistentialTypeMetadata.asFullMetadata(in: machO).valueWitnesses.resolve(in: machO)
        case .fixedArray(let fixedArrayTypeMetadata):
            return try fixedArrayTypeMetadata.asFullMetadata(in: machO).valueWitnesses.resolve(in: machO)
        case .heapLocalVariable(let heapLocalVariableMetadata):
            return try heapLocalVariableMetadata.asFullMetadata(in: machO).valueWitnesses.resolve(in: machO)
        case .heapGenericLocalVariable(let genericBoxHeapMetadata):
            return try genericBoxHeapMetadata.asFullMetadata(in: machO).valueWitnesses.resolve(in: machO)
        case .errorObject(let enumMetadata):
            return try enumMetadata.asFullMetadata(in: machO).valueWitnesses.resolve(in: machO)
        case .task(let dispatchClassMetadata):
            return try dispatchClassMetadata.asFullMetadata(in: machO).valueWitnesses.resolve(in: machO)
        case .job(let dispatchClassMetadata):
            return try dispatchClassMetadata.asFullMetadata(in: machO).valueWitnesses.resolve(in: machO)
        }
    }
    
    public func valueWitnessTable() throws -> ValueWitnessTable {
        switch self {
        case .class(let classMetadataObjCInterop):
            return try classMetadataObjCInterop.asFullMetadata().valueWitnesses.resolve()
        case .struct(let structMetadata):
            return try structMetadata.asFullMetadata().valueWitnesses.resolve()
        case .enum(let enumMetadata):
            return try enumMetadata.asFullMetadata().valueWitnesses.resolve()
        case .optional(let enumMetadata):
            return try enumMetadata.asFullMetadata().valueWitnesses.resolve()
        case .foreignClass(let foreignClassMetadata):
            return try foreignClassMetadata.asFullMetadata().valueWitnesses.resolve()
        case .foreignReferenceType(let foreignReferenceTypeMetadata):
            return try foreignReferenceTypeMetadata.asFullMetadata().valueWitnesses.resolve()
        case .opaque(let opaqueMetadata):
            return try opaqueMetadata.asFullMetadata().valueWitnesses.resolve()
        case .tuple(let tupleTypeMetadata):
            return try tupleTypeMetadata.asFullMetadata().valueWitnesses.resolve()
        case .function(let functionTypeMetadata):
            return try functionTypeMetadata.asFullMetadata().valueWitnesses.resolve()
        case .existential(let existentialTypeMetadata):
            return try existentialTypeMetadata.asFullMetadata().valueWitnesses.resolve()
        case .metatype(let metatypeMetadata):
            return try metatypeMetadata.asFullMetadata().valueWitnesses.resolve()
        case .objcClassWrapper(let objCClassWrapperMetadata):
            return try objCClassWrapperMetadata.asFullMetadata().valueWitnesses.resolve()
        case .existentialMetatype(let existentialMetatypeMetadata):
            return try existentialMetatypeMetadata.asFullMetadata().valueWitnesses.resolve()
        case .extendedExistential(let extendedExistentialTypeMetadata):
            return try extendedExistentialTypeMetadata.asFullMetadata().valueWitnesses.resolve()
        case .fixedArray(let fixedArrayTypeMetadata):
            return try fixedArrayTypeMetadata.asFullMetadata().valueWitnesses.resolve()
        case .heapLocalVariable(let heapLocalVariableMetadata):
            return try heapLocalVariableMetadata.asFullMetadata().valueWitnesses.resolve()
        case .heapGenericLocalVariable(let genericBoxHeapMetadata):
            return try genericBoxHeapMetadata.asFullMetadata().valueWitnesses.resolve()
        case .errorObject(let enumMetadata):
            return try enumMetadata.asFullMetadata().valueWitnesses.resolve()
        case .task(let dispatchClassMetadata):
            return try dispatchClassMetadata.asFullMetadata().valueWitnesses.resolve()
        case .job(let dispatchClassMetadata):
            return try dispatchClassMetadata.asFullMetadata().valueWitnesses.resolve()
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
