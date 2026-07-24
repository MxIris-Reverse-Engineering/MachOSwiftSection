import MemberwiseInit
import Semantic
import Demangling

@MemberwiseInit(.public)
public struct ExtensionName: DefinitionName, Hashable, Sendable, Codable {
    public let node: NodeReference

    public let kind: ExtensionKind

    @SemanticStringBuilder
    public func print() -> SemanticString {
        switch kind {
        case .type(.enum):
            TypeDeclaration(kind: .enum, name)
        case .type(.struct):
            TypeDeclaration(kind: .struct, name)
        case .type(.class):
            TypeDeclaration(kind: .class, name)
        case .protocol:
            TypeDeclaration(kind: .protocol, name)
        case .typeAlias:
            TypeDeclaration(kind: .other, name)
        }
    }
}

extension ExtensionName {
    package var isProtocol: Bool {
        switch kind {
        case .protocol: return true
        default: return false
        }
    }
}

// MARK: - Structural Hashable

// See `TypeName`: names hash and compare by node STRUCTURE, not by
// `NodeReference`'s store-identity `Hashable`.
extension ExtensionName {
    public static func == (lhs: ExtensionName, rhs: ExtensionName) -> Bool {
        lhs.kind == rhs.kind && lhs.node.structurallyEquals(rhs.node)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(kind)
        node.structuralHash(into: &hasher)
    }
}

// MARK: - Codable

// Wire-compatible with the historical `node: Node` encoding.
extension ExtensionName {
    private enum CodingKeys: String, CodingKey {
        case node
        case kind
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.node = NodeReference(interning: try container.decode(Node.self, forKey: .node))
        self.kind = try container.decode(ExtensionKind.self, forKey: .kind)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(node.materialize(), forKey: .node)
        try container.encode(kind, forKey: .kind)
    }
}
