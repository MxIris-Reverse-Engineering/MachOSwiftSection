import Demangling
import MachOSwiftSection
@_spi(Internals) import MachOSymbols
@_spi(Internals) import SwiftInspection

extension ProtocolConformance {
    package func typeName(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> TypeName? {
        switch typeReference {
        case .directTypeDescriptor(let descriptor):
            return try descriptor?.typeContextDescriptorWrapper?.typeName(in: machO)
        case .indirectTypeDescriptor(let descriptorOrSymbol):
            switch descriptorOrSymbol {
            case .symbol(let symbol):
                guard let node = try SymbolicDemangler.demangleType(for: symbol, in: machO)?.first(of: .type) else { return nil }
                guard let kind = node.typeKind else { return nil }
                return TypeName(node: InternedNodeReferenceCache.shared.reference(interning: node, in: machO), kind: kind)

            case .element(let element):
                return try element.typeContextDescriptorWrapper?.typeName(in: machO)

            case nil:
                return nil
            }
        case .directObjCClassName,
             .indirectObjCClass:
            guard let node = try typeNode(in: machO) else { return nil }
            return TypeName(node: InternedNodeReferenceCache.shared.reference(interning: node, in: machO), kind: .class)
        }
    }
    
    package func typeName() throws -> TypeName? {
        switch typeReference {
        case .directTypeDescriptor(let descriptor):
            return try descriptor?.typeContextDescriptorWrapper?.typeName()
        case .indirectTypeDescriptor(let descriptorOrSymbol):
            switch descriptorOrSymbol {
            case .symbol(let symbol):
                guard let node = try SymbolicDemangler.demangleType(for: symbol)?.first(of: .type) else { return nil }
                let allChildren = node.map { $0 }
                let kind: TypeKind
                if allChildren.contains(.enum) || allChildren.contains(.boundGenericEnum) {
                    kind = .enum
                } else if allChildren.contains(.structure) || allChildren.contains(.boundGenericStructure) {
                    kind = .struct
                } else if allChildren.contains(.class) || allChildren.contains(.boundGenericClass) {
                    kind = .class
                } else {
                    return nil
                }
                return TypeName(node: InternedNodeReferenceCache.shared.reference(interning: node), kind: kind)
            case .element(let element):
                return try element.typeContextDescriptorWrapper?.typeName()
            case nil:
                return nil
            }
        case .directObjCClassName,
             .indirectObjCClass:
            guard let node = try typeNode() else { return nil }
            return TypeName(node: InternedNodeReferenceCache.shared.reference(interning: node), kind: .class)
        }
    }

    package func protocolName(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> ProtocolName? {
        guard let node = try protocolNode(in: machO) else { return nil }
        return ProtocolName(node: InternedNodeReferenceCache.shared.reference(interning: node, in: machO))
    }
    
    package func protocolName() throws -> ProtocolName? {
        guard let node = try protocolNode() else { return nil }
        return ProtocolName(node: InternedNodeReferenceCache.shared.reference(interning: node))
    }
}
