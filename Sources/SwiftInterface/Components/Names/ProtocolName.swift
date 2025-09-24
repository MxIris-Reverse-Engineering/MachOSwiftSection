import MemberwiseInit
import Semantic

@MemberwiseInit(.public)
public struct ProtocolName: DefinitionName, Hashable, Sendable {
    public let name: String
    
    @SemanticStringBuilder
    public func print() -> SemanticString {
        TypeDeclaration(kind: .protocol, name)
    }
}

extension ProtocolName {
    public var extensionName: ExtensionName {
        ExtensionName(name: name, kind: .protocol)
    }
}
