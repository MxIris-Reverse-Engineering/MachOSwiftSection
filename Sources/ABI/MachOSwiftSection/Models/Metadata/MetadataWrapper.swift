import Foundation
import MachOBase
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
    case borrow(BorrowTypeMetadata)
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
        case .borrow(let borrowTypeMetadata):
            return borrowTypeMetadata
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
}

// MARK: - ReadingContext Support

extension MetadataWrapper {
    // On arm64e the value-witness-table slot in a live `TargetFullMetadata`
    // header is PAC-signed (`__ptrauth_swift_value_witness_table`). Every leg
    // below is safe as long as it dereferences through `Pointer.resolve` —
    // `PointerProtocol.resolve(in:)` / `InProcessContext` strip pointer tags on
    // every in-process read (evolution proposal 0004). Do not replace these
    // with raw pointer arithmetic.
    public func valueWitnessTable(in context: some ReadingContext) throws -> ValueWitnessTable {
        switch self {
        case .class(let classMetadataObjCInterop):
            return try classMetadataObjCInterop.asFullMetadata(in: context).valueWitnesses.resolve(in: context)
        case .struct(let structMetadata):
            return try structMetadata.asFullMetadata(in: context).valueWitnesses.resolve(in: context)
        case .enum(let enumMetadata):
            return try enumMetadata.asFullMetadata(in: context).valueWitnesses.resolve(in: context)
        case .optional(let enumMetadata):
            return try enumMetadata.asFullMetadata(in: context).valueWitnesses.resolve(in: context)
        case .foreignClass(let foreignClassMetadata):
            return try foreignClassMetadata.asFullMetadata(in: context).valueWitnesses.resolve(in: context)
        case .foreignReferenceType(let foreignReferenceTypeMetadata):
            return try foreignReferenceTypeMetadata.asFullMetadata(in: context).valueWitnesses.resolve(in: context)
        case .opaque(let opaqueMetadata):
            return try opaqueMetadata.asFullMetadata(in: context).valueWitnesses.resolve(in: context)
        case .tuple(let tupleTypeMetadata):
            return try tupleTypeMetadata.asFullMetadata(in: context).valueWitnesses.resolve(in: context)
        case .function(let functionTypeMetadata):
            return try functionTypeMetadata.asFullMetadata(in: context).valueWitnesses.resolve(in: context)
        case .existential(let existentialTypeMetadata):
            return try existentialTypeMetadata.asFullMetadata(in: context).valueWitnesses.resolve(in: context)
        case .metatype(let metatypeMetadata):
            return try metatypeMetadata.asFullMetadata(in: context).valueWitnesses.resolve(in: context)
        case .objcClassWrapper(let objCClassWrapperMetadata):
            return try objCClassWrapperMetadata.asFullMetadata(in: context).valueWitnesses.resolve(in: context)
        case .existentialMetatype(let existentialMetatypeMetadata):
            return try existentialMetatypeMetadata.asFullMetadata(in: context).valueWitnesses.resolve(in: context)
        case .extendedExistential(let extendedExistentialTypeMetadata):
            return try extendedExistentialTypeMetadata.asFullMetadata(in: context).valueWitnesses.resolve(in: context)
        case .fixedArray(let fixedArrayTypeMetadata):
            return try fixedArrayTypeMetadata.asFullMetadata(in: context).valueWitnesses.resolve(in: context)
        case .borrow(let borrowTypeMetadata):
            return try borrowTypeMetadata.asFullMetadata(in: context).valueWitnesses.resolve(in: context)
        case .heapLocalVariable(let heapLocalVariableMetadata):
            return try heapLocalVariableMetadata.asFullMetadata(in: context).valueWitnesses.resolve(in: context)
        case .heapGenericLocalVariable(let genericBoxHeapMetadata):
            return try genericBoxHeapMetadata.asFullMetadata(in: context).valueWitnesses.resolve(in: context)
        case .errorObject(let enumMetadata):
            return try enumMetadata.asFullMetadata(in: context).valueWitnesses.resolve(in: context)
        case .task(let dispatchClassMetadata):
            return try dispatchClassMetadata.asFullMetadata(in: context).valueWitnesses.resolve(in: context)
        case .job(let dispatchClassMetadata):
            return try dispatchClassMetadata.asFullMetadata(in: context).valueWitnesses.resolve(in: context)
        }
    }

    public static func resolve<Context: ReadingContext>(at address: Context.Address, in context: Context) throws -> Self {
        let metadata = try context.readWrapperElement(at: address) as Metadata
        switch metadata.kind {
        case .class:
            return try .class(context.readWrapperElement(at: address))
        case .struct:
            return try .struct(context.readWrapperElement(at: address))
        case .enum:
            return try .enum(context.readWrapperElement(at: address))
        case .optional:
            return try .optional(context.readWrapperElement(at: address))
        case .foreignClass:
            return try .foreignClass(context.readWrapperElement(at: address))
        case .foreignReferenceType:
            return try .foreignReferenceType(context.readWrapperElement(at: address))
        case .opaque:
            return try .opaque(context.readWrapperElement(at: address))
        case .tuple:
            return try .tuple(context.readWrapperElement(at: address))
        case .function:
            return try .function(context.readWrapperElement(at: address))
        case .existential:
            return try .existential(context.readWrapperElement(at: address))
        case .metatype:
            return try .metatype(context.readWrapperElement(at: address))
        case .objcClassWrapper:
            return try .objcClassWrapper(context.readWrapperElement(at: address))
        case .existentialMetatype:
            return try .existentialMetatype(context.readWrapperElement(at: address))
        case .extendedExistential:
            return try .extendedExistential(context.readWrapperElement(at: address))
        case .fixedArray:
            return try .fixedArray(context.readWrapperElement(at: address))
        case .borrow:
            return try .borrow(context.readWrapperElement(at: address))
        case .heapLocalVariable:
            return try .heapLocalVariable(context.readWrapperElement(at: address))
        case .heapGenericLocalVariable:
            return try .heapGenericLocalVariable(context.readWrapperElement(at: address))
        case .errorObject:
            return try .errorObject(context.readWrapperElement(at: address))
        case .task:
            return try .task(context.readWrapperElement(at: address))
        case .job:
            return try .job(context.readWrapperElement(at: address))
        case .lastEnumerated:
            throw MachOSwiftSectionError.unknownMetadataKind(rawValue: UInt(metadata.kind.rawValue))
        }
    }
}

// MARK: - Deprecated Mach-O and pointer forms

extension MetadataWrapper {
    @available(*, deprecated, message: "Pass a ReadingContext: anyMetadata.asMetadata(in: .inProcess).")
    public var metadata: Metadata {
        get throws {
            try anyMetadata.asMetadata(in: InProcessContext.shared)
        }
    }

    @available(*, deprecated, message: "Pass a ReadingContext: valueWitnessTable(in: machO.context).")
    public func valueWitnessTable(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> ValueWitnessTable {
        try valueWitnessTable(in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: valueWitnessTable(in: .inProcess).")
    public func valueWitnessTable() throws -> ValueWitnessTable {
        try valueWitnessTable(in: InProcessContext.shared)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: resolve(at: offset, in: machO.context).")
    public static func resolve(from offset: Int, in machO: some MachORepresentableWithCache & Readable) throws -> Self {
        try resolve(at: offset, in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: resolve(at: pointer, in: .inProcess).")
    public static func resolve(from ptr: UnsafeRawPointer) throws -> Self {
        try resolve(at: ptr, in: InProcessContext.shared)
    }
}
