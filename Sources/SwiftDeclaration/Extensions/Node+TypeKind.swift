import Demangling
extension Node {
    /// The declaration kind a type tree spells, or `nil` for a tree that
    /// names no nominal type.
    ///
    /// A `typeAlias` counts as a value type: in a type tree it is how the
    /// compiler spells a C typedef the importer promoted to its own nominal
    /// type (`__C.NSNotificationName`, `__C.CGColorRef`; evolution proposal
    /// `type-import-info-identity`). Whether the descriptor behind it is a
    /// struct or a CF class is not recoverable from the tree, and nothing
    /// prints a declaration keyword for such a type — the kind only has to
    /// exist so the name can be built and keyed.
    public var typeKind: TypeKind? {
        func findKind(_ node: Node) -> TypeKind? {
            if node.contains(.enum) || node.contains(.boundGenericEnum) {
                return .enum
            } else if node.contains(.structure) || node.contains(.boundGenericStructure) {
                return .struct
            } else if node.contains(.class) || node.contains(.boundGenericClass) {
                return .class
            } else if node.contains(.typeAlias) {
                return .struct
            } else {
                return nil
            }
        }
        if let node = first(of: .type) {
            return findKind(node)
        } else {
            return findKind(self)
        }
    }
}
