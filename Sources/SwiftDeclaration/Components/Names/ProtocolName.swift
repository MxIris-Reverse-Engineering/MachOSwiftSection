import MemberwiseInit
import Semantic
import Demangling

@MemberwiseInit(.public)
public struct ProtocolName: DefinitionName, Hashable, Sendable, Codable {
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

// MARK: - Codable

// Wire-compatible with the historical `node: Node` encoding.
extension ProtocolName {
    private enum CodingKeys: String, CodingKey {
        case node
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.node = NodeReference(interning: try container.decode(Node.self, forKey: .node))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(node.materialize(), forKey: .node)
    }
}
