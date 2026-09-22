import MachOSwiftSection
@_spi(Internals) import MachOSymbols
@_spi(Internals) import SwiftInspection

/// Comment text the dumpers share for the ObjC member facts (evolution
/// proposals `objc-ancestor-override-recovery` and
/// `objc-member-selector-recovery`), and the name-only third tier over a
/// dump's member symbols.
enum ObjCMemberRendering {
    /// The name-only third tier over the dump's member symbols — the same
    /// inference `ObjCMemberApplication` runs on the declaration model, keyed
    /// here by implementation symbol name: for each overriding method the
    /// table tied to no symbol, the ONE symbol among `memberSymbols` not
    /// already in the table whose shape is the importer's spelling of the
    /// selector. Empty unless the image's `ObjCMemberRecoveryOptions` ask
    /// for it, so the default dump stays evidence-only.
    static func inferredOverrides(for table: ObjCMemberTable?, memberSymbols: [DemangledSymbol], in machO: some MachORepresentableWithCache) -> [String: ObjCMember] {
        guard let table, !table.unattributedOverriddenMethods.isEmpty,
              ObjCMemberRecoveryOptionsStore.shared.options(for: machO).infersOverridesFromSelectorNames
        else { return [:] }
        var shapes: [(key: String, shape: ObjCMemberShape)] = []
        for symbol in memberSymbols {
            guard table.member(forMemberSymbolNamed: symbol.name) == nil,
                  table.member(forAllocatorSymbolNamed: symbol.name) == nil,
                  let shape = ObjCMemberShape(demangledSymbol: symbol.demangledNode.materialize())
            else { continue }
            shapes.append((symbol.name, shape))
        }
        return table.inferredOverrides(forMemberShapes: shapes)
    }

    /// A Swift class's `class_ro_t` name is its mangled runtime name
    /// (`_TtC7SwiftUI16PlatformDocument`); the comment spells it the way the
    /// rest of the dump does (`SwiftUI.PlatformDocument`). An ObjC class's
    /// bare name passes through.
    static func displayName(forClassNamed runtimeName: String) -> String {
        NodeTypeNaming.swiftClassQualifiedName(fromRuntimeName: runtimeName) ?? runtimeName
    }

    /// `ObjC ancestor chain: NSView → NSResponder → NSObject`, with the
    /// unfollowable superclass spelled out when the chain broke:
    /// `ObjC ancestor chain: ClangWidget → NSObject (bound; chain not resolvable offline)`.
    static func ancestorChainComment(for hierarchy: ObjCClassHierarchy) -> String {
        var names = hierarchy.ancestors.map { displayName(forClassNamed: $0.className) }
        if !hierarchy.isAncestorChainComplete {
            if let unresolvedAncestorName = hierarchy.unresolvedAncestorName {
                names.append("\(displayName(forClassNamed: unresolvedAncestorName)) (bound; chain not resolvable offline)")
            } else {
                names.append("… (chain not resolvable)")
            }
        }
        return "ObjC ancestor chain: " + names.joined(separator: " → ")
    }

    /// `overrides -[NSView layout] (the IMP's code references the implementation)`
    /// for an override; `@objc -[NSGlassEffectView foo] (To thunk symbol at the IMP)`
    /// for any other member of the ObjC method table, `, explicit selector`
    /// added when the source spelled the selector in `@objc(name)`.
    static func memberComment(for member: ObjCMember) -> String {
        let prefix = member.isClassMethod ? "+" : "-"
        let evidence = "(\(member.evidence.description))"
        if let overriddenAncestorClassName = member.overriddenAncestorClassName {
            return "overrides \(prefix)[\(displayName(forClassNamed: overriddenAncestorClassName)) \(member.selector)] \(evidence)"
        }
        var comment = "@objc \(prefix)[\(displayName(forClassNamed: member.className)) \(member.selector)]"
        if member.hasExplicitSelector {
            comment += ", explicit selector"
        }
        return comment + " " + evidence
    }
}
