import SwiftStdlibToolbox

@AssociatedValue(.public)
@CaseCheckable(.public)
public enum ExtensionKind: Hashable, Sendable, Codable {
    case type(TypeKind)
    case `protocol`
    case typeAlias
}
