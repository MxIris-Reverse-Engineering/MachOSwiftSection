import SwiftDump
import MachOSwiftSection
import Demangling

/// Infers member-level Swift attributes by analyzing demangled Node trees and MethodDescriptorFlags.
///
/// Detectable attributes:
/// - `@objc`: Node tree has `.objCAttribute` child (from @objc thunk symbols)
/// - `@nonobjc`: Node tree has `.nonObjCAttribute` child
/// - `dynamic`: `MethodDescriptorFlags.isDynamic` is true
/// - `@inlinable` (resilience-gated): Node tree has `.isSerialized` child recursively
public struct MemberAttributeInferrer: Sendable {
    /// Whether to include resilience-gated attributes (`@inlinable`).
    public let resilienceAwareAttributes: Bool

    public init(resilienceAwareAttributes: Bool) {
        self.resilienceAwareAttributes = resilienceAwareAttributes
    }

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

    /// Detect @inlinable from isSerialized child in specialization nodes.
    public static func detectFromSpecializationNode(_ node: Node) -> [SwiftAttribute] {
        var attributes: [SwiftAttribute] = []
        if hasSerializedChild(node) {
            attributes.append(.inlinable)
        }
        return attributes
    }

    // Internal (not private) so Task 7 can use it for @inlinable cross-referencing
    static func hasSerializedChild(_ node: Node) -> Bool {
        if node.kind == .isSerialized {
            return true
        }
        for child in node.children {
            if hasSerializedChild(child) {
                return true
            }
        }
        return false
    }
}
