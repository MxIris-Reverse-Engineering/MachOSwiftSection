import Demangling
extension DemanglingNode where Self: Sequence<Self> {
    /// The accessor this member symbol is; `.none` for a property's storage,
    /// or for anything else that is no accessor.
    ///
    /// The search stops at the first accessor OR declaration in preorder: a
    /// member's own accessor comes before its `variable` / `subscript`, and
    /// the declaration's context comes after it. A local type's context can
    /// hold an accessor of its own — the getter declaring the type — which a
    /// search for accessors alone found for a static stored property's
    /// storage symbol, and the property printed as a computed one (evolution
    /// proposal `local-type-context-names`).
    package var accessorKind: AccessorKind {
        guard let node = first(of: .getter, .setter, .modifyAccessor, .readAccessor, .variable, .subscript) else { return .none }
        switch node.kind {
        case .getter: return .getter
        case .setter: return .setter
        case .modifyAccessor: return .modifyAccessor
        case .readAccessor: return .readAccessor
        default: return .none
        }
    }
}
