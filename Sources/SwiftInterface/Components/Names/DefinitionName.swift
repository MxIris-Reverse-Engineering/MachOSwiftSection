import Foundation
import Demangling

public protocol DefinitionName {
    var node: Node { get }
}

extension DefinitionName {
    public var name: String {
        name(using: .interfaceTypeBuilderOnly)
    }
    
    public func name(using options: DemangleOptions) -> String {
        node.print(using: options)
    }

    public var currentName: String {
        name.components(separatedBy: ".").last ?? name
    }
}
