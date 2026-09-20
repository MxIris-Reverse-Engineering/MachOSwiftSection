@_spi(Internals) import SwiftInspection

/// Comment text the dumpers share for the ObjC-ancestor override facts
/// (evolution proposal `objc-ancestor-override-recovery`).
enum ObjCAncestorOverrideRendering {
    /// A Swift ancestor's `class_ro_t` name is its mangled runtime name
    /// (`_TtC7SwiftUI16PlatformDocument`); the comment spells it the way the
    /// rest of the dump does (`SwiftUI.PlatformDocument`). An ObjC class's
    /// bare name passes through.
    static func displayName(forAncestorClassNamed runtimeName: String) -> String {
        NodeTypeNaming.swiftClassQualifiedName(fromRuntimeName: runtimeName) ?? runtimeName
    }

    /// `ObjC ancestor chain: NSView → NSResponder → NSObject`, with the
    /// unfollowable superclass spelled out when the chain broke:
    /// `ObjC ancestor chain: ClangWidget → NSObject (bound; chain not resolvable offline)`.
    static func ancestorChainComment(for hierarchy: ObjCClassHierarchy) -> String {
        var names = hierarchy.ancestors.map { displayName(forAncestorClassNamed: $0.className) }
        if !hierarchy.isAncestorChainComplete {
            if let unresolvedAncestorName = hierarchy.unresolvedAncestorName {
                names.append("\(displayName(forAncestorClassNamed: unresolvedAncestorName)) (bound; chain not resolvable offline)")
            } else {
                names.append("… (chain not resolvable)")
            }
        }
        return "ObjC ancestor chain: " + names.joined(separator: " → ")
    }

    /// `overrides -[NSView layout] (the IMP's code references the implementation)`.
    static func overrideComment(for override: ObjCAncestorOverride) -> String {
        "overrides \(override.isClassMethod ? "+" : "-")[\(displayName(forAncestorClassNamed: override.ancestorClassName)) \(override.selector)] (\(override.evidence.description))"
    }
}
