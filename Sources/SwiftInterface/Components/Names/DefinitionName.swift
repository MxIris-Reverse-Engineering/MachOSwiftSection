import Foundation

public protocol DefinitionName {
    var name: String { get }
}

extension DefinitionName {
    public var currentName: String {
        name.components(separatedBy: ".").last ?? name
    }
}
