import SwiftDeclaration
import MemberwiseInit

@MemberwiseInit(.public)
public struct SwiftDeclarationIndexConfiguration: Hashable, Codable, Sendable {
    public var showCImportedTypes: Bool = false
}
