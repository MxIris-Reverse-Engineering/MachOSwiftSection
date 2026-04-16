import SwiftDump
import MachOSwiftSection
import Demangling

/// Infers member-level Swift attributes by analyzing demangled Node trees and MethodDescriptorFlags.
///
/// Detectable attributes:
/// - `@objc`: Node tree has `.objCAttribute` child (from @objc thunk symbols)
/// - `@nonobjc`: Node tree has `.nonObjCAttribute` child
/// - `dynamic`: `MethodDescriptorFlags.isDynamic` is true
public struct MemberAttributeInferrer: Sendable {
    public init() {}

    /// Detect attributes from a thunk symbol node (e.g., @objc thunk).
    /// The node structure is: global(objCAttribute, function(...))
    public static func detectFromThunkNode(_ rootNode: Node) -> [SwiftAttribute] {
        var attributes: [SwiftAttribute] = []
        for child in rootNode.children {
            switch child.kind {
            case .objCAttribute:
                attributes.append(.objc)
            case .nonObjCAttribute:
                attributes.append(.nonobjc)
            default:
                break
            }
        }
        return attributes
    }

    /// Detect attributes from MethodDescriptorFlags.
    public static func detectFromMethodFlags(_ flags: MethodDescriptorFlags) -> [SwiftAttribute] {
        var attributes: [SwiftAttribute] = []
        if flags.isDynamic {
            attributes.append(.dynamic)
        }
        return attributes
    }
}
