import Demangling
import MachOSwiftSection
@_spi(Internals) import MachOSymbols
@_spi(Internals) import SwiftInspection
import SwiftDeclarationRendering

extension ProtocolConformance {
    /// The conforming type's name. A type bound from another image — an
    /// indirect reference that resolved to a symbol — takes its kind from the
    /// demangled symbol; one that names only a type alias (a C typedef) reads
    /// as a struct, as `Node.typeKind` decides.
    package func typeName(in context: some ReadingContext) throws -> TypeName? {
        switch typeReference {
        case .directTypeDescriptor(let descriptor):
            return try descriptor?.typeContextDescriptorWrapper?.typeName(in: context)
        case .indirectTypeDescriptor(let descriptorOrSymbol):
            switch descriptorOrSymbol {
            case .symbol(let symbol):
                guard let node = try SymbolicDemangler.demangleType(for: symbol, in: context)?.first(of: .type) else { return nil }
                guard let kind = node.typeKind else { return nil }
                return TypeName(node: InternedNodeReferenceCache.shared.reference(interning: node, in: context), kind: kind)

            case .element(let element):
                return try element.typeContextDescriptorWrapper?.typeName(in: context)

            case nil:
                return nil
            }
        case .directObjCClassName,
             .indirectObjCClass:
            guard let node = try typeNode(in: context) else { return nil }
            return TypeName(node: InternedNodeReferenceCache.shared.reference(interning: node, in: context), kind: .class)
        }
    }

    package func protocolName(in context: some ReadingContext) throws -> ProtocolName? {
        guard let node = try protocolNode(in: context) else { return nil }
        return ProtocolName(node: InternedNodeReferenceCache.shared.reference(interning: node, in: context))
    }
}
