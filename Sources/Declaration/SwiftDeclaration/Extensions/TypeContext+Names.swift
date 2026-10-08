import Demangling
import MachOSwiftSection
@_spi(Internals) import MachOSymbols
@_spi(Internals) import SwiftInspection

extension TypeContextWrapper {
    package func typeName(in context: some ReadingContext) throws -> TypeName {
        try typeContextDescriptorWrapper.typeName(in: context)
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

    package func typeName(in context: some ReadingContext) throws -> TypeName {
        return TypeName(node: InternedNodeReferenceCache.shared.reference(interning: try SymbolicDemangler.demangleContext(for: .type(self), in: context), in: context), kind: kind)
    }
}
