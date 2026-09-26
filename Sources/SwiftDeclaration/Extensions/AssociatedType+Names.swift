import Demangling
import MachOSwiftSection
@_spi(Internals) import MachOSymbols
@_spi(Internals) import SwiftInspection

extension AssociatedType {
    package func typeName(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> TypeName? {
        let node = try SymbolicDemangler.demangleType(for: conformingTypeName, in: machO)
        guard let kind = node.typeKind else { return nil }
        return TypeName(node: InternedNodeReferenceCache.shared.reference(interning: node, in: machO), kind: kind)
    }
    
    package func typeName() throws -> TypeName? {
        let node = try SymbolicDemangler.demangleType(for: conformingTypeName)
        guard let kind = node.typeKind else { return nil }
        return TypeName(node: InternedNodeReferenceCache.shared.reference(interning: node), kind: kind)
    }

    package func protocolName(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> ProtocolName {
        ProtocolName(node: InternedNodeReferenceCache.shared.reference(interning: try SymbolicDemangler.demangleType(for: protocolTypeName, in: machO), in: machO))
    }
    
    package func protocolName() throws -> ProtocolName {
        ProtocolName(node: InternedNodeReferenceCache.shared.reference(interning: try SymbolicDemangler.demangleType(for: protocolTypeName)))
    }
}
