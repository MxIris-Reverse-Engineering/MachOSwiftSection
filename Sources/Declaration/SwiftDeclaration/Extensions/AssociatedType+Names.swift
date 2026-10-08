import Demangling
import MachOSwiftSection
@_spi(Internals) import MachOSymbols
@_spi(Internals) import SwiftInspection

extension AssociatedType {
    package func typeName(in context: some ReadingContext) throws -> TypeName? {
        let node = try SymbolicDemangler.demangleType(for: conformingTypeName, in: context)
        guard let kind = node.typeKind else { return nil }
        return TypeName(node: InternedNodeReferenceCache.shared.reference(interning: node, in: context), kind: kind)
    }

    package func protocolName(in context: some ReadingContext) throws -> ProtocolName {
        ProtocolName(node: InternedNodeReferenceCache.shared.reference(interning: try SymbolicDemangler.demangleType(for: protocolTypeName, in: context), in: context))
    }
}
