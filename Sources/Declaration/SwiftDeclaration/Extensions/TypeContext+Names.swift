import Demangling
import MachOSwiftSection
@_spi(Internals) import MachOSymbols
@_spi(Internals) import SwiftInspection

extension TypeContextWrapper {
    package func typeName(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> TypeName {
        try typeContextDescriptorWrapper.typeName(in: machO)
    }
    
    package func typeName() throws -> TypeName {
        try typeContextDescriptorWrapper.typeName()
    }
}

extension TypeContextDescriptorWrapper {
    package var kind: TypeKind {
        switch self {
        case .enum:
            .enum
        case .struct:
            .struct
        case .class:
            .class
        }
    }

    package func typeName(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> TypeName {
        return TypeName(node: InternedNodeReferenceCache.shared.reference(interning: try SymbolicDemangler.demangleContext(for: .type(self), in: machO), in: machO), kind: kind)
    }
    
    package func typeName() throws -> TypeName {
        return TypeName(node: InternedNodeReferenceCache.shared.reference(interning: try SymbolicDemangler.demangleContext(for: .type(self))), kind: kind)
    }
}
