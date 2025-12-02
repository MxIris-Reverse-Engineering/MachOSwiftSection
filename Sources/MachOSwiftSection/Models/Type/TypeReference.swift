import MachOKit
import MachOFoundation

public enum TypeReference: Sendable {
    case directTypeDescriptor(RelativeDirectPointer<ContextDescriptorWrapper?>)
    case indirectTypeDescriptor(RelativeDirectPointer<ContextPointer>)
    case directObjCClassName(RelativeDirectPointer<String?>)
    case indirectObjCClass(RelativeDirectPointer<SymbolOrElementPointer<ClassMetadataObjCInterop?>>)

    public static func forKind(_ kind: TypeReferenceKind, at relativeOffset: RelativeOffset) -> TypeReference {
        switch kind {
        case .directTypeDescriptor:
            return .directTypeDescriptor(.init(relativeOffset: relativeOffset))
        case .indirectTypeDescriptor:
            return .indirectTypeDescriptor(.init(relativeOffset: relativeOffset))
        case .directObjCClassName:
            return .directObjCClassName(.init(relativeOffset: relativeOffset))
        case .indirectObjCClass:
            return .indirectObjCClass(.init(relativeOffset: relativeOffset))
        }
    }

    public func resolve<MachO: MachOSwiftSectionRepresentableWithCache>(at offset: Int, in machO: MachO) throws -> ResolvedTypeReference {
        switch self {
        case .directTypeDescriptor(let relativeDirectPointer):
            return try .directTypeDescriptor(relativeDirectPointer.resolve(from: offset, in: machO))
        case .indirectTypeDescriptor(let relativeIndirectPointer):
            return try .indirectTypeDescriptor(relativeIndirectPointer.resolve(from: offset, in: machO).resolve(in: machO).asOptional)
        case .directObjCClassName(let relativeDirectPointer):
            return try .directObjCClassName(relativeDirectPointer.resolve(from: offset, in: machO))
        case .indirectObjCClass(let relativeIndirectPointer):
            return try .indirectObjCClass(relativeIndirectPointer.resolve(from: offset, in: machO).resolve(in: machO).asOptional)
        }
    }

    public func resolve(from ptr: UnsafeRawPointer) throws -> ResolvedTypeReference {
        switch self {
        case .directTypeDescriptor(let relativeDirectPointer):
            return try .directTypeDescriptor(relativeDirectPointer.resolve(from: ptr))
        case .indirectTypeDescriptor(let relativeIndirectPointer):
            return try .indirectTypeDescriptor(relativeIndirectPointer.resolve(from: ptr).resolve().asOptional)
        case .directObjCClassName(let relativeDirectPointer):
            return try .directObjCClassName(relativeDirectPointer.resolve(from: ptr))
        case .indirectObjCClass(let relativeIndirectPointer):
            return try .indirectObjCClass(relativeIndirectPointer.resolve(from: ptr).resolve().asOptional)
        }
    }
}

public enum ResolvedTypeReference: Sendable {
    case directTypeDescriptor(ContextDescriptorWrapper?)
    case indirectTypeDescriptor(SymbolOrElement<ContextDescriptorWrapper>?)
    case directObjCClassName(String?)
    case indirectObjCClass(SymbolOrElement<ClassMetadataObjCInterop>?)
}
