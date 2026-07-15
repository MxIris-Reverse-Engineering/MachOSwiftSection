import Demangling

/// Extracts a stable, generic-argument-free fully-qualified type name from a
/// demangled type `Node`, e.g. `"Swift.Array"`, `"MyModule.Outer.Inner"`.
///
/// The same extraction is used both to index a type descriptor (from its
/// demangled mangled-name) and to look a field type up against that index, so
/// the two sides always agree on key format.
enum NodeTypeNaming {
    /// The broad nominal category of a type node, used to pick a layout path.
    enum NominalCategory {
        case structure
        case `enum`
        case `class`
    }

    /// Strips `.type` wrappers and `boundGeneric*` shells down to the
    /// underlying `.structure` / `.enum` / `.class` node, or `nil` if the node
    /// is not a nominal type.
    static func unwrappedNominal(of node: Node) -> Node? {
        switch node.kind {
        case .type:
            return node.firstChild.flatMap(unwrappedNominal)
        case .boundGenericStructure, .boundGenericEnum, .boundGenericClass:
            return node.firstChild.flatMap(unwrappedNominal)
        case .structure, .enum, .class:
            return node
        default:
            return nil
        }
    }

    /// The nominal category of a (possibly wrapped) type node.
    static func nominalCategory(of node: Node) -> NominalCategory? {
        guard let nominal = unwrappedNominal(of: node) else { return nil }
        switch nominal.kind {
        case .structure: return .structure
        case .enum: return .enum
        case .class: return .class
        default: return nil
        }
    }

    /// The fully-qualified name of a (possibly wrapped) nominal type node, or
    /// `nil` if the node is not nominal.
    static func nominalQualifiedName(of node: Node) -> String? {
        guard let nominal = unwrappedNominal(of: node) else { return nil }
        return qualifiedName(ofNominal: nominal)
    }

    /// The fully-qualified name of a protocol reference node (`.protocol`),
    /// stripping any `.type` wrapper — e.g. `"SymbolTestsCore.Protocols.Foo"`.
    /// Used to key the per-image protocol class-constraint index and to look a
    /// protocol up from an existential's component list, sharing the same
    /// `qualifiedName(ofNominal:)` formatting as the type side so the two agree.
    static func protocolQualifiedName(of node: Node) -> String? {
        let unwrapped = (node.kind == .type ? node.firstChild : node) ?? node
        guard unwrapped.kind == .protocol else { return nil }
        return qualifiedName(ofNominal: unwrapped)
    }

    /// The fully-qualified name of a declared nominal-or-protocol node. Lets the
    /// per-image index treat a protocol context the same way as a type context.
    static func declaredQualifiedName(of node: Node) -> String? {
        nominalQualifiedName(of: node) ?? protocolQualifiedName(of: node)
    }

    /// The bare name of an Objective-C class node (a `.class` whose module is
    /// the synthetic `__C` Clang-importer module), e.g. `"NSObject"` for
    /// `__C.NSObject`, or `nil` if the node is not an imported ObjC class.
    ///
    /// An ObjC ancestor has no Swift type descriptor, so the resolver routes it
    /// to the ObjC class index rather than `resolveType` — and routes it *first*,
    /// because a Swift-side lookup of an ObjC name is a guaranteed miss that
    /// would needlessly fold the entire dependency closure.
    static func objCClassBareName(of node: Node) -> String? {
        guard let nominal = unwrappedNominal(of: node), nominal.kind == .class else { return nil }
        guard
            let context = nominal.firstChild,
            context.kind == .module,
            context.text == objcModule
        else { return nil }
        return nominal.identifier
    }

    /// The bare name of an imported Objective-C protocol node (a `.protocol`
    /// whose module is the synthetic `__C` Clang-importer module), e.g.
    /// `"NSCopying"`, or `nil` if the node is not an imported ObjC protocol.
    ///
    /// An ObjC protocol has no Swift protocol descriptor (`__swift5_protos`), so
    /// an existential routes it through this check instead of the Swift
    /// class-constraint index: an ObjC protocol is always class-bound and carries
    /// no Swift witness table.
    static func objCProtocolBareName(of node: Node) -> String? {
        let unwrapped = (node.kind == .type ? node.firstChild : node) ?? node
        guard unwrapped.kind == .protocol else { return nil }
        guard
            let context = unwrapped.firstChild,
            context.kind == .module,
            context.text == objcModule
        else { return nil }
        return unwrapped.identifier
    }

    private static func qualifiedName(ofNominal node: Node) -> String? {
        guard let identifier = node.identifier else { return nil }
        guard let context = node.firstChild else { return identifier }
        if let contextName = contextQualifiedName(of: context) {
            return contextName + "." + identifier
        }
        return identifier
    }

    private static func contextQualifiedName(of node: Node) -> String? {
        switch node.kind {
        case .module:
            return node.text
        case .structure, .enum, .class:
            return qualifiedName(ofNominal: node)
        case .type:
            // A `.type`-wrapped context (as appears inside a bound-generic
            // parent's first child): unwrap and recurse.
            return node.firstChild.flatMap(contextQualifiedName)
        case .boundGenericStructure, .boundGenericEnum, .boundGenericClass:
            // A nested type whose enclosing type is a *specialized* generic
            // (e.g. the `Environment<Bool>` in `Environment<Bool>.Content`)
            // carries a `boundGeneric*` context node. Key by the enclosing
            // type's generic-argument-free name — matching how the type index
            // names the nested type's own descriptor — by unwrapping to the
            // underlying nominal. Without this the parent chain is lost and the
            // nested type degrades to a bare, unresolvable identifier.
            return unwrappedNominal(of: node).flatMap(contextQualifiedName)
        case .extension:
            // `.extension` children are [module, extendedType, ...]; the
            // nesting context is the extended type.
            return node.children.at(1).flatMap(contextQualifiedName)
        default:
            return node.text
        }
    }
}
