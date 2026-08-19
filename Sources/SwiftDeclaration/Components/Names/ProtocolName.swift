import MemberwiseInit
import Semantic
import Demangling

@MemberwiseInit(.public)
public struct ProtocolName: DefinitionName, Hashable, Sendable {
    public let node: NodeReference

    @SemanticStringBuilder
    public func print() -> SemanticString {
        TypeDeclaration(kind: .protocol, name)
    }
}

extension ProtocolName {
    public var extensionName: ExtensionName {
        ExtensionName(node: node, kind: .protocol)
    }
}

// MARK: - Structural Hashable

// See `TypeName`: names hash and compare by node STRUCTURE, not by
// `NodeReference`'s store-identity `Hashable`.
extension ProtocolName {
    public static func == (lhs: ProtocolName, rhs: ProtocolName) -> Bool {
        lhs.node.structurallyEquals(rhs.node)
    }

    public func hash(into hasher: inout Hasher) {
        node.structuralHash(into: &hasher)
    }
}
