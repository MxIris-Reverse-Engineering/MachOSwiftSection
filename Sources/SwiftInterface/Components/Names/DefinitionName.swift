import Foundation
import Demangling

public protocol DefinitionName {
    var node: Node { get }
}

extension DefinitionName {
    public var name: String {
        node.print(using: .interfaceTypeBuilderOnly)
    }

    public var currentName: String {
        name.components(separatedBy: ".").last ?? name
    }
}
