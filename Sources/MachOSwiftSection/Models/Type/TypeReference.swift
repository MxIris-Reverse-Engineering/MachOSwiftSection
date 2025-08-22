import MachOKit
import MachOMacro
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

    
    public func resolve<MachO: MachORepresentableWithCache & MachOReadable>(at offset: Int, in machO: MachO) throws -> ResolvedTypeReference {
        switch self {
        case let .directTypeDescriptor(relativeDirectPointer):
            return try .directTypeDescriptor(relativeDirectPointer.resolve(from: offset, in: machO))
        case let .indirectTypeDescriptor(relativeIndirectPointer):
            return try .indirectTypeDescriptor(relativeIndirectPointer.resolve(from: offset, in: machO).resolve(in: machO).asOptional)
        case let .directObjCClassName(relativeDirectPointer):
            return try .directObjCClassName(relativeDirectPointer.resolve(from: offset, in: machO))
        case let .indirectObjCClass(relativeIndirectPointer):
            return try .indirectObjCClass(relativeIndirectPointer.resolve(from: offset, in: machO).resolve(in: machO).asOptional)
        }
    }
}

public enum ResolvedTypeReference: Sendable {
    case directTypeDescriptor(ContextDescriptorWrapper?)
    case indirectTypeDescriptor(SymbolOrElement<ContextDescriptorWrapper>?)
    case directObjCClassName(String?)
    case indirectObjCClass(SymbolOrElement<ClassMetadataObjCInterop>?)
}
