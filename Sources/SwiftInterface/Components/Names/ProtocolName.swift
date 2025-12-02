import MemberwiseInit
import Semantic
import Demangling

@MemberwiseInit(.public)
public struct ProtocolName: DefinitionName, Hashable, Sendable {
    public let node: Node

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
