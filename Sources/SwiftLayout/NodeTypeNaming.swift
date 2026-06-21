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
        case .extension:
            // `.extension` children are [module, extendedType, ...]; the
            // nesting context is the extended type.
            return node.children.at(1).flatMap(contextQualifiedName)
        default:
            return node.text
        }
    }
}
